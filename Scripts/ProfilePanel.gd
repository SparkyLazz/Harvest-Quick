class_name ProfilePanel
extends Control

## The player's screen, opened with E. Two columns: who you are on the left, and
## what you are doing on the right, behind a row of tabs.
##
## The left rail is a readout -- portrait, hearts, stamina, carry weight and a
## few running totals -- with one thing on it to play with: the cat wears a face
## from the pack's emote sheet that tracks how worn out you are, and prodding it
## makes it pull a different one. The right side swaps between pages:
##   Inventory  the full grid, with click-to-move stacks and hover tooltips
##   Crafting   recipes from RecipeDB, spent and granted against the inventory
##   Settings   UI scale, hotkey numbers and tooltips, plus the key list
##
## Everything is built from Control nodes and measured in source pixels; the
## whole window is then scaled by `pixel_scale` to match the zoomed-in pixel art,
## the same trick HUD.gd uses on the bars.
##
## Left click picks up a whole stack, drops it, merges it, or swaps it with the
## one underneath. Right click picks up half a stack, or drops a single item.

# One plate, three shades. The pack's boxes were 110x28 strips with their own
# palettes; these are the same rounded plate the storage window uses, recoloured
# a step down and a step up the pack's own shade ladder, so the whole UI is cut
# from one shape. The shades still carry meaning and must stay distinct: the
# frame is what the lighter plates sit on, and it is also what an unselected tab
# is drawn with.
const PANEL_TEXTURE := preload("res://Assets/UI/Panel_Plate_Dark.png")
const INNER_TEXTURE := preload("res://Assets/UI/Panel_Plate.png")
const TOOLTIP_TEXTURE := preload("res://Assets/UI/Panel_Plate_Tip.png")
const CHECK_TEXTURE := preload("res://Assets/UI/Check.png")
const CROSS_TEXTURE := preload("res://Assets/UI/Cross.png")
const EMOJI := preload("res://Assets/UI/Emoji.png")

const TEXT_COLOR := Color("5a3d3d")
const MUTED_COLOR := Color("90625d")
const SHORT_COLOR := Color("b5513f")
const RULE_COLOR := Color("c9a376")
const GRASS_COLOR := Color("a6c877")

## Bar tints, multiplied over the fill sprite's own green.
const STAMINA_COLOR := Color8(164, 194, 99)
const WEIGHT_COLOR := Color8(224, 182, 74)

## The portrait is one of the pack's cat emote faces rather than the walking
## sprite: the sprite is drawn to be read from across a field at 16px, while the
## emote sheet is drawn to be read close up, which is what a portrait is.
const PORTRAIT_SIZE := Vector2(108, 66)
const PORTRAIT_ZOOM := 2
## Cell size on the emote sheet. The same grid EmoteBubble reads.
const EMOJI_CELL := 32

## The resting faces, as (column, row) on the emote sheet. Which one the cat
## wears is the rail's quietest readout: you see how tired you are before you
## read the bar underneath.
const FACE_CALM := Vector2i(4, 2)
const FACE_SWEAT := Vector2i(1, 4)
const FACE_TIRED := Vector2i(9, 3)
const FACE_STUFFED := Vector2i(0, 5)
## Cycled through on each poke, so pressing the cat again always gives something
## it has not just done.
const FACE_POKES: Array[Vector2i] = [
	Vector2i(3, 2), Vector2i(0, 3), Vector2i(7, 2),
	Vector2i(3, 5), Vector2i(5, 2), Vector2i(1, 3),
]
## Seconds a poked face holds before the cat settles back to how it feels.
const POKE_HOLD := 1.8
## How far the cat lifts when the mouse is over it, in source pixels.
const PORTRAIT_HOVER_LIFT := 2

## What the key list calls each action. The action names are the game's own, and
## "inventory" has outlived its name.
const ACTION_LABELS := {
	"inventory": "OPEN PROFILE",
	"use": "USE / HARVEST",
	"run": "RUN",
}

## Width of the left rail, in source pixels.
const RAIL_WIDTH := 124
## Gap between the two columns, in source pixels.
const COLUMN_GAP := 8
## Space inside a plate, in source pixels: the dark window frame first, then the
## lighter plates it holds. Measured from the plate edge, not from its art, so
## raising these is how the whole panel is given more air.
const WINDOW_PAD_X := 10
const WINDOW_PAD_Y := 9
const PLATE_PAD_X := 9
const PLATE_PAD_Y := 8
## Space between the stacked blocks down the rail.
const RAIL_GAP := 7
## Side of one UI-scale step button on the settings tab, in source pixels.
const STEP_SIZE := 14
## The crafting detail card, in source pixels. Fixed, not fitted: the card used
## to be as big as whatever recipe was open, so picking "cauliflower" after
## "corn" grew it a line taller and a word wider and shoved the list beside it.
## Both of its labels are held to the tallest any recipe needs instead, which is
## measured from the recipes themselves -- so it is one size for all of them,
## with nothing clipped, and it resizes itself if the recipe list ever changes.
const DETAIL_WIDTH := 128
## How much narrower than its own width a label wraps. Measured, not guessed:
## see `_wrapped_height`.
const WRAP_SLACK := 3

