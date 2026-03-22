extends Node

enum MenuState { MAIN, LEVEL_SELECT, CAR_SELECT, OPTIONS }

@export_category("References")
@export var anim_player: AnimationPlayer
@export var start_label: Label3D
@export var options_label: Label3D
@export var quit_label: Label3D

@export_category("Level Selection")
@export var level_1_label: Label3D
@export var level_2_label: Label3D
@export var level_3_label: Label3D

@export_category("Car Selection")
@export var car_1_label: Label3D
@export var car_2_label: Label3D
@export var car_3_label: Label3D
@export var car_4_label: Label3D
@export var car_5_label: Label3D
@export var car_6_label: Label3D
@export var car_1_model: Node3D
@export var car_2_model: Node3D
@export var car_3_model: Node3D
@export var car_4_model: Node3D
@export var car_5_model: Node3D
@export var car_6_model: Node3D
@export var car_rotation_speed: float = 1.0
@export var car_display_marker: Marker3D
@export var box_start_offset: Vector3 = Vector3(-5, 0, 0)
@export var box_enter_duration: float = 0.5
@export var car_1_anim_name: String = "open"
@export var car_2_anim_name: String = "open"
@export var car_3_anim_name: String = "open"
@export var car_4_anim_name: String = "open"
@export var car_5_anim_name: String = "open"
@export var car_6_anim_name: String = "open"

@export_category("Options Menu")
@export var fullscreen_label: Label3D
@export var vsync_label: Label3D
@export var back_options_label: Label3D

@export_category("Configuration")
@export var start_animation_name: String = "start_game"
@export var car_to_level_animation_name: String = "car_to_level"
@export var options_animation_name: String = "options_menu"
@export var level_1_scene: String = "res://Scenes/World.tscn"
@export var level_2_scene: String = "res://Scenes/World_Supermarket.tscn"
@export var level_3_scene: String = "res://Scenes/World_Fight.tscn"

@export_category("Visuals")
@export var selected_color: Color = Color.YELLOW
@export var normal_color: Color = Color.WHITE
@export var normal_scale: Vector3 = Vector3(1.0, 1.0, 1.0)
@export var hover_scale: Vector3 = Vector3(1.1, 1.1, 1.1)
@export var arrow_text: String = "> "

@export var menu_move_sfx: String = "res://resources/models/Music/Step.mp3"
@export var menu_anim_sfx: String = "res://resources/models/Music/Step2.mp3"

var _state: MenuState = MenuState.MAIN
var _labels: Array[Label3D] = []
var _original_texts: Dictionary = {}
var _current_selection: int = 0
var _pending_level_scene: String = ""

func _ready() -> void:
	_labels = [start_label, options_label, quit_label]
	
	var all_interactive_labels = [
		start_label, options_label, quit_label,
		level_1_label, level_2_label, level_3_label,
		car_1_label, car_2_label, car_3_label, car_4_label, car_5_label, car_6_label,
		fullscreen_label, vsync_label, back_options_label
	]
	
	if car_1_label and Global.car_stats.has(0): car_1_label.text = Global.car_stats[0]["name"]
	if car_2_label and Global.car_stats.has(1): car_2_label.text = Global.car_stats[1]["name"]
	if car_3_label and Global.car_stats.has(2): car_3_label.text = Global.car_stats[2]["name"]
	if car_4_label and Global.car_stats.has(3): car_4_label.text = Global.car_stats[3]["name"]
	if car_5_label and Global.car_stats.has(4): car_5_label.text = Global.car_stats[4]["name"]
	if car_6_label and Global.car_stats.has(5): car_6_label.text = Global.car_stats[5]["name"]

	_set_labels_visible([start_label, options_label, quit_label], true)

	for label in all_interactive_labels:
		if label:
			_original_texts[label] = label.text

	_set_labels_visible([start_label, options_label, quit_label], true)
	_set_labels_visible([level_1_label, level_2_label, level_3_label], false)
	_set_labels_visible([car_1_label, car_2_label, car_3_label, car_4_label, car_5_label, car_6_label], false)
	_set_labels_visible([fullscreen_label, vsync_label, back_options_label], false)
	
	if fullscreen_label:
		var mode = DisplayServer.window_get_mode()
		fullscreen_label.text = "Fullscreen: ON" if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else "Fullscreen: OFF"
	
	if vsync_label:
		var mode = DisplayServer.window_get_vsync_mode()
		vsync_label.text = "VSync: ON" if mode == DisplayServer.VSYNC_ENABLED else "VSync: OFF"

	_update_visuals()
	
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

func _process(delta: float) -> void:
	if _state == MenuState.CAR_SELECT:
		var models = [car_1_model, car_2_model, car_3_model, car_4_model, car_5_model, car_6_model]
		if _current_selection >= 0 and _current_selection < models.size():
			var m = models[_current_selection]
			if m and m.visible:
				m.rotate_y(car_rotation_speed * delta)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_navigate(1)
	elif event.is_action_pressed("ui_up"):
		_navigate(-1)
	elif event.is_action_pressed("ui_accept"):
		_confirm_selection()
	elif event.is_action_pressed("ui_cancel"):
		if _state == MenuState.LEVEL_SELECT:
			_return_to_car_select()
		elif _state == MenuState.CAR_SELECT:
			_return_to_main_menu()
		elif _state == MenuState.OPTIONS:
			_return_from_options()

