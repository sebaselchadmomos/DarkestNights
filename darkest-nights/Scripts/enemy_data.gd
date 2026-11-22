class_name EnemyData
extends Resource
## Datos de un enemigo. Un .tres por enemigo (chaser_data.tres, jumper_data.tres...).
## Balancear = editar el .tres, sin tocar código.

enum Size { SMALL, MEDIUM, LARGE }

@export var id: StringName = &""
@export var display_name := ""
@export var size: Size = Size.MEDIUM
@export_multiline var counterplay := ""  # nota de diseño: cómo se le hace frente

@export_group("Movimiento")
@export var patrol_speed := 3.0
@export var chase_speed := 5.5
@export var patrol_radius := 15.0
@export var patrol_wait_time := 2.0

@export_group("Percepción")
@export var detection_range := 14.0
@export var lose_target_range := 22.0
@export var lose_sight_time := 3.0  # segundos sin ver al objetivo antes de rendirse
@export var requires_line_of_sight := true

@export_group("Combate")
@export var attack_damage := 5.0  # vida que le quita al jugador por golpe
@export var attack_range := 1.6
@export var attack_windup := 0.4  # tiempo de aviso antes del golpe (counterplay)
@export var attack_cooldown := 1.5

@export_group("Stun")
@export_range(0.0, 1.0) var stun_resistance := 0.0  # 0 = duración completa, 1 = inmune