const TAB_INVENTORY := 0
const TAB_CRAFTING := 1
const TAB_SETTINGS := 2
const TAB_NAMES := ["INVENTORY", "CRAFTING", "SETTINGS"]

@export_group("Layout")
## Whole-number zoom for the pixel art, matching the hotbar.
@export_range(1, 8) var pixel_scale: int = 2
## Slots per row. The first row is the hotbar.
@export_range(2, 12) var columns: int = 8
## Rows visible at once; the rest scroll. Five fills the height the left rail
## sets, and shows a default 40-slot pack whole.
@export_range(1, 8) var visible_rows: int = 5
## Gap between slots, in source pixels.
@export_range(0, 16) var slot_gap: int = 4

@export_group("Profile")
## Shown over the portrait. Blank falls back to the project name.
@export var player_name: String = "Rui"

@export_group("Tooltip")
## Seconds the mouse must rest on an item before its details appear.
@export_range(0.0, 3.0, 0.05) var hover_delay: float = 0.5
## Width of the description text, in source pixels.
@export_range(60, 240) var tooltip_width: int = 110

var hud: HUD
var inventory: Inventory

var _window: PanelContainer
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _tab := TAB_INVENTORY

var _grid: GridContainer
var _slots: Array[InventorySlot] = []
var _carry: InventorySlot
## The stack on the cursor and the rules for it, shared with the wardrobe
## screen so both behave the same way.
var _carry_stack := CarriedStack.new()

var _tooltip: PanelContainer
var _tip_name: Label
var _tip_kind: Label
var _tip_body: Label
var _hover_slot := -1
var _hover_time := 0.0
var _tooltips_on := true
var _hotkeys_on := true

## Each settings layout registers how its own widget shows a toggle, keyed by
## setting name, so flipping one does not have to know which layout is up.
var _toggle_views := {}
var _scale_steps: HBoxContainer

var _face_holder: Control
var _face_atlas: AtlasTexture
var _face_rest := Vector2.ZERO
var _poke_index := 0
## Seconds left on a poked face before the cat goes back to its resting one.
var _poke_left := 0.0
var _poke_tween: Tween

var _hearts: HBoxContainer
var _stamina_bar: PixelBar
var _stamina_text: Label
var _weight_bar: PixelBar
var _weight_text: Label
var _stat_values: Dictionary = {}
var _player: Player
var _farm: Farm

var _recipes: Array[Dictionary] = []
var _recipe_rows: Array[Button] = []
var _recipe_index := 0
var _craft_icon: InventorySlot
var _craft_name: Label
var _craft_body: Label
var _craft_cost: Label
var _craft_button: Button

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
	_find_scene_nodes()
	# The cat greets you with how it feels, not with whatever it was left mid-poke.
	_poke_left = 0.0
	_face_holder.scale = Vector2.ONE
	_face_holder.position = _face_rest
	_refresh_all()
	# Bars wind up from where they were last time otherwise, which reads as the
	# panel loading rather than as the value having changed.
	_sync_profile(true)
	_recenter()


## Closing puts whatever is on the cursor back in the inventory.
func close() -> void:
	_carry_stack.spill_into(inventory)
	_hide_tooltip()
	_hover_slot = -1
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	if _poke_left > 0.0:
		_poke_left -= delta
	_sync_profile()
	var mouse := get_viewport().get_mouse_position()
	if not _carry_stack.is_empty():
		_carry.position = (mouse - _carry.size * pixel_scale * 0.5).round()
	if _tab != TAB_INVENTORY:
		return
	if _hover_slot >= 0 and not _tooltip.visible and _carry_stack.is_empty() and _tooltips_on:
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
	_pages.clear()
	_tabs.clear()
	_stat_values.clear()
	_recipe_rows.clear()

	var dim := ColorRect.new()
	dim.color = Color(0.1, 0.06, 0.04, 0.45)
	add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	_window = PanelContainer.new()
	_window.scale = Vector2.ONE * pixel_scale
	_window.add_theme_stylebox_override("panel", _sliced(PANEL_TEXTURE, 6, WINDOW_PAD_X, WINDOW_PAD_Y))
	_window.resized.connect(_recenter)
	add_child(_window)

	var columns_row := HBoxContainer.new()
	columns_row.add_theme_constant_override("separation", COLUMN_GAP)
	_window.add_child(columns_row)
	columns_row.add_child(_build_rail())

	var work := VBoxContainer.new()
	work.add_theme_constant_override("separation", 4)
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns_row.add_child(work)
	work.add_child(_build_tabs())

	var page_host := PanelContainer.new()
	page_host.add_theme_stylebox_override("panel", _sliced(INNER_TEXTURE, 6, PLATE_PAD_X, PLATE_PAD_Y))
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	work.add_child(page_host)

	# Every page is stacked in the same spot and all but one hidden, so the
	# window keeps one size and the tabs do not make it jump.
	_pages = [_build_inventory_page(), _build_crafting_page(), _build_settings_page()]
	for page in _pages:
		page_host.add_child(page)
	# A hidden child counts for nothing in its parent's minimum size, so the
	# window would come out the size of whichever page happened to be open when
	# it was built. Pin the host to the largest of the three instead.
	var widest := Vector2.ZERO
	for page in _pages:
		var want := page.get_combined_minimum_size()
		widest = Vector2(maxf(widest.x, want.x), maxf(widest.y, want.y))
	page_host.custom_minimum_size = widest
	_show_tab(_tab)

	_window.reset_size()

	_carry = InventorySlot.new()
	_carry.show_background = false
	_carry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_carry.icon_scale = hud.item_icon_scale
	_carry.scale = Vector2.ONE * pixel_scale
	_carry.visible = false
	add_child(_carry)
	_carry_stack.changed.connect(_sync_carry)

	_build_tooltip()


