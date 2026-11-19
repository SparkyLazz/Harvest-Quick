extends Node

## The post: Mom's letters, and the few other things that arrive in the box.
##
## This is how the story is told day to day (`Docs/GAME_DESIGN.md` §7). Mom is
## never seen; she exists only here, and almost every letter of hers costs
## money -- `econ_sim` calls it the biggest share of the debt's growth, which is
## the point: the player can see who is to blame.
##
## **A letter's debt lands when the letter does, not when it is read.** The post
## does not wait for you to open it, and `econ_sim` adds Mom's at the start of
## the week whichever way the player behaves. Leaving the box shut is not a way
## to dodge her.
##
## **Nothing is rolled at runtime.** How much a letter costs comes out of a
## mixer fed the week number, the way the weather does it (`Weather.gd`), so a
## given week's letter is always the same letter -- a save reloaded, a test, or
## a question asked about week 30 all give one answer. The inbox itself *is*
## saved, because which letters you have read is real state.

## A letter has landed.
signal arrived(letter: Dictionary)
## The inbox changed: a letter arrived, or one was read.
signal changed

## `Tools/econ_sim.py`'s rules for Mom, name for name.
const MOM_EVERY := 2
const MOM_BASE := 80
const MOM_STEP := 30
const MOM_SPREAD := 0.25

## Who letters come from, as the window shows it.
const FROM_MOM := "MOM"
const FROM_NEIGHBOUR := "THE NEIGHBOUR"

## Mom's letters, picked by week. She never explains and never quite
## apologises; the money is always already gone.
const MOM_BODIES: Array[Array] = [
	[
		"I NEEDED IT FOR ONE MORE WEEK.",
		"THAT IS ALL. ONE MORE WEEK AND I",
		"WOULD HAVE HAD IT BACK.",
		"DO NOT BE LIKE THIS.",
	],
	[
		"THE MAN SAID IT WAS THE LAST TIME",
		"AND I BELIEVED HIM. YOUR NAME WAS",
		"ALREADY ON THE FORM BY THEN.",
		"THERE WAS NOTHING TO SIGN.",
	],
	[
		"I DID NOT ASK YOU. I KNOW.",
		"IF I HAD ASKED YOU WOULD HAVE SAID",
		"NO, AND THEN WHERE WOULD WE BE.",
		"DO NOT COME LOOKING FOR ME.",
	],
	[
		"IT WILL BE DIFFERENT AFTER THIS ONE.",
		"I HAVE A FEELING ABOUT IT.",
		"YOU ALWAYS WERE THE STEADY ONE.",
		"THE FARM SUITS YOU.",
	],
]

const OPENING_BODY: Array[String] = [
	"THE FARM IS YOURS NOW.",
	"SO IS THE REST OF IT.",
	"THE MAN WILL COME ON SUNDAYS.",
	"PAY HIM AND HE WILL GO AWAY.",
]

const WINTER_BODY: Array[String] = [
	"WINTER IS THREE WEEKS OFF AND",
	"NOTHING GROWS IN IT. NOTHING.",
	"PUT MONEY BY NOW OR THE COLLECTOR",
	"WILL TAKE WHAT YOU HAVE NOT GOT.",
]

## Set false to stop anything being delivered. `test_debt` does this, so that
## its figures are about the debt's own rules and not about whichever week Mom
## happened to write in; nothing in the game turns it off.
var delivering := true

## Every letter that has landed, oldest first. Each is plain data:
##   {id, day, from, subject, lines, debt, read}
var letters: Array[Dictionary] = []
## Ids already delivered, so nothing can arrive twice however the days are
## walked -- a catch-up, a loaded save, a debug jump.
var _delivered := {}


func _ready() -> void:
	# Deferred, and *after* Debt's own deferred binding, so that on the morning
	# a week turns the account is settled before Mom's letter is added to it --
	# the order `econ_sim` uses. Autoload order decides the order these two
	# deferred calls are queued in, so Mail is registered after Debt.
	_bind.call_deferred()


func _bind() -> void:
	PlayerState.day_changed.connect(_on_day_changed)
	# The opening letter is waiting in the box on day one, and day one has no
	# `day_changed` to hang it on.
	deliver_due(PlayerState.day)


