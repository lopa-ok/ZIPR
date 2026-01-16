extends CanvasLayer

@export var car_path: NodePath

var car: VehicleBody3D
var race_manager: Node

var speedometer_label: Label
var speed_unit_label: Label
var speed_panel: PanelContainer

var speed_gauge: Control
var current_speed_kmh: float = 0.0
var gauge_max_kmh: float = 120.0

var hud_margin: int = 18
var gauge_size: int = 240

var powerup_panel: PanelContainer
var powerup_icon: TextureRect
var powerup_label: Label

var powerup_icon_map: Dictionary[String, String] = {
	"speed_boost": "res://images/godotwaka.png",
	"oil": "res://images/godotwaka2.png",
	"water_balloon": "res://images/icon.jpg",
}

var lap_time_label: Label
var best_lap_label: Label
var position_label: Label
var gap_label: Label
var countdown_label: Label

func _ready():
	car = _resolve_car()

	if car != null:
		var ai: Variant = car.get("is_ai_controlled")
		if ai is bool and ai:
			visible = false
			return
		if car.has_method("has_ai_control") and bool(car.call("has_ai_control")):
			visible = false
			return

	race_manager = get_tree().get_first_node_in_group("race_manager")
	visible = true
	create_hud()

func _resolve_car() -> VehicleBody3D:
	if car_path != NodePath(""):
		var n: Node = get_node_or_null(car_path)
		if n is VehicleBody3D:
			return n

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

func _process(_delta):
	if not visible:
		if speed_gauge:
			speed_gauge.visible = false
		if speed_panel:
			speed_panel.visible = false
		if powerup_panel:
			powerup_panel.visible = false
		return

	if speed_gauge:
		speed_gauge.visible = true
	if speed_panel:
		speed_panel.visible = true

	if car == null:
		car = _resolve_car()
		if car == null:
			return

	var speed: float = 0.0
	if car.has_method("get_speed"):
		speed = float(car.call("get_speed"))
	else:
		speed = float(car.linear_velocity.length())
	current_speed_kmh = speed * 3.6
	if speedometer_label:
		speedometer_label.text = "%02d" % int(clamp(current_speed_kmh, 0.0, 99.0))
	if speed_gauge:
		speed_gauge.queue_redraw()

	if powerup_label:
		var has_pu: bool = false
		var pu_id: String = ""
		var hp: Variant = car.get("has_powerup")
		if hp is bool and hp:
			has_pu = true
			pu_id = String(car.get("current_powerup"))

		if has_pu:
			powerup_label.text = pu_id.capitalize().replace("_", " ")
			powerup_panel.visible = powerup_label.text.strip_edges() != ""

			if powerup_icon:
				var path: String = powerup_icon_map.get(pu_id, "")
				powerup_icon.texture = load(path) if path != "" else null
				powerup_icon.visible = powerup_icon.texture != null
		else:
			powerup_label.text = ""
			powerup_panel.visible = false
			if powerup_icon:
				powerup_icon.texture = null
				powerup_icon.visible = false

	if countdown_label and race_manager.has_method("get_countdown_text"):
		var txt: String = race_manager.call("get_countdown_text")
		countdown_label.text = txt
		countdown_label.visible = txt != ""
		if txt != "":
			var t = race_manager.countdown_timer if "countdown_timer" in race_manager else 0.0
			var frac = t - floor(t)
			var s = 1.0 + frac * 0.5
			if txt == "GO!": s = 1.0
			countdown_label.scale = Vector2(s, s)
			countdown_label.pivot_offset = countdown_label.size / 2

	_update_race_hud()

