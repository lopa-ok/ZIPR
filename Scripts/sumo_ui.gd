extends CanvasLayer

var sumo_manager: Node = null
var car: VehicleBody3D = null

var alive_panel: PanelContainer
var alive_label: Label
var alive_icon_label: Label

var timer_label: Label

var countdown_label: Label
var result_label: Label
var result_sub_label: Label

var feed_container: VBoxContainer

var speed_gauge: Control
var speedometer_label: Label

var edge_warning: Control
var mode_badge: PanelContainer

var current_speed_kmh: float = 0.0
var gauge_max_kmh: float = 120.0
var hud_margin: int = 24
var gauge_size: int = 260

var _feed_entries: Array[Label] = []
var _max_feed_entries: int = 5
var _edge_danger: float = 0.0
var _round_over: bool = false

func _enter_tree() -> void:
	var existing := get_tree().get_nodes_in_group("sumo_hud")
	if existing.size() > 0:
		queue_free()
		return
	add_to_group("sumo_hud")

func _ready() -> void:
	car = _resolve_car()
	if car != null:
		var ai: Variant = car.get("is_ai_controlled")
		if ai is bool and ai:
			queue_free()
			return

	sumo_manager = get_tree().get_first_node_in_group("sumo_manager")
	visible = true
	_build_ui()

	if sumo_manager:
		if sumo_manager.has_signal("car_eliminated"):
			sumo_manager.car_eliminated.connect(_on_car_eliminated)
		if sumo_manager.has_signal("round_ended"):
			sumo_manager.round_ended.connect(_on_round_ended)

func _resolve_car() -> VehicleBody3D:
	var p := get_parent()
	if p is VehicleBody3D:
		return p
	var cur: Node = p
	while cur != null:
		if cur is VehicleBody3D:
			return cur
		cur = cur.get_parent()
	var found := get_tree().get_first_node_in_group("player")
	if found is VehicleBody3D:
		return found
	return null

func _process(delta: float) -> void:
	if not visible:
		return
	if car == null:
		car = _resolve_car()
		if car == null:
			return

	var car_speed: float = car.linear_velocity.length()
	current_speed_kmh = lerpf(current_speed_kmh, car_speed * 3.6, 0.15)
	if speedometer_label:
		speedometer_label.text = "%d" % int(clamp(current_speed_kmh, 0.0, 999.0))
	if speed_gauge:
		speed_gauge.queue_redraw()

	if not sumo_manager:
		sumo_manager = get_tree().get_first_node_in_group("sumo_manager")
		return

	if alive_label:
		var alive: int = sumo_manager.get_alive_count() if sumo_manager.has_method("get_alive_count") else 0
		alive_label.text = str(alive)

	if timer_label:
		var t: float = sumo_manager.get_round_time() if sumo_manager.has_method("get_round_time") else 0.0
		timer_label.text = _format_time(t)

	_update_edge_danger(delta)
	_update_countdown()

	if _round_over and Input.is_action_just_pressed("ui_accept"):
		get_tree().change_scene_to_file("res://Scenes/Main_menu.tscn")

func _update_countdown() -> void:
	if not countdown_label or not sumo_manager:
		return
	if sumo_manager.has_method("get_countdown_text"):
		var txt: String = sumo_manager.get_countdown_text()
		if txt.is_valid_float():
			txt = str(int(txt.to_float()))
		countdown_label.text = txt
		countdown_label.visible = txt != ""
		if txt != "":
			var timer_val: float = sumo_manager.countdown_timer if "countdown_timer" in sumo_manager else 0.0
			var frac: float = timer_val - floor(timer_val)
			var s: float = 1.0 + frac * 0.3
			if txt == "GO!":
				s = 1.5 - (frac * 0.5)
			countdown_label.scale = Vector2(s, s)
			countdown_label.pivot_offset = countdown_label.size / 2

