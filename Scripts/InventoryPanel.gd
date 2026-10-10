class_name InventoryPanel
extends Control

## The full inventory: a stretchy panel holding a scrolling grid of slots, a
## tooltip that shows after hovering an item for a moment, and click-to-move
## stacks. Everything is built from Control nodes. The panel, tooltip and
## scrollbar are sliced StyleBoxTextures, so they stretch to whatever they hold.
##
## Left click picks up a whole stack, drops it, merges it, or swaps it with the
## one underneath. Right click picks up half a stack, or drops a single item.

const PANEL_TEXTURE := preload("res://Assets/UI/Panel_Dark.png")
const TOOLTIP_TEXTURE := preload("res://Assets/UI/Tooltip_Box.png")
const SCROLL_TEXTURE := preload("res://Assets/UI/Scrollbar.png")
const TEXT_COLOR := Color("5a3d3d")
const MUTED_COLOR := Color("90625d")

@export_group("Layout")
## Whole-number zoom for the pixel art, matching the hotbar.
@export_range(1, 8) var pixel_scale: int = 2
## Slots per row. The first row is the hotbar.
@export_range(2, 12) var columns: int = 8
## Rows visible at once; the rest scroll.
@export_range(1, 8) var visible_rows: int = 3
## Gap between slots, in source pixels.
@export_range(0, 16) var slot_gap: int = 4

@export_group("Tooltip")
## Seconds the mouse must rest on an item before its details appear.
@export_range(0.0, 3.0, 0.05) var hover_delay: float = 0.5
## Width of the description text, in source pixels.
@export_range(60, 240) var tooltip_width: int = 110

var hud: HUD
var inventory: Inventory

var _window: PanelContainer
var _grid: GridContainer
var _slots: Array[InventorySlot] = []
var _carry: InventorySlot
var _carry_item := ""
var _carry_count := 0
var _tooltip: PanelContainer
var _tip_name: Label
var _tip_kind: Label
var _tip_body: Label
var _hover_slot := -1
var _hover_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	get_viewport().size_changed.connect(_recenter)


## Hooks the panel to a HUD and its inventory. Call again if the HUD swaps its
## inventory for a new one.
func bind(target: HUD) -> void:
	if hud != null and hud.slot_selected.is_connected(_refresh_all):
		hud.slot_selected.disconnect(_refresh_all)
	if inventory != null and inventory.changed.is_connected(_on_inventory_changed):
		inventory.changed.disconnect(_on_inventory_changed)
	hud = target
	inventory = hud.inventory
	pixel_scale = hud.ui_scale
	columns = hud.slot_count
	hud.slot_selected.connect(_refresh_all)
	inventory.changed.connect(_on_inventory_changed)
	_build()
	_refresh_all()


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if inventory == null:
		return
	visible = true
	_refresh_all()
	_recenter()


## Closing puts whatever is on the cursor back in the inventory.
func close() -> void:
	if _carry_item != "":
		inventory.add(_carry_item, _carry_count)
		_set_carry("", 0)
	_hide_tooltip()
	_hover_slot = -1
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	var mouse := get_viewport().get_mouse_position()
	if _carry_item != "":
		_carry.position = (mouse - _carry.size * pixel_scale * 0.5).round()
	if _hover_slot >= 0 and not _tooltip.visible and _carry_item == "":
		_hover_time += delta
		if _hover_time >= hover_delay:
			_show_tooltip(_hover_slot)
	if _tooltip.visible:
		_place_tooltip(_hover_slot)


# --- building ---------------------------------------------------------------

