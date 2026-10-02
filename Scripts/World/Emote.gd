class_name Emote
extends Sprite2D

## A little picture that pops above something and goes away again.
##
## Nothing in the world needs to own one of these. It is spawned, it plays,
## and it frees itself, so the thing that had something to say does not have
## to remember having said it — which matters for crops, because a harvested
## plant is gone the same frame its emote appears and would otherwise take
## the emote down with it.
##
## It draws over everything by z-index rather than by sorting, because it is
## a thing being *said* rather than a thing standing in the field: an emote
## disappearing behind the plant it belongs to would only ever be a bug.
##
## The pictures are cells of the emoji sheet already used for item icons, so
## a new one is a rectangle and nothing else.

## Where the emoji sheet keeps the things worth saying about a farm.
##
## Verified cell by cell against Emoji_Spritesheet.png, which is ten columns of
## 32-pixel cells: row 8 is the symbols, 9 the hearts, 10 the stars and coins,
## 11 the thumbs, 24 the tools. Counting these rows by eye off the whole sheet
## is how they get shifted by one, so they were sampled rather than looked at.
const CHECK := Rect2(0, 256, 32, 32)
const CROSS := Rect2(64, 256, 32, 32)
const BANG := Rect2(160, 256, 32, 32)
const QUERY := Rect2(192, 256, 32, 32)
const NOTE := Rect2(224, 256, 32, 32)
const HEARTS_PINK := Rect2(0, 288, 32, 32)
const HEARTS_GREEN := Rect2(96, 288, 32, 32)
const HEARTS_BLUE := Rect2(192, 288, 32, 32)
const STAR := Rect2(0, 320, 32, 32)
const COIN := Rect2(192, 320, 32, 32)
const MONEY := Rect2(256, 320, 32, 32)
const THUMB_UP := Rect2(0, 352, 32, 32)
const THUMB_DOWN := Rect2(96, 352, 32, 32)
const DROPLET := Rect2(224, 768, 32, 32)

## How big the 32-pixel cell is drawn. Half, so it reads as a remark over a
## sixteen-pixel plant rather than as scenery in its own right.
@export var rest_scale: float = 0.5

@export_group("Motion")
## Seconds for the pop.
@export var rise_time: float = 0.2
## Seconds it hangs there.
@export var hold_time: float = 0.35
## Seconds to fade.
@export var fade_time: float = 0.28
## How far it climbs while popping, in pixels.
@export var rise: float = 7.0
## How far it drifts on while fading.
@export var drift: float = 5.0
## How far past its size it swells before settling. 1.0 is no overshoot.
@export var overshoot: float = 1.25

## Spawns one over [param at] and plays it. [param parent] is whatever should
## hold it for the second it exists — the world layer, usually, rather than
## the thing emoting, so that thing is free to be removed.
static func pop(parent: Node, at: Vector2, region: Rect2) -> Emote:
	if parent == null:
		return null
	var scene := load("res://Scenes/World/Emote.tscn") as PackedScene
	if scene == null:
		return null
	var emote := scene.instantiate() as Emote
	if emote == null:
		return null
	parent.add_child(emote)
	emote.global_position = at
	emote.show_region(region)
	emote.play()
	return emote

## Points it at [param region] of the sheet.
func show_region(region: Rect2) -> void:
	var atlas := texture as AtlasTexture
	if atlas != null:
		atlas.region = region

## Pops, hangs, fades, and frees itself.
##
## Parallel and sequential steps are switched explicitly rather than chained,
## because chaining out of a parallel group does not sequence the way it
## reads and the final step never ran — the emote hung in the field forever.
## Freeing hangs off [signal Tween.finished] rather than a last step, so it
## happens whatever the steps in front of it do.
func play() -> void:
	scale = Vector2.ONE * rest_scale * 0.4
	modulate.a = 0.0
	var start := position

	var tween := create_tween()

	# Up, swelling past its size, brightening as it goes.
	tween.set_parallel(true)
	(tween.tween_property(self, "scale", Vector2.ONE * rest_scale * overshoot, rise_time)
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	(tween.tween_property(self, "position:y", start.y - rise, rise_time)
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	# Alpha eases plainly; a springy curve would overshoot past opaque.
	tween.tween_property(self, "modulate:a", 1.0, rise_time * 0.6).set_trans(Tween.TRANS_SINE)

	# Settling back from the overshoot is what sells it as cheerful.
	tween.set_parallel(false)
	(tween.tween_property(self, "scale", Vector2.ONE * rest_scale, rise_time * 0.5)
		.set_trans(Tween.TRANS_SINE))

	tween.tween_interval(hold_time)

	# The fade leads, and the drift joins it.
	tween.tween_property(self, "modulate:a", 0.0, fade_time).set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	(tween.tween_property(self, "position:y", start.y - rise - drift, fade_time)
		.set_trans(Tween.TRANS_SINE))

	tween.finished.connect(queue_free)
