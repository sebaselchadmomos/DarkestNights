class_name Enemy
extends CharacterBody3D
## Base de todos los enemigos.
## - La IA corre SOLO en el servidor; los clientes reciben position/rotation/state.
## - Escena mínima: CharacterBody3D (este script) + CollisionShape3D + NavigationAgent3D.
## - Se debe spawnear desde el servidor con un MultiplayerSpawner.
## - Requiere un NavigationRegion3D horneado en el mapa.
##
## Contrato con el jugador (duck typing):
##   - estar en el grupo "players"
##   - is_targetable() -> bool   (false si está derribado/muerto)
##   - receive_damage(amount)    (RPC; el ataque por defecto se lo manda al peer dueño del jugador)
##
## Para crear un enemigo nuevo: extender esta clase y sobreescribir los hooks "_..." de abajo.

signal state_changed(new_state: StringName)
signal target_changed(new_target: Node3D)
signal stunned(duration: float)

const STATE_PATROL := &"patrol"
const STATE_CHASE := &"chase"
const STATE_ATTACK := &"attack"
const STATE_STUNNED := &"stunned"
const PATROL_TIMEOUT := 15.0  # si no llega a un punto de patrulla en este tiempo, elige otro

@export var data: EnemyData
@export var ai_enabled := true  # apagar para probar sin que estorbe
@export var gravity := 20.0
@export var eye_height := 0.5
@export var turn_speed := 10.0
@export var fallback_feet_offset := 1.0  # distancia origen-pies si la colisión no es cápsula/cilindro/caja
@export var debug_log := false  # imprime posición y camino cada 0,5 s

# Se replica a los clientes. El setter corre en todos los peers (útil para animaciones/audio).
var state: StringName = STATE_PATROL:
	set = _set_state
var target: Node3D = null

var _nav: NavigationAgent3D
var _home := Vector3.ZERO
var _has_patrol_point := false
var _patrol_wait := 0.0
var _patrol_timeout := 0.0
var _nav_calibrated := false
var _repath_timer := 0.0
var _time_since_seen := 0.0
var _state_timer := 0.0  # usado por ATTACK (windup) y STUNNED
var _attack_cooldown := 0.0


func _enter_tree() -> void:
	_setup_replication()


func _ready() -> void:
	assert(data != null, "Enemy sin EnemyData asignado")
	add_to_group("enemies")
	_nav = $NavigationAgent3D
	# El origen del enemigo está a media altura (cápsula centrada) pero la malla de navegación
	# está en el piso. Sin este offset el agente nunca "llega" a los puntos del camino y se frena.
	_nav.path_height_offset = -_feet_offset()
	_nav.path_desired_distance = 0.6
	_nav.target_desired_distance = 0.9
	if not multiplayer.is_server():
		return
	_home = global_position
	_on_spawned()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or not ai_enabled:
		return

	if not _nav_calibrated:
		_calibrate_nav_height()
	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	velocity.x = 0.0
	velocity.z = 0.0

	match state:
		STATE_PATROL: _state_patrol(delta)
		STATE_CHASE: _state_chase(delta)
		STATE_ATTACK: _state_attack(delta)
		STATE_STUNNED: _state_stunned(delta)
		_: _state_custom(state, delta)

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


# =============================================================================
# API pública (la llaman objetos, eventos, el director de rondas...)
# =============================================================================

## Solo tiene efecto en el servidor. Los objetos deben pedirlo vía RPC al servidor.
func stun(duration: float) -> void:
	if not multiplayer.is_server():
		return
	var final_duration := duration * (1.0 - data.stun_resistance)
	if final_duration <= 0.0:
		return
	_state_timer = final_duration
	state = STATE_STUNNED
	stunned.emit(final_duration)


func despawn() -> void:
	if multiplayer.is_server():
		queue_free()  # el MultiplayerSpawner replica el borrado


# =============================================================================
# HOOKS: sobreescribir en los enemigos derivados
# =============================================================================

## Corre una vez en el servidor al nacer.
func _on_spawned() -> void:
	pass


## ¿Este jugador es un objetivo permitido? (Lurker: solo si está en la oscuridad).
## Se evalúa al buscar objetivo y mientras persigue.
func _is_target_allowed(_player: Node3D) -> bool:
	return true


## Qué pasa cuando el ataque conecta.
func _on_attack_hit(victim: Node3D) -> void:
	# La vida la maneja el peer dueño del jugador (puede ser el propio servidor).
	if victim.has_method("receive_damage"):
		victim.rpc_id(victim.get_multiplayer_authority(), "receive_damage", data.attack_damage)


## Estados propios de un enemigo derivado (ej: &"flee" del Jumper).
func _state_custom(_custom_state: StringName, _delta: float) -> void:
	pass


# =============================================================================
# Estados base
# =============================================================================

func _state_patrol(delta: float) -> void:
	var seen := _find_target()
	if seen != null:
		_set_target(seen)
		state = STATE_CHASE
		return

	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		return
	if not _has_patrol_point:
		_pick_patrol_point()
		if not _has_patrol_point:
			return  # el mapa de navegación aún no está listo
	_patrol_timeout -= delta
	if _reached_horizontally(_nav.target_position, 1.0) \
			or _nav.is_navigation_finished() \
			or _patrol_timeout <= 0.0:
		_has_patrol_point = false
		_patrol_wait = data.patrol_wait_time
		return
	_move_along_path(data.patrol_speed, delta)