func _build() -> void:
	for child in get_children():
		child.queue_free()
		remove_child(child)
	_slots.clear()

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.04, 0.45)
	add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	_window = PanelContainer.new()
	_window.scale = Vector2.ONE * pixel_scale
	_window.add_theme_stylebox_override("panel", _sliced(PANEL_TEXTURE, 6, 9, 8))
	_window.resized.connect(_recenter)
	add_child(_window)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	_window.add_child(column)

	var title := Label.new()
	title.text = "INVENTORY"
	title.add_theme_font_override("font", UIFont.title())
	title.add_theme_font_size_override("font_size", UIFont.SIZE)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	column.add_child(title)

	var slot_size := HUD.SLOT_REGION.size
	var grid_width := int(columns * slot_size.x + (columns - 1) * slot_gap)
	var rows_height := int(visible_rows * slot_size.y + (visible_rows - 1) * slot_gap)
	var scrollbar_width := 11
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(grid_width + slot_gap + scrollbar_width, rows_height)
	scroll.theme = _scroll_theme()
	column.add_child(scroll)
	# The bar's width comes from its art; the sliced boxes carry no minimum.
	scroll.get_v_scroll_bar().custom_minimum_size.x = scrollbar_width
	# The scrollbar sits on the right edge of the scroll area; the margin keeps
	# the slots a gap clear of it.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right", slot_gap)
	scroll.add_child(margin)

	_grid = GridContainer.new()
	_grid.columns = columns
	_grid.add_theme_constant_override("h_separation", slot_gap)
	_grid.add_theme_constant_override("v_separation", slot_gap)
	margin.add_child(_grid)
	for i in inventory.size():
		var slot := InventorySlot.new()
		slot.index = i
		slot.icon_scale = hud.item_icon_scale
		slot.hotkey = i + 1 if i < hud.slot_count else 0
		slot.pressed.connect(_on_slot_pressed)
		slot.hover_started.connect(_on_hover_started)
		slot.hover_ended.connect(_on_hover_ended)
		_grid.add_child(slot)
		_slots.append(slot)
	_window.reset_size()

	_carry = InventorySlot.new()
	_carry.show_background = false
	_carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry.icon_scale = hud.item_icon_scale
	_carry.scale = Vector2.ONE * pixel_scale
	_carry.visible = false
	add_child(_carry)

	_build_tooltip()


func _build_tooltip() -> void:
	_tooltip = PanelContainer.new()
	_tooltip.scale = Vector2.ONE * pixel_scale
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.visible = false
	var box_style := _sliced(TOOLTIP_TEXTURE, 6, 8, 7)
	# The box art carries a 3px shadow along its bottom edge, so the text needs
	# less room there to look centred.
	box_style.content_margin_bottom = 5
	_tooltip.add_theme_stylebox_override("panel", box_style)
	add_child(_tooltip)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	_tooltip.add_child(box)
	_tip_name = _label(UIFont.title(), TEXT_COLOR)
	_tip_kind = _label(UIFont.body(), MUTED_COLOR)
	_tip_body = _label(UIFont.body(), TEXT_COLOR)
	_tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for label in [_tip_name, _tip_kind, _tip_body]:
		box.add_child(label)


func _label(font: Font, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", UIFont.SIZE)
	label.add_theme_color_override("font_color", color)
	return label


## A box that stretches: the corners stay put and the edges and middle grow.
## `edge` is how much of the texture is border; `pad` is the space inside it.
func _sliced(texture: Texture2D, edge: int, pad_x: int, pad_y: int) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = edge
	box.texture_margin_right = edge
	box.texture_margin_top = edge
	box.texture_margin_bottom = edge
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


## The scrollbar, sliced the same way: the grabber stretches along the bar, and
## the track stays 7px wide inside its 11px cell.
func _scroll_theme() -> Theme:
	var theme := Theme.new()
	theme.set_stylebox("scroll", "VScrollBar", _scroll_part(Rect2(33, 0, 11, 40), 5, 3))
	theme.set_stylebox("scroll_focus", "VScrollBar", _scroll_part(Rect2(33, 0, 11, 40), 5, 3))
	theme.set_stylebox("grabber", "VScrollBar", _scroll_part(Rect2(11, 0, 11, 21), 4, 5))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _scroll_part(Rect2(22, 0, 11, 21), 4, 5))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _scroll_part(Rect2(0, 0, 11, 21), 4, 5))
	return theme


func _scroll_part(region: Rect2, side: int, end: int) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SCROLL_TEXTURE
	atlas.region = region
	var box := StyleBoxTexture.new()
	box.texture = atlas
	box.texture_margin_left = side
	box.texture_margin_right = side
	box.texture_margin_top = end
	box.texture_margin_bottom = end
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box


# --- state ------------------------------------------------------------------

func _on_inventory_changed(_slot: int) -> void:
	_refresh_all()


func _refresh_all(_unused: int = 0) -> void:
	if inventory == null:
		return
	for slot in _slots:
		slot.item = inventory.item_at(slot.index)
		slot.count = inventory.count_at(slot.index)
		slot.held = slot.index == hud.selected_slot
	if _hover_slot >= 0 and _tooltip.visible:
		_show_tooltip(_hover_slot)


func _recenter() -> void:
	# A Control under a CanvasLayer gets no size from anchors, so fit the screen
	# by hand.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if _window == null:
		return
	var free := size - _window.size * pixel_scale
	_window.position = (free * 0.5).round()


