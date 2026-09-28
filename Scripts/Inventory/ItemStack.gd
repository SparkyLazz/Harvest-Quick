class_name ItemStack
extends Resource

## What one occupied inventory slot holds: an item id and how many of it.
##
## Stacks are treated as values. Nothing hands the same [ItemStack] to two
## slots; moving one between slots moves the object, and splitting one
## makes a second. That is why [Inventory] never stores a stack it was
## given without taking ownership of it.
##
## An empty slot is [code]null[/code] rather than a stack of zero, so
## "is there anything here" is one null check instead of two.

## Key into [ItemDatabase]. See [member ItemData.id].
@export var id: StringName = &""
## How many. Always at least 1 while the stack is in a slot.
@export var count: int = 1

func _init(item_id: StringName = &"", amount: int = 1) -> void:
	id = item_id
	count = amount

## The shared definition behind this stack, or null if the id is unknown.
func data() -> ItemData:
	return ItemDb.get_item(id)

## Most of this item one slot can hold.
func max_stack() -> int:
	var item := data()
	return item.max_stack if item != null else 1

## Room left before this stack is full.
func space_left() -> int:
	return maxi(max_stack() - count, 0)

func is_full() -> bool:
	return count >= max_stack()

## Whether [param other] holds the same kind of item and so could merge
## into this one.
func matches(other: ItemStack) -> bool:
	return other != null and other.id == id

func copy() -> ItemStack:
	return ItemStack.new(id, count)

func _to_string() -> String:
	return "ItemStack(%s x%d)" % [id, count]
