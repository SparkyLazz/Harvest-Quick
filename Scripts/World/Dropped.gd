class_name Dropped
extends Node2D

## An item lying in the field, waiting to be walked over.
##
## Breaking something no longer puts its drops in the satchel. They are
## thrown out of it, land nearby, and come to the player when the player
## comes near — because a tree that fills your bag from across the field
## never looks like it was felled, it looks like a number going up.
##
## Three things happen to it in order, and each finishes before the next
## begins: it is thrown, it lies there, and it is drawn in. The order is a
## state rather than a chain of tweens because the middle one has no end —
## an item can lie in the grass all day — and because the player can walk
## away halfway through being near it.
##
## The arc is kept apart from the position. [member Node2D.position] is where
## the item is *on the ground* and never leaves it; the hop is the sprite
## moving up and down above that point. Anything else would break the y-sort
## it shares with the player, and an item thrown past someone's head would
## draw in front of them on the way up and behind them on the way down.
##
## It can always be dropped and never be lost. A satchel with no room simply
## does not take it, and it goes back to lying there until there is room —
## which is why nothing needs to ask whether a thing may be broken any more.

## Emitted when it goes in, with what went and how many.
signal collected(item: ItemData, count: int)

## How it is behaving.
enum Phase {
	THROWN, ## In the air, on its way out of whatever produced it.
	LYING, ## On the ground, waiting.
	DRAWN, ## On its way to the player.
}

## The most separate pieces one drop is broken into. A handful of wood
## reading as a handful is worth a few nodes; ninety-nine carrots reading as
## ninety-nine is worth nothing and costs ninety-nine.
const MAX_PIECES: int = 6

## What it is, and how many of it.
var item: ItemData
var count: int = 1

@export_group("Throw")
## How fast it leaves, along the ground, in pixels a second.
@export var throw_speed: float = 26.0
## How hard it is thrown upwards.
@export var throw_lift: float = 46.0
## How quickly the hop is pulled back down.
@export var gravity: float = 240.0
## How much of the fall is given back on landing. Zero lands dead.
@export var bounce: float = 0.34
## How quickly it stops sliding once thrown.
@export var drag: float = 3.4

@export_group("Pickup")
## How near the player comes before it starts travelling to them.
@export var magnet_range: float = 24.0
## How near it gets before it goes in.
@export var reach: float = 6.0
## How fast it sets off towards the player.
@export var draw_speed: float = 30.0
## How fast it is allowed to travel. Above the player's run, or a running
## player would outpace their own harvest.
@export var draw_top_speed: float = 145.0
## How quickly it works up to that.
@export var draw_accel: float = 500.0
## How quickly it can turn, in pixels a second squared.
##
## This is what stops it circling. Sideways speed dies at this rate, so it
## is spent within roughly draw_top_speed squared over this many pixels —
## about nine at these numbers, comfortably inside [member magnet_range].
## Much lower and the item starts rounding the player instead of reaching
## them.
@export var draw_turn: float = 2400.0
## Seconds it must lie still before it may be picked up. Without this an
## item thrown at the player's feet is gone before it is seen to be thrown,
## and breaking something looks like nothing happening.
@export var settle_time: float = 0.3
## Seconds before a drop the satchel had no room for tries again.
@export var retry_time: float = 0.8

@export_group("Look")
## How big the icon is drawn. Item icons are 32 across and a tile is 16, so
## a drop at this scale is about half a tile.
@export var icon_scale: float = 0.4
## How far it bobs while lying, in pixels.
@export var bob: float = 1.2
## Seconds for one bob.
@export var bob_period: float = 1.6

@onready var sprite: Sprite2D = $Sprite

var _phase: Phase = Phase.THROWN
## How far the sprite is above its ground point, and how fast that is
## changing. The hop, kept out of [member Node2D.position] so the y-sort is
## never told the item is somewhere it is not.
var _height: float = 0.0
var _rise: float = 0.0
## How fast it is sliding across the ground.
var _slide: Vector2 = Vector2.ZERO
## How fast it is allowed to be going while it travels in. Ramps up from
## [member draw_speed]; kept apart from [member _slide] so that speeding up
## and changing direction are two separate things.
var _speed: float = 0.0
## Seconds since it landed.
var _lain: float = 0.0
## How long to wait before trying the satchel again, after it was full.
var _wait: float = 0.0
var _age: float = 0.0
var _player: Node2D

## Throws [param count] of [param item] out of [param at], in pieces.
##
## Static, and takes the parent it should hang on, for the same reason
## [method Emote.pop] does: the thing producing the drop is usually being
## destroyed in the same breath, and a drop parented to it would be destroyed
## with it. The parent wanted is the world layer.
static func scatter(parent: Node, at: Vector2, item: ItemData, count: int) -> Array:
	var out: Array = []
	if parent == null or item == null or count <= 0:
		return out
	var scene := load("res://Scenes/World/Dropped.tscn") as PackedScene
	if scene == null:
		return out

	var pieces: int = mini(count, MAX_PIECES)
	for i in pieces:
		var node := scene.instantiate() as Dropped
		if node == null:
			continue
		# The remainder rides on the first few pieces rather than the last,
		# so a pile of five split three ways is 2,2,1 and never 1,1,3.
		node.item = item
		node.count = count / pieces + (1 if i < count % pieces else 0)
		parent.add_child(node)
		node.global_position = at
		node.fling(TAU * float(i) / float(pieces) + randf() * 0.6)
		out.append(node)
	return out