func _state_chase(delta: float) -> void:
	if not _is_valid_target(target) or not _is_target_allowed(target):
		_lose_target()
		return

	var dist := global_position.distance_to(target.global_position)
	if dist > data.lose_target_range:
		_lose_target()
		return

	if _can_see(target):
		_time_since_seen = 0.0
	else:
		_time_since_seen += delta
		if _time_since_seen > data.lose_sight_time:
			_lose_target()
			return

	if dist <= data.attack_range:
		_face(target.global_position, delta)
		if _attack_cooldown <= 0.0:
			_state_timer = data.attack_windup
			state = STATE_ATTACK
		return

	_repath_timer -= delta
	if _repath_timer <= 0.0:
		_nav.target_position = target.global_position
		_repath_timer = 0.2
	_move_along_path(data.chase_speed, delta)


func _state_attack(delta: float) -> void:
	if _is_valid_target(target):
		_face(target.global_position, delta)
	_state_timer -= delta
	if _state_timer > 0.0:
		return

	_attack_cooldown = data.attack_cooldown
	if _is_valid_target(target) \
			and global_position.distance_to(target.global_position) <= data.attack_range * 1.25:
		_on_attack_hit(target)

	if _is_valid_target(target):
		state = STATE_CHASE
	else:
		_lose_target()


func _state_stunned(delta: float) -> void:
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	if _is_valid_target(target):
		state = STATE_CHASE
	else:
		_lose_target()


# =============================================================================
# Utilidades (usables por los derivados)
# =============================================================================

func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dist := data.detection_range
	for p in get_tree().get_nodes_in_group("players"):
		if not _is_valid_target(p) or not _is_target_allowed(p):
			continue
		var d := global_position.distance_to(p.global_position)
		if d > best_dist or not _can_see(p):
			continue
		best = p
		best_dist = d
	return best


func _is_valid_target(p: Node3D) -> bool:
	if not is_instance_valid(p):
		return false
	return not p.has_method("is_targetable") or p.is_targetable()


func _can_see(p: Node3D) -> bool:
	if not data.requires_line_of_sight:
		return true
	var from := global_position + Vector3.UP * eye_height
	var query := PhysicsRayQueryParameters3D.create(from, p.global_position)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == p


func _set_target(new_target: Node3D) -> void:
	if target == new_target:
		return
	target = new_target
	_time_since_seen = 0.0
	target_changed.emit(target)


func _lose_target() -> void:
	_set_target(null)
	_has_patrol_point = false
	state = STATE_PATROL


func _pick_patrol_point() -> void:
	var map := _nav.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return  # el mapa aún no se sincronizó; reintenta el próximo frame
	var dir := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
	var point := _home + dir * randf_range(2.0, data.patrol_radius)
	_nav.target_position = NavigationServer3D.map_get_closest_point(map, point)
	_patrol_timeout = PATROL_TIMEOUT
	_has_patrol_point = true


## La malla de navegación puede quedar a otra altura que los pies del enemigo.
## Se mide la diferencia real (origen del enemigo vs punto más cercano de la malla)
## en vez de suponerla, y se usa como path_height_offset.
func _calibrate_nav_height() -> void:
	var map := _nav.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0 or not is_on_floor():
		return
	var surface := NavigationServer3D.map_get_closest_point(map, global_position)
	var off := global_position - surface
	if Vector2(off.x, off.z).length() > 1.5:
		return  # el enemigo está lejos de la malla: no es una medición confiable
	_nav.path_height_offset = -off.y
	_nav_calibrated = true


func _reached_horizontally(point: Vector3, distance: float) -> bool:
	var d := point - global_position
	d.y = 0.0
	return d.length() < distance


## Distancia del origen del enemigo a sus pies (el origen de una cápsula centrada está a media altura).
func _feet_offset() -> float:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null:
		if col.shape is CapsuleShape3D:
			return (col.shape as CapsuleShape3D).height * 0.5 - col.position.y
		if col.shape is CylinderShape3D:
			return (col.shape as CylinderShape3D).height * 0.5 - col.position.y
		if col.shape is BoxShape3D:
			return (col.shape as BoxShape3D).size.y * 0.5 - col.position.y
	return fallback_feet_offset


func _move_along_path(speed: float, delta: float) -> void:
	var next_pos := _nav.get_next_path_position()
	if debug_log and Engine.get_physics_frames() % 30 == 0:
		print("[%s] estado=%s pos=%s siguiente=%s destino=%s terminado=%s" % [
			name, state, global_position, next_pos, _nav.target_position, _nav.is_navigation_finished()])
	var dir := next_pos - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face(global_position + dir, delta)


func _face(point: Vector3, delta: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length_squared() < 0.001:
		return
	var yaw := atan2(-d.x, -d.z)  # el frente es -Z
	rotation.y = lerp_angle(rotation.y, yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _set_state(value: StringName) -> void:
	if state == value:
		return
	state = value
	state_changed.emit(value)


func _setup_replication() -> void:
	var cfg := SceneReplicationConfig.new()
	var paths: Array[NodePath] = [^".:position", ^".:rotation", ^".:state"]
	for path in paths:
		cfg.add_property(path)
		cfg.property_set_spawn(path, true)
		cfg.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	cfg.property_set_replication_mode(^".:state", SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)

	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = cfg
	add_child(sync)
