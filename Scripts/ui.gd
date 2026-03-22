extends CanvasLayer

@export var car_path: NodePath
@export var turn_signal_sheet: Texture
@export var turn_signal_textures: Dictionary = {}

var car: VehicleBody3D
var race_manager: Node

var speedometer_label: Label
var speed_unit_label: Label
var speed_panel: PanelContainer
var speed_gauge: Control

var powerup_panel: PanelContainer
var powerup_icon: TextureRect
var powerup_label: Label

var lap_time_label: Label
var best_lap_label: Label
var position_label: Label
var gap_label: Label
var countdown_label: Label

var turn_signal_icon: TextureRect

var current_speed_kmh: float = 0.0
var gauge_max_kmh: float = 120.0
var hud_margin: int = 24
var gauge_size: int = 260

var _cached_car_has_speed_method: bool = false
var _cached_mgr_has_lap_time: bool = false
var _cached_mgr_has_best_lap: bool = false
var _cached_mgr_has_pos: bool = false
var _cached_mgr_has_gap: bool = false
var _cached_mgr_has_countdown: bool = false

var powerup_icon_map: Dictionary[String, String] = {
	"speed_boost": "res://images/godotwaka.png",
	"oil": "res://images/godotwaka2.png",
	"water_balloon": "res://images/icon.jpg",
}

var turn_signal_regions := {
	"turn": Rect2(0, 0, 64, 64),
	"u_turn": Rect2(64, 0, 64, 64),
	"snake": Rect2(128, 0, 64, 64),
	"both": Rect2(192, 0, 64, 64),
	"go": Rect2(256, 0, 64, 64),
}

var _roulette_active: bool = false
var _roulette_timer: float = 0.0
var _roulette_duration: float = 1.2
var _roulette_icons: Array = ["speed_boost", "oil", "water_balloon"]
var _roulette_index: int = 0
var _roulette_final: String = ""

func _enter_tree():
	if Global.current_game_mode == Global.GameMode.SUMO:
		visible = false
		queue_free()
		return
	if get_tree().get_first_node_in_group("sumo_manager") != null:
		visible = false
		queue_free()
		return
	var existing = get_tree().get_nodes_in_group("race_hud")
	if existing.size() > 0:
		visible = false
		queue_free()
		return
	add_to_group("race_hud")

func _ready():
	if Global.current_game_mode == Global.GameMode.SUMO:
		visible = false
		return
	if get_tree().get_first_node_in_group("sumo_manager") != null:
		visible = false
		return

	car = _resolve_car()

	if car != null:
		var ai: Variant = car.get("is_ai_controlled")
		if ai is bool and ai:
			queue_free()
			return
		if car.has_method("has_ai_control") and bool(car.call("has_ai_control")):
			queue_free()
			return
		_cached_car_has_speed_method = car.has_method("get_speed")

	race_manager = get_tree().get_first_node_in_group("race_manager")
	if race_manager:
		_cached_mgr_has_lap_time = race_manager.has_method("get_lap_time")
		_cached_mgr_has_best_lap = race_manager.has_method("get_best_lap_time")
		_cached_mgr_has_pos = race_manager.has_method("get_position")
		_cached_mgr_has_gap = race_manager.has_method("get_gap_to_ahead_meters")
		_cached_mgr_has_countdown = race_manager.has_method("get_countdown_text")

	visible = true
	_build_ui()

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

func _process(delta):
	if not visible:
		return

	if car == null:
		car = _resolve_car()
		if car == null:
			return
		_cached_car_has_speed_method = car.has_method("get_speed")

	var car_speed: float = 0.0
	if _cached_car_has_speed_method:
		car_speed = float(car.call("get_speed"))
	else:
		car_speed = float(car.linear_velocity.length())
	
	current_speed_kmh = lerpf(current_speed_kmh, car_speed * 3.6, 0.1)
	
	if speedometer_label:
		speedometer_label.text = "%02d" % int(clamp(current_speed_kmh, 0.0, 999.0))
	if speed_gauge:
		speed_gauge.queue_redraw()

	_update_powerup_ui()
	_update_countdown_ui()
	_update_race_stats_ui()

	if _roulette_active:
		_roulette_timer += delta
		var t = clamp(_roulette_timer / _roulette_duration, 0, 1)
		var speed = lerp(0.08, 0.25, t)
		if int(_roulette_timer / speed) != _roulette_index:
			_roulette_index = int(_roulette_timer / speed)
			var idx = _roulette_index % _roulette_icons.size()
			var pu_id = _roulette_icons[idx]
			powerup_icon.texture = load(powerup_icon_map.get(pu_id, ""))
			powerup_label.text = pu_id.capitalize().replace("_", " ")
		if _roulette_timer >= _roulette_duration:
			_roulette_active = false
			powerup_icon.texture = load(powerup_icon_map.get(_roulette_final, ""))
			powerup_label.text = _roulette_final.capitalize().replace("_", " ")

