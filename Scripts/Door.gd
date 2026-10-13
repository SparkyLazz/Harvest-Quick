class_name Door
extends Area2D

## A doorway you walk into. Touching it hands over to SceneTransition, which
## fades out, swaps scenes and fades back in. There is no key to press: walking
## into the door is the whole interaction.
##
## `spawn_point` names a Marker2D in the destination to stand the player on, so
## a pair of doors pointing at each other's markers makes a round trip.

## Where walking in leads.
@export_file("*.tscn") var target_scene: String = ""
## Marker2D in the destination to arrive on. Empty leaves the player wherever
## the destination scene already puts them.
@export var spawn_point: StringName = &""

var _armed := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# You arrive standing in the door you just came out of, so a door starts
	# disarmed while the player is inside it and only wakes once they step off.
	# Without this, coming back through would send you straight back again.
	await get_tree().physics_frame
	_armed = _player_inside() == null


func _on_body_entered(body: Node2D) -> void:
	# The tilemaps are bodies on the same layer, so the type check is what picks
	# the player out rather than the collision mask.
	if not _armed or not (body is Player):
		return
	if target_scene.is_empty():
		push_warning("Door '%s' has no target scene." % name)
		return
	_armed = false
	SceneTransition.go_to(target_scene, spawn_point)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_armed = true


func _player_inside() -> Player:
	for body in get_overlapping_bodies():
		if body is Player:
			return body
	return null
