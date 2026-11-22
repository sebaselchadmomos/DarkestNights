extends CharacterBody3D

signal stamina_changed(current: float, maximum: float)
signal exhausted_changed(is_exhausted: bool)
signal health_changed(current: float, maximum: float)
signal downed_changed(is_downed: bool)

const MOUSE_SENSITIVITY := 0.002

@export_group("Movimiento")
@export var walk_speed := 5.0
@export var sprint_speed := 8.5
@export var crouch_speed := 2.5
@export var ground_acceleration := 30.0  # m/s² al empezar a moverse
@export var ground_deceleration := 40.0  # m/s² al soltar las teclas
@export var air_acceleration := 10.0     # control en el aire

@export_group("Salto y caída")
@export var jump_height := 1.2           # altura máxima en metros
@export var time_to_apex := 0.4          # segundos hasta el punto más alto
@export var fall_gravity_multiplier := 1.6  # cae más rápido de lo que sube
@export var jump_cut_multiplier := 2.2   # soltar el salto = salto más corto
@export var max_fall_speed := 40.0
@export var coyote_time := 0.1           # saltar justo después de dejar el borde
@export var jump_buffer_time := 0.1      # saltar justo antes de aterrizar

@export_group("Stamina")
@export var max_stamina := 100.0
@export var sprint_drain := 20.0         # por segundo corriendo
@export var jump_stamina_cost := 10.0    # 0 = saltar no gasta
@export var regen_rate := 18.0           # por segundo
@export var regen_delay := 1.0           # espera antes de empezar a recuperar
@export var exhaustion_recover := 25.0   # tras agotarse, no corre hasta llegar a este valor

@export_group("Vida")
@export var max_health := 100.0
@export var crawl_speed := 1.2           # velocidad al arrastrarse derribado

@export_group("Agacharse")
@export var crouch_height := 1.2         # debe ser >= 2 * radio de la cápsula
@export var crouch_camera_speed := 12.0

@export_group("Cámara")
@export_range(0.0, 2.0) var camera_motion_intensity := 1.0  # 0 = cámara quieta (accesibilidad)
@export var breath_frequency := 1.6      # rad/s en reposo (~4 s por respiración)
@export var breath_amount := 0.008       # metros; con poca stamina sube hasta 2,5x
@export var walk_bob_frequency := 6.5    # rad/s (un ciclo = dos pasos)
@export var sprint_bob_frequency := 9.0
@export var crouch_bob_frequency := 4.2
@export var walk_bob_amount := 0.025     # metros
@export var sprint_bob_amount := 0.055
@export var crouch_bob_amount := 0.012
@export var landing_dip_scale := 0.01    # metros de "golpe" por cada m/s de caída
@export var landing_dip_max := 0.12

# Estado público (HUD, animaciones, enemigos, etc.)
var stamina := 0.0
var is_sprinting := false
var is_crouching := false
var is_exhausted := false
var health := 0.0
var is_downed := false

var _jump_gravity := 0.0
var _jump_velocity := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _regen_timer := 0.0
var _was_on_floor := true

var _stand_height := 2.0
var _capsule: CapsuleShape3D
var _stand_shape: CapsuleShape3D  # cápsula de pie, para comprobar si hay lugar al levantarse

# Cámara
var _pitch := 0.0           # mirada vertical controlada por el mouse
var _camera_stand_y := 0.5
var _camera_y := 0.5        # altura actual (baja suave al agacharse)
var _breath_phase := 0.0
var _bob_phase := 0.0
var _bob_freq := 6.5
var _bob_amp := 0.0
var _move_blend := 0.0      # 0 = quieto, 1 = moviéndose en el piso
var _air_pitch := 0.0
var _land_target := 0.0
var _land_pos := 0.0

