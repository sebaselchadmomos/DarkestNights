extends Node
# Autoload "Network" (reemplaza al script ENet/UPnP).
# Requiere los addons GodotSteam y SteamMultiplayerPeer instalados y habilitados,
# y Steam abierto en la PC. Los nombres de funciones/constantes de GodotSteam
# cambian un poco entre versiones: si algo no existe, revisá la doc de tu versión.

signal lobby_code_ready(code: String)   # el host muestra este código
signal join_failed(reason: String)      # el cliente muestra el error

const APP_ID: int = 480                 # Spacewar: SOLO para pruebas. Cambiar por tu App ID al publicar.
const GAME_KEY: String = "mi_juego_v1"  # identifica TU juego (el 480 lo usa todo el mundo)
const MAX_PLAYERS: int = 2
const CODE_ALPHABET: String = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH: int = 6

var steam_ready: bool = false
var lobby_id: int = 0
var lobby_code: String = ""
var _is_host: bool = false


func _ready() -> void:
	# 2º argumento = true: GodotSteam corre run_callbacks() solo.
	# Si tu versión no lo soporta, usá steamInitEx() y llamá Steam.run_callbacks() en _process.
	var result: Dictionary = Steam.steamInitEx(APP_ID, true)
	if result.get("status", 1) != 0:
		push_error("Steam no inició: %s" % str(result))
		return
	steam_ready = true
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_joined.connect(_on_lobby_joined)


# --- HOST -------------------------------------------------------------------

func start_server() -> void:
	if not steam_ready:
		join_failed.emit("Steam no está iniciado. ¿Está abierto y con sesión?")
		return
	_is_host = true
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)


func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	if result != 1:
		join_failed.emit("No se pudo crear la sala (%d)" % result)
		return
	lobby_id = new_lobby_id
	lobby_code = _generate_code()
	Steam.setLobbyData(lobby_id, "game", GAME_KEY)
	Steam.setLobbyData(lobby_id, "code", lobby_code)

	var peer := SteamMultiplayerPeer.new()
	peer.create_host(0)
	peer.server_relay = true
	multiplayer.multiplayer_peer = peer

	lobby_code_ready.emit(lobby_code)


# --- CLIENTE ----------------------------------------------------------------

func start_client(code: String) -> void:
	if not steam_ready:
		join_failed.emit("Steam no está iniciado. ¿Está abierto y con sesión?")
		return
	_is_host = false
	code = code.strip_edges().to_upper()
	# Los filtros se limpian en cada requestLobbyList, así que se ponen siempre antes.
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListStringFilter("game", GAME_KEY, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter("code", code, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()


func _on_lobby_match_list(lobbies: Array) -> void:
	if _is_host:
		return
	if lobbies.is_empty():
		join_failed.emit("No existe ninguna sala con ese código.")
		return
	Steam.joinLobby(lobbies[0])


func _on_lobby_joined(joined_lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		join_failed.emit("No se pudo entrar a la sala (%d)." % response)
		return
	lobby_id = joined_lobby_id
	var owner_id: int = Steam.getLobbyOwner(joined_lobby_id)
	# El host también recibe lobby_joined al crear el lobby: ahí no hay que crear cliente.
	if owner_id == Steam.getSteamID():
		return
	var peer := SteamMultiplayerPeer.new()
	peer.create_client(owner_id, 0)
	peer.server_relay = true
	multiplayer.multiplayer_peer = peer


# --- COMUNES ----------------------------------------------------------------

func stop() -> void:
	if lobby_id != 0:
		Steam.leaveLobby(lobby_id)
		lobby_id = 0
	lobby_code = ""
	multiplayer.multiplayer_peer = null  # siempre se crea un SteamMultiplayerPeer nuevo


func _generate_code() -> String:
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return code


func _exit_tree() -> void:
	stop()