func _update_edge_danger(_delta: float) -> void:
	if not edge_warning or not sumo_manager:
		return
	if sumo_manager.has_method("get_edge_factor"):
		var factor: float = sumo_manager.get_edge_factor(car)
		var danger: float = clamp((factor - 0.6) / 0.35, 0.0, 1.0)
		_edge_danger = lerpf(_edge_danger, danger, _delta * 6.0)
		var pulse: float = 1.0
		if _edge_danger > 0.5:
			pulse = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.008)
		edge_warning.modulate.a = _edge_danger * 0.55 * pulse
		edge_warning.visible = _edge_danger > 0.01

func _on_car_eliminated(car_node: Node, reason: String) -> void:
	var car_name_str: String = str(car_node.name) if car_node else "???"
	car_name_str = car_name_str.replace("_", " ")
	var entry_text := "☠  %s  —  %s" % [car_name_str, reason]
	_add_feed_entry(entry_text)

func _on_round_ended(winner: Node) -> void:
	_round_over = true
	if not result_label:
		return
	if winner:
		var is_player: bool = not winner.get("is_ai_controlled")
		if is_player:
			result_label.text = "YOU WIN!"
			result_label.label_settings.font_color = Color(1.0, 0.85, 0.0)
		else:
			result_label.text = "%s WINS!" % str(winner.name).replace("_", " ")
			result_label.label_settings.font_color = Color(1.0, 0.3, 0.3)
	else:
		result_label.text = "DRAW!"
		result_label.label_settings.font_color = Color(0.7, 0.7, 0.7)
	result_label.visible = true

	if result_sub_label:
		result_sub_label.text = "Press ENTER to return to menu"
		result_sub_label.visible = true

	result_label.scale = Vector2(0.3, 0.3)
	var tween := create_tween()
	tween.tween_property(result_label, "scale", Vector2(1.0, 1.0), 0.6)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	if result_sub_label:
		result_sub_label.modulate.a = 0.0
		var sub_tw := create_tween()
		sub_tw.tween_interval(0.8)
		sub_tw.tween_property(result_sub_label, "modulate:a", 1.0, 0.5)

func _add_feed_entry(text: String) -> void:
	if not feed_container:
		return
	var label := Label.new()
	label.text = text
	label.label_settings = _make_label_settings(17, Color(1, 0.35, 0.3))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed_container.add_child(label)
	_feed_entries.append(label)

	label.modulate.a = 0.0
	label.position.x = 50.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.35)
	tween.tween_property(label, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	while _feed_entries.size() > _max_feed_entries:
		var old: Label = _feed_entries.pop_front() as Label
		if is_instance_valid(old):
			old.queue_free()

	var fade_tween := create_tween()
	fade_tween.tween_interval(4.0)
	fade_tween.tween_property(label, "modulate:a", 0.0, 1.0)
	fade_tween.tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
			_feed_entries.erase(label)
	)

func _build_ui() -> void:
	_create_edge_warning()
	_create_mode_badge()
	_create_alive_display()
	_create_timer_display()
	_create_feed()
	_create_countdown()
	_create_result_labels()
	_create_speed_gauge()

func _create_edge_warning() -> void:
	var panel := PanelContainer.new()
	add_child(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.05, 0.0, 0.06)
	sb.border_color = Color(1.0, 0.12, 0.05, 0.95)
	sb.border_width_left = 14
	sb.border_width_right = 14
	sb.border_width_top = 10
	sb.border_width_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	edge_warning = panel

