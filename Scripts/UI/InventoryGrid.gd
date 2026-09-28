class_name InventoryGrid
extends Control

## A block of [ItemSlot]s over an [Inventory], laid out in rows.
##
## The grid owns nothing but the arrangement. Each slot binds itself to
## its index and listens for that index to change, so the grid never
## redraws: it builds the slots once and the inventory tells them apart
## from then on. Rebuilding only happens when the shape changes.
##
## The inventory's first row is the hotbar — the one row that is also on
## screen with the menu shut — so the grid leaves [member hotbar_divide]
## pixels of air under it. That gap is the only thing marking the row, and
## it is enough: the row underneath the gap is the bar you can see.
##
## The control sizes itself to its contents, which is what lets a
## [ScrollContainer] above it work out how far there is to scroll.

## Emitted when the pointer enters or leaves a slot. [param index] is -1
## on leaving.
signal slot_hovered(index: int)

@export var inventory: Inventory:
	set(value):
		inventory = value
		if is_node_ready():
			rebuild()
@export_range(1, 20) var columns: int = PlayerInventory.COLUMNS:
	set(value):
		columns = maxi(value, 1)
		if is_node_ready():
			rebuild()
## Cell art behind each item.
@export var slot_texture: Texture2D:
	set(value):
		slot_texture = value
		if is_node_ready():
			rebuild()
@export var slot_gap: int = 2:
	set(value):
		slot_gap = maxi(value, 0)
		if is_node_ready():
			rebuild()
## Air left under the hotbar row. 0 runs the rows together.
@export var hotbar_divide: int = 8:
	set(value):
		hotbar_divide = maxi(value, 0)
		if is_node_ready():
			rebuild()
## Cell pixels kept clear around each icon. The menu's cells are smaller
## than the hotbar's, so they need a tighter margin to leave the icon
## room. See [member ItemSlot.icon_inset].
@export var icon_inset: int = 4:
	set(value):
		icon_inset = maxi(value, 0)
		if is_node_ready():
			rebuild()

var _slots: Array[ItemSlot] = []

func _ready() -> void:
	rebuild()

## The slot showing [param index], or null if the grid is not built or
## does not reach that far.
func slot_for(index: int) -> ItemSlot:
	return _slots[index] if index >= 0 and index < _slots.size() else null

func rebuild() -> void:
	for slot in _slots:
		slot.queue_free()
	_slots.clear()

	if inventory == null or slot_texture == null:
		custom_minimum_size = Vector2.ZERO
		return

	var cell := slot_texture.get_size()
	for i in inventory.slot_count():
		var slot := ItemSlot.new()
		slot.texture = slot_texture
		slot.icon_inset = icon_inset
		slot.size = cell
		slot.pivot_offset = cell * 0.5
		slot.position = _origin(i, cell)
		slot.bind(inventory, i)
		slot.hovered.connect(slot_hovered.emit)
		add_child(slot)
		_slots.append(slot)

	var rows := ceili(float(inventory.slot_count()) / float(columns))
	custom_minimum_size = Vector2(
		columns * cell.x + maxi(columns - 1, 0) * slot_gap,
		rows * cell.y + maxi(rows - 1, 0) * slot_gap + hotbar_divide)
	size = custom_minimum_size

## Top-left of slot [param i]. Everything below the first row is pushed
## down by the divide.
func _origin(i: int, cell: Vector2) -> Vector2:
	var row := i / columns
	return Vector2(
		(i % columns) * (cell.x + slot_gap),
		row * (cell.y + slot_gap) + (hotbar_divide if row > 0 else 0))