## How many letters are still unread.
func unread() -> int:
	var count := 0
	for letter in letters:
		if not letter["read"]:
			count += 1
	return count


func has_unread() -> bool:
	return unread() > 0


## Marks one letter read, by its id. Reading changes nothing but the dot
## beside it: the money was taken when it arrived.
func mark_read(id: String) -> void:
	for letter in letters:
		if letter["id"] == id and not letter["read"]:
			letter["read"] = true
			changed.emit()
			return


func mark_all_read() -> void:
	var any := false
	for letter in letters:
		if not letter["read"]:
			letter["read"] = true
			any = true
	if any:
		changed.emit()


## Delivers whatever `day` brings. Safe to call twice: a letter's id is
## remembered, and a letter never lands a second time.
func deliver_due(day: int) -> void:
	if day <= 0 or not delivering:
		return
	# Once the lawyer has done his work she cannot write in your name any
	# more, so she stops writing at all. That is the whole prize (step 6).
	if Lawyer.is_hired:
		return
	if day == 1:
		_deliver("opening", day, FROM_MOM, "ABOUT THE FARM", OPENING_BODY, 0)
	# Mom writes on the morning a week starts, every MOM_EVERY weeks.
	if is_week_start(day):
		var week := Calendar.week(day)
		if week % MOM_EVERY == 0:
			_deliver("mom-w%d" % week, day, FROM_MOM, "I AM SORRY",
					MOM_BODIES[(week / MOM_EVERY - 1) % MOM_BODIES.size()],
					mom_amount(week))
	# The neighbour's warning, once a year, at the start of Fall's last week --
	# three weeks before the winter that is the real test (§4).
	if is_week_start(day) and Calendar.season_index(day) == 2 \
			and Calendar.day_of_season(day) == Calendar.DAYS_PER_SEASON - 6:
		_deliver("winter-y%d" % Calendar.year(day), day, FROM_NEIGHBOUR,
				"BEFORE THE SNOW", WINTER_BODY, 0)


## True on the Monday that opens a week.
static func is_week_start(day: int) -> bool:
	return (day - 1) % Calendar.DAYS_PER_WEEK == 0


## What Mom's letter costs in `week`: (MOM_BASE + MOM_STEP * week) give or take
## MOM_SPREAD, spread by the same kind of mixer the weather uses, so the figure
## is fixed for that week and never rolled twice.
static func mom_amount(week: int) -> int:
	var base := float(MOM_BASE + MOM_STEP * week)
	var swing := (_roll(week) * 2.0 - 1.0) * MOM_SPREAD
	return maxi(1, roundi(base * (1.0 + swing)))


## A repeatable number in [0, 1) for a week. Same shape as `Weather._roll`:
## multiply by a large odd number, fold the high bits down, mix again, all
## masked to 31 bits so it can never turn negative.
static func _roll(week: int) -> float:
	var h := (week * 2246822519 + 974634137) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 2654435761) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h % 100000) / 100000.0


func _deliver(id: String, day: int, from: String, subject: String,
		lines: Array, debt: int) -> void:
	if _delivered.has(id):
		return
	_delivered[id] = true
	var letter := {
		"id": id, "day": day, "from": from, "subject": subject,
		"lines": lines.duplicate(), "debt": debt, "read": false,
	}
	letters.append(letter)
	if debt > 0:
		Debt.add(debt)
	arrived.emit(letter)
	changed.emit()


func _on_day_changed(day: int) -> void:
	deliver_due(day)


## Everything that goes in the save file. Plain data only.
func to_record() -> Dictionary:
	return {"letters": letters.duplicate(true), "delivered": _delivered.duplicate()}


func from_record(record: Dictionary) -> void:
	letters.clear()
	for letter: Dictionary in record.get("letters", []):
		letters.append(letter.duplicate(true))
	_delivered = record.get("delivered", {}).duplicate()
	changed.emit()


## An empty box, for a new game -- and then the opening letter in it, because
## a new game starts on day 1 and day 1 has no `day_changed` to deliver it on.
func reset() -> void:
	letters.clear()
	_delivered.clear()
	changed.emit()
	# Day 1 explicitly, not today's date: a reset *is* going back to day 1
	# (`PlayerState.reset` has already put the calendar there), and asking for
	# today's post would deliver whatever week the old game happened to end on.
	deliver_due(1)
