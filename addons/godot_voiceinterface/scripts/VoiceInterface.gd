extends Node

class_name VoiceInterface

signal voice_command(command)

export(float) var microphone_gain_db = 1.2
export(float) var command_minlen_sec = 0.3

var capture_effect = null

var request

var maxlen_sec = 10.0

var audio_player

var audio_buffer = PoolByteArray()
var audio_buffer_pos = 0

var endpoint
var is_ssl = true
var host = "api.wit.ai"
var port = 443
var token 
var target_rate = 16000
var actual_rate = AudioServer.get_mix_rate()

var interface_enabled = false

func _ready():
	#TODO: Load the token from the server, do not store it in the app
	if "game/witai/token" in ProjectSettings:
		token = ProjectSettings.get("game/witai/token") 
	
	if "game/witai/endpoint" in ProjectSettings:
		endpoint = ProjectSettings.get("game/witai/endpoint")
	
	audio_buffer.resize(2*target_rate*maxlen_sec)
	
	var current_number = 0
	while AudioServer.get_bus_index("VoiceMicRecorder" + str(current_number)) != -1:
		current_number += 1

	var bus_name = "VoiceMicRecorder" + str(current_number)
	var record_bus_idx = AudioServer.bus_count

	AudioServer.add_bus(record_bus_idx)
	AudioServer.set_bus_name(record_bus_idx, bus_name)

	capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(record_bus_idx, capture_effect)

	AudioServer.set_bus_mute(record_bus_idx, true)

	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.bus = bus_name
	
func activate_voice_commands(value):
	interface_enabled = value
	if value:
		if audio_player.stream == null:
			audio_player.stream = AudioStreamMicrophone.new()
		capture_effect.clear_buffer()
		audio_player.play()
	else:	
		if audio_player.playing:
			audio_player.stop()

		audio_player.stream = null
	
var sending = false	
func _process(delta):
	if capture_effect and sending:
		var data: PoolVector2Array = capture_effect.get_buffer(capture_effect.get_frames_available())
		var sample_skip = actual_rate/target_rate 
		var samples = ceil(float(data.size())/sample_skip)

		if data.size() > 0:
			var max_value = 0.0
			var min_value = 0.0
			var idx = 0
			var buffer_len = data.size()
			var target_idx = 0
		
			while idx < buffer_len:
				var val =  (data[int(idx)].x + data[int(idx)].y)/2.0
				var val_discreet = int( clamp( val * 32768, -32768, 32768))

				audio_buffer[2*audio_buffer_pos] = 0xFF & (val_discreet >> 8)
				audio_buffer[2*audio_buffer_pos+1] = 0xFF & val_discreet

				idx += sample_skip
				audio_buffer_pos = min(audio_buffer_pos+1, audio_buffer.size()/2-1)
		
func start_voice_command():
	if not sending and interface_enabled:
		print ("Reading sound")
		sending = true
		audio_buffer_pos = 0
		
func end_voice_command():
	if sending:
		print ("Finish reading sound")
		sending = false
		
		if audio_buffer_pos / target_rate > command_minlen_sec:
			#Only process audio if there is enough speech
			#Prevent spurious calls	
		
			var audio_content = audio_buffer.subarray(0,audio_buffer_pos*2)
					
			request = HTTPRequest.new()
			add_child(request)
			request.connect("request_completed",self,"_http_request_completed")
			
			var error = request.request_raw("https://%s:%d%s"%[host,port,endpoint], ["Authorization: Bearer %s"%token, "Content-type: audio/raw;encoding=signed-integer;bits=16;rate=%d;endian=big"%target_rate], true, HTTPClient.METHOD_POST, audio_content)
			if error != OK:
				push_error("An error occurred in the HTTP request.")

# Called when the HTTP request is completed.
func _http_request_completed(result, response_code, headers, body):
	if response_code == 200:
		var data = fix_chunked_response(body.get_string_from_utf8())

		print ("Data received: %s"%data)
		var response = parse_json(data)
		var selected_intent = ""
		var selected_score = 0.0
		for r in response:
			var intents = r.get("intents",Array())
			for i in intents:
				if i["confidence"] > selected_score:
					selected_score = i["confidence"]
					selected_intent = i["name"]
		if selected_intent:
			print ("Command is: %s"%selected_intent)
			emit_signal("voice_command",selected_intent)	
			
		print("Response: %s"%data)

#I have to rant about that. We don't understand chunks so 
#we have to fix it with a dirty hack
func fix_chunked_response(data):
	var tmp = data.replace("}\r\n{","},\n{")
	return ("[%s]"%tmp)



