class_name Collector
extends Node2D

## The debt collector: the man who stands at the farm gate on Sundays and wants
## his money.
##
## Walking up to him and using him gets a line or two and then the bill
## (`DebtPanel`) -- the window opens after the last line, not over it, or it
## would cover the man saying it. What he says depends on the week: whether
## anything is owed, how many strikes are against you, and whether you have
## just paid him.
##
## He is only there on `Debt.COLLECTION_WEEKDAY`, and only while there is still
## something to collect. The week is settled that night whether or not he was
## paid, so a Sunday spent indoors is the way to miss a payment.
##
## Art: the pack's *basic* character, not the premium one the player wears, so
## he reads as someone from elsewhere. The pack has no debt-collector sprite
## and nothing in it is close, so he is tinted cold instead -- a grey-blue cast
## over a sheet drawn in warm cream. Replace the tint with proper art when there
## is any.

## Nodes in this group can be used the way painted furniture can; see
## `Player._interactable_in_reach`.
const GROUP := &"interactable"

const SHEET := preload("res://Assets/Character/Basic_Character.png")
## The sheet is a 4x4 grid of 48px cells. Row 0 is facing down; column 0 is the
## standing frame.
const CELL := 48
const FRAME_DOWN := Vector2i(0, 0)
## Where the character's feet are inside that cell, so the sprite can be placed
## by the ground he stands on rather than by his box. **Measured**, not
## guessed: the art fills x 17..31, y 16..32 of the 48px cell, so the feet are
## at (24, 32). Guessed at 40 first, which floated him eight pixels off the
## ground -- invisible in a test, obvious in a render.
const FEET := Vector2(24, 32)

## The cold cast that marks him out from the warm farm. Not art -- a stand-in.
const TINT := Color(0.72, 0.76, 0.95)

## What he is called over the dialogue box.
const NAME := "THE DEBT COLLECTOR"

## How far he bobs, and how often, so he is not a statue. One pixel, stepped,
## like the clock's picture: a tween would put him between pixels.
const BOB := 0.7

@export_group("Scene")
## Layer that supplies the grid, so his cell can be worked out from where he
## stands. Defaults to a sibling named "Grass Layer", as Farm's does.
@export var ground_layer_path: NodePath = ^"../Grass Layer"

var _sprite: Sprite2D
var _layer: TileMapLayer
var _bob := 0.0
var _up := false


func _ready() -> void:
	add_to_group(GROUP)
	_layer = get_node_or_null(ground_layer_path) as TileMapLayer

	_sprite = Sprite2D.new()
	_sprite.centered = false
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.texture = UISkin.atlas(SHEET,
			Rect2(FRAME_DOWN.x * CELL, FRAME_DOWN.y * CELL, CELL, CELL))
	_sprite.offset = -FEET
	_sprite.modulate = TINT
	add_child(_sprite)

	PlayerState.day_changed.connect(_on_day_changed)
	Debt.changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_bob += delta
	if _bob >= BOB:
		_bob -= BOB
		_up = not _up
		_sprite.position.y = -1.0 if _up else 0.0


## The cell he is standing on, which is what the player has to reach.
func interact_cell() -> Vector2i:
	if _layer == null:
		return Vector2i.ZERO
	return _layer.local_to_map(_layer.to_local(global_position))


## What using him would do, for the prompt. Empty when he is not here.
func interact_verb() -> String:
	return "collector" if visible else ""


## Says his piece, then opens the bill. The HUD owns the window, as it owns
## every other one.
func interact(_player: Node) -> bool:
	if not visible:
		return false
	# The last piece of the lawyer's case is his own copy of the form, and he
	# hands it over without a fight: by now you have been paying him for
	# months, and a man who gets paid has no reason to keep anything back.
	var given := Lawyer.piece_from("collector")
	if not given.is_empty():
		Lawyer.take(given)
	Dialogue.say(NAME, _paper_lines() if not given.is_empty() else _lines(),
			Townsfolk.face(), TINT)
	if not Dialogue.finished.is_connected(_open_bill):
		Dialogue.finished.connect(_open_bill, CONNECT_ONE_SHOT)
	return true


func _open_bill() -> void:
	var hud := get_tree().get_first_node_in_group(HUD.GROUP) as HUD
	if hud != null:
		hud.open_debt()


## The day he hands over the paper that undoes his own errand. He does not
## know what it is for, and would not much care.
func _paper_lines() -> Array[String]:
	return [
		"THE ORIGINAL? I HAVE A COPY OF IT.",
		"YOU WANT IT? TAKE IT.",
		"PAPER DOES NOT CHANGE WHAT IS OWED.",
		"SUNDAY, THEN.",
	]


## What he says today. Picked here, from the state of the debt, and handed to
## `Dialogue` as a flat list -- see `Townsfolk` for why the branching lives at
## this end and not inside the dialogue system.
func _lines() -> Array[String]:
	if Debt.is_settled_for_week():
		return [
			"PAID. I WILL MARK IT DOWN.",
			"SAME TIME NEXT SUNDAY.",
			"IT DOES NOT STOP FOR BEING EARLY.",
		]
	if Debt.strikes >= Debt.STRIKES_TO_LOSE - 1:
		return [
			"TWO AGAINST YOU ALREADY.",
			"I DO NOT WANT THE FARM.",
			"I WANT THE MONEY.",
			"BUT I WILL TAKE THE FARM.",
		]
	if Debt.strikes > 0:
		return [
			"YOU WERE NOT HERE LAST TIME.",
			"I PUT A MARK BY YOUR NAME.",
			"THREE MARKS AND WE STOP TALKING.",
		]
	if Calendar.week(PlayerState.day) <= 1:
		return [
			"YOUR MOTHER'S PAPER, YOUR NAME ON IT.",
			"I COME EVERY SUNDAY.",
			"PAY THE MINIMUM OR I MARK YOU DOWN.",
			"THREE MARKS AND THE FARM IS MINE.",
			"NOTHING PERSONAL IN IT.",
		]
	return [
		"SUNDAY AGAIN.",
		"LET US KEEP THIS SHORT.",
	]


func _on_day_changed(_day: int) -> void:
	_refresh()


## He comes on collection day, and stops coming once there is nothing left to
## collect or the farm is already lost.
func _refresh() -> void:
	visible = Debt.is_collection_day(PlayerState.day) \
			and Debt.balance > 0 and not Debt.lost_farm
	set_process(visible)
	if visible:
		_sprite.position.y = 0.0
