class_name StoragePanel
extends Control

## The window a wardrobe or a chest opens behind.
##
## Only the frame so far: the plate, dimmed world behind it, and the rules for
## how big it is and where it sits. The slots that will live inside it are the
## next job -- what this fixes now is the shape they get to fill, because that
## is what every later measurement is taken from.
##
## The shape is 16:10 and stays 16:10. A storage window is read as a grid, and a
## grid wants a stable frame: if the window followed the screen's aspect the
## same chest would be a different shape on every machine, and the row and
## column counts that look right on one would be wrong on the next. So the panel
## is authored once at `BASE_SIZE` in source pixels and only ever multiplied by
## a whole number, which keeps both the ratio exact and the pixel art sharp.

## Fires when the window goes away, however it went -- the key it was opened
## on, so whoever opened it can put the furniture back. A chest's lid belongs to
## its window: dismissing the window with Esc has to shut the lid too, or the
## room is left standing open with nothing on screen to explain it.
signal closed(key: String)

const PANEL_BOX := preload("res://Assets/UI/Panel_Plate.tres")

## The lighter plate the two halves are drawn on. A plate the same shade as the
## window would vanish into it, so the halves step one shade up the pack's
## ladder -- the same way the profile screen floats its boxes on its frame.
const INNER_BOX := preload("res://Assets/UI/Panel_Plate_Tip.tres")

## The padding inside the plates, as their .tres files set them.
const PAD := 8
const INNER_PAD := 7
## Space between the two halves.
const SPLIT_GAP := 6

## One slot and the gap between them, matching the profile screen's grid.
const SLOT := Vector2(30, 32)
const SLOT_GAP := 4

## The window in source pixels, 16:10. Multiplied by a whole-number zoom; never
## stretched, so the ratio survives every screen size.
##
## Sized for nine slots across when it was one undivided space. Split in two it
## no longer holds nine to a half -- `columns_per_half` reports what it does
## hold, which is four. Worth knowing before the slots are built, because the
## shape is the part that cannot bend: the ratio is fixed, so more columns means
## a wider window rather than a different proportion.
const BASE_SIZE := Vector2(336, 210)

## What the window calls itself.
const TITLE := "STORAGE"

## The close button's mark. The pack's own X -- the same one the settings page
## uses for "off" -- so the window shuts with a glyph the game already speaks.
const CROSS := preload("res://Assets/UI/Cross.png")
## How much the X brightens under the mouse and dips when held. The pack ships
## no pressed variant of it, so the feedback is in the tint, the way
## ProfilePanel dresses its buttons.
const HOVER_TINT := Color(1.12, 1.12, 1.12)
const PRESS_TINT := Color(0.88, 0.88, 0.88)

## The ink and the rule under the heading, from the shared skin.
const INK := UISkin.TEXT_COLOR
const RULE := UISkin.RULE_COLOR

## What each half is called.
const LEFT_TITLE := "BACKPACK"
const RIGHT_TITLE := "CHEST"

## The most of the screen the window may take up before the zoom steps down.
## Leaves the hotbar and a margin of world visible around it.
const MAX_FILL := 0.82

## How dark the world goes behind the panel. The same wash the profile screen
## uses, so the two read as one game rather than two.
const DIM_COLOR := Color(0.1, 0.06, 0.04, 0.45)

## Which piece of furniture is open, as `PlayerState.storage_key` spells it.
## Nothing reads it yet; it is what the slots will be filled from.
var storage_key := ""

var hud: HUD

var _window: PanelContainer
var _dim: ColorRect
var _left: PanelContainer
var _right: PanelContainer
var _close_button: TextureButton
var _player_slots: Array[InventorySlot] = []
var _store_slots: Array[InventorySlot] = []
## The furniture's own contents, for as long as its window is up.
var _store: Inventory
## The stack riding on the cursor, and the rules for what a click does to it.
## The same object the profile screen uses, so picking a stack up here behaves
## exactly as it does there.
var _carry_stack := CarriedStack.new()
var _carry: InventorySlot


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visible = false
	get_viewport().size_changed.connect(_recenter)


## Hooks the panel to a HUD, which is where its zoom comes from.
func bind(target: HUD) -> void:
	if hud != null and hud.inventory != null:
		if hud.inventory.changed.is_connected(_refresh):
			hud.inventory.changed.disconnect(_refresh)
	hud = target
	# Built here rather than in _ready: the grids are sized from the HUD's zoom
	# and filled from its bag, and neither is known before this.
	_build()
	if hud.inventory != null:
		hud.inventory.changed.connect(_refresh)
	_refresh()
	_recenter()


func is_open() -> bool:
	return visible


