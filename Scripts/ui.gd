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
		speedometer_label.text = "%d KM/H" % int(speed_kmh)

func create_speedometer():
	var panel = PanelContainer.new()
	add_child(panel)
	panel.position = Vector2(20, 20)
	
	var margin = MarginContainer.new()
	panel.add_child(margin)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	
	speedometer_label = Label.new()
	margin.add_child(speedometer_label)
	speedometer_label.text = "0 KM/H"
	
	var label_settings = LabelSettings.new()
	label_settings.font_size = 32
	label_settings.font_color = Color.WHITE
	label_settings.outline_size = 4
	label_settings.outline_color = Color.BLACK
	speedometer_label.label_settings = label_settings
