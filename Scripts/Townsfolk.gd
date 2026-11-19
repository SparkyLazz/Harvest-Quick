class_name Townsfolk
extends Node2D

## The people in town, and what they say.
##
## One script for all of them: a `person` id picks the name, the tint and the
## lines. They are nodes in the `interactable` group, like the collector, so
## walking up and using them is the same gesture as everything else.
##
## **What they say is chosen before the conversation starts**, not inside it.
## `Dialogue` runs a flat list of lines; the branching lives here, in
## `_lines_for`, where it can read the debt, the calendar and the weather and
## pick a list. That keeps the dialogue system a dumb pipe and keeps the
## writing in one place where it can be read as writing.
##
## There are no drawn portraits in either pack, so a speaker's face is their own
## sprite shown in the profile screen's frame.
##
## Art: the pack's basic character for everyone, tinted per person. A stand-in,
## like the collector's -- they are all the same cat at the moment.

const GROUP := &"interactable"

const SHEET := preload("res://Assets/Character/Basic_Character.png")
const CELL := 48
## Row 0 column 0 is the standing, facing-down frame.
const FRAME := Vector2i(0, 0)
## Measured off the sheet: the art fills x 17..31, y 16..32 of the cell.
const FEET := Vector2(24, 32)
## Just the character, with the cell's empty margin cut away, for the portrait
## frame. A whole 48px cell in the frame draws a very small cat in a lot of
## nothing.
const FACE_REGION := Rect2(17, 16, 14, 16)

## Who can be stood in a map. `tint` is the stand-in for having their own art.
const PEOPLE := {
	"seller": {"name": "THE SEED SELLER", "tint": Color(0.80, 1.00, 0.78)},
	"neighbour": {"name": "THE NEIGHBOUR", "tint": Color(1.00, 0.88, 0.72)},
	"lawyer": {"name": "THE LAWYER", "tint": Color(0.86, 0.82, 0.98)},
}

## One pixel up and down, so nobody is a statue.
const BOB := 0.9

@export_group("Who")
## Which of `PEOPLE` this is.
@export var person: String = "neighbour"

@export_group("Scene")
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
	_sprite.texture = standing()
	_sprite.offset = -FEET
	_sprite.modulate = tint()
	add_child(_sprite)


func _process(delta: float) -> void:
	_bob += delta
	if _bob < BOB:
		return
	_bob -= BOB
	_up = not _up
	_sprite.position.y = -1.0 if _up else 0.0


## What this person is called.
func display_name() -> String:
	return str(_entry().get("name", person.to_upper()))


## The standing frame, for the sprite in the world.
static func standing() -> Texture2D:
	return UISkin.atlas(SHEET, Rect2(FRAME.x * CELL, FRAME.y * CELL, CELL, CELL))


## The face alone, for the portrait frame.
static func face() -> Texture2D:
	return UISkin.atlas(SHEET, FACE_REGION)


## The colour this person is drawn in, in the world and in the frame.
func tint() -> Color:
	return _entry().get("tint", Color.WHITE)


func interact_cell() -> Vector2i:
	if _layer == null:
		return Vector2i.ZERO
	return _layer.local_to_map(_layer.to_local(global_position))


func interact_verb() -> String:
	return person


## Says their piece -- and hands over a piece of the case if they have one to
## hand over, or takes the fee if they are the lawyer and it is all there.
##
## Both happen as the conversation is *started*, not after it, because the
## lines are chosen from the state and the state has to be the one the lines
## describe. The seller's stall is the exception: it is a window, and a window
## would cover the man talking, so it waits for the last line.
func interact(_player: Node) -> bool:
	var given := Lawyer.piece_from(person)
	var taking := person == "lawyer" and Lawyer.can_hire()
	if not given.is_empty():
		Lawyer.take(given)
	if taking:
		Lawyer.hire()
	Dialogue.say(display_name(), _lines_for(given, taking), face(), tint())
	if person == "seller":
		# After the last line, not over it: the window would cover him.
		if not Dialogue.finished.is_connected(_open_stall):
			Dialogue.finished.connect(_open_stall, CONNECT_ONE_SHOT)
	return true


func _open_stall() -> void:
	var hud := get_tree().get_first_node_in_group(HUD.GROUP) as HUD
	if hud != null:
		hud.open_shop()


func _entry() -> Dictionary:
	return PEOPLE.get(person, {})


## What they say today. Everything that varies is decided here, from the state
## of the game, and handed to `Dialogue` as a plain list.
## `given` is a piece of the case just handed over, and `hiring` is true on the
## one visit that wins the game -- both override whatever the person would
## otherwise have said, because it is the bigger thing that happened.
func _lines_for(given: String = "", hiring: bool = false) -> Array[String]:
	if hiring:
		return _hired_lines()
	if not given.is_empty():
		return _handing_over_lines(given)
	match person:
		"seller":
			return _seller_lines()
		"neighbour":
			return _neighbour_lines()
		"lawyer":
			return _lawyer_lines()
	return ["..."]