func _set_carry(item: String, count: int) -> void:
	_carry_item = item
	_carry_count = count
	_carry.item = item
	_carry.count = count
	_carry.visible = item != ""


# --- clicks -----------------------------------------------------------------

func _on_slot_pressed(index: int, button: int) -> void:
	_hide_tooltip()
	_hover_time = 0.0
	var item := inventory.item_at(index)
	var count := inventory.count_at(index)
	if button == MOUSE_BUTTON_LEFT:
		_left_click(index, item, count)
	elif button == MOUSE_BUTTON_RIGHT:
		_right_click(index, item, count)


func _left_click(index: int, item: String, count: int) -> void:
	if _carry_item == "":
		if item != "":
			_set_carry(item, count)
			inventory.set_slot(index, "", 0)
	elif item == "":
		inventory.set_slot(index, _carry_item, _carry_count)
		_set_carry("", 0)
	elif item == _carry_item:
		var moved := mini(ItemDB.max_stack(item) - count, _carry_count)
		inventory.set_slot(index, item, count + moved)
		_carry_count -= moved
		_set_carry(_carry_item if _carry_count > 0 else "", _carry_count)
	else:
		inventory.set_slot(index, _carry_item, _carry_count)
		_set_carry(item, count)


func _right_click(index: int, item: String, count: int) -> void:
	if _carry_item == "":
		if item == "":
			return
		var half := (count + 1) / 2
		_set_carry(item, half)
		inventory.set_slot(index, item, count - half)
	elif item == "" or (item == _carry_item and count < ItemDB.max_stack(item)):
		inventory.set_slot(index, _carry_item, count + 1)
		_carry_count -= 1
		_set_carry(_carry_item if _carry_count > 0 else "", _carry_count)


# --- tooltip ----------------------------------------------------------------

func _on_hover_started(index: int) -> void:
	_hover_slot = index
	_hover_time = 0.0
	_hide_tooltip()


func _on_hover_ended(index: int) -> void:
	if _hover_slot == index:
		_hover_slot = -1
		_hide_tooltip()


func _show_tooltip(index: int) -> void:
	var item := inventory.item_at(index)
	if item == "":
		_hide_tooltip()
		return
	var count := inventory.count_at(index)
	_tip_name.text = ItemDB.display_name(item).to_upper()
	_tip_kind.text = ItemDB.kind_label(item).to_upper() \
			+ ("   x%d" % count if count > 1 else "")
	_tip_body.text = ItemDB.describe(item).to_upper()
	# Size the text column to what is actually written: the widest line of the
	# wrapped description, or the name if that is wider. A fixed width leaves a
	# dead strip on the right whenever the last word wraps early.
	var body_font := UIFont.body()
	var wrapped := body_font.get_multiline_string_size(_tip_body.text,
			HORIZONTAL_ALIGNMENT_LEFT, tooltip_width, UIFont.SIZE)
	var name_width := UIFont.title().get_string_size(_tip_name.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UIFont.SIZE).x
	var kind_width := body_font.get_string_size(_tip_kind.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, UIFont.SIZE).x
	_tip_body.custom_minimum_size.x = ceilf(maxf(wrapped.x, maxf(name_width, kind_width))) + 1.0
	_tooltip.reset_size()
	# Held back one frame: the text wraps against its new width only once laid
	# out, so the first frame's size is wrong.
	_tooltip.modulate.a = 0.0
	_tooltip.visible = true


func _hide_tooltip() -> void:
	if _tooltip:
		_tooltip.visible = false


## Hangs the tooltip under the hovered slot with their left edges lined up, or
## above it if there is no room below. Tracks the slot, so it stays put when the
## grid scrolls.
func _place_tooltip(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return
	# A Control only ever grows to fit; shrink it back every frame so a tall
	# first guess at the wrapped text does not stick.
	_tooltip.reset_size()
	_tooltip.modulate.a = 1.0
	var slot := _slots[index]
	var tip_size := _tooltip.size * pixel_scale
	var slot_pos := slot.global_position
	var slot_height := slot.size.y * pixel_scale
	var gap := 2.0 * pixel_scale
	var pos := Vector2(slot_pos.x, slot_pos.y + slot_height + gap)
	var screen := get_viewport_rect().size
	if pos.y + tip_size.y > screen.y - 4.0:
		pos.y = slot_pos.y - tip_size.y - gap
	pos.x = clampf(pos.x, 4.0, maxf(screen.x - tip_size.x - 4.0, 4.0))
	_tooltip.position = pos.round()