## The left rail: portrait, name, hearts, the two bars and the running totals.
func _build_rail() -> Control:
	var rail := PanelContainer.new()
	rail.add_theme_stylebox_override("panel", _sliced(INNER_TEXTURE, 6, PLATE_PAD_X, PLATE_PAD_Y))
	rail.custom_minimum_size.x = RAIL_WIDTH
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", RAIL_GAP)
	rail.add_child(column)

	column.add_child(_build_portrait())

	var name_row := HBoxContainer.new()
	column.add_child(name_row)
	var who := _label(UIFont.title(), TEXT_COLOR)
	who.text = (player_name if player_name != "" else "FARMER").to_upper()
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(who)
	var held := _label(UIFont.body(), MUTED_COLOR)
	held.name = "Held"
	name_row.add_child(held)
	_stat_values["held"] = held

	_hearts = HBoxContainer.new()
	_hearts.add_theme_constant_override("separation", 2)
	_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_hearts)

	var stamina := _build_meter("STAMINA", STAMINA_COLOR, column)
	_stamina_bar = stamina[0]
	_stamina_text = stamina[1]
	var weight := _build_meter("PACK", WEIGHT_COLOR, column)
	_weight_bar = weight[0]
	_weight_text = weight[1]

	column.add_child(_rule())

	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 4)
	column.add_child(stats)
	for key: String in ["tilled", "watered", "growing", "kinds"]:
		stats.add_child(_build_stat(key))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(filler)
	return rail


## The cat on its patch of grass. It is a control you can press: clicking it
## pops a different face and bounces it, which is the one thing on this screen
## that exists purely to be played with.
func _build_portrait() -> Control:
	var portrait := Control.new()
	portrait.custom_minimum_size = PORTRAIT_SIZE
	portrait.clip_contents = true
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP
	portrait.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	portrait.gui_input.connect(_on_portrait_input)
	portrait.mouse_entered.connect(_on_portrait_hover.bind(true))
	portrait.mouse_exited.connect(_on_portrait_hover.bind(false))

	var field := ColorRect.new()
	field.color = GRASS_COLOR
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(field)
	field.set_anchors_preset(Control.PRESET_FULL_RECT)

	# The face sits in a holder of its own so the bounce scales the holder. The
	# pivot is the cat's chin, so a squash presses it into the grass rather than
	# floating it off the ground.
	var face_size := Vector2.ONE * EMOJI_CELL * PORTRAIT_ZOOM
	_face_holder = Control.new()
	_face_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_holder.custom_minimum_size = face_size
	_face_holder.size = face_size
	_face_holder.pivot_offset = Vector2(face_size.x * 0.5, face_size.y)
	_face_rest = ((PORTRAIT_SIZE - face_size) * 0.5).round()
	_face_holder.position = _face_rest
	portrait.add_child(_face_holder)

	_face_atlas = AtlasTexture.new()
	_face_atlas.atlas = EMOJI
	var face := TextureRect.new()
	face.texture = _face_atlas
	face.stretch_mode = TextureRect.STRETCH_KEEP
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.scale = Vector2.ONE * PORTRAIT_ZOOM
	_face_holder.add_child(face)
	_set_face(FACE_CALM)
	return portrait


func _set_face(cell: Vector2i) -> void:
	_face_atlas.region = Rect2(cell.x * EMOJI_CELL, cell.y * EMOJI_CELL,
			EMOJI_CELL, EMOJI_CELL)


