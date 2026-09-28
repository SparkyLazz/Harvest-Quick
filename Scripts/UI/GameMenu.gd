class_name GameMenu
extends CanvasLayer

## The menu behind E: a profile down the left, tabbed sections down the
## right, one panel of art for the lot.
##
## The two panels sit at a fixed one-to-two ratio, so the right is always
## twice the width of the left and the split does not wander when the
## window is resized. [member content_size] is the room inside the outer
## panel; everything else — where the divide falls, how wide a section
## viewport is, where the tab bar starts — is worked out from it, which is
## why there is one number to change rather than six.
##
## Sections are built once, all of them, and shown one at a time. Each one
## lives in its own [ScrollContainer], so a section longer than the
## viewport scrolls on the pixel-art bar without the others knowing
## anything about it; a tab is nothing more than which container is
## visible.
##
## All three panels are the same trick as the hotbar: a single block of
## art drawn as a [NinePatchRect]. The corners are hand-drawn pixels and
## only flat colour in the middle stretches, so no size the menu is ever
## asked to be costs a new texture.

## Group the menu joins while it is on screen, so anything that has to
## stand down while it is up can ask without knowing what a menu is.
const OPEN_GROUP := &"menu_open"

## Emitted when the menu opens or closes.
signal toggled(is_open: bool)
## Emitted when a different section is shown.
signal section_changed(id: StringName)

## The sections, in tab order: id, the icon's cell on the button sheet,
## and the tooltip.
const SECTIONS: Array = [
	[&"inventory", MenuTheme.ICON_BAG, "Backpack"],
	[&"almanac", MenuTheme.ICON_ALMANAC, "Almanac"],
	[&"stats", MenuTheme.ICON_FARM, "Farm"],
]

@export_group("Layout")
## Room inside the outer panel, in panel pixels. The left panel takes a
## third of the width and the right the rest, less the gap between them.
@export var content_size: Vector2i = Vector2i(482, 220):
	set(value):
		content_size = value
		if is_node_ready():
			_rebuild()
## Space between the outer panel's edge and the two inner ones.
@export var padding: int = 10:
	set(value):
		padding = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space between the profile panel and the section panel.
@export var panel_gap: int = 8:
	set(value):
		panel_gap = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space inside a panel, between its edge and its contents.
@export var inner_padding: int = 8:
	set(value):
		inner_padding = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space between two tab buttons.
@export var tab_gap: int = 2:
	set(value):
		tab_gap = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space between a section and its scrollbar.
@export var scroll_gap: int = 4:
	set(value):
		scroll_gap = maxi(value, 0)
		if is_node_ready():
			_rebuild()
## Space under the tab bar, before the section starts.
@export var tab_bar_gap: int = 6:
	set(value):
		tab_bar_gap = maxi(value, 0)
		if is_node_ready():
			_rebuild()

## Nudge from the middle of the screen, in panel pixels. The default
## lifts the window clear of the hotbar along the bottom edge.
@export var centre_offset: Vector2i = Vector2i(0, -20):
	set(value):
		centre_offset = value
		if is_node_ready():
			_reposition()

@export_group("Art")
## Nine-patch block the outer window is drawn from.
@export var window_texture: Texture2D
## Nine-patch block the two inner panels are drawn from.
@export var panel_texture: Texture2D
## Size of the corner artwork in both blocks.
@export var patch_margin: int = 10
## Cell art behind each item in the backpack grid.
@export var slot_texture: Texture2D

@export_group("Motion")
## Seconds the menu takes to pop open or drop shut. 0 snaps.
@export var open_duration: float = 0.14

@onready var _root: Node2D = $Root
@onready var _window: NinePatchRect = $Root/Window

var _profile: ProfilePanel
var _sections_panel: NinePatchRect
var _tabs: Dictionary[StringName, TextureButton] = {}
var _views: Dictionary[StringName, ScrollContainer] = {}
var _bars: Dictionary[StringName, PixelScrollBar] = {}
var _grid: InventoryGrid
var _caption: Label
var _current: StringName = &""
var _tween: Tween
var _is_open: bool = false

