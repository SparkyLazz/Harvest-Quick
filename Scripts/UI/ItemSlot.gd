class_name ItemSlot
extends TextureRect

## One inventory slot: a hand-drawn cell, the item's icon on top of it and
## a count in the bottom-right corner.
##
## The slot is a [TextureRect] so that its own [member TextureRect.texture]
## is the cell art, which lets the hotbar keep swapping between its two
## slot sizes and tweening [member Node2D.scale] exactly as it did before
## items existed. The icon and the count are children, so they come along
## with that scaling for free.
##
## Nothing is authored in a scene. The icon and the label are built in
## [method _ready], so a slot is [code]ItemSlot.new()[/code] wherever one
## is needed — which is how both the hotbar and the grid make theirs.
##
## A slot does not own its contents. It points at an [Inventory] and an
## index into it, watches [signal Inventory.slot_changed], and redraws
## when that index moves. Dragging never touches the visuals directly: it
## asks the inventory to move something and lets the signal come back.

## Emitted when the slot is clicked, after any drag would have started.
signal activated(index: int)
## Emitted when the pointer enters or leaves, so the panel can show what
## is under it. [param index] is -1 on leaving.
signal hovered(index: int)

const COUNT_FONT: Font = preload("res://Assets/UI/Fonts/pixelFont-4-7x7-sproutLands.ttf")
## Matches the lettering on the weather panel.
const COUNT_COLOUR := Color(0.565, 0.384, 0.365)
const COUNT_FONT_SIZE: int = 9
## Pixels of cell art to keep clear on each side of the icon in the
## full-size 42x44 cell, which leaves the icon at its native 32x32.
const DEFAULT_ICON_INSET: int = 5

## Pixels of cell art kept clear on each side of the icon. Smaller cells
## want a tighter margin, or the icon shrinks faster than the cell does.
var icon_inset: int = DEFAULT_ICON_INSET:
	set(value):
		icon_inset = maxi(value, 0)
		_layout()

## The inventory this slot is a window onto.
var inventory: Inventory
## Which slot of it. -1 until bound.
var index: int = -1

var _icon: TextureRect
var _count: Label

func _ready() -> void:
	# Drag and drop only reaches a control that takes the press itself,
	# and TextureRect does not stop the mouse by default.
	mouse_filter = Control.MOUSE_FILTER_STOP

	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_SCALE
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	_count = Label.new()
	_count.add_theme_font_override("font", COUNT_FONT)
	_count.add_theme_font_size_override("font_size", COUNT_FONT_SIZE)
	_count.add_theme_color_override("font_color", COUNT_COLOUR)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count)

	mouse_entered.connect(func() -> void: hovered.emit(index))
	mouse_exited.connect(func() -> void: hovered.emit(-1))

	_layout()
	refresh()

## Points the slot at [param source] slot [param slot_index] and redraws.
## Safe to call before the slot is in the tree.
func bind(source: Inventory, slot_index: int) -> void:
	if inventory != null and inventory.slot_changed.is_connected(_on_slot_changed):
		inventory.slot_changed.disconnect(_on_slot_changed)

	inventory = source
	index = slot_index

	if inventory != null:
		inventory.slot_changed.connect(_on_slot_changed)
	if is_node_ready():
		refresh()

## The stack this slot is showing, or null.
func stack() -> ItemStack:
	return inventory.stack_at(index) if inventory != null else null

## Redraws the icon and the count from the inventory.
func refresh() -> void:
	if _icon == null:
		return

	var held := stack()
	if held == null:
		_icon.texture = null
		_count.text = ""
		tooltip_text = ""
		return

	var item := held.data()
	_icon.texture = item.icon if item != null else null
	# A lone item reads as itself; only a stack needs a number on it.
	_count.text = str(held.count) if held.count > 1 else ""
	tooltip_text = ItemDb.get_display_name(held.id)

## Every slot hears about every change, so each one checks whether the
## change was its own before redrawing.
func _on_slot_changed(changed_index: int) -> void:
	if changed_index == index:
		refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()

# --- Drag and drop -----------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	var held := stack()
	if held == null:
		return null

	# Ctrl splits the stack. The split happens on drop, not here, so
	# letting go over nothing leaves the stack as it was.
	var amount := (held.count + 1) / 2 if Input.is_key_pressed(KEY_CTRL) else held.count
	set_drag_preview(_make_drag_preview(held.id, amount))
	return {
		"source": inventory,
		"index": index,
		"amount": amount,
	}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or not data.has("index"):
		return false
	# Only slots looking at the same inventory, which for now is all of
	# them: the hotbar row and the backpack are one array.
	return data.get("source") == inventory and inventory != null

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var from: int = data["index"]
	var amount: int = data.get("amount", -1)
	inventory.move(from, index, amount)

## A floating copy of the icon, held under the cursor while dragging.
func _make_drag_preview(id: StringName, amount: int) -> Control:
	# Godot centres the preview on the cursor, so wrap it: the wrapper
	# takes the centring and the icon inside it sits where we want.
	var wrapper := Control.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# The preview is parented to the viewport, outside the scaled Node2D
	# the slots live under, so it has to be sized in screen pixels or it
	# would come out half the size of the slot it left. The count goes up
	# by the same factor, for the same reason.
	var zoom := get_global_transform_with_canvas().get_scale()
	var on_screen := _icon.size * zoom

	var ghost := TextureRect.new()
	ghost.texture = ItemDb.get_icon(id)
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.size = on_screen
	ghost.position = -ghost.size * 0.5
	ghost.modulate.a = 0.85
	wrapper.add_child(ghost)

	if amount > 1:
		var label := Label.new()
		label.add_theme_font_override("font", COUNT_FONT)
		label.add_theme_font_size_override(
			"font_size", maxi(int(COUNT_FONT_SIZE * zoom.y), COUNT_FONT_SIZE))
		label.add_theme_color_override("font_color", COUNT_COLOUR)
		label.text = str(amount)
		label.size = ghost.size
		label.position = ghost.position
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		wrapper.add_child(label)

	return wrapper

# --- Input -------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		if event.shift_pressed and inventory == PlayerInventory.inventory:
			PlayerInventory.quick_move(index)
			accept_event()
			return
		activated.emit(index)

# --- Layout ------------------------------------------------------------

## Centres the icon in the cell and parks the count in its corner. Called
## on every resize, because the hotbar changes a slot's size when the
## selection moves.
func _layout() -> void:
	if _icon == null:
		return

	var side := mini(int(size.x), int(size.y)) - icon_inset * 2
	_icon.size = Vector2(side, side)
	_icon.position = ((size - _icon.size) * 0.5).round()

	# The count sits over the icon rather than beside it; the cell has no
	# room to spare, and a number in the corner of the art is the usual
	# place to look for one.
	_count.size = Vector2(size.x - icon_inset, size.y - icon_inset)
	_count.position = Vector2.ZERO
