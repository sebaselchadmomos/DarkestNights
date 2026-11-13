extends Control

@onready var code_input: LineEdit = $CodeInput   # ajustá la ruta a tus nodos
@onready var status_label: Label = $StatusLabel

func _ready() -> void:
	NetworkHandler.lobby_code_ready.connect(_on_lobby_code_ready)
	NetworkHandler.join_failed.connect(func(reason: String): status_label.text = reason)

func _on_host_pressed() -> void:
	status_label.text = "Creando sala..."
	NetworkHandler.start_server()

func _on_join_pressed() -> void:
	NetworkHandler.start_client(code_input.text)

func _on_lobby_code_ready(code: String) -> void:
	status_label.text = "Código de sala: " + code
	# Si cambiás de escena acá, el código desaparece de pantalla; mostralo en el juego
	# o esperá a que entre el otro jugador antes de cambiar.