## Whether the menu is on screen.
var is_open: bool:
	get:
		return _is_open

## Which section is showing.
var section: StringName:
	get:
		return _current

func _ready() -> void:
	_rebuild()
	# Park the menu where a close leaves it, so the first open pops like
	# every one after it.
	_window.scale = Vector2.ZERO
	_window.modulate.a = 0.0
	_root.visible = false
	get_viewport().size_changed.connect(_reposition)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif _is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if _is_open:
		close()
	else:
		open()

func open() -> void:
	if _is_open:
		return
	_is_open = true
	add_to_group(OPEN_GROUP)
	_root.visible = true
	_animate_to(1.0)
	_profile.greet()
	toggled.emit(true)

func close() -> void:
	if not _is_open:
		return
	_is_open = false
	remove_from_group(OPEN_GROUP)
	_animate_to(0.0)
	toggled.emit(false)

## Shows section [param id]. Unknown ids are ignored.
func show_section(id: StringName) -> void:
	if not _views.has(id) or id == _current:
		return

	_current = id
	for key in _views:
		_views[key].visible = key == id
		# The bar hides itself when there is nothing to scroll, so it is
		# only ever shown along with its own section.
		if key != id:
			_bars[key].visible = false
		else:
			_bars[key].refresh()
		# A tab stays pressed while its section is the one showing, which
		# is the whole of what marks it as selected.
		# Setting it outright would fire the group's own toggling back at
		# us; the tab is being told, not clicked.
		_tabs[key].set_pressed_no_signal(key == id)
	_set_caption("")
	section_changed.emit(id)

# --- Motion ------------------------------------------------------------

