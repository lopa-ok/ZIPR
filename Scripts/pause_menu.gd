extends CanvasLayer

var _is_paused: bool = false
var _panel: PanelContainer
var _vbox: VBoxContainer
var _title_label: Label
var _overlay: ColorRect
var _buttons: Array[Button] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _is_paused:
			_resume()
		else:
			if _is_main_menu():
				return
			_pause()
		get_viewport().set_input_as_handled()

func _is_main_menu() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return true
	if scene.scene_file_path.contains("Main_menu"):
		return true
	return false

func _pause() -> void:
	if _is_paused:
		return
	_is_paused = true
	get_tree().paused = true
	_build_menu()
	visible = true

func _resume() -> void:
	if not _is_paused:
		return
	_is_paused = false
	get_tree().paused = false
	_clear_menu()
	visible = false

func _clear_menu() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	_panel = null
	_vbox = null
	_title_label = null
	_overlay = null

func _build_menu() -> void:
	_clear_menu()

	_overlay = ColorRect.new()
	add_child(_overlay)
	_overlay.color = Color(0, 0, 0, 0.6)
	_overlay.anchor_left = 0.0
	_overlay.anchor_top = 0.0
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -180
	_panel.offset_right = 180
	_panel.offset_top = -175
	_panel.offset_bottom = 175

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.12, 0.95)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.border_color = Color(1, 1, 1, 0.15)
	sb.set_border_width_all(2)
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	_panel.add_theme_stylebox_override("panel", sb)

	_vbox = VBoxContainer.new()
	_panel.add_child(_vbox)
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_theme_constant_override("separation", 14)

	_title_label = Label.new()
	_vbox.add_child(_title_label)
	_title_label.text = "PAUSED"
	_title_label.label_settings = _make_label_settings(36, Color(1, 1, 1))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	_vbox.add_child(spacer)

	_add_button("Resume", _on_resume_pressed)
	_add_button("Restart", _on_restart_pressed)
	_add_button("Main Menu", _on_main_menu_pressed)
	_add_button("Quit", _on_quit_pressed)

	if _buttons.size() > 0:
		_buttons[0].grab_focus()

func _add_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	_vbox.add_child(btn)
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 44)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.2, 0.24, 0.9)
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.border_color = Color(1, 1, 1, 0.1)
	normal.set_border_width_all(1)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", normal)

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.35, 0.35, 0.4, 0.95)
	hover.corner_radius_top_left = 8
	hover.corner_radius_top_right = 8
	hover.corner_radius_bottom_left = 8
	hover.corner_radius_bottom_right = 8
	hover.border_color = Color(1, 0.8, 0.3, 0.6)
	hover.set_border_width_all(2)
	hover.content_margin_left = 16
	hover.content_margin_right = 16
	hover.content_margin_top = 8
	hover.content_margin_bottom = 8
	btn.add_theme_stylebox_override("hover", hover)

	btn.add_theme_stylebox_override("focus", hover)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.45, 0.4, 0.2, 0.95)
	pressed.corner_radius_top_left = 8
	pressed.corner_radius_top_right = 8
	pressed.corner_radius_bottom_left = 8
	pressed.corner_radius_bottom_right = 8
	pressed.border_color = Color(1, 0.85, 0.0, 0.8)
	pressed.set_border_width_all(2)
	pressed.content_margin_left = 16
	pressed.content_margin_right = 16
	pressed.content_margin_top = 8
	pressed.content_margin_bottom = 8
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	btn.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.4))
	btn.add_theme_color_override("font_pressed_color", Color(1, 0.85, 0.0))
	btn.add_theme_color_override("font_focus_color", Color(1, 0.9, 0.4))

	btn.pressed.connect(callback)
	_buttons.append(btn)

func _on_resume_pressed() -> void:
	_resume()

func _on_restart_pressed() -> void:
	_resume()
	Global.reset_ai_assignments()
	get_tree().reload_current_scene()

func _on_main_menu_pressed() -> void:
	_resume()
	Global.current_game_mode = Global.GameMode.RACE
	Global.reset_ai_assignments()
	get_tree().change_scene_to_file("res://Scenes/Main_menu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _make_label_settings(font_size: int, color: Color = Color.WHITE) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = font_size
	s.font_color = color
	s.outline_size = 4
	s.outline_color = Color(0, 0, 0, 0.8)
	return s
