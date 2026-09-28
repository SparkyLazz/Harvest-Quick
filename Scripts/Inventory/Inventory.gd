class_name Inventory
extends Resource

## A fixed row of slots, each holding an [ItemStack] or nothing.
##
## This is data only: it knows how many of a thing fit in a slot and where
## a new pickup should land, and nothing about panels, drag previews or
## keys. The UI listens to [signal slot_changed] and redraws the one slot
## that moved, which is why the signal carries an index rather than just
## saying "something changed".
##
## Slot indices are flat. The grid is a UI decision — [PlayerInventory]
## picks the row width and everything else counts from 0.

## Emitted after slot [param index] gains, loses or swaps its contents.
signal slot_changed(index: int)
## Emitted once after a change that touched more than one slot, on top of
## the per-slot signals. Useful for anything that redraws wholesale.
signal contents_changed()

## One entry per slot; [code]null[/code] where the slot is empty.
@export var slots: Array[ItemStack] = []

func _init(size: int = 0) -> void:
	if size > 0:
		resize(size)

# --- Reading -----------------------------------------------------------

func slot_count() -> int:
	return slots.size()

func has_slot(index: int) -> bool:
	return index >= 0 and index < slots.size()

## The stack in [param index], or null if the slot is empty or the index
## is out of range.
func stack_at(index: int) -> ItemStack:
	return slots[index] if has_slot(index) else null

func is_empty(index: int) -> bool:
	return stack_at(index) == null

## How many more of [param id] would fit across the whole inventory,
## counting both room in part-filled stacks and empty slots.
func space_for(id: StringName) -> int:
	var item := ItemDb.get_item(id)
	if item == null:
		return 0

	var room := 0
	for stack in slots:
		if stack == null:
			room += item.max_stack
		elif stack.id == id:
			room += stack.space_left()
	return room

## Total count of [param id] held anywhere in the inventory.
func count_of(id: StringName) -> int:
	var total := 0
	for stack in slots:
		if stack != null and stack.id == id:
			total += stack.count
	return total

# --- Writing -----------------------------------------------------------

func resize(size: int) -> void:
	slots.resize(maxi(size, 0))
	contents_changed.emit()

## Puts [param stack] in [param index], discarding whatever was there.
## The inventory takes ownership; pass a [method ItemStack.copy] if the
## caller means to keep using it.
func set_stack(index: int, stack: ItemStack) -> void:
	if not has_slot(index):
		return
	slots[index] = stack if stack == null or stack.count > 0 else null
	slot_changed.emit(index)

func clear_slot(index: int) -> void:
	set_stack(index, null)

## Adds [param amount] of [param id], topping up matching stacks before
## opening empty slots, and returns however much did not fit.
##
## [param from] and [param to] narrow it to a range of slots; [param to]
## of -1 means "to the end". Quick-move uses that to aim at one row.
func add(id: StringName, amount: int = 1, from: int = 0, to: int = -1) -> int:
	var item := ItemDb.get_item(id)
	if item == null or amount <= 0:
		return amount

	var last := slots.size() if to < 0 else mini(to, slots.size())
	var first := maxi(from, 0)
	var left := amount
	var touched: Array[int] = []

	# Top up part-filled stacks first, so picking up a second turnip lands
	# on the turnips already held instead of eating a fresh slot.
	for i in range(first, last):
		if left <= 0:
			break
		var stack := slots[i]
		if stack == null or stack.id != id or stack.is_full():
			continue
		var fits := mini(stack.space_left(), left)
		stack.count += fits
		left -= fits
		touched.append(i)

	for i in range(first, last):
		if left <= 0:
			break
		if slots[i] != null:
			continue
		var fits := mini(item.max_stack, left)
		slots[i] = ItemStack.new(id, fits)
		left -= fits
		touched.append(i)

	for i in touched:
		slot_changed.emit(i)
	if touched.size() > 1:
		contents_changed.emit()
	return left

