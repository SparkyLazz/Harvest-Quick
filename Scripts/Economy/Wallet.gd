extends Node

## The player's money.
##
## An autoload, and a node of its own rather than a field on [Debt] or on the
## shop, because by the end of a run nearly everything will want to read it:
## the shop to grey out what cannot be afforded, the collector to find out
## whether this is the day the run ends, the HUD to show the figure, and the
## lawyer to see whether the game is over. A pile of coins belongs to the
## player, not to any one of the things that wants to take them.
##
## Nothing here can go negative. [method spend] refuses and says so rather
## than overdrawing, which is the same bargain [method Stamina.spend] makes —
## the caller asks, believes the answer, and does not have to check first.

## Emitted whenever the figure moves, with what it now is.
signal changed(coins: int)

## Emitted when money comes in, with how much and where it came from. The
## source is a bare name — &"market", &"loan" — so a till or a day's-takings
## panel can total up by it without the earner knowing such a thing exists.
signal earned(amount: int, source: StringName)

## Emitted when money goes out, with how much and what for.
signal spent(amount: int, reason: StringName)

## Emitted when a payment is asked for that cannot be met, with the shortfall.
## Not an error — the collector turning this into a lost run is [Debt]'s
## business, and the shop simply declines the sale.
signal refused(shortfall: int)

## What the player starts a run with. Enough for a first planting and not a
## coin more: the opening move should be which seed, never whether to buy.
@export var starting_coins: int = 500

var coins: int = 0

func _ready() -> void:
	reset()

## Put the purse back to the start of a run.
func reset() -> void:
	coins = starting_coins
	changed.emit(coins)

## Take [param amount] out, or nothing at all if it is not there.
## Returns whether it was paid.
func spend(amount: int, reason: StringName = &"") -> bool:
	if amount <= 0:
		return true
	if coins < amount:
		refused.emit(amount - coins)
		return false
	coins -= amount
	spent.emit(amount, reason)
	changed.emit(coins)
	return true

## Put [param amount] in.
func earn(amount: int, source: StringName = &"") -> void:
	if amount <= 0:
		return
	coins += amount
	earned.emit(amount, source)
	changed.emit(coins)

## Whether [param amount] could be paid right now.
func can_afford(amount: int) -> bool:
	return coins >= amount
