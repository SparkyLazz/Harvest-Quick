class_name EmoteBubble
extends Node2D

## A little cat-face reaction that pops up over the player: a check when a seed
## goes in, sparkles on a harvest, a sweat drop on hard work, a "?" when an
## action does nothing and a sleepy Z when out of stamina. Cut from the pack's
## emoji sheet, 32px cells.

const SHEET := preload("res://Assets/UI/Emoji.png")
const CELL := 32

## Emote name -> (column, row) on the sheet.
const EMOTES := {
	"sweat": Vector2i(1, 4),
	"happy": Vector2i(0, 3),
	"check": Vector2i(6, 2),
	"sparkle": Vector2i(6, 5),
	"tired": Vector2i(9, 3),
	"question": Vector2i(9, 2),
}

@export_group("Look")
## Where the bubble rests, relative to the player's feet, in world pixels:
## centred over the head.
@export var rest_offset: Vector2 = Vector2(0, -27)
## Size of the bubble. The art is 32px; 0.5 brings it down to a 16px badge.
@export_range(0.25, 1.0, 0.25) var bubble_scale: float = 0.5

@export_group("Timing")
## Seconds the pop-in takes.
@export_range(0.05, 1.0, 0.05) var pop_time: float = 0.22
## Seconds the bubble stays up.
@export_range(0.1, 5.0, 0.1) var hold_time: float = 0.8
## Seconds the float-and-fade at the end takes.
@export_range(0.05, 2.0, 0.05) var fade_time: float = 0.3
## How far the bubble drifts up while fading, in world pixels.
@export_range(0.0, 16.0, 1.0) var drift: float = 5.0

var _sprite: Sprite2D
var _atlas := AtlasTexture.new()
var _tween: Tween

func _ready() -> void:
	z_index = 20
	position = rest_offset
	_atlas.atlas = SHEET
	_sprite = Sprite2D.new()
	_sprite.texture = _atlas
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.visible = false
	add_child(_sprite)


## Shows an emote by name, replacing any still on screen. Unknown names are ignored.
func show_emote(emote: String) -> void:
	if not EMOTES.has(emote):
		return
	var cell: Vector2i = EMOTES[emote]
	_atlas.region = Rect2(cell.x * CELL, cell.y * CELL, CELL, CELL)
	if _tween and _tween.is_valid():
		_tween.kill()
	_sprite.visible = true
	_sprite.modulate.a = 1.0
	_sprite.position = Vector2.ZERO
	_sprite.scale = Vector2.ZERO
	_tween = create_tween()
	# TRANS_BACK overshoots on the way in, so the bubble pops rather than slides.
	_tween.tween_property(_sprite, "scale", Vector2.ONE * bubble_scale, pop_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_interval(hold_time)
	_tween.tween_property(_sprite, "modulate:a", 0.0, fade_time)
	_tween.parallel().tween_property(_sprite, "position:y", -drift, fade_time)
	_tween.tween_callback(func() -> void: _sprite.visible = false)
