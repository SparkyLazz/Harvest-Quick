extends Node

## What the sky is doing, day by day.
##
## The weather is not stored anywhere: it is worked out from the day number, so
## every scene, the clock, the farm and a save reloaded a week later all agree
## without anything being written to disk or passed between them. Ask it for any
## day, past or future, and you get the same answer -- which is also what makes
## it testable.
##
## Each season has its own chance of rain, and a share of those rainy days come
## down as storms instead (same water, darker sky, lightning). Winter is dry:
## the icon sheet has snow for it, but nothing in the game knows what snow does
## yet, so winter stays clear rather than pretending. Day 1 is always clear --
## the first morning on the farm should not be spent indoors.
##
## Rain waters every tilled cell for free (see Farm), which is the whole point
## of it: a rainy day is a day off from the watering can.

## Emitted the morning the sky changes, with today's kind.
signal changed(kind: int)

enum { CLEAR, RAIN, STORM }

## How a kind is said out loud, for tests and debugging.
const NAMES: Array[String] = ["clear", "rain", "storm"]

## Chance of rain in each season, Spring first. Winter is dry -- see above.
const RAIN_CHANCE: Array[float] = [0.28, 0.16, 0.24, 0.0]
## Of the rainy days in each season, the share that come down as storms.
## Summer's few rains are the violent ones.
const STORM_SHARE: Array[float] = [0.10, 0.35, 0.15, 0.0]
## Days from the start that are always clear, however the roll comes out.
const CLEAR_UNTIL := 1

## Set to a kind to hold the sky there whatever the day says; -1 follows the
## calendar. The debug key below flips through it, and tests use it.
var forced := -1: set = set_forced

## F9 in a debug build steps the sky through clear, rain, storm and back to
## whatever the day actually says, so the rain can be looked at without waiting
## for a rainy day. Gone from an exported build.
const DEBUG_KEY := KEY_F9

var _last := -1


func _ready() -> void:
	PlayerState.day_changed.connect(_on_day_changed)
	# Anything run with --script gets a clear sky unless it asks for another.
	# A suite that sleeps through a dozen days would otherwise pass or fail on
	# which of them happened to be rainy -- test_clock's "comes back dry" did
	# exactly that the first time the weather existed. test_weather and
	# shoot_rain set `forced` themselves.
	var args := OS.get_cmdline_args()
	if "--script" in args or "-s" in args:
		forced = CLEAR
	_last = today()
	set_process_unhandled_key_input(OS.is_debug_build())


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != DEBUG_KEY:
		return
	get_viewport().set_input_as_handled()
	# -1 (follow the calendar) -> clear -> rain -> storm -> -1.
	forced = -1 if forced >= STORM else forced + 1
	print("Weather: ", "day (%s)" % NAMES[today()] if forced < 0 else NAMES[forced])


## Today's weather, honouring `forced`.
func today() -> int:
	return kind_for(PlayerState.day)


## The weather on `day`, honouring `forced`.
func kind_for(day: int) -> int:
	if forced >= 0:
		return forced
	return rolled_for(day)


## True when the sky waters the farm for you -- rain and storm both do.
func is_wet_today() -> bool:
	return is_wet(today())


static func is_wet(kind: int) -> bool:
	return kind == RAIN or kind == STORM


## The weather `day` rolls, ignoring `forced`. Pure: same day, same sky.
static func rolled_for(day: int) -> int:
	if day <= CLEAR_UNTIL:
		return CLEAR
	var season := Calendar.season_index(day)
	if _roll(day, 1) >= RAIN_CHANCE[season]:
		return CLEAR
	return STORM if _roll(day, 2) < STORM_SHARE[season] else RAIN


## A repeatable number in [0, 1) for a day and a purpose. The day alone is a
## poor seed -- consecutive days land next to each other -- so it is stirred:
## multiply by a large odd number, fold the high bits down over the low ones,
## stir again. Masked to 31 bits throughout so the arithmetic cannot run into
## the sign bit and come back negative.
static func _roll(day: int, salt: int) -> float:
	var h := (day * 374761393 + salt * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h % 100000) / 100000.0


func set_forced(value: int) -> void:
	forced = value if value in [CLEAR, RAIN, STORM] else -1
	_announce()


## The name of today's weather, for tests and debugging.
func name_of_today() -> String:
	return NAMES[today()]


func _on_day_changed(_day: int) -> void:
	_announce()


func _announce() -> void:
	var kind := today()
	if kind == _last:
		return
	_last = kind
	changed.emit(kind)
