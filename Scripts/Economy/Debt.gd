extends Node

## The money your mother borrowed in your name, and the man who comes for it.
##
## This is the clock the whole game is played against. The farm does not fail
## because the soil is poor or the weather turned; it fails because on the
## fourteenth day a man knocks and the purse is light. Everything the player
## does with a seed is really about this.
##
## The squeeze is deliberate and has exactly one shape: [b]what the collector
## takes is interest, and it never touches the principal.[/b] Pay him every
## week for a year and you will owe precisely what you owed on the first
## morning. That is not a cruelty for its own sake — it is the only way the
## lawyer can be the point. A debt that paid down would make grinding the
## collector a winning line, and the player would never need [method
## hire_lawyer] at all; the first run simulated here did exactly that and
## cleared the whole loan by the sixth week without a lawyer in sight.
##
## So every coin is the same question asked again: feed the collector, or hoard
## for the lawyer. Hoard too hard and you miss a phase. Feed him too long and
## the rate has climbed past what the farm can carry. The window to save
## [member lawyer_fee] is widest at the start and closes every phase.
##
## The run is played in [b]phases[/b] of [member phase_length] days, each ending
## with the knock. Missing one does not end the run: he takes whatever is in the
## purse, the shortfall goes onto the principal, and it costs a heart. Three
## hearts, so the player can afford to be wrong twice — which is the only way
## betting a field on a forecast is a decision rather than a dare.
##
## Missing compounds, though. The shortfall joins the principal and the rent is
## a share of the principal, so the phase after a miss is dearer than the one
## before it. Hearts are a slope, not three free lives.
##
## The mother is not a character yet and may never need to be. What she is, is
## the reason the number is allowed to go [i]up[/i] on its own: a run where the
## debt only ever shrinks is an arithmetic problem, and one where it can grow
## on the night you were counting on a margin is a game. She gambles when the
## collector calls, which is the moment the player is already looking at the
## figure.
##
## Reached as the [code]Debt[/code] autoload.

## Emitted when a phase begins, with its number and the day it ends on.
signal phase_began(phase: int, ends_on: int)

## Emitted when the collector is due in, with how many days and what he wants.
## The warning, not the knock — this is what a calendar or a letter shows.
signal collector_due(days: int, amount: int)

## Emitted when he is paid, with what he took and what is still owed.
signal paid(amount: int, remaining: int)

## Emitted when a phase ends short, with the shortfall, what he did take and
## which phase it was. A heart has gone by the time this is heard.
##
## It carries the shortfall because "you were forty short" is a reason to play
## again and "you failed" is not.
signal missed(shortfall: int, taken: int, phase: int)

## Emitted when the last heart goes with the debt still standing, on the phase
## it happened. The run is over.
signal collapsed(phase: int)

## Emitted when the mother has been at the tables again, with what she added
## and what is now owed.
signal mother_gambled(added: int, owed: int)

## Emitted when the debt is gone and the game is won, with the day it took.
signal freed(day: int)

## Emitted whenever the figure moves at all, for a HUD that shows it.
signal changed(owed: int)

@export_group("The debt")
## What is owed on the first morning. Large enough that the player cannot
## simply pay it off with a good week, or the lawyer is pointless.
@export var starting_debt: int = 6000

@export_group("The collector")
## How long a phase runs. The player plans in phases because he arrives at the
## end of them, and the whole game is paced in this one number.
@export var phase_length: int = 7

## What a missed phase costs, in half-hearts. Two is a whole heart.
@export var miss_cost: int = 2

## What share of the principal he takes each visit. The ask is this times
## [member owed], so the mother's losses raise the weekly rent as well as the
## total — which is what makes one bad night at the tables hurt twice.
@export_range(0.0, 1.0, 0.005) var interest_rate: float = 0.10

## How much the rate climbs per visit. Small, because it compounds against a
## principal that is itself growing: this is the hand slowly closing, and it is
## what puts a deadline on saving for the lawyer.
@export_range(0.0, 0.2, 0.005) var rate_climb: float = 0.025

## Where the rate stops. Without a ceiling a long run becomes arithmetic
## nobody can survive, and the last few weeks stop being decisions.
@export_range(0.0, 1.0, 0.01) var rate_ceiling: float = 0.45

## How many days ahead the knock is announced. Long enough to sell into it.
@export var notice_days: int = 3

@export_group("The mother")
## The chance, per visit, that she has borrowed again.
@export_range(0.0, 1.0, 0.01) var gamble_chance: float = 0.35

