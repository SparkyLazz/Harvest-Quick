class_name CarriedStack
extends RefCounted

## The stack riding on the cursor while an inventory screen is open, and the
## rules for what a click does to it.
##
## These rules are the fiddly part of an inventory screen, so they live here
## rather than in any one panel: the wardrobe and the profile screen share this
## object, which is also what lets a single cursor carry a stack out of one
## inventory and drop it into another. Every method takes the inventory that was
## clicked, so nothing here knows or cares which panel it belongs to.

signal changed

var item: String = ""
var count: int = 0


func is_empty() -> bool:
	return item == ""


func set_to(new_item: String, new_count: int) -> void:
	item = new_item if new_count > 0 else ""
	count = new_count if item != "" else 0
	changed.emit()


## Whole stack: pick it up, put it down, top up a matching stack, or swap.
func left_click(inv: Inventory, index: int) -> void:
	var there := inv.item_at(index)
	var n := inv.count_at(index)
	if is_empty():
		if there != "":
			set_to(there, n)
			inv.set_slot(index, "", 0)
	elif there == "":
		inv.set_slot(index, item, count)
		set_to("", 0)
	elif there == item:
		var moved := mini(ItemDB.max_stack(there) - n, count)
		inv.set_slot(index, there, n + moved)
		set_to(item, count - moved)
	else:
		var swap_item := item
		var swap_count := count
		set_to(there, n)
		inv.set_slot(index, swap_item, swap_count)


## Half a stack when picking up, one at a time when putting down.
func right_click(inv: Inventory, index: int) -> void:
	var there := inv.item_at(index)
	var n := inv.count_at(index)
	if is_empty():
		if there == "":
			return
		var half := (n + 1) / 2
		set_to(there, half)
		inv.set_slot(index, there, n - half)
	elif there == "" or (there == item and n < ItemDB.max_stack(there)):
		inv.set_slot(index, item, n + 1)
		set_to(item, count - 1)


## Shift-click: send a whole stack across to the other inventory without it ever
## touching the cursor. Returns false when nothing moved, so the caller can
## leave the slot alone rather than redraw for nothing.
func quick_move(from: Inventory, index: int, to: Inventory) -> bool:
	var what := from.item_at(index)
	if what == "":
		return false
	var n := from.count_at(index)
	var left := to.add(what, n)
	if left == n:
		return false
	from.set_slot(index, what, left)
	return true


## Puts whatever is on the cursor back, so closing a screen never eats a stack.
func spill_into(inv: Inventory) -> void:
	if is_empty():
		return
	inv.add(item, count)
	set_to("", 0)