func _navigate(direction: int) -> void:
	_current_selection += direction
	
	if _current_selection >= _labels.size():
		_current_selection = 0
	elif _current_selection < 0:
		_current_selection = _labels.size() - 1
		
	_update_visuals()
	
	if SoundManager and menu_move_sfx:
		SoundManager.play_sfx(menu_move_sfx, 0.0, 1.0)
	
	if _state == MenuState.CAR_SELECT:
		var models = [car_1_model, car_2_model, car_3_model, car_4_model, car_5_model, car_6_model]
		var anims = [car_1_anim_name, car_2_anim_name, car_3_anim_name, car_4_anim_name, car_5_anim_name, car_6_anim_name]
		
		if _current_selection >= 0 and _current_selection < models.size():
			var m = models[_current_selection]
			if m:
				_animate_car_entry(m, anims[_current_selection])

func _update_visuals() -> void:
	for i in range(_labels.size()):
		var label = _labels[i]
		if not label: continue
		
		if not _original_texts.has(label):
			_original_texts[label] = label.text
			
		var original_text = _original_texts[label]
		
		if i == _current_selection:
			label.modulate = selected_color
			label.scale = hover_scale
			label.text = arrow_text + original_text
		else:
			label.modulate = normal_color
			label.scale = normal_scale
			label.text = original_text

	if _state == MenuState.CAR_SELECT:
		var models = [car_1_model, car_2_model, car_3_model, car_4_model, car_5_model, car_6_model]
		for i in range(models.size()):
			if models[i]:
				models[i].visible = (i == _current_selection)
	else:
		var models = [car_1_model, car_2_model, car_3_model, car_4_model, car_5_model, car_6_model]
		for m in models:
			if m: m.visible = false

func _play_node_anim(node: Node, anim_name: String) -> void:
	var anim = node.get_node_or_null("AnimationPlayer")
	if anim and anim.has_animation(anim_name):
		anim.play(anim_name)

func _animate_car_entry(model: Node3D, anim_name: String) -> void:
	var models = [car_1_model, car_2_model, car_3_model, car_4_model, car_5_model, car_6_model]
	for m in models:
		if m and m != model:
			m.visible = false
	
	if not model: return
	model.visible = true
	
	if car_display_marker:
		model.global_position = car_display_marker.global_position + box_start_offset
		model.global_rotation = car_display_marker.global_rotation
		
		var tween = create_tween()
		tween.tween_property(model, "global_position", car_display_marker.global_position, box_enter_duration)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		tween.tween_callback(func(): _play_node_anim(model, anim_name))
	else:
		_play_node_anim(model, anim_name)
	
	if SoundManager and menu_anim_sfx:
		SoundManager.play_sfx(menu_anim_sfx, 0.0, 1.0)

func _confirm_selection() -> void:
	if _state == MenuState.MAIN:
		match _current_selection:
			0: _start_game()
			1: _open_options()
			2: _quit_game()
	elif _state == MenuState.LEVEL_SELECT:
		match _current_selection:
			0: _load_level(level_1_scene)
			1: _load_level(level_2_scene)
			2: _load_level(level_3_scene)
	elif _state == MenuState.CAR_SELECT:
		match _current_selection:
			0: _confirm_car_selection(0)
			1: _confirm_car_selection(1)
			2: _confirm_car_selection(2)
			3: _confirm_car_selection(3)
			4: _confirm_car_selection(4)
			5: _confirm_car_selection(5)
	elif _state == MenuState.OPTIONS:
		match _current_selection:
			0: _toggle_fullscreen()
			1: _toggle_vsync()
			2: _return_from_options()

func _start_game() -> void:
	_state = MenuState.CAR_SELECT
	_labels = [car_1_label, car_2_label, car_3_label, car_4_label, car_5_label, car_6_label]
	_current_selection = 0
	_update_visuals()
	
	_set_labels_visible(_labels, true)
	
	if car_1_model:
		_animate_car_entry(car_1_model, car_1_anim_name)
	
	if anim_player and anim_player.has_animation(start_animation_name):
		anim_player.play(start_animation_name)
	else:
		_on_animation_finished(start_animation_name)

func _enter_level_select() -> void:
	_state = MenuState.LEVEL_SELECT
	_labels = [level_1_label, level_2_label, level_3_label]
	_current_selection = 0
	_update_visuals()
	
	_set_labels_visible(_labels, true)
	
	if anim_player and anim_player.has_animation(car_to_level_animation_name):
		anim_player.play(car_to_level_animation_name)
	else:
		_on_animation_finished(car_to_level_animation_name)

