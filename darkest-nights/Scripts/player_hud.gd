class_name PlayerHUD
extends CanvasLayer
## HUD del jugador local: vida y estamina (abajo a la izquierda), flash al recibir daño
## y aviso de "derribado". Se arma por código, no necesita escena.
## Lo crea el jugador desde player.gd (reemplaza a stamina_hud.gd).

const COLOR_NORMAL := Color(1.0, 1.0, 1.0, 0.9)
const COLOR_EXHAUSTED := Color(1.0, 0.35, 0.3, 1.0)
const COLOR_HEALTH := Color(0.8, 0.12, 0.12)
const COLOR_STAMINA := Color(0.9, 0.8, 0.25)

var _damage_flash: ColorRect
var _downed_label: Label
var _health_label: Label
var _health_bar: ProgressBar
var _stamina_box: VBoxContainer
var _stamina_label: Label
var _stamina_bar: ProgressBar
var _last_health := -1.0


func _ready() -> void:
	layer = 10
	_build_damage_flash()
	_build_bars()
	_build_downed_label()
	set_exhausted(false)


func set_health(current: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = current
	_health_label.text = "VIDA %d HP" % ceili(current)
	if _last_health >= 0.0 and current < _last_health:
		_flash_damage()
	_last_health = current


func set_stamina(current: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = current
	_stamina_label.text = "ESTAMINA %d%%" % roundi(current / maximum * 100.0)


func set_exhausted(value: bool) -> void:
	_stamina_box.modulate = COLOR_EXHAUSTED if value else COLOR_NORMAL


func set_downed(value: bool) -> void:
	_downed_label.visible = value


func _flash_damage() -> void:
	_damage_flash.modulate.a = 1.0
	create_tween().tween_property(_damage_flash, "modulate:a", 0.0, 0.4)


# --- Construcción ------------------------------------------------------------

func _build_damage_flash() -> void:
	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.color = Color(0.8, 0.0, 0.0, 0.35)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.modulate.a = 0.0
	add_child(_damage_flash)


func _build_bars() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	# Abajo a la izquierda: vida arriba, estamina abajo
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.size_flags_vertical = Control.SIZE_SHRINK_END
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var health_box := VBoxContainer.new()
	health_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(health_box)
	_health_label = _make_label("VIDA 100 HP")
	health_box.add_child(_health_label)
	_health_bar = _make_bar(COLOR_HEALTH)
	health_box.add_child(_health_bar)

	_stamina_box = VBoxContainer.new()
	_stamina_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_stamina_box)
	_stamina_label = _make_label("ESTAMINA 100%")
	_stamina_box.add_child(_stamina_label)
	_stamina_bar = _make_bar(COLOR_STAMINA)
	_stamina_box.add_child(_stamina_bar)


func _build_downed_label() -> void:
	_downed_label = Label.new()
	_downed_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_downed_label.text = "DERRIBADO"
	_downed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_downed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_downed_label.add_theme_font_size_override("font_size", 42)
	_downed_label.add_theme_color_override("font_color", COLOR_EXHAUSTED)
	_downed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_downed_label.visible = false
	add_child(_downed_label)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(240.0, 14.0)
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	return bar
