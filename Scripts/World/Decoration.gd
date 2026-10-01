class_name Decoration
extends Placed

## A piece of scenery: a tuft of grass, a stone, a bush, a lily pad.
##
## A [Placed] with its picture taken from a sheet rather than drawn into its
## own scene, because there are a hundred of these and they differ only by a
## rectangle. One scene serves them all, and a kind of decoration is a
## resource with a region in it.
##
## Most of it is walkable. A tuft of grass the player cannot step on would be
## a worse farm than one with no grass in it, so [member solid] is off unless
## the thing is big enough that walking through it would look wrong.
##
## Being a [Placed] is what makes scenery part of the map rather than paint
## on top of it: [WorldObjects] adopts these at load, so a bush occupies its
## tile, a chest cannot be dropped on it, and a tool swung at it is offered
## to it like anything else.

@onready var sprite: Sprite2D = $Sprite

## Whether the player is stopped by it.
@export var solid: bool = false:
	set(value):
		solid = value
		_apply_solid()

func _ready() -> void:
	_apply_solid()

## Points it at [param region] of [param sheet], and stands it so the bottom
## of the art sits on the bottom of its tile.
##
## Scenery is drawn from the ground up: a tree is tall and a pebble is not,
## but both have their feet on the same line. Anchoring to the bottom means a
## kind of decoration only has to say how big its picture is, never where to
## hang it.
func show_art(sheet: Texture2D, region: Rect2) -> void:
	if sprite == null:
		sprite = get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	sprite.texture = sheet
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.centered = false
	# The node stands on the bottom edge of its tile, so the art hangs up and
	# left from there, centred across whatever width it has.
	sprite.offset = Vector2(-region.size.x * 0.5, -region.size.y)

func _apply_solid() -> void:
	var shape := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null:
		shape.disabled = not solid
