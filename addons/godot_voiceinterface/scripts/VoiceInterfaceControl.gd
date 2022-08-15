extends Control


export (NodePath) var voice_interface_api
var _interface = null

var input_active = false

var first_activation = -1
var activation_delay_ms = 250

func _ready():
	_interface = get_node(voice_interface_api)
	if _interface:
		_interface.activate_voice_commands(true)

func _process(delta):
	if first_activation > 0 and not input_active:
		var now = OS.get_ticks_msec()
		if now > first_activation + activation_delay_ms:
			input_active = true
			if _interface:
				print ("Actually activating voice command")
				_interface.start_voice_command()

func input_start():
	if not input_active:
		print ("Try to start voice command")
		var now = OS.get_ticks_msec()
		if first_activation < 0:
			first_activation = now
			
	return true

func input_end():
	first_activation = -1
	if input_active:
		print ("End voice command")

		input_active = false
		if _interface:
			 _interface.end_voice_command()
	return true