## How the cat looks when it is left alone: tired before the stamina bar has to
## be read, and stuffed once the pack is nearly out of room.
func _resting_face() -> Vector2i:
	if is_instance_valid(_player) and _player.max_stamina > 0.0:
		var share := _player.stamina / _player.max_stamina
		if share <= 0.25:
			return FACE_TIRED
		if share <= 0.55:
			return FACE_SWEAT
	if _used_slots() >= inventory.size() - 2:
		return FACE_STUFFED
	return FACE_CALM


func _on_portrait_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_poke_cat()
		accept_event()


func _on_portrait_hover(inside: bool) -> void:
	if _face_holder == null:
		return
	_face_holder.position = _face_rest - Vector2(0, PORTRAIT_HOVER_LIFT if inside else 0)


## Squash, stretch, settle. The overshoot on the way back is what makes it read
## as a creature rather than a sprite being resized.
func _poke_cat() -> void:
	_set_face(FACE_POKES[_poke_index])
	_poke_index = (_poke_index + 1) % FACE_POKES.size()
	_poke_left = POKE_HOLD
	if _poke_tween and _poke_tween.is_valid():
		_poke_tween.kill()
	_poke_tween = create_tween()
	_poke_tween.tween_property(_face_holder, "scale", Vector2(1.16, 0.84), 0.07)
	_poke_tween.tween_property(_face_holder, "scale", Vector2(0.93, 1.1), 0.09)
	_poke_tween.tween_property(_face_holder, "scale", Vector2.ONE, 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A labelled bar. Returns [bar, value label] so the caller can keep both.
func _build_meter(title: String, tint: Color, into: Container) -> Array:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	into.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := _label(UIFont.body(), MUTED_COLOR)
	name_label.text = title
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := _label(UIFont.body(), TEXT_COLOR)
	row.add_child(value_label)
	var bar := PixelBar.new()
	bar.fill_color = tint
	box.add_child(bar)
	return [bar, value_label]


func _build_stat(key: String) -> Control:
	var row := HBoxContainer.new()
	var name_label := _label(UIFont.body(), MUTED_COLOR)
	name_label.text = key.to_upper()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := _label(UIFont.body(), TEXT_COLOR)
	value_label.text = "0"
	row.add_child(value_label)
	_stat_values[key] = value_label
	return row


func _build_tabs() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	for i in TAB_NAMES.size():
		var tab := Button.new()
		tab.text = TAB_NAMES[i]
		tab.focus_mode = Control.FOCUS_NONE
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 20
		tab.add_theme_font_override("font", UIFont.title())
		tab.add_theme_font_size_override("font_size", UIFont.SIZE)
		tab.pressed.connect(_show_tab.bind(i))
		row.add_child(tab)
		_tabs.append(tab)
	return row


func _build_inventory_page() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 5)
	page.add_child(_page_head("BACKPACK", "slots"))

	var slot_size := HUD.SLOT_REGION.size
	var grid_width := int(columns * slot_size.x + (columns - 1) * slot_gap)
	var rows_height := int(visible_rows * slot_size.y + (visible_rows - 1) * slot_gap)
	var scrollbar_width := 11
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(grid_width + slot_gap + scrollbar_width, rows_height)
	scroll.theme = _scroll_theme()
	page.add_child(scroll)
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
	return page


func _build_crafting_page() -> Control:
	_recipes = RecipeDB.all()
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 5)
	page.add_child(_page_head("WORKBENCH", "recipes"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(row)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.theme = _scroll_theme()
	scroll.get_v_scroll_bar().custom_minimum_size.x = 11
	row.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in _recipes.size():
		var entry := _build_recipe_row(_recipes[i], i)
		list.add_child(entry)
		_recipe_rows.append(entry)

	var detail := PanelContainer.new()
	detail.custom_minimum_size.x = DETAIL_WIDTH
	detail.add_theme_stylebox_override("panel", _sliced(TOOLTIP_TEXTURE, 6, 7, 6))
	detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(detail)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	detail.add_child(box)

	_craft_icon = InventorySlot.new()
	_craft_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_craft_icon.icon_scale = hud.item_icon_scale
	_craft_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_craft_icon)

	# The text inside the plate, once the stylebox's own padding is taken off.
	var inner := DETAIL_WIDTH - 7 * 2

	_craft_name = _label(UIFont.title(), TEXT_COLOR)
	_craft_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Wrapping rather than running on is what stops a long name from widening
	# the whole card; holding the height stops the wrap from making it taller.
	_craft_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_name.custom_minimum_size.x = inner
	box.add_child(_craft_name)
	_craft_name.custom_minimum_size.y = _tallest(_craft_name, _recipe_names(), inner)

	_craft_body = _label(UIFont.body(), MUTED_COLOR)
	_craft_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_body.custom_minimum_size.x = inner
	box.add_child(_craft_body)
	_craft_body.custom_minimum_size.y = _tallest(_craft_body, _recipe_bodies(), inner)

	_craft_cost = _label(UIFont.body(), TEXT_COLOR)
	_craft_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_craft_cost)

	_craft_button = Button.new()
	_craft_button.text = "CRAFT"
	_craft_button.focus_mode = Control.FOCUS_NONE
	_craft_button.custom_minimum_size.y = 19
	_craft_button.add_theme_font_override("font", UIFont.title())
	_craft_button.add_theme_font_size_override("font_size", UIFont.SIZE)
	_craft_button.add_theme_color_override("font_color", TEXT_COLOR)
	_craft_button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	_craft_button.add_theme_color_override("font_pressed_color", TEXT_COLOR)
	_craft_button.add_theme_color_override("font_disabled_color", MUTED_COLOR)
	_style_button(_craft_button, PANEL_TEXTURE)
	_craft_button.pressed.connect(_on_craft_pressed)
	box.add_child(_craft_button)
	return page