## What someone says as they part with their bit of the case.
func _handing_over_lines(given: String) -> Array[String]:
	match given:
		"word":
			return [
				"YOU ARE TAKING IT TO A LAWYER.",
				"GOOD. I WONDERED WHEN.",
				"I WILL SAY WHAT I SAW.",
				"I SAW HER SIGN. THAT IS ENOUGH.",
			]
		"ledger":
			return [
				"SHE BOUGHT HERE ON YOUR ACCOUNT.",
				"I KEPT THE PAGE. OF COURSE I DID.",
				"TAKE IT. I WANT NO PART OF HER.",
			]
	return ["TAKE IT."]


## The lawyer, the day he is paid. The only time anyone says this.
func _hired_lines() -> Array[String]:
	return [
		"IT IS DONE. THE DEBT IS NOT YOURS.",
		"IT NEVER WAS. NOW IT IS WRITTEN DOWN.",
		"SHE CANNOT SIGN AS YOU AGAIN.",
		"GO HOME. IT IS YOUR FARM.",
	]


func _seller_lines() -> Array[String]:
	var season := Calendar.season(PlayerState.day).to_upper()
	if Calendar.season_index(PlayerState.day) == 3:
		return [
			"NOTHING GROWS IN WINTER.",
			"NOTHING I CAN SELL YOU, ANYWAY.",
			"COME BACK IN SPRING.",
			"I WILL HAVE THE LOT.",
		]
	return [
		"MORNING. %s SEED, IS IT?" % season,
		"I ONLY CARRY WHAT GROWS NOW.",
		"SAVES YOU PLANTING A MISTAKE.",
	]


func _neighbour_lines() -> Array[String]:
	# The warnings come first: they are the ones worth interrupting a greeting
	# for. Order matters -- the worst news wins.
	if Debt.strikes >= Debt.STRIKES_TO_LOSE - 1:
		return [
			"HE HAS BEEN TO SEE ME.",
			"ASKING WHAT THE FARM IS WORTH.",
			"ONE MORE MISSED SUNDAY,",
			"AND YOU ARE OUT, LAD.",
			"WHATEVER YOU HAVE, GIVE IT HIM.",
		]
	if Debt.strikes > 0:
		return [
			"YOU MISSED HIM, THEN.",
			"IT IS NOT THE MONEY THAT GETS YOU.",
			"IT IS THE COUNTING.",
			"THREE AND HE TAKES THE FARM.",
			"DO NOT LET HIM COUNT AGAIN.",
		]
	if Calendar.season_index(PlayerState.day) == 2 \
			and Calendar.day_of_season(PlayerState.day) > 14:
		return [
			"FALL IS GETTING ON.",
			"YOU HAVE THOUGHT ABOUT WINTER?",
			"NOTHING GROWS IN IT.",
			"AND HE STILL COMES ON SUNDAYS.",
			"PUT SOMETHING BY.",
			"THAT IS ALL I WILL SAY.",
		]
	if Weather.is_wet_today():
		return [
			"RAIN DOES YOUR WATERING FOR YOU.",
			"RAIN DOES NOTHING ABOUT HIM, MIND.",
		]
	return [
		"YOUR MOTHER WAS THE SAME AT YOUR AGE.",
		"ALWAYS BUSY.",
		"DIFFERENT KIND OF BUSY.",
		"ANYWAY. THE FARM LOOKS WELL ON YOU.",
	]


## The lawyer is also the quest log: he says what he holds and what is still
## wanting, because there is no screen that does.
func _lawyer_lines() -> Array[String]:
	if Lawyer.is_hired:
		return [
			"THE MATTER IS CLOSED.",
			"KEEP THE PAPERS SOMEWHERE DRY.",
		]
	var said: Array[String] = [
		"A DEBT IN YOUR NAME.",
		"ONE YOU DID NOT SIGN FOR.",
		"THAT CAN BE UNDONE.",
	]
	if Lawyer.gathered_count() == 0:
		said.append("IT IS NOT CHEAP. IT IS NOT QUICK.")
		said.append("TEN THOUSAND,")
		said.append("AND PROOF SHE SIGNED AS YOU.")
		said.append("HER OWN LETTERS FIRST.")
		said.append("WAIT FOR THEM. SHE WILL WRITE.")
		return said
	said.append("I HAVE %d OF THE FOUR." % Lawyer.gathered_count())
	if Lawyer.is_complete():
		said.append("THE CASE IS WHOLE.")
		var short := Lawyer.FEE - PlayerState.coins
		if short > 0:
			said.append("NOW THE FEE. YOU ARE %d SHORT." % short)
		else:
			said.append("TEN THOUSAND, AND I BEGIN.")
		return said
	for name_ in Lawyer.missing_names():
		said.append("STILL WANTING: %s." % name_)
	if not Lawyer.has("paper") \
			and Calendar.week(PlayerState.day) < Lawyer.EVIDENCE_WEEK:
		said.append("THE LAST OF IT TAKES MONTHS.")
	return said