func _update_powerup_ui():
	if not powerup_label: return
	
	var has_pu: bool = false
	var pu_id: String = ""
	var hp: Variant = car.get("has_powerup")
	
	if hp is bool and hp:
		has_pu = true
		pu_id = String(car.get("current_powerup"))

	if has_pu:
		powerup_label.text = pu_id.capitalize().replace("_", " ")
		powerup_panel.visible = powerup_label.text.strip_edges() != ""
		powerup_panel.modulate.a = lerpf(powerup_panel.modulate.a, 1.0, 0.1)

		if powerup_icon:
			var path: String = powerup_icon_map.get(pu_id, "")
			if powerup_icon.texture == null or powerup_icon.texture.resource_path != path:
				powerup_icon.texture = load(path) if path != "" else null
			powerup_icon.visible = powerup_icon.texture != null
	else:
		powerup_panel.modulate.a = lerpf(powerup_panel.modulate.a, 0.0, 0.2)
		if powerup_panel.modulate.a < 0.05:
			powerup_label.text = ""
			powerup_panel.visible = false

func _update_countdown_ui():
	if not countdown_label or not race_manager: return

	if _cached_mgr_has_countdown:
		var txt: String = race_manager.call("get_countdown_text")
		if txt.is_valid_float():
			txt = str(int(txt.to_float()))
		countdown_label.text = txt
		countdown_label.visible = txt != ""
		if txt != "":
			var t = race_manager.countdown_timer if "countdown_timer" in race_manager else 0.0
			var frac = t - floor(t)
			var s = 1.0 + frac * 0.3
			if txt == "GO!": s = 1.5 - (frac * 0.5)
			countdown_label.scale = Vector2(s, s)
			countdown_label.pivot_offset = countdown_label.size / 2

func _update_race_stats_ui():
	if not race_manager or not car: return
	if not _cached_mgr_has_lap_time: return

	var lap_t: float = float(race_manager.call("get_lap_time", car))
	var best_t: float = 0.0
	if _cached_mgr_has_best_lap:
		best_t = float(race_manager.call("get_best_lap_time", car))
	
	var lap_num: int = 1
	if race_manager.has_method("get_current_lap"):
		lap_num = int(race_manager.call("get_current_lap", car))
	
	var pos: int = 1
	if _cached_mgr_has_pos:
		pos = int(race_manager.call("get_position", car))
	
	var gap_m: float = 0.0
	if _cached_mgr_has_gap:
		gap_m = float(race_manager.call("get_gap_to_ahead_meters", car))

	if lap_time_label:
		lap_time_label.text = "LAP %d  %s" % [lap_num, _format_time(lap_t)]
	if best_lap_label:
		best_lap_label.text = "BEST   %s" % _format_time(best_t)
	if position_label:
		position_label.text = "POS    %d" % pos
	if gap_label:
		gap_label.text = "GAP    %.0fm" % gap_m if pos > 1 else "GAP    --"

func _format_time(seconds: float) -> String:
	if seconds < 0.0: return "--:--.--"
	var total_ms: int = int(seconds * 1000.0)
	var ms: int = total_ms % 1000
	var total_s: int = total_ms / 1000
	var s: int = total_s % 60
	var m: int = total_s / 60
	return "%02d:%02d.%02d" % [m, s, int(ms / 10)]

func _make_label_settings(font_size: int, color: Color = Color.WHITE) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = font_size
	s.font_color = color
	s.outline_size = 4
	s.outline_color = Color(0, 0, 0, 0.8)
	return s

func _build_ui():
	_create_gauge()
	_create_speed_readout()
	_create_powerup_panel()
	_create_stats_panel()
	_create_countdown()

func _create_gauge():
	speed_gauge = _SpeedGauge.new()
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
	speedometer_label.text = "00"
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

func _create_speed_readout():
	speed_panel = PanelContainer.new()
	add_child(speed_panel)
	speed_panel.anchor_left = 1.0
	speed_panel.anchor_top = 1.0
	speed_panel.anchor_right = 1.0
	speed_panel.anchor_bottom = 1.0
	
	var sb := StyleBoxEmpty.new()
	speed_panel.add_theme_stylebox_override("panel", sb)
	
	speed_panel.offset_left = -hud_margin - 120.0
	speed_panel.offset_right = -hud_margin - 10
	speed_panel.offset_top = -hud_margin - 80.0
	speed_panel.offset_bottom = -hud_margin - 10

	var vbox := VBoxContainer.new()
	speed_panel.add_child(vbox)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var kmh := Label.new()
	vbox.add_child(kmh)
	kmh.text = "KM/H"
	kmh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kmh.label_settings = _make_label_settings(14, Color(1, 1, 1, 0.7))

func _create_powerup_panel():
	powerup_panel = PanelContainer.new()
	add_child(powerup_panel)
	powerup_panel.visible = false
	powerup_panel.anchor_left = 1.0
	powerup_panel.anchor_right = 1.0
	powerup_panel.anchor_top = 0.0
	powerup_panel.anchor_bottom = 0.0
	powerup_panel.offset_left = -320
	powerup_panel.offset_right = -20
	powerup_panel.offset_top = 20
	powerup_panel.offset_bottom = 100

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.border_color = Color(1, 1, 1, 0.4)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	powerup_panel.add_theme_stylebox_override("panel", sb)

	var hbox := HBoxContainer.new()
	powerup_panel.add_child(hbox)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)

	powerup_icon = TextureRect.new()
	hbox.add_child(powerup_icon)
	powerup_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	powerup_icon.custom_minimum_size = Vector2(48, 48)
	powerup_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	powerup_label = Label.new()
	hbox.add_child(powerup_label)
	powerup_label.label_settings = _make_label_settings(22)

