extends Control
# Menú Host / Join con Steam. Se arma por código: solo adjuntá este script a un nodo Control.
# Requiere el Autoload "NetworkHandler" con el script de Steam (steam_network.gd).

const GAME_SCENE_PATH: String = "res://Scenes/Gym.tscn"

# true:  el host espera en el menú (viendo el código) hasta que entre el otro jugador.
# false: el host entra al juego apenas se crea la sala; el código queda en
#        NetworkHandler.lobby_code por si querés mostrarlo en el juego.
const HOST_WAITS_FOR_PLAYER: bool = true

var code_input: LineEdit
var host_button: Button
var join_button: Button
var cancel_button: Button
var status_label: Label


func _ready() -> void:
	_build_ui()
	NetworkHandler.lobby_code_ready.connect(_on_lobby_code_ready)
	NetworkHandler.join_failed.connect(_on_join_failed)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "Multijugador"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	host_button = Button.new()
	host_button.text = "Hostear partida"
	host_button.pressed.connect(_on_host_pressed)
	box.add_child(host_button)

	box.add_child(HSeparator.new())

	code_input = LineEdit.new()
	code_input.placeholder_text = "Código de sala (ej: K7QM2X)"
	code_input.max_length = NetworkHandler.CODE_LENGTH
	box.add_child(code_input)

	join_button = Button.new()
	join_button.text = "Unirse"
	join_button.pressed.connect(_on_join_pressed)
	box.add_child(join_button)

	cancel_button = Button.new()
	cancel_button.text = "Cancelar"
	cancel_button.visible = false
	cancel_button.pressed.connect(_on_cancel_pressed)
	box.add_child(cancel_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)


func _set_busy(busy: bool) -> void:
	host_button.disabled = busy
	join_button.disabled = busy
	code_input.editable = not busy


func _reset_ui() -> void:
	NetworkHandler.stop()
	cancel_button.visible = false
	_set_busy(false)


# --- Host -------------------------------------------------------------------

func _on_host_pressed() -> void:
	_set_busy(true)
	status_label.text = "Creando sala..."
	NetworkHandler.start_server()


func _on_lobby_code_ready(code: String) -> void:
	DisplayServer.clipboard_set(code)
	if HOST_WAITS_FOR_PLAYER:
		status_label.text = "Código de sala: %s\n(copiado al portapapeles)\nEsperando al otro jugador..." % code
		cancel_button.visible = true
	else:
		get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_peer_connected(_id: int) -> void:
	# En el cliente este signal también salta (al conectarse al host): solo el host reacciona.
	if multiplayer.is_server() and HOST_WAITS_FOR_PLAYER:
		get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_cancel_pressed() -> void:
	status_label.text = ""
	_reset_ui()


# --- Cliente ----------------------------------------------------------------

func _on_join_pressed() -> void:
	var code := code_input.text.strip_edges()
	if code.is_empty():
		status_label.text = "Escribí el código de sala."
		return
	_set_busy(true)
	status_label.text = "Buscando la sala %s..." % code.to_upper()
	NetworkHandler.start_client(code)


func _on_connected_to_server() -> void:
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


# --- Errores ----------------------------------------------------------------

func _on_join_failed(reason: String) -> void:
	status_label.text = reason
	_reset_ui()


func _on_connection_failed() -> void:
	status_label.text = "No se pudo conectar con el host."
	_reset_ui()


func _on_server_disconnected() -> void:
	status_label.text = "Se perdió la conexión con el host."
	_reset_ui()