## Every recipe's name and blurb, as the card will show them.
func _recipe_names() -> Array[String]:
	var out: Array[String] = []
	for recipe in _recipes:
		out.append(String(recipe["name"]).to_upper())
	return out


func _recipe_bodies() -> Array[String]:
	var out: Array[String] = []
	for recipe in _recipes:
		out.append(RecipeDB.describe(recipe).to_upper())
	return out


## How tall `label` has to be to hold the longest of `lines` without growing.
##
## The wrap is worked out here rather than asked of the label, because a label
## only shapes its text once it is on screen: at build time the crafting page is
## still detached and hidden, so it reports one line for everything. Godot's
## `get_multiline_string_size` is no good either -- it breaks one line later
## than the label does, which is how a card sized by it ends up a line short for
## exactly the longest recipe.
##
## So the words are laid out the way the label lays them out, greedily, and the
## height follows from the line count. `test_craft_card.gd` checks the answer
## against what the label really does for every recipe, which is what keeps this
## honest if the font or the padding ever changes.
func _tallest(label: Label, lines: Array[String], width: int) -> float:
	var font := label.get_theme_font("font")
	var tallest := 0.0
	for line in lines:
		tallest = maxf(tallest, _wrapped_height(label, font, line, width))
	return tallest


func _wrapped_height(label: Label, font: Font, text: String, width: int) -> float:
	# A label breaks a line a pixel or two before the measured string actually
	# runs past its edge, so wrapping against the full width guesses one line
	# too few on the longest recipe. Wrapping against a slightly narrower line
	# errs the other way: the worst case that is reserved is never smaller than
	# the one the label lays out, which is the side to be wrong on.
	var usable := float(width) - WRAP_SLACK
	var count := 1
	var current := ""
	for word in text.split(" ", false):
		var candidate: String = word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1,
				UIFont.SIZE).x > usable:
			count += 1
			current = word
		else:
			current = candidate
	# Lines are spaced apart, not padded, so the gap falls between them only.
	var gap := label.get_theme_constant("line_spacing")
	return count * (font.get_height(UIFont.SIZE) + gap) - gap


func _build_recipe_row(recipe: Dictionary, index: int) -> Button:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_NONE
	row.custom_minimum_size.y = HUD.SLOT_REGION.size.y + 2
	row.pressed.connect(_select_recipe.bind(index))
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		row.add_theme_stylebox_override(state, StyleBoxEmpty.new())

	# A Button lays nothing out, so the row's contents are anchored to it by hand.
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	line.set_anchors_preset(Control.PRESET_FULL_RECT)

	var icon := InventorySlot.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.icon_scale = hud.item_icon_scale
	icon.item = recipe["out"]
	icon.count = int(recipe["out_count"])
	line.add_child(icon)

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(text)
	var name_label := _label(UIFont.title(), TEXT_COLOR)
	name_label.text = String(recipe["name"]).to_upper()
	name_label.name = "Name"
	text.add_child(name_label)
	var cost_label := _label(UIFont.body(), MUTED_COLOR)
	cost_label.name = "Cost"
	text.add_child(cost_label)
	return row


# --- settings ---------------------------------------------------------------

## Grouped on their own plates, the way a printed form is grouped: one titled
## block for what the panel looks like, one for the keys. It reads top to bottom
## and keeps working as more settings arrive.
func _build_settings_page() -> Control:
	_toggle_views.clear()
	var page := _settings_page_root()
	var look: Array[Control] = [
		_scale_row(),
		_toggle_row("hotkeys", "SHOW HOTKEYS"),
		_toggle_row("tooltips", "ITEM TOOLTIPS"),
	]
	page.add_child(_settings_group("DISPLAY", look))
	var keys: Array[Control] = []
	for action: String in ACTION_LABELS:
		keys.append(_key_row(action))
	page.add_child(_settings_group("CONTROLS", keys))
	page.add_child(_filler())
	return page


