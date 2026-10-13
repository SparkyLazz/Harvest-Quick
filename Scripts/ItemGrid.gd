class_name ItemGrid
extends GridContainer

## A block of inventory slots bound to one Inventory.
##
## Clicks and hovers are reported with the grid attached, so a screen showing
## two of these -- your bag and a wardrobe's -- can tell which one was touched
## without wiring every slot up twice.

signal slot_pressed(grid: ItemGrid, index: int, button: int)
signal slot_hovered(grid: ItemGrid, index: int, entered: bool)

var inventory: Inventory
var slots: Array[InventorySlot] = []


func build(from: Inventory, column_count: int, gap: int, icon_scale: float,
		hotkey_count: int = 0) -> void:
	inventory = from
	columns = maxi(column_count, 1)
	add_theme_constant_override("h_separation", gap)
	add_theme_constant_override("v_separation", gap)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	slots.clear()
	for i in inventory.size():
		var slot := InventorySlot.new()
		slot.index = i
		slot.icon_scale = icon_scale
		slot.hotkey = i + 1 if i < hotkey_count else 0
		slot.pressed.connect(_on_pressed)
		slot.hover_started.connect(_on_hover.bind(true))
		slot.hover_ended.connect(_on_hover.bind(false))
		add_child(slot)
		slots.append(slot)
	refresh()


## `held_index` draws one slot in the darker plate, for the hotbar selection.
func refresh(held_index: int = -1) -> void:
	if inventory == null:
		return
	for slot in slots:
		slot.item = inventory.item_at(slot.index)
		slot.count = inventory.count_at(slot.index)
		slot.held = slot.index == held_index


func set_hotkeys(shown: bool, hotkey_count: int) -> void:
	for slot in slots:
		slot.hotkey = (slot.index + 1 if slot.index < hotkey_count else 0) if shown else 0


func _on_pressed(index: int, button: int) -> void:
	slot_pressed.emit(self, index, button)


func _on_hover(index: int, entered: bool) -> void:
	slot_hovered.emit(self, index, entered)
