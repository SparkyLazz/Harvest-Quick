extends Node

## Who the player is and what they are worth, autoloaded as
## [code]PlayerProfile[/code].
##
## This is the small pile of state the profile panel reads that is not an
## item and not the clock: a name, a farm, a purse. Money lives here
## rather than as a stack of coins in the bag, so there is one place to
## ask how much the player has and spending never has to hunt for slots.
##
## Everything else on the panel is read from somewhere that already owns
## it — the date and time from [DayNightCycle], the contents from
## [PlayerInventory] — so nothing on screen can drift out of step with the
## thing it is describing.

## Emitted when [member money] changes, with the new balance.
signal money_changed(amount: int)

@export var player_name: String = "RUI"
@export var farm_name: String = "QUICK FARM"

var money: int = 500:
	set(value):
		var clamped := maxi(value, 0)
		if clamped == money:
			return
		money = clamped
		money_changed.emit(money)

## Adds [param amount] to the purse.
func earn(amount: int) -> void:
	money += maxi(amount, 0)

## Takes [param amount] out of the purse if it is there, and says whether
## it was. Callers check the return rather than the balance, so the test
## and the deduction cannot come apart.
func spend(amount: int) -> bool:
	if amount <= 0 or money < amount:
		return false
	money -= amount
	return true

func can_afford(amount: int) -> bool:
	return money >= amount
