extends MultiplayerSpawner

@export var network_player: PackedScene

func _ready() -> void:
	if multiplayer.is_server():
		multiplayer.peer_connected.connect(spawn_player)

		# Creamos el jugador del servidor
		spawn_player(multiplayer.get_unique_id())

		# Creamos jugadores de clientes que quizás ya se conectaron
		for id in multiplayer.get_peers():
			spawn_player(id)


func spawn_player(id: int) -> void:
	if !multiplayer.is_server():
		return

	var parent = get_node(spawn_path)

	# Evitamos instanciar dos veces al mismo jugador
	if parent.has_node(str(id)):
		return

	var player: Node = network_player.instantiate()
	player.name = str(id)

	parent.call_deferred("add_child", player)
