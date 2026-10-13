class_name InteractPrompt
extends Node2D

## The little "E Open" sign that appears over whatever furniture you are facing.
##
## It sits over the thing, not over the player, so two wardrobes side by side
## each point at their own. What it says comes from the tile's "interact" data,
## the same string the Player acts on, so painting a new piece of furniture
## gives it a prompt without a line of code here.

## What each verb reads as. A tile tagged with something not listed stays quiet
## rather than showing a blank sign.
const WORDS := {
	"wardrobe": "OPEN",
	"bed": "SLEEP",
}

@export_group("Look")
## How far above the furniture's middle the sign rests, in world pixels.
@export var lift: float = -14.0
## How far it bobs, and how long one bob takes.
@export_range(0.0, 6.0, 0.5) var bob: float = 2.0
@export_range(0.2, 4.0, 0.1) var bob_time: float = 1.1
## Seconds the fade in and out take.
@export_range(0.0, 0.6, 0.02) var fade_time: float = 0.12

const BG := Color("fff4dc")
const EDGE := Color("5a3d3d")
const KEY_BG := Color("90625d")
const PAD := Vector2(5, 3)

var player: Player

var _key_font: Font
var _word_font: Font
var _key := "E"
var _word := ""
var _shown := false
var _age := 0.0
var _tween: Tween


func _ready() -> void:
	z_index = 40
	top_level = true          # positioned in world space, not relative to the player
	modulate.a = 0.0
	_key_font = UIFont.title()
	_word_font = UIFont.title()
	set_process(true)


func _process(delta: float) -> void:
	_age += delta
	var verb := _verb_ahead()
	var want := verb != ""
	if want:
		_word = WORDS.get(verb, "")
		want = _word != ""
	if want:
		global_position = player.cell_center(player.facing_cell()) + Vector2(0, lift)
		if bob > 0.0:
			position.y += sin(_age * TAU / bob_time) * bob
	if want != _shown:
		_shown = want
		_fade(1.0 if want else 0.0)
	if want:
		queue_redraw()


## Empty unless the player is facing a tile that says it can be used, and a
## menu is not already covering the screen.
func _verb_ahead() -> String:
	if player == null or not is_instance_valid(player):
		return ""
	return player.interaction_ahead()


func _fade(to: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", to, fade_time)


func _draw() -> void:
	if _word.is_empty():
		return
	var size := UIFont.SIZE
	var key_w := _key_font.get_string_size(_key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var word_w := _word_font.get_string_size(_word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var key_box := Vector2(key_w + 6.0, size + 3.0)
	var inner := key_box.x + 4.0 + word_w
	var box := Vector2(inner + PAD.x * 2.0, key_box.y + PAD.y * 2.0)
	var at := Vector2(-box.x * 0.5, -box.y)

	# bubble
	draw_rect(Rect2(at, box), EDGE)
	draw_rect(Rect2(at + Vector2.ONE, box - Vector2.ONE * 2.0), BG)
	# tail, pointing down at the furniture
	var tip := Vector2(0.0, at.y + box.y + 3.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-3.0, at.y + box.y - 1.0), Vector2(3.0, at.y + box.y - 1.0), tip]), EDGE)

	# key cap
	var key_at := at + PAD
	draw_rect(Rect2(key_at, key_box), EDGE)
	draw_rect(Rect2(key_at + Vector2.ONE, key_box - Vector2.ONE * 2.0), KEY_BG)
	draw_string(_key_font, key_at + Vector2(3.0, size), _key,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, BG)
	# the verb
	draw_string(_word_font, key_at + Vector2(key_box.x + 4.0, size), _word,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, EDGE)
