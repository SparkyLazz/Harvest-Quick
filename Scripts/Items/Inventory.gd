extends Node

## What the player is carrying, and which of it is in hand.
##
## An autoload, because two views already want the same answer — the hotbar
## along the bottom and the tool row inside the inventory window — and the
## player needs it too, to know what it is swinging. Keeping the contents
## here means none of the three owns it and none has to ask another.
##
## Slots are fixed: there are always [member slot_count] of them and an empty
## one is a null item, never a hole in an array. That way a slot's index is a
## place on screen, and picking something up does not shuffle what is already
## laid out.
##
## The views are told to redraw by [signal changed] and to move their cursor
## by [signal selection_changed]; neither is sent for a call that changed
## nothing, so a view may redraw everything and not flicker.

## Emitted when what is in the slots changes.
signal changed
## Emitted when a different slot comes to hand, with its index.
signal selection_changed(index: int)

## How many slots there are. Nine, to match the hotbar and the number keys.
const SLOT_COUNT: int = 9

## What a new farm is sent out with, slot by slot from the left, and how many
## of each. Tools come one apiece; anything that stacks comes in a handful,
## which for now is the only way a placeable reaches the player at all.
const STARTER_KIT: Dictionary[String, int] = {
	"res://Assets/Items/WateringCan.tres": 1,
	"res://Assets/Items/Hoe.tres": 1,
	"res://Assets/Items/Axe.tres": 1,
	"res://Assets/Items/Chest.tres": 8,
	"res://Assets/Crops/CarrotSeeds.tres": 12,
	"res://Assets/Crops/CauliflowerSeeds.tres": 12,
	"res://Assets/Crops/EggplantSeeds.tres": 12,
}

var _items: Array[ItemData] = []
var _counts: Array[int] = []
var _selected: int = 0

## Which slot is in hand.
var selected: int:
	get:
		return _selected
	set(value):
		var clamped := clampi(value, 0, SLOT_COUNT - 1)
		if clamped == _selected:
			return
		_selected = clamped
		selection_changed.emit(_selected)

func _ready() -> void:
	_items.resize(SLOT_COUNT)
	_counts.resize(SLOT_COUNT)
	grant_starter_kit()

## Fills the first slots with the tools every farm starts with. Anything
## already in those slots is replaced, so this is also how a new game resets.
func grant_starter_kit() -> void:
	var i := 0
	for path in STARTER_KIT:
		if i >= SLOT_COUNT:
			break
		var item := load(path) as ItemData
		if item != null:
			_items[i] = item
			_counts[i] = mini(STARTER_KIT[path], maxi(item.stack_size, 1))
		i += 1
	changed.emit()

## What is in slot [param index], or null if it is empty or out of range.
func item_at(index: int) -> ItemData:
	if index < 0 or index >= _items.size():
		return null
	return _items[index]

## How many of it are in slot [param index]. Zero for an empty slot.
func count_at(index: int) -> int:
	if index < 0 or index >= _counts.size():
		return 0
	return _counts[index]

## What is in hand, or null if that slot is empty.
func selected_item() -> ItemData:
	return item_at(_selected)

## Puts [param count] of [param item] in slot [param index], replacing
## whatever was there. A null item — or a count of zero or less — empties it.
func set_slot(index: int, item: ItemData, count: int = 1) -> void:
	if index < 0 or index >= _items.size():
		return
	if item == null or count <= 0:
		item = null
		count = 0
	else:
		count = mini(count, maxi(item.stack_size, 1))
	if _items[index] == item and _counts[index] == count:
		return
	_items[index] = item
	_counts[index] = count
	changed.emit()

## Empties slot [param index].
func clear_slot(index: int) -> void:
	set_slot(index, null)

## Takes [param count] out of slot [param index], emptying the slot if that
## leaves nothing in it. Returns how many were actually taken, which is
## fewer than asked for when the slot held fewer — so a caller spending one
## of something can tell a successful spend from an empty hand.
func take(index: int, count: int = 1) -> int:
	if index < 0 or index >= _items.size() or count <= 0:
		return 0
	var taken: int = mini(_counts[index], count)
	if taken <= 0:
		return 0
	_counts[index] -= taken
	if _counts[index] <= 0:
		_items[index] = null
		_counts[index] = 0
	changed.emit()
	return taken

## Finds a home for [param count] of [param item], topping up a stack of the
## same thing before opening a new slot. Returns how many would not fit.
func add(item: ItemData, count: int = 1) -> int:
	if item == null or count <= 0:
		return 0
	var left := count
	var cap: int = maxi(item.stack_size, 1)
	var touched := false
	# Stacks first, then empties, so picking two of a thing up leaves one
	# slot used rather than two.
	for pass_empties in [false, true]:
		for i in _items.size():
			if left <= 0:
				break
			var here: ItemData = _items[i]
			if pass_empties:
				if here != null:
					continue
				_items[i] = item
				_counts[i] = 0
			elif here != item or _counts[i] >= cap:
				continue
			var room: int = cap - _counts[i]
			var taken: int = mini(room, left)
			_counts[i] += taken
			left -= taken
			touched = true
	if touched:
		changed.emit()
	return left

## Whether [param count] of [param item] would fit, without putting any of
## it in.
##
## Asked before something is destroyed to produce it. A drop with nowhere to
## go is worse than a swing that did nothing — the player would lose the tree
## as well as the wood — so the question has to be answerable in advance.
func has_room_for(item: ItemData, count: int = 1) -> bool:
	if item == null or count <= 0:
		return true
	var cap: int = maxi(item.stack_size, 1)
	var room: int = 0
	for i in _items.size():
		if _items[i] == null:
			room += cap
		elif _items[i] == item:
			room += maxi(cap - _counts[i], 0)
		if room >= count:
			return true
	return false

## Moves the hand [param step] slots along, rolling off one end onto the other.
func step_selection(step: int) -> void:
	selected = posmod(_selected + step, SLOT_COUNT)