func _settings_group(title: String, rows: Array[Control]) -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", _sliced(TOOLTIP_TEXTURE, 6, 7, 6))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	plate.add_child(body)
	var head := _label(UIFont.title(), TEXT_COLOR)
	head.text = title
	body.add_child(head)
	body.add_child(_rule())
	for row in rows:
		body.add_child(row)
	return plate


func _settings_page_root() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 5)
	page.add_child(_page_head("SETTINGS", "live"))
	return page


func _filler() -> Control:
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return filler


## UI scale as a row of steps: one button per whole-number zoom the HUD allows.
## Each step is a plate small enough that the nine-slice leaves it octagonal,
## which is as good a shape for a numbered pip as any.
func _scale_row() -> Control:
	var row := HBoxContainer.new()
	row.add_child(_row_label("UI SCALE", TEXT_COLOR))
	_scale_steps = HBoxContainer.new()
	_scale_steps.add_theme_constant_override("separation", 2)
	row.add_child(_scale_steps)
	for n in range(1, 5):
		var step := Button.new()
		step.text = str(n)
		step.focus_mode = Control.FOCUS_NONE
		step.custom_minimum_size = Vector2(STEP_SIZE, STEP_SIZE)
		step.add_theme_font_override("font", UIFont.body())
		step.add_theme_font_size_override("font_size", UIFont.SIZE)
		step.pressed.connect(_on_scale_picked.bind(n))
		_scale_steps.add_child(step)
	_refresh_scale_steps()
	return row


## A setting's name, taking the width so whatever follows sits on the right edge.
func _row_label(text: String, color: Color) -> Label:
	var label := _label(UIFont.body(), color)
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


## A switch drawn as the pack's check or cross, on its own.
func _toggle_row(key: String, title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_row_label(title, TEXT_COLOR))
	var mark := TextureButton.new()
	mark.ignore_texture_size = true
	mark.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	mark.custom_minimum_size = Vector2(16, 14)
	mark.pressed.connect(_flip_toggle.bind(key))
	row.add_child(mark)
	_register_toggle(key, func(on: bool) -> void:
			mark.texture_normal = CHECK_TEXTURE if on else CROSS_TEXTURE)
	return row


## Hands a layout's own widget the job of showing a setting, and draws it once.
## The state then does not know, or care, what it is being drawn as.
func _register_toggle(key: String, view: Callable) -> void:
	_toggle_views[key] = view
	view.call(_toggle_state(key))


## One key binding, read straight from the input map so the list cannot drift
## from what the game actually listens for.
func _key_row(action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_row_label(ACTION_LABELS.get(action, action.to_upper()), MUTED_COLOR))
	var keys := _label(UIFont.body(), TEXT_COLOR)
	keys.text = _key_label(action)
	row.add_child(keys)
	return row


func _key_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "-"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			return OS.get_keycode_string(code).to_upper()
	return "-"


func _page_head(title: String, counter: String) -> Control:
	var row := HBoxContainer.new()
	var label := _label(UIFont.title(), TEXT_COLOR)
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var sub := _label(UIFont.body(), MUTED_COLOR)
	row.add_child(sub)
	_stat_values["head_" + counter] = sub
	return row


func _rule() -> Control:
	var line := ColorRect.new()
	line.color = RULE_COLOR
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


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
## Lives in UISkin now, so the storage window slices its plates the same way.
func _sliced(texture: Texture2D, edge: int, pad_x: int, pad_y: int) -> StyleBoxTexture:
	return UISkin.sliced(texture, edge, pad_x, pad_y)


## Dresses a button in one of the panel plates. Hover and press shift the plate's
## brightness rather than swapping art, because the pack has no pressed variant
## of these boxes.
func _style_button(button: Button, texture: Texture2D) -> void:
	var normal := _sliced(texture, 6, 6, 4)
	var hover := _sliced(texture, 6, 6, 4)
	hover.modulate_color = Color(1.07, 1.07, 1.07)
	var pressed := _sliced(texture, 6, 6, 4)
	pressed.modulate_color = Color(0.9, 0.9, 0.9)
	var disabled := _sliced(texture, 6, 6, 4)
	disabled.modulate_color = Color(0.86, 0.84, 0.82)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## The scrollbar, shared with the storage window -- see UISkin.
func _scroll_theme() -> Theme:
	return UISkin.scroll_theme()



func _atlas(region: Rect2, sheet: Texture2D) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = sheet
	t.region = region
	return t


# --- tabs -------------------------------------------------------------------

