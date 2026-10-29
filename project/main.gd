extends Control

@onready var voicebox: Control = %Voicebox


func _on_always_voice_toggled(on: bool) -> void:
	if voicebox.synth:
		voicebox.synth.always_voice = on


func _on_pitch_wobble_toggled(on: bool) -> void:
	if voicebox.synth:
		voicebox.synth.auto_wobble = on