## How much she adds when she does.
@export var gamble_amount: Vector2i = Vector2i(300, 900)

@export_group("The way out")
## What a lawyer costs. Pay it once and the debt is finished, whatever is left
## on it. This is the win condition and should read as nearly out of reach.
@export var lawyer_fee: int = 4500

## How much is still owed. The mother moves this up, and so does a phase the
## player could not pay for — never a payment.
var owed: int = 0
## The share of it he is taking at the moment.
var rate: float = 0.0
## Which phase is being played, counting from 1.
var phase: int = 0
## The day this phase ends and he knocks.
var next_visit: int = 0
## Whether the lawyer has been paid and the run won.
var settled: bool = false
## What has gone to the collector across the run, for the end-of-run tally.
## Worth showing: it is the number that argues for hiring the lawyer sooner.
var interest_paid: int = 0
## How many phases ended short. The run's scar tissue.
var phases_missed: int = 0

var _rng := RandomNumberGenerator.new()
var _warned: bool = false

## What the collector will ask for on his next visit.
var installment: int:
	get: return maxi(1, roundi(owed * rate))

## Start a run's debt. Seeded so that the mother's luck is part of the run's
## identity rather than a separate roll of the dice every time it is replayed.
func open(debt_seed: int) -> void:
	_rng.seed = debt_seed if debt_seed != 0 else randi()
	owed = starting_debt
	rate = interest_rate
	phase = 1
	next_visit = phase_length
	settled = false
	interest_paid = 0
	phases_missed = 0
	_warned = false
	changed.emit(owed)
	phase_began.emit(phase, next_visit)

## Move the debt on a day. Returns false when the run has ended on it, so the
## caller can stop the clock rather than having to ask afterwards.
##
## The warning and the knock are both here because they are the same schedule
## seen from two distances, and splitting them across two callers is how they
## come to disagree about which day he is due.
func advance_to(day: int) -> bool:
	if settled:
		return true
	if not _warned and next_visit - day <= notice_days and next_visit > day:
		_warned = true
		collector_due.emit(next_visit - day, installment)
	if day >= next_visit:
		return _collect(day)
	return true

## The knock at the end of a phase. Returns whether the run goes on.
func _collect(day: int) -> bool:
	var due := installment
	var standing := true
	if Wallet.can_afford(due):
		Wallet.spend(due, &"collector")
		interest_paid += due
		# [member owed] is deliberately untouched on a payment. See the note at
		# the top: the principal is not payable, and the lawyer is the only
		# door out.
		paid.emit(due, owed)
	else:
		# He takes what there is and the rest goes onto the principal, so a
		# missed phase is felt twice — a heart now, and heavier rent for the
		# rest of the run. That is what makes the second miss harder than the
		# first, and it is why hearts are a slope rather than three free lives.
		var taken: int = Wallet.coins
		var short: int = due - taken
		Wallet.spend(taken, &"collector")
		interest_paid += taken
		owed += short
		phases_missed += 1
		standing = Hearts.lose(miss_cost)
		missed.emit(short, taken, phase)
		if not standing:
			changed.emit(owed)
			collapsed.emit(phase)
			return false
	# She hears that the collector called and takes it as proof of credit.
	if _rng.randf() < gamble_chance:
		var added := _rng.randi_range(gamble_amount.x, gamble_amount.y)
		owed += added
		mother_gambled.emit(added, owed)
	rate = minf(rate + rate_climb, rate_ceiling)
	phase += 1
	next_visit = day + phase_length
	_warned = false
	changed.emit(owed)
	phase_began.emit(phase, next_visit)
	return true

## Pay a lawyer and be done with it. Returns whether it could be afforded.
##
## It does not matter how much was still owed. The point of the fee is that it
## is a single number the player can aim a whole run at, and making it depend
## on the remaining balance would mean the target moved every time the
## collector called — which is the one thing a long-term goal must not do.
func hire_lawyer() -> bool:
	if settled:
		return true
	if not Wallet.spend(lawyer_fee, &"lawyer"):
		return false
	owed = 0
	settled = true
	changed.emit(owed)
	freed.emit(Market.day())
	return true

## Whether the lawyer could be paid for right now.
func can_hire_lawyer() -> bool:
	return not settled and Wallet.can_afford(lawyer_fee)

## Days until the end of this phase, or 0 once the debt is finished.
func days_until_visit(day: int) -> int:
	return 0 if settled else maxi(next_visit - day, 0)