var _hud: PlayerHUD

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _mesh: MeshInstance3D = $CollisionShape3D/MeshInstance3D


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	_ensure_input_actions()

	# El recurso de la cápsula es compartido entre instancias: cada jugador usa su copia.
	_collision.shape = _collision.shape.duplicate() as Shape3D
	_capsule = _collision.shape as CapsuleShape3D
	_stand_height = _capsule.height
	_stand_shape = _capsule.duplicate() as CapsuleShape3D
	_stand_shape.radius -= 0.05  # margen para no "rozar" paredes al levantarse

	_camera_stand_y = _camera.position.y
	_camera_y = _camera_stand_y
	_pitch = _camera.rotation.x

	# Salto derivado de altura y tiempo: gravedad = 2h/t², velocidad = 2h/t
	_jump_gravity = 2.0 * jump_height / (time_to_apex * time_to_apex)
	_jump_velocity = 2.0 * jump_height / time_to_apex

	stamina = max_stamina
	health = max_health
	add_to_group("players")  # los enemigos buscan objetivos en este grupo

	if is_multiplayer_authority():
		_camera.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_create_hud()
	else:
		_camera.current = false


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	# Deslockea el cursor con ESC
	if Input.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Lockea el cursor con TAB
	if Input.is_action_pressed("ui_focus_next"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_update_camera(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clampf(
			_pitch - event.relative.y * MOUSE_SENSITIVITY,
			deg_to_rad(-70),
			deg_to_rad(70)
		)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	_update_crouch()

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	# Correr: mantener Shift, solo hacia adelante, de pie y con stamina
	is_sprinting = Input.is_action_pressed("sprint") \
			and input_dir.y < -0.1 \
			and not is_crouching \
			and not is_downed \
			and not is_exhausted \
			and stamina > 0.0

	_update_stamina(delta)
	_update_vertical(delta)
	_update_horizontal(delta, direction)

	var vy_before := velocity.y
	move_and_slide()

	# Aterrizaje: el "golpe" de cámara depende de la velocidad de caída
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor and vy_before < -2.0:
		_land_target = clampf(-vy_before * landing_dip_scale, 0.0, landing_dip_max)
	_was_on_floor = on_floor


# =============================================================================
# Movimiento
# =============================================================================

func _update_horizontal(delta: float, direction: Vector3) -> void:
	var target_speed := walk_speed
	if is_downed:
		target_speed = crawl_speed
	elif is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed

	var has_input := direction != Vector3.ZERO
	var accel: float
	if is_on_floor():
		accel = ground_acceleration if has_input else ground_deceleration
	else:
		accel = air_acceleration if has_input else air_acceleration * 0.25

	var target := Vector2(direction.x, direction.z) * target_speed
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(target, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _update_vertical(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
		velocity.y = 0.0
	else:
		_coyote_timer -= delta
		var gravity := _jump_gravity
		if velocity.y < 0.0:
			gravity *= fall_gravity_multiplier
		elif velocity.y > 0.0 and not Input.is_action_pressed("jump"):
			gravity *= jump_cut_multiplier
		velocity.y = maxf(velocity.y - gravity * delta, -max_fall_speed)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer -= delta

	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and _can_jump():
		velocity.y = _jump_velocity
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_spend_stamina(jump_stamina_cost)


func _can_jump() -> bool:
	return not is_crouching and not is_downed and stamina >= jump_stamina_cost


# =============================================================================
# Agacharse
# =============================================================================

func _update_crouch() -> void:
	var wants_crouch := is_downed or Input.is_action_pressed("crouch")  # derribado = pegado al piso
	if wants_crouch and not is_crouching:
		_set_crouch(true)
	elif not wants_crouch and is_crouching and can_stand():
		_set_crouch(false)


func _set_crouch(value: bool) -> void:
	is_crouching = value
	var h := crouch_height if value else _stand_height
	_capsule.height = h
	# Los pies quedan fijos: la cápsula se achica hacia abajo, el cuerpo no cae.
	_collision.position.y = -(_stand_height - h) / 2.0
	_mesh.scale.y = h / _stand_height


func can_stand() -> bool:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _stand_shape
	params.transform = global_transform
	params.exclude = [get_rid()]
	params.collision_mask = collision_mask
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


# =============================================================================
# Stamina
# =============================================================================

func _update_stamina(delta: float) -> void:
	var before := stamina
	if is_sprinting:
		stamina = maxf(stamina - sprint_drain * delta, 0.0)
		_regen_timer = regen_delay
		if stamina <= 0.0:
			_set_exhausted(true)
			is_sprinting = false
	else:
		_regen_timer = maxf(_regen_timer - delta, 0.0)
		if _regen_timer <= 0.0:
			stamina = minf(stamina + regen_rate * delta, max_stamina)
			if is_exhausted and stamina >= exhaustion_recover:
				_set_exhausted(false)

	if not is_equal_approx(before, stamina):
		stamina_changed.emit(stamina, max_stamina)


func _spend_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = maxf(stamina - amount, 0.0)
	_regen_timer = regen_delay
	if stamina <= 0.0:
		_set_exhausted(true)
	stamina_changed.emit(stamina, max_stamina)


func _set_exhausted(value: bool) -> void:
	if is_exhausted == value:
		return
	is_exhausted = value
	exhausted_changed.emit(value)


# =============================================================================
# Cámara: respiración, pasos, salto/caída y aterrizaje
# Corre en _process (a la tasa de dibujado) para que se vea fluido.
# =============================================================================

func _update_camera(delta: float) -> void:
	var on_floor := is_on_floor()
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var move_target := clampf(horizontal_speed / walk_speed, 0.0, 1.0) if on_floor else 0.0
	_move_blend = lerpf(_move_blend, move_target, 1.0 - exp(-8.0 * delta))

	# --- Respiración: siempre activa; más rápida y fuerte cuanto menos stamina ---
	var tired := 1.0 - stamina / max_stamina
	var breath_freq := lerpf(breath_frequency, breath_frequency * 2.5, tired)
	var breath_amp := lerpf(breath_amount, breath_amount * 2.5, tired)
	if is_crouching:
		breath_freq *= 0.85
		breath_amp *= 0.7
	_breath_phase += delta * breath_freq
	var breath := sin(_breath_phase) * breath_amp * lerpf(1.0, 0.3, _move_blend)

	# --- Pasos: frecuencia y amplitud según caminar / correr / agachado ---
	var target_freq := walk_bob_frequency
	var target_amp := walk_bob_amount
	if is_crouching:
		target_freq = crouch_bob_frequency
		target_amp = crouch_bob_amount
	elif is_sprinting:
		target_freq = sprint_bob_frequency
		target_amp = sprint_bob_amount
	var k := 1.0 - exp(-6.0 * delta)
	_bob_freq = lerpf(_bob_freq, target_freq, k)
	_bob_amp = lerpf(_bob_amp, target_amp, k)
	_bob_phase += delta * _bob_freq * _move_blend  # la fase solo avanza al moverse
	var step_amp := _bob_amp * _move_blend
	var step_y := sin(_bob_phase * 2.0) * step_amp           # un rebote por paso
	var step_x := sin(_bob_phase) * step_amp * 0.5           # balanceo izquierda-derecha
	var step_roll := -sin(_bob_phase) * step_amp * 0.12      # leve inclinación lateral

	# --- Aire: mira un poco arriba al subir y abajo al caer ---
	var air_target := 0.0 if on_floor else clampf(velocity.y * 0.0025, -0.04, 0.025)
	_air_pitch = lerpf(_air_pitch, air_target, 1.0 - exp(-10.0 * delta))

	# --- Aterrizaje: baja rápido y se recupera más lento ---
	_land_target = lerpf(_land_target, 0.0, 1.0 - exp(-8.0 * delta))
	_land_pos = lerpf(_land_pos, _land_target, 1.0 - exp(-30.0 * delta))

	# --- Altura al agacharse (suavizada) ---
	var target_y := _camera_stand_y
	if is_crouching:
		target_y -= _stand_height - crouch_height
	_camera_y = lerpf(_camera_y, target_y, 1.0 - exp(-crouch_camera_speed * delta))

	# --- Aplicar ---
	var i := camera_motion_intensity
	_camera.position = Vector3(step_x * i, _camera_y + (breath + step_y - _land_pos) * i, 0.0)
	_camera.rotation = Vector3(
		_pitch + (breath * 0.8 + _air_pitch - _land_pos * 0.5) * i,
		0.0,
		step_roll * i
	)


# =============================================================================
# Vida
# =============================================================================

## Los enemigos (en el servidor) llaman a esto por RPC al peer dueño del jugador.
@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return  # solo el servidor puede dañar jugadores
	if is_downed or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_sync_downed.rpc(true)


## Curar (botiquín, etc.). Se llama en el peer dueño del jugador.
func heal(amount: float) -> void:
	if not is_multiplayer_authority() or is_downed or amount <= 0.0:
		return
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


## El estado "derribado" se replica a todos: los enemigos lo consultan en el servidor.
@rpc("authority", "call_local", "reliable")
func _sync_downed(value: bool) -> void:
	is_downed = value
	downed_changed.emit(value)


## Contrato con Enemy: un jugador derribado ya no es objetivo.
func is_targetable() -> bool:
	return not is_downed


# =============================================================================
# HUD
# =============================================================================

func _create_hud() -> void:
	_hud = PlayerHUD.new()
	add_child(_hud)
	stamina_changed.connect(_hud.set_stamina)
	exhausted_changed.connect(_hud.set_exhausted)
	health_changed.connect(_hud.set_health)
	downed_changed.connect(_hud.set_downed)
	_hud.set_stamina(stamina, max_stamina)
	_hud.set_health(health, max_health)


# =============================================================================
# Input
# =============================================================================

# Crea la acción "sprint" (Shift) si no existe en el Input Map.
# Cuando la agreguen en Project Settings > Input Map, esto no hace nada.
func _ensure_input_actions() -> void:
	if InputMap.has_action("sprint"):
		return
	InputMap.add_action("sprint")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_SHIFT
	InputMap.action_add_event("sprint", key)