func _show_tab(index: int) -> void:
	_tab = clampi(index, 0, _pages.size() - 1)
	_hide_tooltip()
	_hover_slot = -1
	for i in _pages.size():
		_pages[i].visible = i == _tab
	for i in _tabs.size():
		# The open tab wears the light plate the page below it is cut from; the
		# rest wear the dark one, so the pair reads as one surface.
		_style_button(_tabs[i], INNER_TEXTURE if i == _tab else PANEL_TEXTURE)
		var tint := TEXT_COLOR if i == _tab else MUTED_COLOR
		_tabs[i].add_theme_color_override("font_color", tint)
		_tabs[i].add_theme_color_override("font_hover_color", TEXT_COLOR)
		_tabs[i].add_theme_color_override("font_pressed_color", TEXT_COLOR)
	if _tab == TAB_CRAFTING:
		_select_recipe(_recipe_index)
	_refresh_all()


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
	_refresh_heads()
	_refresh_recipes()
	if _hover_slot >= 0 and _tooltip != null and _tooltip.visible:
		_show_tooltip(_hover_slot)


func _refresh_heads() -> void:
	var used := _used_slots()
	if _stat_values.has("head_slots"):
		(_stat_values["head_slots"] as Label).text = "%d / %d SLOTS" % [used, inventory.size()]
	if _stat_values.has("head_recipes"):
		var ready := 0
		for recipe in _recipes:
			if RecipeDB.can_make(recipe, inventory):
				ready += 1
		(_stat_values["head_recipes"] as Label).text = "%d READY" % ready
	if _stat_values.has("head_live"):
		(_stat_values["head_live"] as Label).text = "APPLIED AT ONCE"


## The left rail. Called every frame while the panel is up, because stamina and
## the farm keep moving underneath it.
func _sync_profile(instant: bool = false) -> void:
	if hud == null:
		return
	_refresh_hearts()
	# A poked face holds its moment; the resting one only comes back after.
	if _poke_left <= 0.0:
		_set_face(_resting_face())

	var stamina := 1.0
	var stamina_max := 1.0
	if is_instance_valid(_player):
		stamina = _player.stamina
		stamina_max = maxf(_player.max_stamina, 1.0)
	if instant:
		_stamina_bar.set_instantly(stamina, stamina_max)
	else:
		_stamina_bar.max_value = stamina_max
		_stamina_bar.value = stamina
	_stamina_text.text = "%d/%d" % [roundi(stamina), roundi(stamina_max)]

	var used := _used_slots()
	if instant:
		_weight_bar.set_instantly(float(used), float(inventory.size()))
	else:
		_weight_bar.max_value = float(inventory.size())
		_weight_bar.value = float(used)
	_weight_text.text = "%d/%d" % [used, inventory.size()]

	var held := hud.held_item()
	(_stat_values["held"] as Label).text = (ItemDB.display_name(held).to_upper()
			if held != "" else "EMPTY HANDS")
	_refresh_farm_stats()


func _refresh_hearts() -> void:
	var want := hud.max_hearts
	while _hearts.get_child_count() > want:
		var extra := _hearts.get_child(_hearts.get_child_count() - 1)
		_hearts.remove_child(extra)
		extra.queue_free()
	while _hearts.get_child_count() < want:
		var icon := TextureRect.new()
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.custom_minimum_size = HUD.HEART_FULL_REGION.size
		_hearts.add_child(icon)
	for i in _hearts.get_child_count():
		var region := HUD.HEART_EMPTY_REGION
		if hud.health >= i + 1:
			region = HUD.HEART_FULL_REGION
		elif hud.health >= i + 0.5:
			region = HUD.HEART_HALF_REGION
		(_hearts.get_child(i) as TextureRect).texture = _atlas(region, HUD.SHEET)


## Counts off the farm, so the rail says something about the world rather than
## only about the player. Silently zero when the scene has no Farm.
func _refresh_farm_stats() -> void:
	var tilled := 0
	var watered := 0
	var growing := 0
	if is_instance_valid(_farm):
		var counts := _farm.counts()
		tilled = int(counts["tilled"])
		watered = int(counts["watered"])
		growing = int(counts["growing"])
	(_stat_values["tilled"] as Label).text = str(tilled)
	(_stat_values["watered"] as Label).text = str(watered)
	(_stat_values["growing"] as Label).text = str(growing)
	(_stat_values["kinds"] as Label).text = str(_distinct_items())


func _used_slots() -> int:
	var used := 0
	for i in inventory.size():
		if inventory.item_at(i) != "":
			used += 1
	return used


func _distinct_items() -> int:
	var seen := {}
	for i in inventory.size():
		var item := inventory.item_at(i)
		if item != "":
			seen[item] = true
	return seen.size()


## The Player and the Farm, looked up once per opening rather than held, so a
## scene that swaps either out does not leave the rail reading a freed node.
func _find_scene_nodes() -> void:
	_player = null
	_farm = null
	if not is_inside_tree():
		return
	for node in get_tree().root.find_children("*", "CharacterBody2D", true, false):
		if node is Player:
			_player = node
			break
	for node in get_tree().root.find_children("*", "Node2D", true, false):
		if node is Farm:
			_farm = node
			break


