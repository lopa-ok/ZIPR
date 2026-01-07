extends CanvasLayer

var car: VehicleBody3D
var speedometer_label: Label

func _ready():
	car = get_parent()
	create_speedometer()

func _process(_delta):
	if speedometer_label and car:
		var speed = car.get_speed()
		var speed_kmh = speed * 3.6
		speedometer_label.text = "%03d" % int(speed_kmh)
		var powerup_label = speedometer_label.get_parent().get_node("PowerupLabel")
		if car.has_powerup:
			powerup_label.text = car.current_powerup.capitalize()
		else:
			powerup_label.text = ""

func create_speedometer():
	var vbox = VBoxContainer.new()
	add_child(vbox)
	vbox.anchor_left = 1.0
	vbox.anchor_top = 1.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = -200
	vbox.offset_top = -120
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	vbox.size_flags_vertical = Control.SIZE_SHRINK_END
	vbox.custom_minimum_size = Vector2(180, 90)
	vbox.grow_horizontal = Control.GROW_DIRECTION_END
	vbox.grow_vertical = Control.GROW_DIRECTION_END

	speedometer_label = Label.new()
	vbox.add_child(speedometer_label)
	speedometer_label.text = "000"
	speedometer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speedometer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speedometer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speedometer_label.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var label_settings = LabelSettings.new()
	label_settings.font_size = 48
	label_settings.font_color = Color(1, 1, 1)
	label_settings.font = load("res://pixel_font.tres")
	speedometer_label.label_settings = label_settings

	var powerup_label = Label.new()
	vbox.add_child(powerup_label)
	powerup_label.name = "PowerupLabel"
	powerup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	powerup_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	powerup_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	powerup_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var powerup_settings = LabelSettings.new()
	powerup_settings.font_size = 24
	powerup_settings.font_color = Color(1, 1, 1)
	powerup_settings.font = load("res://pixel_font.tres")
	powerup_label.label_settings = powerup_settings
