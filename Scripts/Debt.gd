extends Node

## Mom's debt, in the player's name: the balance, the weekly minimum, the
## interest, and the three strikes that take the farm.
##
## The rules are `Docs/GAME_DESIGN.md` §4, and the numbers are the ones
## `Tools/econ_sim.py` was tuned with -- the constants below are that script's,
## spelled the same way, so the simulation's claim that every skill level can
## survive is a claim about this code and not about a different set of numbers.
## If one side changes, change the other.
##
## **The week is the unit.** Nothing happens day to day: a week's payments pile
## up in `paid_this_week`, and the whole account is settled in one go the night
## the week turns -- minimum met or missed, late fee, strike, then interest on
## whatever is left. That is also the order `econ_sim` uses.
##
## Who collects it is `Collector.gd` (the man at the gate, Sundays) and what
## the player sees is `DebtPanel.gd`. This script never touches the screen.

## Emitted whenever the balance, the strikes or what has been paid changes.
signal changed
## Emitted the night a week is settled: `met` is false if the minimum was
## missed, `fee` is what that cost, `strikes` is the count after it.
signal settled(week: int, due: int, paid: int, met: bool, fee: int, strikes: int)
## Emitted when the third strike lands. The farm is lost; `EndingScreen` listens.
signal lost

## `Tools/econ_sim.py`'s rules, name for name.
const START_DEBT := 1000
## Weekly, on the unpaid balance.
const INTEREST := 0.01
## The minimum is the higher of `MIN_BASE + MIN_STEP * week` and `MIN_PCT` of
## the debt -- and never more than the debt itself, so the last payment is not
## bigger than what is owed.
const MIN_BASE := 40
const MIN_STEP := 8
const MIN_PCT := 0.04
## Of the missed minimum, added to the debt.
const LATE_FEE := 0.10
const STRIKES_TO_LOSE := 3

## The day of the week the collector comes, counted as `Calendar.WEEKDAYS` is:
## 6 is Sunday, the last day of the week. He waits all day, and the account is
## settled that night, so a Sunday spent indoors is the way to miss a payment.
const COLLECTION_WEEKDAY := 6

var balance := START_DEBT
var strikes := 0
## Paid towards the week named below. Reset when that week is settled.
var paid_this_week := 0
## The week `paid_this_week` belongs to -- the one being collected now.
var week := 1
## True once the third strike has landed, so nothing settles twice afterwards.
var lost_farm := false


func _ready() -> void:
	# Deferred, because this autoload is registered *before* PlayerState: it has
	# to exist by the time PlayerState reads a save, which it does in its own
	# `_ready` (`from_record` below). Nothing is up yet when this runs, so the
	# connection waits a frame, by which time every autoload is in place.
	_bind.call_deferred()


func _bind() -> void:
	PlayerState.day_changed.connect(_on_day_changed)


## What is owed this week. Never more than the balance.
func minimum() -> int:
	return minimum_for(week, balance)


static func minimum_for(for_week: int, for_balance: int) -> int:
	if for_balance <= 0:
		return 0
	var by_step := MIN_BASE + MIN_STEP * for_week
	var by_share := roundi(MIN_PCT * for_balance)
	return mini(maxi(by_step, by_share), for_balance)


## What is still needed this week to avoid a strike. 0 once the minimum is met.
func still_due() -> int:
	return maxi(minimum() - paid_this_week, 0)


## True once this week's minimum has been covered.
func is_settled_for_week() -> bool:
	return still_due() == 0


## Takes `amount` from the purse and off the debt. Returns what was actually
## paid: less than asked if the purse or the balance is smaller, 0 if neither
## has anything to give. Paying more than the minimum is allowed and is the
## point -- it is what slows the interest down (§4).
func pay(amount: int) -> int:
	if lost_farm:
		return 0
	var sum := mini(mini(amount, PlayerState.coins), balance)
	if sum <= 0:
		return 0
	if not PlayerState.spend(sum):
		return 0
	balance -= sum
	paid_this_week += sum
	changed.emit()
	return sum


## The whole balance, if the purse can cover it.
func pay_off() -> int:
	return pay(balance)


## Puts `amount` on the debt. Mom's letters are the only thing that does this
## (see `Mail.gd`), and they do it the moment the letter lands, read or not --
## the post does not wait for you to open it, and `econ_sim` adds hers at the
## start of the week regardless. A game already lost takes nothing more.
func add(amount: int) -> void:
	if lost_farm or amount <= 0:
		return
	balance += amount
	changed.emit()


## A night has passed. The account is only touched when the week turns, and
## then once per week gone by -- a week skipped (which nothing does today, but
## a cutscene or a debug jump could) is still collected, not forgiven.
func _on_day_changed(day: int) -> void:
	if lost_farm:
		return
	var now := Calendar.week(day)
	while week < now:
		_settle()
		week += 1
		paid_this_week = 0
		if lost_farm:
			return
	changed.emit()


## One week's account, in `econ_sim`'s order: the minimum is checked, a missed
## one costs a fee and a strike, and then interest runs on what is left.
##
## A partial payment is still a miss. It counts against the balance -- nothing
## paid is ever lost -- but it does not buy off the strike, and the fee is a
## share of the whole minimum, not of the shortfall. That is how the simulation
## plays it, and softening it here would make its "no skill level loses" a
## claim about rules the game does not have.
func _settle() -> void:
	var due := minimum()
	var paid := paid_this_week
	var met := paid >= due
	var fee := 0
	if not met:
		fee = roundi(due * LATE_FEE)
		balance += fee
		strikes += 1
	# Interest on the unpaid balance, after the fee joins it.
	balance = roundi(balance * (1.0 + INTEREST))
	settled.emit(week, due, paid, met, fee, strikes)
	if strikes >= STRIKES_TO_LOSE:
		lost_farm = true
		lost.emit()


## True on the day the collector stands at the gate.
static func is_collection_day(day: int) -> bool:
	return (day - 1) % Calendar.DAYS_PER_WEEK == COLLECTION_WEEKDAY


## Everything that goes in the save file. Plain data only.
func to_record() -> Dictionary:
	return {
		"balance": balance,
		"strikes": strikes,
		"paid_this_week": paid_this_week,
		"week": week,
		"lost_farm": lost_farm,
	}


func from_record(record: Dictionary) -> void:
	balance = record.get("balance", START_DEBT)
	strikes = record.get("strikes", 0)
	paid_this_week = record.get("paid_this_week", 0)
	week = record.get("week", 1)
	lost_farm = record.get("lost_farm", false)
	changed.emit()


## Wipes the debt out -- not paid, *void*. The lawyer does this and nothing
## else does: the whole point of him is that it was never your debt to pay, so
## the balance does not go to zero by being settled, it stops existing. The
## strikes stay on the record; they just have nothing left to count towards.
func void_debt() -> void:
	if balance == 0:
		return
	balance = 0
	paid_this_week = 0
	changed.emit()


## Back to the first week owing everything, for a new game.
func reset() -> void:
	balance = START_DEBT
	strikes = 0
	paid_this_week = 0
	week = 1
	lost_farm = false
	changed.emit()
