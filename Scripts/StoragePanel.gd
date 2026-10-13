class_name StoragePanel
extends Control

## The wardrobe screen: your bag on the left, the wardrobe's on the right, with
## one stack on the cursor that can move between them.
##
## The click rules and the slot grids are shared with the profile screen (see
## CarriedStack and ItemGrid), so the two behave the same and only the layout
## is written here.
##
## Controls match what players expect from a chest:
##   left click    pick up or put down a whole stack, or swap
##   right click   take half, or put down one at a time
##   shift click   send the stack straight across to the other side

const PANEL_TEXTURE := preload("res://Assets/UI/Panel_Dark.png")
const INNER_TEXTURE := preload("res://Assets/UI/Panel_Light.png")
const TEXT_COLOR := Color("5a3d3d")
const MUTED_COLOR := Color("90625d")

## Both halves share this, so the two grids line up instead of stepping: the
## wardrobe is three rows of it and the bag five.
const COLUMNS := 9
const SLOT_GAP := 4
const WINDOW_PAD := 9
const PLATE_PAD := 8
## Clear space kept around the window at every resolution.
const EDGE_MARGIN := 24.0
const TOOLTIP_TEXTURE := preload("res://Assets/UI/Tooltip_Box.png")
const CREAM := Color("fff4dc")

var hud: HUD
var bag: Inventory
var store: Inventory
var title: String = "WARDROBE"

var _window: PanelContainer
var _bag_grid: ItemGrid
var _store_grid: ItemGrid
var _carry := CarriedStack.new()
var _carry_icon: InventorySlot
var _title_label: Label
var _scale := 2.0
## The frame this opened on. The same key press that opens a wardrobe is still
## travelling when the panel appears, so it would otherwise shut again at once.
var _opened_on := -1


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Shows the screen for one wardrobe. Called again for a different wardrobe,
## it simply rebinds -- the grids are only built once.
func open(owner_hud: HUD, player_bag: Inventory, contents: Inventory, label: String) -> void:
	hud = owner_hud
	bag = player_bag
	store = contents
	title = label
	_scale = float(hud.ui_scale)
	if _window == null:
		_build()
	_retitle()
	_bag_grid.build(bag, COLUMNS, SLOT_GAP, hud.item_icon_scale)
	_store_grid.build(store, COLUMNS, SLOT_GAP, hud.item_icon_scale)
	if not bag.changed.is_connected(_refresh):
		bag.changed.connect(_refresh)
	if not store.changed.is_connected(_refresh):
		store.changed.connect(_refresh)
	visible = true
	_opened_on = Engine.get_process_frames()
	_recentre()


## Closing puts whatever is on the cursor back in your bag, never the wardrobe,
## so a stack cannot be lost by shutting the lid on it.
func close() -> void:
	if bag != null:
		_carry.spill_into(bag)
	if bag != null and bag.changed.is_connected(_refresh):
		bag.changed.disconnect(_refresh)
	if store != null and store.changed.is_connected(_refresh):
		store.changed.disconnect(_refresh)
	visible = false


func is_open() -> bool:
	return visible


func _process(_delta: float) -> void:
	if not visible:
		return
	if not _carry.is_empty():
		var mouse := get_viewport().get_mouse_position()
		_carry_icon.position = (mouse - _carry_icon.size * _scale * 0.5).round()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("inventory") \
			or event.is_action_pressed("use"):
		close()
		get_viewport().set_input_as_handled()


# --- layout -----------------------------------------------------------------

func _build() -> void:
	_window = PanelContainer.new()
	_window.add_theme_stylebox_override("panel", _sliced(PANEL_TEXTURE, 6, WINDOW_PAD, WINDOW_PAD))
	_window.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_window)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	_window.add_child(page)
	page.add_child(_header())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	page.add_child(row)

	_bag_grid = ItemGrid.new()
	_store_grid = ItemGrid.new()
	row.add_child(_side("BACKPACK", _bag_grid))
	row.add_child(_transfer())
	row.add_child(_side(title, _store_grid))

	page.add_child(_hints())

	for grid in [_bag_grid, _store_grid]:
		grid.slot_pressed.connect(_on_slot_pressed)

	# The carried stack is drawn last so it rides over both grids.
	_carry_icon = InventorySlot.new()
	_carry_icon.show_background = false
	_carry_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry_icon.icon_scale = hud.item_icon_scale
	_carry_icon.visible = false
	add_child(_carry_icon)
	_carry.changed.connect(_sync_carry)

	get_viewport().size_changed.connect(_recentre)