func _format_time(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--.--"
	var total_ms: int = int(seconds * 1000.0)
	var ms: int = total_ms % 1000
	var total_s: int = total_ms / 1000
	var s: int = total_s % 60
	var m: int = total_s / 60
	return "%02d:%02d.%02d" % [m, s, int(ms / 10)]

func _update_race_hud() -> void:
	if race_manager == null or car == null:
		return
	if not race_manager.has_method("get_lap_time"):
		return

	var lap_t: float = float(race_manager.call("get_lap_time", car))
	var best_t: float = float(race_manager.call("get_best_lap_time", car))
	var lap_num: int = int(race_manager.call("get_current_lap", car)) if race_manager.has_method("get_current_lap") else 1
	var pos: int = int(race_manager.call("get_position", car)) if race_manager.has_method("get_position") else 1
	var gap_m: float = float(race_manager.call("get_gap_to_ahead_meters", car)) if race_manager.has_method("get_gap_to_ahead_meters") else 0.0

	if lap_time_label:
		lap_time_label.text = "LAP %d  %s" % [lap_num, _format_time(lap_t)]
	if best_lap_label:
		best_lap_label.text = "BEST   %s" % _format_time(best_t)
	if position_label:
		position_label.text = "POS    %d" % pos
	if gap_label:
		gap_label.text = "GAP    %.0fm" % gap_m if pos > 1 else "GAP    --"

func _make_pixel_label(font_size: int, color: Color = Color(1, 1, 1)) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = font_size
	s.font_color = color
	s.font = load("res://pixel_font.tres")
	s.outline_size = 2
	s.outline_color = Color(0, 0, 0, 0.85)
	return s

func create_hud():
	speed_gauge = _SpeedGauge.new()
	add_child(speed_gauge)
	speed_gauge.anchor_left = 1.0
	speed_gauge.anchor_top = 1.0
	speed_gauge.anchor_right = 1.0
	speed_gauge.anchor_bottom = 1.0
	speed_gauge.offset_left = -float(gauge_size) - float(hud_margin)
	speed_gauge.offset_right = -float(hud_margin)
	speed_gauge.offset_top = -float(gauge_size) - float(hud_margin)
	speed_gauge.offset_bottom = -float(hud_margin)
	speed_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	speed_panel = PanelContainer.new()
	add_child(speed_panel)
	speed_panel.anchor_left = 1.0
	speed_panel.anchor_top = 1.0
	speed_panel.anchor_right = 1.0
	speed_panel.anchor_bottom = 1.0

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(0)
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_bottom_right = 0
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	speed_panel.add_theme_stylebox_override("panel", sb)

	speed_panel.offset_left = -float(hud_margin) - 88.0
	speed_panel.offset_right = -float(hud_margin)
	speed_panel.offset_top = -float(hud_margin) - 92.0
	speed_panel.offset_bottom = -float(hud_margin)

	var speed_vbox := VBoxContainer.new()
	speed_panel.add_child(speed_vbox)
	speed_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	speed_vbox.add_theme_constant_override("separation", -8)

	speedometer_label = Label.new()
	speed_vbox.add_child(speedometer_label)
	speedometer_label.text = "00"
	speedometer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speedometer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speedometer_label.label_settings = _make_pixel_label(58, Color(1, 1, 1))

	speed_unit_label = null

	powerup_panel = PanelContainer.new()
	add_child(powerup_panel)
	powerup_panel.visible = false
	powerup_panel.anchor_left = 0.5
	powerup_panel.anchor_top = 0.0
	powerup_panel.anchor_right = 0.5
	powerup_panel.anchor_bottom = 0.0
	powerup_panel.offset_left = -180
	powerup_panel.offset_right = 180
	powerup_panel.offset_top = 12
	powerup_panel.offset_bottom = 58

	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0.40)
	sb2.border_color = Color(1, 1, 1, 0.28)
	sb2.set_border_width_all(2)
	sb2.corner_radius_top_left = 6
	sb2.corner_radius_top_right = 6
	sb2.corner_radius_bottom_left = 6
	sb2.corner_radius_bottom_right = 6
	sb2.content_margin_left = 10
	sb2.content_margin_right = 10
	sb2.content_margin_top = 6
	sb2.content_margin_bottom = 6
	powerup_panel.add_theme_stylebox_override("panel", sb2)

	var pbox := HBoxContainer.new()
	powerup_panel.add_child(pbox)
	pbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pbox.add_theme_constant_override("separation", 8)

	powerup_icon = TextureRect.new()
	pbox.add_child(powerup_icon)
	powerup_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	powerup_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	powerup_icon.custom_minimum_size = Vector2(32, 32)
	powerup_icon.visible = false

	powerup_label = Label.new()
	pbox.add_child(powerup_label)
	powerup_label.text = ""
	powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	powerup_label.label_settings = _make_pixel_label(24, Color(1, 1, 1))

	var race_panel := VBoxContainer.new()
	add_child(race_panel)
	race_panel.anchor_left = 0.0
	race_panel.anchor_top = 0.0
	race_panel.anchor_right = 0.0
	race_panel.anchor_bottom = 0.0
	race_panel.offset_left = 18
	race_panel.offset_top = 18
	race_panel.offset_right = 260
	race_panel.offset_bottom = 130
	race_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	race_panel.add_theme_constant_override("separation", 2)

	lap_time_label = Label.new()
	race_panel.add_child(lap_time_label)
	lap_time_label.label_settings = _make_pixel_label(20, Color(1, 1, 1))
	lap_time_label.text = "LAP 1  00:00.00"

	best_lap_label = Label.new()
	race_panel.add_child(best_lap_label)
	best_lap_label.label_settings = _make_pixel_label(20, Color(1, 1, 1, 0.9))
	best_lap_label.text = "BEST   --:--.--"

	position_label = Label.new()
	race_panel.add_child(position_label)
	position_label.label_settings = _make_pixel_label(20, Color(1, 1, 1, 0.9))
	position_label.text = "POS    1"

	gap_label = Label.new()
	race_panel.add_child(gap_label)
	gap_label.label_settings = _make_pixel_label(20, Color(1, 1, 1, 0.9))
	gap_label.text = "GAP    --"

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
	countdown_label.text = ""
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	countdown_label.label_settings = _make_pixel_label(96, Color(1, 1, 0))
	countdown_label.label_settings.outline_size = 12
	countdown_label.label_settings.outline_color = Color(0,0,0)