func _animate_to(amount: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()

	if open_duration <= 0.0:
		_window.scale = Vector2.ONE * amount
		_window.modulate.a = amount
		_root.visible = amount > 0.0
		return

	_tween = create_tween().set_parallel()
	_tween.tween_property(_window, "scale", Vector2.ONE * amount, open_duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if amount > 0.0 else Tween.EASE_IN)
	_tween.tween_property(_window, "modulate:a", amount, open_duration)
	if amount <= 0.0:
		_tween.chain().tween_callback(func() -> void: _root.visible = false)

# --- Building ----------------------------------------------------------

func _rebuild() -> void:
	for child in _window.get_children():
		_window.remove_child(child)
		child.queue_free()
	_tabs.clear()
	_views.clear()
	_bars.clear()
	_current = &""

	if slot_texture == null:
		push_warning("GameMenu: slot_texture is not set; the backpack will be empty.")
		return

	_dress(_window, window_texture)
	_window.size = Vector2(content_size) + Vector2.ONE * padding * 2
	_window.pivot_offset = _window.size * 0.5

	var left_width := _left_width()
	var right_width := content_size.x - left_width - panel_gap

	_build_profile(left_width)
	_build_sections(left_width, right_width)

	show_section(SECTIONS[0][0])
	_reposition()

## A third of the room, so the right panel ends up with the other two
## thirds. Rounded down and the remainder given to the right, which is the
## side that has to fit a grid of a fixed width.
func _left_width() -> int:
	return (content_size.x - panel_gap) / 3

func _build_profile(width: int) -> void:
	_profile = ProfilePanel.new()
	_profile.texture = panel_texture
	_profile.panel_margin = patch_margin
	_profile.padding = inner_padding
	# The panel measures its portrait off its own width, so it has to know
	# how big it is before it enters the tree and builds itself.
	_profile.size = Vector2(width, content_size.y)
	_profile.position = Vector2(padding, padding)
	_window.add_child(_profile)

func _build_sections(left_width: int, width: int) -> void:
	_sections_panel = NinePatchRect.new()
	_dress(_sections_panel, panel_texture)
	_sections_panel.size = Vector2(width, content_size.y)
	_sections_panel.position = Vector2(padding + left_width + panel_gap, padding)
	_window.add_child(_sections_panel)

	var inner_width := width - inner_padding * 2
	_build_tab_bar(inner_width)

	# The caption sits on the bottom edge of the panel and names whatever
	# the pointer is over, the same as the hotbar's slots have tooltips.
	_caption = MenuTheme.label("", MenuTheme.TEXT_DIM)
	_caption.size.x = inner_width
	_caption.position = Vector2(
		inner_padding, content_size.y - inner_padding - MenuTheme.FONT_SIZE - 3)
	_sections_panel.add_child(_caption)

	var top := inner_padding + MenuTheme.BUTTON_SIZE + tab_bar_gap
	var view_height := int(_caption.position.y) - top - 4
	for entry in SECTIONS:
		_build_view(entry[0], inner_width, view_height, top)

## Each section gets a scroll view of the same size, stacked on top of one
## another; only the showing one is visible.
func _build_view(id: StringName, width: int, height: int, top: int) -> void:
	# The scrollbar sits beside the view rather than over it, so the view
	# is that much narrower and nothing is ever hidden under the knob.
	var content_width := width - MenuTheme.SCROLL_WIDTH - scroll_gap

	var view := ScrollContainer.new()
	view.size = Vector2(content_width, height)
	view.position = Vector2(inner_padding, top)
	view.clip_contents = true
	_sections_panel.add_child(view)
	_views[id] = view

	var content := _build_section(id)
	content.custom_minimum_size.x = content_width
	content.size.x = content_width
	view.add_child(content)

	var bar := PixelScrollBar.attach(view)
	bar.position = Vector2(inner_padding + content_width + scroll_gap, top)
	bar.size = Vector2(MenuTheme.SCROLL_WIDTH, height)
	_sections_panel.add_child(bar)
	_bars[id] = bar

func _build_section(id: StringName) -> Control:
	match id:
		&"inventory":
			_grid = InventoryGrid.new()
			_grid.inventory = PlayerInventory.inventory
			_grid.columns = PlayerInventory.COLUMNS
			_grid.slot_texture = slot_texture
			_grid.slot_hovered.connect(_on_slot_hovered)
			return _grid
		&"almanac":
			return AlmanacList.new()
		&"stats":
			return StatsList.new()
	return Control.new()

func _build_tab_bar(width: int) -> void:
	# One group across the tabs, which is what stops a second click on the
	# showing tab from unpressing it and leaving none of them marked.
	var group := ButtonGroup.new()
	var x := inner_padding
	for entry in SECTIONS:
		var id: StringName = entry[0]
		var button := MenuTheme.button(entry[1], entry[2])
		button.toggle_mode = true
		button.button_group = group
		button.position = Vector2(x, inner_padding)
		button.pressed.connect(show_section.bind(id))
		_sections_panel.add_child(button)
		_tabs[id] = button
		x += MenuTheme.BUTTON_SIZE + tab_gap

	# The close button is the same kind of button, parked on the far end
	# of the same row.
	var close_button := MenuTheme.button(MenuTheme.ICON_CLOSE, "Close")
	close_button.position = Vector2(
		inner_padding + width - MenuTheme.BUTTON_SIZE, inner_padding)
	close_button.pressed.connect(close)
	_sections_panel.add_child(close_button)

func _dress(rect: NinePatchRect, texture: Texture2D) -> void:
	rect.texture = texture
	rect.patch_margin_left = patch_margin
	rect.patch_margin_top = patch_margin
	rect.patch_margin_right = patch_margin
	rect.patch_margin_bottom = patch_margin

# --- Readouts ----------------------------------------------------------

func _on_slot_hovered(index: int) -> void:
	if index < 0:
		_set_caption("")
		return
	var stack := PlayerInventory.inventory.stack_at(index)
	if stack == null:
		_set_caption("")
		return
	var item := stack.data()
	if item == null:
		_set_caption(String(stack.id))
		return
	_set_caption("%s — %s" % [item.display_name, item.description])

func _set_caption(text: String) -> void:
	if _caption != null:
		_caption.text = text

## Centres the menu on the screen.
func _reposition() -> void:
	var view := get_viewport().get_visible_rect().size
	var window := _window.size * _root.scale
	_root.position = ((view - window) * 0.5 + Vector2(centre_offset) * _root.scale).round()
