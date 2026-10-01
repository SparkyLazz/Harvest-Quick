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
## The slots are one flat run, and the first [constant HOTBAR_COUNT] of them
## are the hotbar — the same arrangement Minecraft uses. That is why the grid
## in the inventory window starts at [constant HOTBAR_COUNT] rather than at
## zero: the row along the bottom of the screen is already showing the slots
## in front of it, and drawing them twice would only raise the question of
## which copy was the real one.
##
## Moving things about is all [method click_slot], which is the whole of the
## mouse's vocabulary: a stack is lifted onto the cursor, carried while
## nothing else can be done with it, and put down somewhere. That stack lives
## here rather than in the window, because it is as much the player's
## property as anything in a slot and must not be lost when the window shuts
## — see [method return_grab].
##
## The views are told to redraw by [signal changed] and to move their cursor
## by [signal selection_changed]; neither is sent for a call that changed
## nothing, so a view may redraw everything and not flicker.

## Emitted when what is in the slots changes.
signal changed
## Emitted when a different slot comes to hand, with its index.
signal selection_changed(index: int)
## Emitted when the stack on the cursor changes, including when it is put
## down and there is no longer one.
signal grab_changed

## How many slots the hotbar shows, and the number keys reach. The first
## slots of the satchel are those slots.
const HOTBAR_COUNT: int = 9

## How many slots there are altogether: the hotbar, plus the backpack behind
## it. The window's grid is built from this, so widening the satchel is this
## number and nothing else.
const SLOT_COUNT: int = 36

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

## The stack lifted onto the cursor, and how many of it. Null and zero when
## the cursor is empty, which is the resting state — nothing may be left on
## the cursor once the window is shut.
var _grabbed: ItemData = null
var _grabbed_count: int = 0

## Which slot is in hand.
var selected: int:
	get:
		return _selected
	set(value):
		# Clamped to the hotbar rather than to the whole satchel: the
		# backpack is storage, and a tool can only be swung from the row the
		# number keys reach.
		var clamped := clampi(value, 0, HOTBAR_COUNT - 1)
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
	selected = posmod(_selected + step, HOTBAR_COUNT)

## Whether [param index] is one of the hotbar slots.
func is_hotbar(index: int) -> bool:
	return index >= 0 and index < HOTBAR_COUNT

## What is on the cursor, or null when nothing is.
func grabbed_item() -> ItemData:
	return _grabbed

## How many are on the cursor.
func grabbed_count() -> int:
	return _grabbed_count

## Whether something is being carried on the cursor.
func has_grab() -> bool:
	return _grabbed != null and _grabbed_count > 0

## Answers a click on slot [param index].
##
## The whole of the mouse's vocabulary in one call, because every one of
## these cases is the same question — what should the cursor and this slot
## hold now? — and splitting them across several methods would only invite
## two of them to disagree about the answer.
##
## [param whole] is the left button: it lifts everything, puts everything
## down, and swaps when the slot holds something else. Clearing it is the
## right button: it lifts half and puts down one at a time, which is how a
## stack gets divided without any arithmetic being asked of the player.
##
## Returns whether anything moved, so a click a slot could not answer falls
## through rather than being swallowed.
func click_slot(index: int, whole: bool = true) -> bool:
	if index < 0 or index >= _items.size():
		return false
	var here: ItemData = _items[index]

	if not has_grab():
		if here == null:
			return false
		# Right-clicking an untouched stack takes the larger half, so one
		# click of three leaves one behind rather than two.
		var lift: int = _counts[index] if whole else (_counts[index] + 1) / 2
		_set_grab(here, lift)
		_take_silently(index, lift)
		changed.emit()
		return true

	var cap: int = maxi(_grabbed.stack_size, 1)
	if here == _grabbed:
		# The same thing, so top the slot up rather than swapping two
		# identical stacks — which would look to the player like the click
		# having done nothing at all.
		var room: int = cap - _counts[index]
		if room <= 0:
			return false
		var moved: int = mini(room, _grabbed_count if whole else 1)
		_counts[index] += moved
		_set_grab(_grabbed, _grabbed_count - moved)
		changed.emit()
		return true

	if here == null:
		var put: int = _grabbed_count if whole else 1
		_items[index] = _grabbed
		_counts[index] = put
		_set_grab(_grabbed, _grabbed_count - put)
		changed.emit()
		return true

	# Two different things, so they trade places. A right-click swaps as
	# well: there is no sensible way to put one of a thing into a slot that
	# already holds something else, and refusing outright would leave the
	# player no way to tell a full slot from a broken one.
	var displaced := here
	var displaced_count: int = _counts[index]
	_items[index] = _grabbed
	_counts[index] = mini(_grabbed_count, cap)
	_set_grab(displaced, displaced_count)
	changed.emit()
	return true

## Sends the stack in slot [param index] to the other half of the satchel —
## the backpack if it is in the hotbar, the hotbar if it is not. The
## shift-click.
##
## Returns whether anything moved. A stack with nowhere to go on the far side
## stays exactly where it is, so a shift-click that cannot finish the job is
## a click that did nothing rather than one that half-emptied a slot.
func quick_move(index: int) -> bool:
	if index < 0 or index >= _items.size():
		return false
	var item: ItemData = _items[index]
	if item == null:
		return false
	var from := 0 if not is_hotbar(index) else HOTBAR_COUNT
	var to := HOTBAR_COUNT if not is_hotbar(index) else SLOT_COUNT
	var left: int = _counts[index]
	var cap: int = maxi(item.stack_size, 1)

	# Stacks first, then empties — the same order [method add] uses, and for
	# the same reason.
	for pass_empties in [false, true]:
		for i in range(from, to):
			if left <= 0:
				break
			if pass_empties:
				if _items[i] != null:
					continue
				_items[i] = item
				_counts[i] = 0
			elif _items[i] != item or _counts[i] >= cap:
				continue
			var moved: int = mini(cap - _counts[i], left)
			_counts[i] += moved
			left -= moved

	if left == _counts[index]:
		return false
	_counts[index] = left
	if left <= 0:
		_items[index] = null
		_counts[index] = 0
	changed.emit()
	return true

## Puts whatever is on the cursor back into the satchel.
##
## Called when the window shuts and when a click lands on nothing, because
## those are the two ways a player can walk away in the middle of a move.
## There is nowhere else for it to go: the world has no way to receive a
## dropped stack yet, so losing it here would simply be the items ceasing to
## exist.
func return_grab() -> void:
	if not has_grab():
		return
	var left := add(_grabbed, _grabbed_count)
	# It came out of these slots and nothing has been added since, so there
	# is always room. Keeping any remainder on the cursor rather than
	# assuming so is what makes that assumption survivable if it ever stops
	# holding.
	_set_grab(_grabbed, left)

func _set_grab(item: ItemData, count: int) -> void:
	if item == null or count <= 0:
		item = null
		count = 0
	if _grabbed == item and _grabbed_count == count:
		return
	_grabbed = item
	_grabbed_count = count
	grab_changed.emit()

## Takes from a slot without announcing it, for a caller part way through a
## move that will announce the whole of it itself.
func _take_silently(index: int, count: int) -> void:
	_counts[index] -= count
	if _counts[index] <= 0:
		_items[index] = null
		_counts[index] = 0