class _SpeedGauge:
	extends Control

	var y_squish: float = 0.78

	func _point_on_ellipse(center: Vector2, radius: float, angle: float) -> Vector2:
		var rx: float = radius
		var ry: float = radius * y_squish
		return center + Vector2(cos(angle) * rx, sin(angle) * ry)

	func _draw_elliptic_arc(center: Vector2, r: float, start_a: float, end_a: float, steps: int, col: Color, width: float) -> void:
		var last: Vector2 = _point_on_ellipse(center, r, start_a)
		for j: int in range(1, steps + 1):
			var tt: float = float(j) / float(steps)
			var a: float = lerpf(start_a, end_a, tt)
			var p: Vector2 = _point_on_ellipse(center, r, a)
			draw_line(last, p, col, width, true)
			last = p

	func _draw() -> void:
		var ui := get_parent() as CanvasLayer
		if ui == null:
			return

		var kmh: float = ui.current_speed_kmh
		var max_kmh: float = max(1.0, ui.gauge_max_kmh)
		var t: float = clamp(kmh / max_kmh, 0.0, 1.0)

		var rect: Rect2 = Rect2(Vector2.ZERO, size)
		var center: Vector2 = rect.size
		var radius: float = minf(rect.size.x, rect.size.y) - 16.0

		var a0: float = PI
		var a1: float = 1.5 * PI
		var ap: float = lerpf(a0, a1, t)

		var base_arc: Color = Color(1, 1, 1, 0.12)
		var base_arc_inner: Color = Color(1, 1, 1, 0.18)
		var fill_arc: Color = Color(1, 1, 1, 0.78)
		var glow: Color = Color(1, 1, 1, 0.18)
		var major_col: Color = Color(1, 1, 1, 0.52)
		var minor_col: Color = Color(1, 1, 1, 0.22)

		var steps: int = 72

		_draw_elliptic_arc(center, radius, a0, a1, steps, base_arc, 7.0)
		_draw_elliptic_arc(center, radius - 8.0, a0, a1, steps, base_arc_inner, 5.0)

		_draw_elliptic_arc(center, radius, a0, ap, steps, glow, 12.0)
		_draw_elliptic_arc(center, radius, a0, ap, steps, fill_arc, 7.0)
		_draw_elliptic_arc(center, radius - 8.0, a0, ap, steps, fill_arc, 5.0)

		var majors: int = 10
		var minors_per_major: int = 4
		var total: int = majors * minors_per_major
		var rx: float = radius
		var ry: float = radius * y_squish
		for i: int in range(total + 1):
			var tt: float = float(i) / float(total)
			var a: float = lerpf(a0, a1, tt)
			var is_major: bool = (i % minors_per_major) == 0

			var line_len: float = 16.0 if is_major else 9.0
			var w: float = 3.0 if is_major else 2.0
			var col: Color = major_col if is_major else minor_col
			if tt <= t:
				col = Color(1, 1, 1, 0.88) if is_major else Color(1, 1, 1, 0.62)

			var p_edge: Vector2 = center + Vector2(cos(a) * rx, sin(a) * ry)
			var n: Vector2 = Vector2((p_edge.x - center.x) / (rx * rx), (p_edge.y - center.y) / (ry * ry)).normalized()

			var p1: Vector2 = p_edge - n * 6.0
			var p2: Vector2 = p1 - n * line_len
			draw_line(p1, p2, col, w, true)