func _ready() -> void:
	_refresh()
	# Drawn above the ground it lies on but still sorted with everything
	# else in the layer, so an item in front of the player covers their feet
	# and one behind them does not.
	_apply_height()

func _process(delta: float) -> void:
	_age += delta
	match _phase:
		Phase.THROWN:
			_fly(delta)
		Phase.LYING:
			_lie(delta)
		Phase.DRAWN:
			_travel(delta)

## Throws it off in [param angle], with the hop that goes with it.
func fling(angle: float) -> void:
	_slide = Vector2.RIGHT.rotated(angle) * throw_speed
	# Flattened vertically, so the spray reads as spreading across the
	# ground rather than as a ring drawn on the wall behind it.
	_slide.y *= 0.5
	_rise = throw_lift
	_height = 1.0
	_phase = Phase.THROWN

## Puts it straight on the ground where it is, for a drop that should not
## appear to have been thrown anywhere.
func lay() -> void:
	_slide = Vector2.ZERO
	_rise = 0.0
	_height = 0.0
	_lain = 0.0
	_phase = Phase.LYING

func _fly(delta: float) -> void:
	position += _slide * delta
	_slide = _slide.move_toward(Vector2.ZERO, drag * _slide.length() * delta)
	_rise -= gravity * delta
	_height += _rise * delta
	if _height > 0.0:
		_apply_height()
		return
	# Landed. One small bounce makes it read as a thing with weight; below
	# that it is noise, so it is cut off rather than converging forever.
	_height = 0.0
	if bounce > 0.0 and _rise < -40.0:
		_rise = -_rise * bounce
		_apply_height()
		return
	_rise = 0.0
	_lain = 0.0
	_phase = Phase.LYING
	_apply_height()

func _lie(delta: float) -> void:
	_lain += delta
	_wait = maxf(_wait - delta, 0.0)
	_height = bob * 0.5 * (1.0 - cos(TAU * _age / maxf(bob_period, 0.01)))
	_apply_height()
	if _lain < settle_time or _wait > 0.0:
		return
	var player := _find_player()
	if player == null:
		return
	if global_position.distance_to(player.global_position) <= magnet_range:
		_slide = Vector2.ZERO
		_speed = draw_speed
		_phase = Phase.DRAWN

func _travel(delta: float) -> void:
	var player := _find_player()
	if player == null:
		_phase = Phase.LYING
		return
	# Aimed at the middle of the player rather than their feet, so the item
	# disappears into them rather than into the ground they stand on.
	var target: Vector2 = player.global_position + Vector2(0.0, -7.0)
	var to := target - global_position
	_speed = minf(_speed + draw_accel * delta, draw_top_speed)
	var step := _speed * delta

	# Arrived — counting a step that would carry it straight through. At
	# this speed one frame covers more ground than [member reach], so asking
	# only whether it is near enough lets the item pass clean through the
	# player and come out the far side with its speed intact.
	if to.length() <= maxf(reach, step):
		_take()
		return

	# Steered towards the player, not merely pulled. Adding a pull to
	# whatever the item was already doing leaves the sideways part of its
	# motion alone, and sideways motion around a central pull is an orbit —
	# which is what this did around a running player: it lapped them until
	# they stopped. Turning the velocity itself spends that sideways speed
	# instead of preserving it.
	_slide = _slide.move_toward(to.normalized() * _speed, draw_turn * delta)
	position += _slide * delta
	# The hop is given up on the way in, so it arrives at the height it is
	# aimed at rather than bobbing through the player.
	_height = move_toward(_height, 0.0, 40.0 * delta)
	_apply_height()

## Tries to put it in the satchel. What does not fit stays on the ground.
func _take() -> void:
	var left := Inventory.add(item, count)
	if left >= count:
		# No room at all. Back to lying there, and do not pester the satchel
		# every frame about it.
		_wait = retry_time
		_lain = 0.0
		_phase = Phase.LYING
		return
	collected.emit(item, count - left)
	if left <= 0:
		queue_free()
		return
	# Part of it went. Keep the rest and wait.
	count = left
	_refresh()
	_wait = retry_time
	_lain = 0.0
	_phase = Phase.LYING

func _refresh() -> void:
	if sprite == null:
		sprite = get_node_or_null("Sprite") as Sprite2D
	if sprite == null or item == null:
		return
	sprite.texture = item.icon
	sprite.scale = Vector2.ONE * icon_scale

func _apply_height() -> void:
	if sprite != null:
		sprite.position.y = -_height

func _find_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player