## Takes up to [param amount] out of [param index] and returns it as its
## own stack, or null if the slot was empty. [param amount] of -1 takes
## the lot.
func take(index: int, amount: int = -1) -> ItemStack:
	var stack := stack_at(index)
	if stack == null:
		return null

	var taken := stack.count if amount < 0 else mini(amount, stack.count)
	if taken <= 0:
		return null

	if taken >= stack.count:
		slots[index] = null
	else:
		stack.count -= taken
	slot_changed.emit(index)
	return ItemStack.new(stack.id, taken)

## Takes the larger half, which is what a player splitting a stack of
## three expects to come away with.
func take_half(index: int) -> ItemStack:
	var stack := stack_at(index)
	if stack == null:
		return null
	return take(index, (stack.count + 1) / 2)

## Merges [param stack] into [param index] if the slot is empty or holds
## the same item, and returns whatever would not fit. The inventory takes
## ownership of what it keeps.
func put(index: int, stack: ItemStack) -> ItemStack:
	if stack == null or stack.count <= 0 or not has_slot(index):
		return stack

	var here := slots[index]
	if here == null:
		var cap := stack.max_stack()
		if stack.count <= cap:
			slots[index] = stack
			slot_changed.emit(index)
			return null
		slots[index] = ItemStack.new(stack.id, cap)
		slot_changed.emit(index)
		return ItemStack.new(stack.id, stack.count - cap)

	if not here.matches(stack):
		return stack

	var fits := mini(here.space_left(), stack.count)
	if fits <= 0:
		return stack
	here.count += fits
	slot_changed.emit(index)
	if fits >= stack.count:
		return null
	return ItemStack.new(stack.id, stack.count - fits)

func swap(a: int, b: int) -> void:
	if a == b or not has_slot(a) or not has_slot(b):
		return
	var keep := slots[a]
	slots[a] = slots[b]
	slots[b] = keep
	slot_changed.emit(a)
	slot_changed.emit(b)
	contents_changed.emit()

## Moves [param amount] from [param from_index] to [param to_index] within
## this inventory, merging onto a matching stack and otherwise swapping
## the two slots. [param amount] of -1 moves the whole stack.
##
## A partial move never swaps: dropping three of ten turnips onto a stack
## of wood would have to put the wood somewhere, and there is nowhere
## obvious for it to go, so the move is simply refused.
func move(from_index: int, to_index: int, amount: int = -1) -> void:
	if from_index == to_index:
		return
	var source := stack_at(from_index)
	if source == null or not has_slot(to_index):
		return

	var whole := amount < 0 or amount >= source.count
	var target := stack_at(to_index)

	if target == null or target.matches(source):
		var moving := take(from_index, amount)
		var left := put(to_index, moving)
		if left != null:
			# Bounced off a full stack: hand the remainder back.
			var returned := put(from_index, left)
			if returned != null:
				add(returned.id, returned.count)
		contents_changed.emit()
		return

	if whole:
		swap(from_index, to_index)

## Moves [param index] into the first slot in [param from]..[param to]
## that will take it, and returns true if anything moved. Used by the
## shift-click shortcut between the hotbar row and the backpack.
func quick_move(index: int, from: int, to: int) -> bool:
	var stack := stack_at(index)
	if stack == null:
		return false

	var last := slots.size() if to < 0 else mini(to, slots.size())
	var first := maxi(from, 0)

	# Merging is strictly better than opening a new slot, so look for a
	# part-filled match across the whole range before settling for a gap.
	for i in range(first, last):
		var here := slots[i]
		if here != null and here.matches(stack) and not here.is_full():
			var left := add(stack.id, stack.count, first, last)
			take(index, stack.count - left)
			contents_changed.emit()
			return left < stack.count

	for i in range(first, last):
		if slots[i] == null:
			move(index, i)
			return true
	return false