func _create_mode_badge() -> void:
	mode_badge = PanelContainer.new()
	add_child(mode_badge)
	mode_badge.anchor_left = 0.0
	mode_badge.anchor_top = 0.0
	mode_badge.offset_left = 20
	mode_badge.offset_top = 20
	mode_badge.offset_right = 160
	mode_badge.offset_bottom = 58

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.15, 0.1, 0.85)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.border_color = Color(1.0, 0.4, 0.2, 0.6)
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	mode_badge.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	mode_badge.add_child(lbl)
	lbl.text = "SUMO"
	lbl.label_settings = _make_label_settings(22, Color(1, 1, 1))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _create_alive_display() -> void:
	alive_panel = PanelContainer.new()
	add_child(alive_panel)
	alive_panel.anchor_left = 0.5
	alive_panel.anchor_right = 0.5
	alive_panel.anchor_top = 0.0
	alive_panel.offset_left = -90
	alive_panel.offset_right = 90
	alive_panel.offset_top = 16
	alive_panel.offset_bottom = 68

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.1, 0.8)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.border_color = Color(1.0, 0.25, 0.2, 0.7)
	sb.set_border_width_all(2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	alive_panel.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	alive_panel.add_child(hbox)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)

	var alive_text_label := Label.new()
	hbox.add_child(alive_text_label)
	alive_text_label.text = "ALIVE"
	alive_text_label.label_settings = _make_label_settings(16, Color(0.8, 0.8, 0.8, 0.7))
	alive_text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	alive_label = Label.new()
	hbox.add_child(alive_label)
	alive_label.text = "?"
	alive_label.label_settings = _make_label_settings(30, Color(1, 0.9, 0.3))
	alive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	alive_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _create_timer_display() -> void:
	timer_label = Label.new()
	add_child(timer_label)
	timer_label.text = "00:00"
	timer_label.label_settings = _make_label_settings(20, Color(1, 1, 1, 0.6))
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.anchor_left = 0.5
	timer_label.anchor_right = 0.5
	timer_label.offset_left = -50
	timer_label.offset_right = 50
	timer_label.offset_top = 74
	timer_label.offset_bottom = 98

func _create_feed() -> void:
	feed_container = VBoxContainer.new()
	add_child(feed_container)
	feed_container.anchor_left = 1.0
	feed_container.anchor_right = 1.0
	feed_container.offset_left = -380
	feed_container.offset_right = -20
	feed_container.offset_top = 20
	feed_container.offset_bottom = 220
	feed_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed_container.add_theme_constant_override("separation", 6)

func _create_countdown() -> void:
	countdown_label = Label.new()
	add_child(countdown_label)
	countdown_label.anchor_left = 0.5
	countdown_label.anchor_right = 0.5
	countdown_label.anchor_top = 0.5
	countdown_label.anchor_bottom = 0.5
	countdown_label.offset_left = -200
	countdown_label.offset_top = -100
	countdown_label.offset_right = 200
	countdown_label.offset_bottom = 100
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.label_settings = _make_label_settings(100, Color(1, 0.8, 0))
	countdown_label.label_settings.outline_size = 16
	countdown_label.visible = false

func _create_result_labels() -> void:
	result_label = Label.new()
	add_child(result_label)
	result_label.anchor_left = 0.5
	result_label.anchor_right = 0.5
	result_label.anchor_top = 0.35
	result_label.anchor_bottom = 0.35
	result_label.offset_left = -350
	result_label.offset_right = 350
	result_label.offset_top = -50
	result_label.offset_bottom = 50
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.label_settings = _make_label_settings(80, Color(1, 0.85, 0))
	result_label.label_settings.outline_size = 14
	result_label.visible = false

	result_sub_label = Label.new()
	add_child(result_sub_label)
	result_sub_label.anchor_left = 0.5
	result_sub_label.anchor_right = 0.5
	result_sub_label.anchor_top = 0.35
	result_sub_label.anchor_bottom = 0.35
	result_sub_label.offset_left = -300
	result_sub_label.offset_right = 300
	result_sub_label.offset_top = 55
	result_sub_label.offset_bottom = 90
	result_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_sub_label.label_settings = _make_label_settings(20, Color(1, 1, 1, 0.6))
	result_sub_label.visible = false

