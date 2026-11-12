extends CharacterBody3D

# Variables de movimiento
@export var speed = 14
@export var fall_acceleration = 10
@export var jump_force = 500
var target_velocity = Vector3.ZERO

# Variables para el mouse
const MOUSE_SENSITIVITY := 0.002
var camera_forward: Vector3
var camera_right: Vector3

func _ready():
	# Lockea el cursor
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	# Deslockea el cursor con ESC
	if Input.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		
	# Lockea el cursor con TAB
	if Input.is_action_pressed("ui_focus_next"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event): # Función para rotar la cámara
	if event is InputEventMouseMotion:
		
		# Rotación
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		$Camera3D.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		
		# Limites verticales
		$Camera3D.rotation.x = clampf(
			$Camera3D.rotation.x, 
			deg_to_rad(-70), 
			deg_to_rad(70)
		)
		
		
func _physics_process(delta): # Función para las físicas
	var direction = Vector3.ZERO
	
	# Conseguimos valores de la cámara
	camera_forward = -$Camera3D.global_transform.basis.z
	camera_right = $Camera3D.global_transform.basis.x

	# Quitamos la parte Y de la cámara (importante más adelante)
	camera_forward.y = 0
	camera_right.y = 0
	camera_forward = camera_forward.normalized()
	camera_right = camera_right.normalized()
	
	# Detectamos los inputs
	if Input.is_action_pressed("move_right"):
		direction += camera_right
	if Input.is_action_pressed("move_left"):
		direction -= camera_right
	if Input.is_action_pressed("move_back"):
		direction -= camera_forward
	if Input.is_action_pressed("move_forward"):
		direction += camera_forward

	if direction != Vector3.ZERO:
		direction = direction.normalized()
		# Setting the basis property will affect the rotation of the node.
		# $Pivot.basis = Basis.looking_at(direction)

	# Ground Velocity
	target_velocity.x = direction.x * speed
	target_velocity.z = direction.z * speed

	# Vertical Velocity
	if not is_on_floor(): # Gravedad
		print("El jugador está en el aire")
		target_velocity.y = target_velocity.y - (fall_acceleration * delta)
		## print(target_velocity.y)
	else:
		target_velocity.y = 0
		
	if is_on_floor() and Input.is_action_pressed("jump"):
		target_velocity.y = target_velocity.y + (jump_force * delta)

	# Moving the Character
	velocity = target_velocity
	move_and_slide()