## Opens on one piece of furniture. `key` identifies it -- see
## `PlayerState.storage_key` -- so reopening the same chest later comes back to
## the same contents once there are contents to come back to.
func open(key: String) -> void:
	_unbind_store()
	storage_key = key
	# Which chest this is only becomes known now, so the right-hand grid is
	# pointed at its contents here rather than at build time.
	_store = PlayerState.storage_for(key)
	_store.changed.connect(_refresh)
	visible = true
	_refresh()
	_recenter()


func close() -> void:
	# Only a window that was actually up has anything to announce; closing one
	# that is already shut would shut the furniture a second time.
	if not visible:
		return
	# The X keeps whatever tint the mouse left on it otherwise, and wears it
	# the next time the window opens.
	if _close_button != null:
		_close_button.self_modulate = Color.WHITE
	# Whatever is on the cursor goes back in the bag. Closing a window is not
	# a way to destroy a stack, and the bag is the one container that is always
	# there to put it in.
	if _bag() != null:
		_carry_stack.spill_into(_bag())
	var was := storage_key
	visible = false
	storage_key = ""
	_unbind_store()
	closed.emit(was)


## Lets go of the furniture's inventory. Left connected, a closed window would
## keep redrawing slots for a chest nobody is standing at.
func _unbind_store() -> void:
	if _store != null and _store.changed.is_connected(_refresh):
		_store.changed.disconnect(_refresh)
	_store = null


func toggle(key: String) -> void:
	if visible and storage_key == key:
		close()
	else:
		open(key)


func _build() -> void:
	# Binding again -- a HUD that swapped its bag, say -- rebuilds rather than
	# stacking a second window on top of the first.
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_player_slots.clear()
	_store_slots.clear()

	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	# STOP, not IGNORE: while the window is up a click belongs to it, not to
	# the hoe swing underneath.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_window = PanelContainer.new()
	_window.add_theme_stylebox_override("panel", PANEL_BOX)
	_window.custom_minimum_size = BASE_SIZE
	_window.size = BASE_SIZE
	add_child(_window)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_window.add_child(box)

	# The heading and the close button share a row, so the X sits on the title's
	# line at the top right rather than floating over the plate.
	var head := HBoxContainer.new()
	box.add_child(head)

	var title := Label.new()
	title.text = TITLE
	title.add_theme_font_override("font", UIFont.title())
	title.add_theme_font_size_override("font_size", UIFont.SIZE)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)

	_close_button = TextureButton.new()
	_close_button.texture_normal = CROSS
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(close)
	_close_button.mouse_entered.connect(func() -> void:
			_close_button.self_modulate = HOVER_TINT)
	_close_button.mouse_exited.connect(func() -> void:
			_close_button.self_modulate = Color.WHITE)
	_close_button.button_down.connect(func() -> void:
			_close_button.self_modulate = PRESS_TINT)
	_close_button.button_up.connect(func() -> void:
			_close_button.self_modulate = Color.WHITE)
	head.add_child(_close_button)

	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)

	# The two halves. Both take an equal share of the width and all of what is
	# left below the heading, so they reach the bottom of the window whatever
	# zoom it is drawn at.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", SPLIT_GAP)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(split)

	_left = _half(LEFT_TITLE, _player_slots, hud.inventory.size() if hud != null
			and hud.inventory != null else 0, false)
	_right = _half(RIGHT_TITLE, _store_slots, PlayerState.STORAGE_SLOTS, true)
	split.add_child(_left)
	split.add_child(_right)

	# The carried stack is drawn last so it rides over everything, and is only
	# an icon -- no slot plate behind it.
	_carry = InventorySlot.new()
	_carry.show_background = false
	_carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if hud != null:
		_carry.icon_scale = hud.item_icon_scale
	_carry.visible = false
	add_child(_carry)
	_carry_stack.changed.connect(_sync_carry)


