class_name Inventory
extends RefCounted

## The player's stacks. Plain data with no UI: the hotbar simply shows the first
## few slots, so the rest can be given a bigger screen later without touching
## this. A slot is an item id plus a count; an empty slot has "" and 0.

## Emitted after any slot changes; `slot` is -1 when several did.
signal changed(slot: int)

var items: Array[String] = []
var counts: Array[int] = []


func _init(slot_total: int = 24) -> void:
	for i in maxi(slot_total, 1):
		items.append("")
		counts.append(0)


func size() -> int:
	return items.size()


func item_at(slot: int) -> String:
	return items[slot] if slot >= 0 and slot < items.size() else ""


func count_at(slot: int) -> int:
	return counts[slot] if slot >= 0 and slot < counts.size() else 0


func set_slot(slot: int, item: String, count: int) -> void:
	if slot < 0 or slot >= items.size():
		return
	items[slot] = item if count > 0 else ""
	counts[slot] = count if item != "" else 0
	changed.emit(slot)


## Total of one item across every slot.
func count_of(item: String) -> int:
	var total := 0
	for i in items.size():
		if items[i] == item:
			total += counts[i]
	return total


## Would `amount` of `item` fit right now?
func can_add(item: String, amount: int = 1) -> bool:
	return _room_for(item) >= amount


## Adds as much as fits, topping up existing stacks before opening new ones, and
## returns how many did not fit.
func add(item: String, amount: int = 1) -> int:
	if item == "" or amount <= 0:
		return amount
	var left := amount
	var cap := ItemDB.max_stack(item)
	for i in items.size():
		if left == 0:
			break
		if items[i] == item and counts[i] < cap:
			var moved := mini(cap - counts[i], left)
			counts[i] += moved
			left -= moved
	for i in items.size():
		if left == 0:
			break
		if items[i] == "":
			var moved := mini(cap, left)
			items[i] = item
			counts[i] = moved
			left -= moved
	if left != amount:
		changed.emit(-1)
	return left


## Takes `amount` out of one slot. False, and no change, if it holds less.
func remove_from_slot(slot: int, amount: int = 1) -> bool:
	if slot < 0 or slot >= items.size() or counts[slot] < amount:
		return false
	counts[slot] -= amount
	if counts[slot] == 0:
		items[slot] = ""
	changed.emit(slot)
	return true


func _room_for(item: String) -> int:
	if item == "":
		return 0
	var cap := ItemDB.max_stack(item)
	var room := 0
	for i in items.size():
		if items[i] == item:
			room += cap - counts[i]
		elif items[i] == "":
			room += cap
	return room