func _recenter() -> void:
	# A Control under a CanvasLayer gets no size from anchors, so fit the screen
	# by hand.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	if _window == null:
		return
	var free := size - _window.size * pixel_scale
	_window.position = (free * 0.5).round()


func _sync_carry() -> void:
	_carry.item = _carry_stack.item
	_carry.count = _carry_stack.count
	_carry.visible = not _carry_stack.is_empty()


# --- crafting ---------------------------------------------------------------

func _select_recipe(index: int) -> void:
	if _recipes.is_empty():
		return
	_recipe_index = clampi(index, 0, _recipes.size() - 1)
	var recipe := _recipes[_recipe_index]
	_craft_icon.item = recipe["out"]
	_craft_icon.count = int(recipe["out_count"])
	_craft_name.text = String(recipe["name"]).to_upper()
	_craft_body.text = RecipeDB.describe(recipe).to_upper()
	_refresh_recipes()


func _refresh_recipes() -> void:
	if _recipes.is_empty() or _craft_button == null:
		return
	for i in _recipe_rows.size():
		var row := _recipe_rows[i]
		var recipe := _recipes[i]
		var cost_label := row.find_child("Cost", true, false) as Label
		var name_label := row.find_child("Name", true, false) as Label
		var makeable := RecipeDB.can_make(recipe, inventory)
		cost_label.text = _cost_text(recipe)
		cost_label.add_theme_color_override("font_color",
				MUTED_COLOR if makeable else SHORT_COLOR)
		# The open recipe is the only one drawn in full ink, so the list reads
		# at a glance without a highlight plate behind the row.
		name_label.add_theme_color_override("font_color",
				TEXT_COLOR if i == _recipe_index else MUTED_COLOR)

	var current := _recipes[_recipe_index]
	var ready := RecipeDB.can_make(current, inventory)
	_craft_cost.text = _cost_text(current)
	_craft_cost.add_theme_color_override("font_color", TEXT_COLOR if ready else SHORT_COLOR)
	_craft_button.disabled = not ready
	_craft_button.text = "CRAFT" if ready else "SHORT"


## "2/5 CARROT" -- what the recipe asks for, and what is actually in the pack.
func _cost_text(recipe: Dictionary) -> String:
	var parts := PackedStringArray()
	for item: String in recipe["costs"]:
		parts.append("%d/%d %s" % [int(recipe["costs"][item]), inventory.count_of(item),
				ItemDB.display_name(item).to_upper()])
	return " ".join(parts)


func _on_craft_pressed() -> void:
	if _recipes.is_empty():
		return
	RecipeDB.make(_recipes[_recipe_index], inventory)
	_refresh_recipes()


# --- settings ---------------------------------------------------------------

func _on_scale_picked(step: int) -> void:
	# Everything inside the window is laid out in source pixels, so a new zoom
	# is a new scale on three nodes; nothing has to be rebuilt.
	pixel_scale = step
	hud.ui_scale = step
	_window.scale = Vector2.ONE * pixel_scale
	_carry.scale = Vector2.ONE * pixel_scale
	_tooltip.scale = Vector2.ONE * pixel_scale
	_refresh_scale_steps()
	_recenter()


func _refresh_scale_steps() -> void:
	if not is_instance_valid(_scale_steps):
		return
	for i in _scale_steps.get_child_count():
		var button := _scale_steps.get_child(i) as Button
		_style_button(button, INNER_TEXTURE if i + 1 == pixel_scale else PANEL_TEXTURE)
		button.add_theme_color_override("font_color",
				TEXT_COLOR if i + 1 == pixel_scale else MUTED_COLOR)


func _toggle_state(key: String) -> bool:
	return _hotkeys_on if key == "hotkeys" else _tooltips_on


## Flips a setting, applies it, and lets whichever control is on screen redraw
## itself.
func _flip_toggle(key: String) -> void:
	if key == "hotkeys":
		_hotkeys_on = not _hotkeys_on
		for slot in _slots:
			slot.hotkey = (slot.index + 1 if slot.index < hud.slot_count else 0) \
					if _hotkeys_on else 0
	else:
		_tooltips_on = not _tooltips_on
		if not _tooltips_on:
			_hide_tooltip()
	if _toggle_views.has(key):
		(_toggle_views[key] as Callable).call(_toggle_state(key))


# --- clicks -----------------------------------------------------------------

func _on_slot_pressed(index: int, button: int) -> void:
	_hide_tooltip()
	_hover_time = 0.0
	if button == MOUSE_BUTTON_LEFT:
		_carry_stack.left_click(inventory, index)
	elif button == MOUSE_BUTTON_RIGHT:
		_carry_stack.right_click(inventory, index)


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
	if item == "" or not _tooltips_on:
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