func _create_stats_panel():
	var panel := VBoxContainer.new()
	add_child(panel)
	panel.offset_left = 20
	panel.offset_top = 20
	panel.offset_right = 300
	panel.offset_bottom = 150
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var stats_font_size = 24
	var stats_color = Color(1, 1, 1)
	var stats_settings = _make_label_settings(stats_font_size, stats_color)

	lap_time_label = Label.new()
	panel.add_child(lap_time_label)
	lap_time_label.label_settings = stats_settings

	best_lap_label = Label.new()
	panel.add_child(best_lap_label)
	best_lap_label.label_settings = stats_settings

	position_label = Label.new()
	panel.add_child(position_label)
	position_label.label_settings = stats_settings

	gap_label = Label.new()
	panel.add_child(gap_label)
	gap_label.label_settings = stats_settings

func _create_countdown():
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

func show_turn_signal(signal_type: String, is_left: bool = false):
	if not turn_signal_icon:
		turn_signal_icon = TextureRect.new()
		add_child(turn_signal_icon)
		turn_signal_icon.anchor_left = 0.5
		turn_signal_icon.anchor_right = 0.5
		turn_signal_icon.anchor_top = 0.5
		turn_signal_icon.anchor_bottom = 0.5
		turn_signal_icon.offset_left = -64
		turn_signal_icon.offset_top = -64
		turn_signal_icon.offset_right = 64
		turn_signal_icon.offset_bottom = 64
		turn_signal_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		turn_signal_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		turn_signal_icon.z_index = 100
		turn_signal_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex = turn_signal_textures.get(signal_type, null)
	if tex == null:
		tex = turn_signal_sheet
	turn_signal_icon.texture = tex

	if tex is AtlasTexture:
		turn_signal_icon.region_enabled = true
		turn_signal_icon.region_rect = turn_signal_regions.get(signal_type, Rect2(0,0,64,64))
	else:
		turn_signal_icon.region_enabled = false

	turn_signal_icon.flip_h = is_left
	turn_signal_icon.visible = true

func show_turn_signal_with_texture(signal_type: String, is_left: bool, custom_texture: Texture):
	if not turn_signal_icon:
		turn_signal_icon = TextureRect.new()
		add_child(turn_signal_icon)
		turn_signal_icon.anchor_left = 0.5
		turn_signal_icon.anchor_right = 0.5
		turn_signal_icon.anchor_top = 0.5
		turn_signal_icon.anchor_bottom = 0.5
		turn_signal_icon.offset_left = -64
		turn_signal_icon.offset_top = -64
		turn_signal_icon.offset_right = 64
		turn_signal_icon.offset_bottom = 64
		turn_signal_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		turn_signal_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		turn_signal_icon.z_index = 100
		turn_signal_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex = custom_texture if custom_texture else turn_signal_textures.get(signal_type, null)
	if tex == null:
		tex = turn_signal_sheet
	turn_signal_icon.texture = tex

	if tex is AtlasTexture:
		turn_signal_icon.region_enabled = true
		turn_signal_icon.region_rect = turn_signal_regions.get(signal_type, Rect2(0,0,64,64))
	else:
		turn_signal_icon.region_enabled = false

	turn_signal_icon.flip_h = is_left
	turn_signal_icon.visible = true

func hide_turn_signal():
	if turn_signal_icon:
		turn_signal_icon.visible = false

class _SpeedGauge:
	extends Control

	var arc_color_start := Color(0.2, 0.8, 0.2, 0.6)
	var arc_color_end := Color(1.0, 0.2, 0.2, 0.8)

	func _draw() -> void:
		var ui := get_parent() as CanvasLayer
		if ui == null: return

		var t: float = clamp(ui.current_speed_kmh / ui.gauge_max_kmh, 0.0, 1.0)
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
			
			if a1 > current_angle: break
			
			var progress := float(i) / float(points)
			var col := arc_color_start.lerp(arc_color_end, progress)
			
			if a2 > current_angle: a2 = current_angle
			draw_arc(center, radius, a1, a2, 2, col, 12.0, true)

		var major_ticks := 10
		for i in range(major_ticks + 1):
			var tr := float(i) / float(major_ticks)
			var ang := start_angle + (total_angle * tr)
			var dir := Vector2(cos(ang), sin(ang))
			var p1 := center + dir * (radius - 15.0)
			var p2 := center + dir * (radius + 5.0)
			var col := Color.WHITE if tr <= t else Color(1, 1, 1, 0.3)
			draw_line(p1, p2, col, 3.0, true)

func start_powerup_roulette(final_powerup: String):
	_roulette_active = true
	_roulette_timer = 0.0
	_roulette_final = final_powerup
	powerup_panel.visible = true
