extends Node3D

@onready var anim_player = $AnimationPlayer
var attack_anims = ["attack", "attack1"]

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if not anim_player.is_playing():
			var chosen_attack = attack_anims[randi() % attack_anims.size()]
			anim_player.play(chosen_attack)