func _confirm_car_selection(car_id: int) -> void:
	Global.selected_car_id = car_id
	_enter_level_select()

func _return_to_car_select() -> void:
	_state = MenuState.CAR_SELECT
	_labels = [car_1_label, car_2_label, car_3_label, car_4_label, car_5_label, car_6_label]
	_current_selection = 0
	_update_visuals()
	
	_set_labels_visible(_labels, true)
	
	var models = [car_1_model, car_2_model, car_3_model, car_4_model, car_5_model, car_6_model]
	var anims = [car_1_anim_name, car_2_anim_name, car_3_anim_name, car_4_anim_name, car_5_anim_name, car_6_anim_name]
	
	if _current_selection >= 0 and _current_selection < models.size():
		if models[_current_selection]:
			_animate_car_entry(models[_current_selection], anims[_current_selection])
	
	if anim_player and anim_player.has_animation(car_to_level_animation_name):
		anim_player.play_backwards(car_to_level_animation_name)
	else:
		_on_animation_finished(car_to_level_animation_name)

func _open_options() -> void:
	_state = MenuState.OPTIONS
	_labels = [fullscreen_label, vsync_label, back_options_label]
	_current_selection = 0
	_update_visuals()
	
	_set_labels_visible(_labels, true)
	
	if anim_player and anim_player.has_animation(options_animation_name):
		anim_player.play(options_animation_name)
	else:
		_on_animation_finished(options_animation_name)

func _quit_game() -> void:
	get_tree().quit()

func _on_animation_finished(anim_name: String) -> void:
	if anim_name == start_animation_name:
		if _state == MenuState.CAR_SELECT:
			_set_labels_visible([start_label, options_label, quit_label], false)
		elif _state == MenuState.MAIN:
			_set_labels_visible([car_1_label, car_2_label, car_3_label, car_4_label, car_5_label, car_6_label], false)
			_set_labels_visible([level_1_label, level_2_label, level_3_label], false)
	elif anim_name == car_to_level_animation_name:
		if _state == MenuState.LEVEL_SELECT:
			_set_labels_visible([car_1_label, car_2_label, car_3_label, car_4_label, car_5_label, car_6_label], false)
		elif _state == MenuState.CAR_SELECT:
			_set_labels_visible([level_1_label, level_2_label, level_3_label], false)
	elif anim_name == options_animation_name:
		if _state == MenuState.OPTIONS:
			_set_labels_visible([start_label, options_label, quit_label], false)
		elif _state == MenuState.MAIN:
			_set_labels_visible([fullscreen_label, vsync_label, back_options_label], false)

func _return_to_main_menu() -> void:
	_state = MenuState.MAIN
	_labels = [start_label, options_label, quit_label]
	_current_selection = 0
	_update_visuals()
	
	_set_labels_visible(_labels, true)
	
	if anim_player and anim_player.has_animation(start_animation_name):
		anim_player.play_backwards(start_animation_name)
	else:
		_on_animation_finished(start_animation_name)

func _return_from_options() -> void:
	_state = MenuState.MAIN
	_labels = [start_label, options_label, quit_label]
	_current_selection = 0
	_update_visuals()
	
	_set_labels_visible(_labels, true)
	
	if anim_player and anim_player.has_animation(options_animation_name):
		anim_player.play_backwards(options_animation_name)
	else:
		_on_animation_finished(options_animation_name)

func _set_labels_visible(labels: Array[Label3D], is_visible: bool) -> void:
	for label in labels:
		if label:
			label.visible = is_visible

func _load_level(scene_path: String) -> void:
	if scene_path != "":
		if scene_path == level_3_scene and scene_path.contains("Fight"):
			Global.current_game_mode = Global.GameMode.SUMO
		else:
			Global.current_game_mode = Global.GameMode.RACE
		get_tree().change_scene_to_file(scene_path)

func _toggle_fullscreen() -> void:
	var mode = DisplayServer.window_get_mode()
	var new_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		new_mode = DisplayServer.WINDOW_MODE_WINDOWED
	
	DisplayServer.window_set_mode(new_mode)
	if fullscreen_label:
		fullscreen_label.text = "Fullscreen: ON" if new_mode == DisplayServer.WINDOW_MODE_FULLSCREEN else "Fullscreen: OFF"
		if _original_texts.has(fullscreen_label):
			_original_texts[fullscreen_label] = fullscreen_label.text
		_update_visuals()

func _toggle_vsync() -> void:
	var mode = DisplayServer.window_get_vsync_mode()
	var new_mode = DisplayServer.VSYNC_ENABLED
	if mode == DisplayServer.VSYNC_ENABLED:
		new_mode = DisplayServer.VSYNC_DISABLED

	DisplayServer.window_set_vsync_mode(new_mode)
	if vsync_label:
		vsync_label.text = "VSync: ON" if new_mode == DisplayServer.VSYNC_ENABLED else "VSync: OFF"
		if _original_texts.has(vsync_label):
			_original_texts[vsync_label] = vsync_label.text
		_update_visuals()