## One side of the window: a lighter plate that fills its share of the width,
## stretches to the bottom, and scrolls its grid when the slots outrun it.
##
## Both sides are built the same way on purpose. A bag and a chest are the same
## thing to look at, and the moment they are built by two different routines
## they start to drift -- different gaps, different scroll feel.
func _half(title: String, into: Array[InventorySlot], slots: int,
		is_store: bool) -> PanelContainer:
	var half := PanelContainer.new()
	half.add_theme_stylebox_override("panel", INNER_BOX)
	half.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	half.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	half.add_child(column)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_override("font", UIFont.body())
	heading.add_theme_font_size_override("font_size", UIFont.SIZE)
	heading.add_theme_color_override("font_color", UISkin.MUTED_COLOR)
	column.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.theme = UISkin.scroll_theme()
	column.add_child(scroll)
	# The bar's width comes from its art; the sliced boxes carry no minimum.
	scroll.get_v_scroll_bar().custom_minimum_size.x = UISkin.SCROLLBAR_WIDTH

	# The bar sits on the scroll area's right edge, so the grid is held a gap
	# clear of it rather than running underneath it.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_right",
			UISkin.SCROLLBAR_WIDTH + SLOT_GAP)
	scroll.add_child(margin)

	var grid := GridContainer.new()
	grid.columns = columns_per_half()
	grid.add_theme_constant_override("h_separation", SLOT_GAP)
	grid.add_theme_constant_override("v_separation", SLOT_GAP)
	margin.add_child(grid)

	for i in slots:
		var slot := InventorySlot.new()
		slot.index = i
		if hud != null:
			slot.icon_scale = hud.item_icon_scale
		# Which grid was clicked is bound here, so the handler knows which
		# inventory the index belongs to and which one is "the other one".
		# Passed in rather than worked out from `into`: comparing arrays in
		# GDScript compares their contents, and both are empty at build time,
		# so the backpack would have been wired to the chest.
		slot.pressed.connect(_on_slot_pressed.bind(is_store))
		grid.add_child(slot)
		into.append(slot)
	return half


## A click on a slot, by the rules every inventory screen in the game shares.
##
## Shift sends the stack straight across to the other container without it
## touching the cursor; otherwise left and right click pick up, put down, merge,
## split and swap, which is all CarriedStack's business rather than this
## window's. Both inventories announce their own changes, so nothing is redrawn
## by hand here.
func _on_slot_pressed(index: int, button: int, from_store: bool) -> void:
	var here: Inventory = _store if from_store else _bag()
	var there: Inventory = _bag() if from_store else _store
	if here == null:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		# Only with empty hands: shift-clicking while carrying something would
		# have to guess whether the stack on the cursor or the one in the slot
		# was meant, and guessing wrong loses items.
		if _carry_stack.is_empty() and there != null:
			_carry_stack.quick_move(here, index, there)
		return
	if button == MOUSE_BUTTON_LEFT:
		_carry_stack.left_click(here, index)
	elif button == MOUSE_BUTTON_RIGHT:
		_carry_stack.right_click(here, index)


func _bag() -> Inventory:
	return hud.inventory if hud != null else null


## Draws the stack on the cursor, and keeps it under the mouse.
func _sync_carry() -> void:
	if _carry == null:
		return
	_carry.item = _carry_stack.item
	_carry.count = _carry_stack.count
	_carry.visible = not _carry_stack.is_empty()


func _process(_delta: float) -> void:
	if not visible or _carry == null or _carry_stack.is_empty():
		return
	var zoom := _zoom()
	_carry.position = (get_viewport().get_mouse_position()
			- _carry.size * zoom * 0.5).round()


## Draws both grids from whatever they are standing for right now.
func _refresh(_slot: int = 0) -> void:
	_fill(_player_slots, hud.inventory if hud != null else null)
	_fill(_store_slots, _store)


func _fill(slots: Array[InventorySlot], from: Inventory) -> void:
	for slot in slots:
		var has: bool = from != null and slot.index < from.size()
		slot.item = from.item_at(slot.index) if has else ""
		slot.count = from.count_at(slot.index) if has else 0


## How many slots fit across one half, at the window's authored size.
##
## The scrollbar and the gap holding the grid clear of it come off the width
## first. Leaving them out reports one column too many, and a grid one column
## too wide does not overflow quietly -- it pushes its half past the plate,
## because a container cannot shrink below what its contents need.
func columns_per_half() -> int:
	var inner := (BASE_SIZE.x - PAD * 2 - SPLIT_GAP) / 2.0 - INNER_PAD * 2
	var usable := inner - UISkin.SCROLLBAR_WIDTH - SLOT_GAP
	return int(floorf((usable + SLOT_GAP) / (SLOT.x + SLOT_GAP)))


## The zoom to draw at: the HUD's, stepped down until the window fits the
## screen with room to spare. Whole numbers only -- a fractional zoom on pixel
## art puts seams through the plate's border.
func _zoom() -> int:
	var want: int = hud.ui_scale if hud != null else 2
	var room := get_viewport_rect().size * MAX_FILL
	while want > 1 and (BASE_SIZE.x * want > room.x or BASE_SIZE.y * want > room.y):
		want -= 1
	return want


func _recenter() -> void:
	# A Control under a CanvasLayer gets no size from anchors, so fit the screen
	# by hand -- the same thing ProfilePanel has to do.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if _dim != null:
		_dim.position = Vector2.ZERO
		_dim.size = size
	if _window == null:
		return
	var zoom := _zoom()
	if _carry != null:
		_carry.scale = Vector2.ONE * zoom
	_window.scale = Vector2.ONE * zoom
	_window.size = BASE_SIZE
	_window.position = ((size - BASE_SIZE * zoom) * 0.5).round()
