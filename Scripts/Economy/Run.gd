class_name Run
extends Node

## One attempt at getting out from under the debt, start to finish.
##
## Everything a run needs already existed and none of it was connected. The
## market had prices nothing read, the debt had a collector who never knocked,
## and the day clock ticked past crops without the economy noticing. This is the
## wire between them, and it is deliberately the only one: [Market] does not
## know what a day is, [Debt] does not know what a market is, and neither has
## any idea a player can lose.
##
## A run is a seed. The same number lays out the same farm, rolls the same
## spikes and gives the mother the same luck, so two players can be handed the
## identical problem and a bad run can be looked at twice. [member random_seed]
## left at 0 picks one, which is the normal way to play.
##
## It is a scene node rather than an autoload because it belongs to the farm —
## the clock and the scatter it wires up are siblings, and a run with no map to
## happen on is not a thing. The pools it drives ([Wallet], [Hearts], [Market],
## [Debt]) are autoloads precisely so that the shop and the HUD can reach them
## without reaching through here.
##
## Reached with get_tree().get_first_node_in_group("run").

## Emitted when a run begins, with its seed.
signal began(seed_used: int)

## Emitted at the top of every day, with the day number. The one place to hang
## anything that should happen each morning.
signal day_began(day: int)

## Emitted when the lawyer has been paid, with the day it happened on.
signal won(day: int)

## Emitted when the last heart goes, with the day and the phase it went on.
signal lost(day: int, phase: int)

@export_group("Wiring")
## The day clock this run is paced by.
@export var clock_path: NodePath = NodePath("../DayNightCycle")

## The scatter whose seed is taken from the run's, so the farm itself differs
## between runs. Left empty, the scatter keeps whatever seed it was authored
## with and every run looks the same.
@export var scatter_path: NodePath = NodePath("../NatureScatter")

@export_group("The run")
## The number the whole run is built from. 0 picks one at random and reports it,
## which is what a normal game does; anything else replays that exact run.
@export var random_seed: int = 0

## How many days the market rolls spikes for. A ceiling, not a deadline —
## nothing ends on it, it is only how far ahead the economy was imagined.
@export var horizon: int = 120

## Whether to hand the player the starter kit. Off once the shop is the way
## seeds are got, which is the point of the shop.
@export var grant_starter_kit: bool = true

## Whether the run starts itself on load. Off for a menu that starts it.
@export var autostart: bool = true

## The seed this run actually used, once it has started.
var seed_used: int = 0
## Which day it is. Mirrors the clock, so anything with a [Run] need not also
## find the clock to ask what day it is.
var day: int = 1
## Whether the run has finished, either way. Nothing advances after this.
var over: bool = false

var _clock: Node = null

func _ready() -> void:
	add_to_group("run")
	_clock = get_node_or_null(clock_path)
	if _clock != null and _clock.has_signal("day_passed"):
		_clock.day_passed.connect(_on_day_passed)
	# The debt is the only thing that can end a run, and it ends it through the
	# hearts, so this listens where the last heart goes rather than to each of
	# the ways one might be lost.
	Hearts.emptied.connect(_on_hearts_emptied)
	Debt.freed.connect(_on_freed)
	if autostart:
		start()

## Begin a run. Safe to call again for a second attempt without reloading the
## farm, which is what a run-again button wants.
func start() -> void:
	seed_used = random_seed if random_seed != 0 else randi() % 100000000
	over = false
	day = 1
	Wallet.reset()
	Hearts.reset()
	Market.open(seed_used, horizon)
	Debt.open(seed_used)
	if grant_starter_kit:
		Inventory.grant_starter_kit()
	# The scatter is sown from the same seed, one step off it, so that a run's
	# farm and its economy vary together without the trees being predictable
	# from the prices.
	var scatter := get_node_or_null(scatter_path)
	if scatter != null and "random_seed" in scatter:
		scatter.random_seed = seed_used + 1
	print("Run: seed %d" % seed_used)
	# Announced a frame late, not now. This node's _ready runs before the HUD's
	# — it does in the farm, since the HUD is the later sibling — so a signal
	# emitted here reaches a shop panel that does not exist yet, and the
	# merchant never came on the first morning. The state above is set up
	# immediately, so anything reading a price or a purse in its own _ready sees
	# a started run; only the telling waits for everyone to be listening.
	_announce.call_deferred()

func _announce() -> void:
	began.emit(seed_used)
	day_began.emit(day)

## A night has passed. The order here is the whole of the daily sequence and is
## not arbitrary: the market moves first so that the prices the player wakes to
## are today's, and the collector is paid last so that a crop sold this morning
## can still cover him.
func _on_day_passed(new_day: int) -> void:
	# The date is taken even on a finished run. The calendar does not stop
	# because the farm did, and anything reading the day off this — the shop's
	# header did — would otherwise disagree with the date plate, which goes on
	# counting regardless.
	day = new_day
	if over:
		return
	Market.advance_to(day)
	day_began.emit(day)
	Debt.advance_to(day)

func _on_freed(on_day: int) -> void:
	if over:
		return
	over = true
	won.emit(on_day)
	print("Run: won on day %d, seed %d" % [on_day, seed_used])

func _on_hearts_emptied() -> void:
	if over:
		return
	over = true
	lost.emit(day, Debt.phase)
	print("Run: lost on day %d, phase %d, seed %d" % [day, Debt.phase, seed_used])
