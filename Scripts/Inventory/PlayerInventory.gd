extends Node

## The player's own [Inventory], autoloaded as [code]PlayerInventory[/code].
##
## One inventory covers both the hotbar and the backpack. The first
## [constant COLUMNS] slots are the hotbar row and the rest are the
## backpack, which is why dragging a turnip from the grid onto the bar is
## an ordinary slot-to-slot move and needs no code of its own.
##
## The UI reads [member inventory] and listens to its signals. Nothing
## else here is state: the starter pack is granted once, in [method
## _ready], and after that this is just a place the inventory lives.

## Slots per row. The hotbar holds exactly one row.
const COLUMNS: int = 9
## Rows in total, the hotbar row included. The menu's backpack tab shows
## all of them in a viewport a few rows tall, so this is also how much
## there is to scroll.
const ROWS: int = 8

## What the player starts the game holding, in slot order.
const STARTER_PACK: Array[StringName] = [
	&"hoe",
	&"axe",
	&"watering_can",
]

var inventory: Inventory

func _ready() -> void:
	inventory = Inventory.new(COLUMNS * ROWS)
	_grant_starter_pack()

## Index of the first slot outside the hotbar row.
func backpack_start() -> int:
	return COLUMNS

func is_hotbar_slot(index: int) -> bool:
	return index >= 0 and index < COLUMNS

## Sends [param index] to the other half of the inventory: hotbar slots go
## to the backpack and backpack slots come to the hotbar. Returns true if
## anything moved.
func quick_move(index: int) -> bool:
	if is_hotbar_slot(index):
		return inventory.quick_move(index, COLUMNS, inventory.slot_count())
	return inventory.quick_move(index, 0, COLUMNS)

## Convenience for the rest of the game: picks something up and returns
## however much would not fit.
func collect(id: StringName, amount: int = 1) -> int:
	return inventory.add(id, amount)

func _grant_starter_pack() -> void:
	for i in STARTER_PACK.size():
		var id := STARTER_PACK[i]
		if not ItemDb.has_item(id):
			push_warning("PlayerInventory: starter item '%s' is not in the database." % id)
			continue
		inventory.set_stack(i, ItemStack.new(id, 1))
