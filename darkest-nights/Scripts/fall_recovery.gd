class_name FallRecovery
extends Node
## Devuelve a su padre (un CharacterBody3D) al mapa si cae por debajo de fall_limit_y.
## Lo agrega por código el jugador (en el peer dueño) y el enemigo (en el servidor),
## así quien controla la posición es quien la corrige y se replica solo.

signal recovered(position: Vector3)

@export var fall_limit_y := -20.0
@export var sample_interval := 0.25  # cada cuánto guarda una posición segura
@export var max_samples := 8         # ~2 s de historial mientras está en el piso
@export var respawn_height := 0.5    # se lo repone un poco arriba para no quedar dentro del piso

var _body: CharacterBody3D
var _samples: Array[Vector3] = []
var _timer := 0.0
var _spawn_position := Vector3.ZERO


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	assert(_body != null, "FallRecovery debe ser hijo de un CharacterBody3D")
	_spawn_position = _body.global_position


func _physics_process(delta: float) -> void:
	if _body == null:
		return

	# Guarda posiciones mientras está en el piso. Al caer se usa la MÁS VIEJA (~2 s atrás),
	# así no reaparece justo en el borde por el que se cayó.
	if _body.is_on_floor():
		_timer -= delta
		if _timer <= 0.0:
			_timer = sample_interval
			_samples.append(_body.global_position)
			if _samples.size() > max_samples:
				_samples.pop_front()

	if _body.global_position.y < fall_limit_y:
		_recover()


func _recover() -> void:
	# Si nunca pisó el piso, vuelve a donde apareció.
	var target := _spawn_position if _samples.is_empty() else _samples[0]
	_body.global_position = target + Vector3.UP * respawn_height
	_body.velocity = Vector3.ZERO
	_samples.clear()
	_samples.append(target)
	_timer = sample_interval
	recovered.emit(target)