## Title, the wardrobe's name, and a way out that is not a keypress.
func _header() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 5)
	_title_label = _label(UIFont.title(), TEXT_COLOR)
	_title_label.text = title
	bar.add_child(_title_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var shut := Button.new()
	shut.text = "X"
	shut.focus_mode = Control.FOCUS_NONE
	shut.add_theme_font_override("font", UIFont.title())
	shut.add_theme_font_size_override("font_size", UIFont.SIZE)
	shut.add_theme_color_override("font_color", TEXT_COLOR)
	shut.add_theme_stylebox_override("normal", _sliced(INNER_TEXTURE, 6, 4, 2))
	shut.add_theme_stylebox_override("hover", _sliced(PANEL_TEXTURE, 6, 4, 2))
	shut.add_theme_stylebox_override("pressed", _sliced(PANEL_TEXTURE, 6, 4, 2))
	shut.pressed.connect(close)
	bar.add_child(shut)
	return bar


## Moving a whole side at once, which clicking one stack at a time cannot.
func _transfer() -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_arrow(">>", "Store everything", _store_all))
	column.add_child(_arrow("<<", "Take everything", _take_all))
	return column


func _arrow(glyph: String, hint: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = glyph
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", UIFont.title())
	button.add_theme_font_size_override("font_size", UIFont.SIZE)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _sliced(INNER_TEXTURE, 6, 5, 4))
	button.add_theme_stylebox_override("hover", _sliced(PANEL_TEXTURE, 6, 5, 4))
	button.add_theme_stylebox_override("pressed", _sliced(PANEL_TEXTURE, 6, 5, 4))
	button.pressed.connect(action)
	return button


func _hints() -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _sliced(INNER_TEXTURE, 6, 6, 3))
	var line := _label(UIFont.body(), MUTED_COLOR)
	line.text = "CLICK TAKE   RIGHT HALF   SHIFT ACROSS   E CLOSE"
	plate.add_child(line)
	return plate


func _side(heading: String, grid: ItemGrid) -> Control:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	var head := _label(UIFont.title(), TEXT_COLOR)
	head.text = heading
	head.name = "Head"
	column.add_child(head)
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _sliced(INNER_TEXTURE, 6, PLATE_PAD, PLATE_PAD))
	plate.add_child(grid)
	column.add_child(plate)
	return column


func _retitle() -> void:
	if _title_label != null:
		_title_label.text = title
	if _store_grid == null:
		return
	var head := _store_grid.get_parent().get_parent().get_node_or_null("Head") as Label
	if head:
		head.text = title


## Sends every stack it can; anything that will not fit simply stays put.
func _store_all() -> void:
	_sweep(bag, store)


func _take_all() -> void:
	_sweep(store, bag)


func _sweep(from: Inventory, to: Inventory) -> void:
	if from == null or to == null:
		return
	for i in from.size():
		_carry.quick_move(from, i, to)


## Fits the window to whatever the screen is.
##
## Eighteen slots across is a wide thing to draw, so the preferred `ui_scale`
## does not fit every resolution -- at 2x it ran off both edges of a 1152-wide
## viewport. The window is measured unscaled, then given the largest scale that
## leaves a margin: whole numbers while they fit, so the pixel art stays crisp,
## and only below 1 does it fall to a fractional scale rather than be clipped.
func _recentre() -> void:
	size = get_viewport_rect().size
	if _window == null:
		return
	_window.scale = Vector2.ONE
	_window.reset_size()
	var natural := _window.size
	if natural.x <= 0.0 or natural.y <= 0.0:
		return
	var room := size - Vector2(EDGE_MARGIN, EDGE_MARGIN) * 2.0
	var fits := minf(room.x / natural.x, room.y / natural.y)
	var want := minf(float(hud.ui_scale if hud else 2), fits)
	_scale = floorf(want) if want >= 1.0 else maxf(want, 0.25)
	_window.scale = Vector2.ONE * _scale
	_window.position = ((size - natural * _scale) * 0.5).round()
	if _carry_icon:
		_carry_icon.scale = Vector2.ONE * _scale


# --- clicks -----------------------------------------------------------------

func _on_slot_pressed(grid: ItemGrid, index: int, button: int) -> void:
	var here := grid.inventory
	var other := store if here == bag else bag
	if Input.is_key_pressed(KEY_SHIFT):
		# Shift sends the stack across; the cursor is not involved.
		if _carry.is_empty():
			_carry.quick_move(here, index, other)
		return
	if button == MOUSE_BUTTON_LEFT:
		_carry.left_click(here, index)
	elif button == MOUSE_BUTTON_RIGHT:
		_carry.right_click(here, index)


func _sync_carry() -> void:
	_carry_icon.item = _carry.item
	_carry_icon.count = _carry.count
	_carry_icon.visible = not _carry.is_empty()


func _refresh(_slot: int = -1) -> void:
	_bag_grid.refresh()
	_store_grid.refresh()


# --- small helpers, matching the profile screen's plates --------------------

func _label(font: Font, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", UIFont.SIZE)
	label.add_theme_color_override("font_color", color)
	return label


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
