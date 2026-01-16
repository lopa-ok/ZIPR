extends Node

enum MenuState { MAIN, LEVEL_SELECT, OPTIONS }

@export_category("References")
@export var anim_player: AnimationPlayer
@export var start_label: Label3D
@export var options_label: Label3D
@export var quit_label: Label3D

@export_category("Level Selection")
@export var level_1_label: Label3D
@export var level_2_label: Label3D
@export var level_3_label: Label3D

@export_category("Options Menu")
@export var fullscreen_label: Label3D
@export var vsync_label: Label3D
@export var back_options_label: Label3D

@export_category("Configuration")
@export var start_animation_name: String = "start_game"
@export var options_animation_name: String = "options_menu"
@export var level_1_scene: String = "res://Scenes/World.tscn"
@export var level_2_scene: String = "res://Scenes/World.tscn"
@export var level_3_scene: String = "res://Scenes/World.tscn"

@export_category("Visuals")
@export var selected_color: Color = Color.YELLOW
@export var normal_color: Color = Color.WHITE
@export var normal_scale: Vector3 = Vector3(1.0, 1.0, 1.0)
@export var hover_scale: Vector3 = Vector3(1.1, 1.1, 1.1)
@export var arrow_text: String = "> "

var _state: MenuState = MenuState.MAIN
var _labels: Array[Label3D] = []
var _original_texts: Dictionary = {}
var _current_selection: int = 0

func _ready() -> void:
	_labels = [start_label, options_label, quit_label]
	
	var all_interactive_labels = [
		start_label, options_label, quit_label,
		level_1_label, level_2_label, level_3_label,
		fullscreen_label, vsync_label, back_options_label
	]
	
	for label in all_interactive_labels:
		if label:
			_original_texts[label] = label.text

	_set_labels_visible([start_label, options_label, quit_label], true)
	_set_labels_visible([level_1_label, level_2_label, level_3_label], false)
	_set_labels_visible([fullscreen_label, vsync_label, back_options_label], false)
	
	_update_visuals()
	
	if anim_player:
		anim_player.animation_finished.connect(_on_animation_finished)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_down"):
		_navigate(1)
	elif event.is_action_pressed("ui_up"):
		_navigate(-1)
	elif event.is_action_pressed("ui_accept"):
		_confirm_selection()
	elif event.is_action_pressed("ui_cancel"):
		if _state == MenuState.LEVEL_SELECT:
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

func _update_visuals() -> void:
	for i in range(_labels.size()):
		var label = _labels[i]
		if not label: continue
		
		var original_text = _original_texts.get(label, "")
		
		if i == _current_selection:
			label.modulate = selected_color
			label.scale = hover_scale
			label.text = arrow_text + original_text
		else:
			label.modulate = normal_color
			label.scale = normal_scale
			label.text = original_text

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
	elif _state == MenuState.OPTIONS:
		match _current_selection:
			0: _toggle_fullscreen()
			1: _toggle_vsync()
			2: _return_from_options()

func _start_game() -> void:
	_state = MenuState.LEVEL_SELECT
	_labels = [level_1_label, level_2_label, level_3_label]
	_current_selection = 0
	_update_visuals()
	
	_set_labels_visible(_labels, true)
	
	if anim_player and anim_player.has_animation(start_animation_name):
		anim_player.play(start_animation_name)
	else:
		_on_animation_finished(start_animation_name)

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
		if _state == MenuState.LEVEL_SELECT:
			_set_labels_visible([start_label, options_label, quit_label], false)
		elif _state == MenuState.MAIN:
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
		get_tree().change_scene_to_file(scene_path)

func _toggle_fullscreen() -> void:
	var mode = DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _toggle_vsync() -> void:
	var mode = DisplayServer.window_get_vsync_mode()
	if mode == DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