func _create_speed_gauge() -> void:
	speed_gauge = _SumoSpeedGauge.new()
	add_child(speed_gauge)
	speed_gauge.anchor_left = 1.0
	speed_gauge.anchor_top = 1.0
	speed_gauge.anchor_right = 1.0
	speed_gauge.anchor_bottom = 1.0
	speed_gauge.offset_left = -gauge_size - hud_margin
	speed_gauge.offset_right = -hud_margin
	speed_gauge.offset_top = -gauge_size - hud_margin
	speed_gauge.offset_bottom = -hud_margin
	speed_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	speedometer_label = Label.new()
	speed_gauge.add_child(speedometer_label)
	speedometer_label.text = "0"
	speedometer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speedometer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speedometer_label.label_settings = _make_label_settings(48, Color(1, 1, 1))
	speedometer_label.anchor_left = 0.5
	speedometer_label.anchor_right = 0.5
	speedometer_label.anchor_top = 0.5
	speedometer_label.anchor_bottom = 0.5
	speedometer_label.offset_left = -50
	speedometer_label.offset_right = 50
	speedometer_label.offset_top = -30
	speedometer_label.offset_bottom = 30
	speedometer_label.z_index = 10

	var kmh_label := Label.new()
	speed_gauge.add_child(kmh_label)
	kmh_label.text = "KM/H"
	kmh_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kmh_label.label_settings = _make_label_settings(13, Color(1, 1, 1, 0.55))
	kmh_label.anchor_left = 0.5
	kmh_label.anchor_right = 0.5
	kmh_label.anchor_top = 0.5
	kmh_label.anchor_bottom = 0.5
	kmh_label.offset_left = -30
	kmh_label.offset_right = 30
	kmh_label.offset_top = 22
	kmh_label.offset_bottom = 42

func _format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "00:00"
	var total_s := int(seconds)
	var s := total_s % 60
	@warning_ignore("integer_division")
	var m := total_s / 60
	return "%02d:%02d" % [m, s]

func _ordinal_suffix(n: int) -> String:
	if n % 100 in [11, 12, 13]:
		return "th"
	match n % 10:
		1: return "st"
		2: return "nd"
		3: return "rd"
		_: return "th"

func _make_label_settings(font_size: int, color: Color = Color.WHITE) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = font_size
	s.font_color = color
	s.outline_size = 4
	s.outline_color = Color(0, 0, 0, 0.85)
	return s

class _SumoSpeedGauge:
	extends Control

	var arc_color_start := Color(0.2, 0.8, 0.2, 0.6)
	var arc_color_end := Color(1.0, 0.2, 0.2, 0.8)

	func _draw() -> void:
		var ui = get_parent()
		if ui == null:
			return
		var spd: float = ui.get("current_speed_kmh")
		var max_spd: float = ui.get("gauge_max_kmh")
		if spd == null or max_spd == null:
			return

		var t: float = clamp(spd / max_spd, 0.0, 1.0)
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 10.0

		var start_angle := PI * 0.8
		var end_angle := PI * 2.2
		var total_angle := end_angle - start_angle
		var current_angle := start_angle + (total_angle * t)

		draw_arc(center, radius, start_angle, end_angle, 64, Color(0, 0, 0, 0.5), 18.0, true)

		var points := 40
		var angle_step := total_angle / float(points)
		for i in range(points):
			var a1 := start_angle + (i * angle_step)
			var a2 := start_angle + ((i + 1) * angle_step)
			if a1 > current_angle:
				break
			var progress := float(i) / float(points)
			var col := arc_color_start.lerp(arc_color_end, progress)
			if a2 > current_angle:
				a2 = current_angle
			draw_arc(center, radius, a1, a2, 2, col, 12.0, true)

		var major_ticks := 10
		for i in range(major_ticks + 1):
			var tick_ratio := float(i) / float(major_ticks)
			var ang := start_angle + (total_angle * tick_ratio)
			var dir := Vector2(cos(ang), sin(ang))
			var p1 := center + dir * (radius - 15.0)
			var p2 := center + dir * (radius + 5.0)
			var col := Color.WHITE if tick_ratio <= t else Color(1, 1, 1, 0.3)
			draw_line(p1, p2, col, 3.0, true)
