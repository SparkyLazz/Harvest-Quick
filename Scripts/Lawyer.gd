extends Node

## The way out: the evidence, the fee, and the day Mom can no longer use your
## name.
##
## `Docs/GAME_DESIGN.md` 4 sets the shape -- ten thousand coins and proof she
## signed as you, and **the proof cannot be complete before week 12**. That
## last rule is not a check written on top; it is built into the evidence
## itself. The last piece is the collector's own copy of the form, and he will
## not part with it before week 12 and not until the rest is already gathered,
## so there is no order of play that finishes the case early.
##
## Where the four pieces come from is 7's three sources, one each and then one
## more: her letters, what the townspeople say, and -- the turn of the knife --
## the man collecting the debt, who hands over the paper that undoes it because
## by then you have been paying him for weeks and he has no reason not to.
##
## A piece is *taken*, once, and then kept: the condition that allowed it is
## checked when it is offered, never again. That matters for the letters, which
## could in principle be read and the game reloaded -- what is kept is the
## piece, not the circumstance.
##
## Hiring him ends the game well (`EndingScreen`): the debt is void and Mom's
## letters stop (`Mail`), because the name she was signing with is no longer
## one a court will accept.

## A piece of evidence has been gathered.
signal gathered(id: String)
## The case is complete -- every piece is in.
signal complete
## He has been hired. The game is won.
signal hired

## What he costs, from 4. `econ_sim.py` has the same number.
const FEE := 10000
## The earliest week the case can be finished, likewise. It is enforced by
## `paper`'s condition below, not by a separate test.
const EVIDENCE_WEEK := 12
## How many of Mom's letters make her own handwriting an exhibit.
const LETTERS_NEEDED := 3

## The pieces, in the order they can be gathered. `from` is who hands it over,
## which is only ever for the writing -- what gates a piece is its condition,
## in `can_take`.
const PIECES: Array[Dictionary] = [
	{"id": "letters", "name": "HER OWN LETTERS", "from": ""},
	{"id": "word", "name": "THE NEIGHBOUR'S WORD", "from": "neighbour"},
	{"id": "ledger", "name": "THE SELLER'S LEDGER", "from": "seller"},
	{"id": "paper", "name": "THE COLLECTOR'S COPY", "from": "collector"},
]

## Which pieces are in, by id.
var _have := {}
## True once the fee has been paid and the case won.
var is_hired := false


func _ready() -> void:
	# Deferred for the same reason Debt's and Mail's bindings are: this
	# autoload is registered before PlayerState, so that it is a node by the
	# time a save is read.
	_bind.call_deferred()


func _bind() -> void:
	# Her letters are not asked for; they pile up on their own.
	Mail.changed.connect(_check_letters)
	_check_letters()


## True when this piece has been gathered.
func has(id: String) -> bool:
	return _have.has(id)


## How many pieces are in.
func gathered_count() -> int:
	return _have.size()


func is_complete() -> bool:
	return _have.size() >= PIECES.size()


## Whether `id` can be taken right now. Each piece waits on the one before it,
## so the case is gathered in an order and not in a scramble; `paper` waits on
## the calendar as well, which is what makes the week-12 rule a rule.
func can_take(id: String) -> bool:
	if is_hired or has(id):
		return false
	match id:
		"letters":
			return _mom_letters() >= LETTERS_NEEDED
		"word":
			return has("letters")
		"ledger":
			return has("word")
		"paper":
			return has("ledger") and Calendar.week(PlayerState.day) >= EVIDENCE_WEEK
	return false


## Takes a piece, if it can be taken. Returns false and changes nothing if not.
func take(id: String) -> bool:
	if not can_take(id):
		return false
	_have[id] = true
	gathered.emit(id)
	if is_complete():
		complete.emit()
	return true


## The piece `who` has to give, or "" if they have none or it is not theirs.
## `who` is a `Townsfolk.person` or "collector".
func piece_from(who: String) -> String:
	for piece in PIECES:
		if piece["from"] == who and can_take(str(piece["id"])):
			return str(piece["id"])
	return ""


## What is still missing, by name, for him to list.
func missing_names() -> Array[String]:
	var out: Array[String] = []
	for piece in PIECES:
		if not has(str(piece["id"])):
			out.append(str(piece["name"]))
	return out


## What a piece is called.
static func name_of(id: String) -> String:
	for piece in PIECES:
		if piece["id"] == id:
			return str(piece["name"])
	return id.to_upper()


## True when the case is complete and the purse can cover the fee.
func can_hire() -> bool:
	return not is_hired and is_complete() and PlayerState.coins >= FEE


## Pays him and wins the game. The debt goes, and so does the reason for it.
func hire() -> bool:
	if not can_hire():
		return false
	if not PlayerState.spend(FEE):
		return false
	is_hired = true
	# Void, not paid: the point of him is that it was never your debt.
	Debt.void_debt()
	hired.emit()
	return true


## How many of Mom's letters have come.
func _mom_letters() -> int:
	var count := 0
	for letter in Mail.letters:
		if letter["from"] == Mail.FROM_MOM:
			count += 1
	return count


## Her letters need no asking for -- enough of them is the exhibit.
func _check_letters() -> void:
	if can_take("letters"):
		take("letters")


## Everything that goes in the save file. Plain data only.
func to_record() -> Dictionary:
	return {"have": _have.duplicate(), "hired": is_hired}


func from_record(record: Dictionary) -> void:
	_have = record.get("have", {}).duplicate()
	is_hired = record.get("hired", false)


## No case and no lawyer, for a new game.
func reset() -> void:
	_have.clear()
	is_hired = false
