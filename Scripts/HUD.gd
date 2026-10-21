class_name HUD
extends CanvasLayer

## Heart bar and hotbar drawn from the Sprout Lands UI pack.
##
## The scene holds the two plates and an empty row inside each; this script
## fills those rows, sizes the plates to fit, and scales the whole thing up to
## match the zoomed-in pixel art. Hearts read in halves, so 2.5 draws two full
## hearts and one half.

signal slot_selected(index: int)
## Fires when the wardrobe or chest window closes, with the key it was on.
signal storage_closed(key: String)
## Fires whenever what the player is holding changes, by id ("" when empty).
signal held_item_changed(item: String)

# The pack ships the light palette split across files: the plate lives in the
# Everything is cut from this one sheet. It carries two palettes side by side:
# the x=1 column of plates is the lighter pair, the x=113 column is the warmer
# one the pack's own example composite uses, so that is the one taken here.
const SHEET := preload("res://Assets/UI/Inventory_Spritesheet.png")

# What an item id means (name, icon, stacking) lives in ItemDB, and the stacks
# themselves in Inventory; this script only draws the first `slot_count` slots.

# Both bars are nine-sliced so they size to whatever they hold.
#
# They used to be cut from the sheet's own 110x28 strips, which are drawn
# open-bottomed -- flat face colour down to the last row -- so they could stack
# flush. They are the same rounded plate as every other window now, which has a
# border on all four sides, so each bar closes itself and the two are given a
# gap to sit in rather than being butted together.
#
# The corner curve runs through rows 0-5, so 6 covers it on every side. That is
# the one number: the plate is one shape, sliced one way, wherever it appears.
const PLATE := preload("res://Assets/UI/Panel_Plate.png")
const PLATE_PATCH := 6
## Gap between the heart bar and the hotbar, in source pixels. Zero butts two
## borders against each other and reads as a seam.
const PLATE_GAP := 2

# Sizes and spacings below are measured off the pack's own example composites,
# so the bars match the reference artwork.
# The 30x32 slots on the main sheet in the same rounded-square style as the
# reference's 42x44 one (the y=73 row is octagonal instead, so not those).
const SLOT_REGION := Rect2(233, 121, 30, 32)           # in SHEET
# The darkest shade of the same 30x32 family, so the held slot reads at a
# glance with no extra decoration on top.
const SLOT_SELECTED_REGION := Rect2(329, 121, 30, 32)  # in SHEET
# The sheet carries two heart palettes side by side. The one at x=0 is rose and
# washes out against the plate; the one at x=112 is the deeper purple set.
const HEART_EMPTY_REGION := Rect2(112, 2, 15, 14)       # in SHEET
const HEART_HALF_REGION := Rect2(128, 2, 15, 14)
const HEART_FULL_REGION := Rect2(144, 2, 15, 14)

@export_group("Hearts")
## How many heart icons the bar shows.
@export_range(1, 20) var max_hearts: int = 4: set = set_max_hearts
## Current health in hearts. Halves are drawn with the half-heart sprite.
@export_range(0.0, 20.0, 0.5) var health: float = 4.0: set = set_health

@export_group("Hotbar")
## How many item slots the bar shows.
@export_range(1, 12) var slot_count: int = 9: set = set_slot_count
## Which slot is highlighted. -1 for none.
@export_range(-1, 11) var selected_slot: int = 0: set = set_selected_slot

@export_group("Layout")
## Whole-number zoom for the pixel art. The world runs at 4x.
@export_range(1, 8) var ui_scale: int = 2: set = set_ui_scale
## Padding between a plate's edge and its contents, in source pixels.
@export_range(0, 16) var padding: int = 5
## Gap between hearts, in source pixels.
@export_range(0, 16) var heart_spacing: int = 2
## Gap between slots, in source pixels.
@export_range(0, 16) var slot_spacing: int = 4
## How far the heart plate sits right of the hotbar's left edge, in source
## pixels. The pack's own reference art uses 13.
@export_range(0, 64) var heart_indent: int = 13: set = set_heart_indent
## Distance from the bottom edge of the screen, in screen pixels. 0 stands the
## bars on the bottom edge; positive floats them, negative hangs them off.
##
## Floated by default, which the closed plate needs: the old strips were drawn
## open-bottomed to sit flush on the edge, but this one has a bottom border, and
## standing it on the edge crops that border off and reads as a bar cut in half.
@export_range(-300, 300) var bottom_margin: int = 10

@export_group("Inventory")
## Total slots in the player's inventory. The hotbar shows the first
## `slot_count`; harvested produce lands in the first free slot, seen or not.
@export_range(1, 96) var inventory_size: int = 45
## Starting loadout, one item id per slot, "" for empty. Ids come from ItemDB.
@export var slot_items: Array[String] = [
	"hoe", "watering_can", "axe", "carrot_seed", "tomato_seed", "pumpkin_seed", "corn_seed", "",
]: set = set_slot_items
## How many of each starting item. A slot with no entry here gets 1.
@export var slot_counts: Array[int] = [1, 1, 1, 10, 10, 10, 10]
## Zoom for item icons inside their slot, on top of each item's own zoom. The
## 16px crop icons fit the 26x26 inner face at 1.0 and stay on whole pixels,
## which keeps them sharp.
@export_range(0.25, 3.0, 0.05) var item_icon_scale: float = 1.0

@export_group("Selection")
## Let 1-9 and the mouse wheel change the held slot.
@export var selection_input: bool = true
## How much the held slot swells. The overshoot on the way there is what makes
## it read as springy rather than mechanical.
@export_range(1.0, 1.6, 0.01) var selected_scale: float = 1.25
## How much the rest shrink back. Pairing a shrink with the swell widens the
## gap between them without making the held slot overrun its neighbours.
@export_range(0.6, 1.0, 0.01) var unselected_scale: float = 0.88
## Seconds for the pop. Short and springy.
@export_range(0.05, 1.0, 0.01) var pop_time: float = 0.3

@onready var _scaler: Control = $Screen/Scaler
@onready var _heart_row: MarginContainer = $Screen/Scaler/Bars/HeartRow
@onready var _heart_plate: NinePatchRect = $Screen/Scaler/Bars/HeartRow/HeartPlate
@onready var _hearts: HBoxContainer = $Screen/Scaler/Bars/HeartRow/HeartPlate/Hearts
@onready var _hotbar_plate: NinePatchRect = $Screen/Scaler/Bars/HotbarPlate
@onready var _slots: HBoxContainer = $Screen/Scaler/Bars/HotbarPlate/Slots

## What the player carries. The hotbar draws its first `slot_count` slots.
var inventory: Inventory

var _ready_done := false
var _pop_tween: Tween
var _panel: ProfilePanel
var _storage: StoragePanel

func _ready() -> void:
	_ready_done = true
	_load_loadout()
	_panel = ProfilePanel.new()
	_panel.name = "ProfilePanel"
	add_child(_panel)
	_panel.bind(self)
	_storage = StoragePanel.new()
	_storage.name = "StoragePanel"
	add_child(_storage)
	_storage.bind(self)
	_storage.closed.connect(storage_closed.emit)
	get_viewport().size_changed.connect(_reposition)
	rebuild()


## True while the profile panel is on screen; the player stands still then.
func is_profile_open() -> bool:
	return _panel != null and _panel.is_open()


## True while a wardrobe or chest window is on screen.
func is_storage_open() -> bool:
	return _storage != null and _storage.is_open()


## Opens the storage window on one piece of furniture, named as
## `PlayerState.storage_key` spells it. The profile screen steps aside: both
## are full-screen windows, so only one of them can be the one you are in.
func open_storage(key: String) -> void:
	if _storage == null:
		return
	if _panel != null and _panel.is_open():
		_panel.close()
	_storage.open(key)


func close_storage() -> void:
	if _storage != null:
		_storage.close()


## Kept under its old name as well: Player asks for this one by name. Any
## window being up means the same thing to the player -- stand still, and let
## the keys belong to the window.
func is_inventory_open() -> bool:
	return is_profile_open() or is_storage_open()


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_done:
		return
	if event.is_action_pressed("inventory"):
		# With a chest open the key shuts it rather than stacking the profile
		# screen on top: one window at a time, and the nearest one first.
		if is_storage_open():
			close_storage()
		else:
			_panel.toggle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and (is_storage_open() or _panel.is_open()):
		if is_storage_open():
			close_storage()
		else:
			_panel.close()
		get_viewport().set_input_as_handled()
		return
	if not selection_input or _panel.is_open() or is_storage_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var digit := (event as InputEventKey).keycode - KEY_1
		if digit >= 0 and digit < slot_count:
			selected_slot = digit
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var b := (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_DOWN:
			selected_slot = (selected_slot + 1) % slot_count
			get_viewport().set_input_as_handled()
		elif b == MOUSE_BUTTON_WHEEL_UP:
			selected_slot = (selected_slot - 1 + slot_count) % slot_count
			get_viewport().set_input_as_handled()


## Rebuilds both rows from scratch. Safe to call at any time.
func rebuild() -> void:
	if not _ready_done:
		return
	# Each plate closes itself now, so they are spaced rather than butted.
	(_scaler.get_node("Bars") as VBoxContainer).add_theme_constant_override("separation", PLATE_GAP)
	_heart_row.add_theme_constant_override("margin_left", heart_indent)
	_apply_plate(_heart_plate, PLATE, Rect2(), PLATE_PATCH)
	_apply_plate(_hotbar_plate, PLATE, Rect2(), PLATE_PATCH)
	_build_row(_hearts, max_hearts, HEART_FULL_REGION, SHEET, heart_spacing)
	_build_row(_slots, slot_count, SLOT_REGION, SHEET, slot_spacing)
	_fit(_heart_plate, _hearts, max_hearts, HEART_FULL_REGION.size, heart_spacing)
	_fit(_hotbar_plate, _slots, slot_count, SLOT_REGION.size, slot_spacing)
	_refresh_hearts()
	_refresh_slots()
	_scaler.scale = Vector2(ui_scale, ui_scale)
	_reposition()


func _build_row(row: HBoxContainer, count: int, region: Rect2, sheet: Texture2D, gap: int) -> void:
	for child in row.get_children():
		child.queue_free()
		row.remove_child(child)
	row.add_theme_constant_override("separation", gap)
	for i in count:
		var icon := TextureRect.new()
		icon.texture = _atlas(region, sheet)
		icon.custom_minimum_size = region.size
		icon.stretch_mode = TextureRect.STRETCH_KEEP
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)


## Grow the plate to hold `count` items plus padding, and inset the row.
func _fit(plate: NinePatchRect, row: HBoxContainer, count: int, item: Vector2, gap: int) -> void:
	var w := padding * 2 + count * int(item.x) + maxi(count - 1, 0) * gap
	var h := padding * 2 + int(item.y)
	plate.custom_minimum_size = Vector2(w, h)
	plate.size = Vector2(w, h)
	row.offset_left = padding
	row.offset_top = padding
	row.offset_right = -padding
	row.offset_bottom = -padding


## Point a plate at its box sprite. Set here rather than in the scene so the
## two bars can use different boxes without hand-editing the .tscn.
func _apply_plate(plate: NinePatchRect, sheet: Texture2D, region: Rect2,
		patch: int, bottom := -1) -> void:
	plate.texture = sheet
	# An empty region means the whole texture, for art that is its own file
	# rather than a crop out of the sheet.
	plate.region_rect = region if region.size != Vector2.ZERO else Rect2(Vector2.ZERO, sheet.get_size())
	plate.patch_margin_left = patch
	plate.patch_margin_top = patch
	plate.patch_margin_right = patch
	plate.patch_margin_bottom = patch if bottom < 0 else bottom


func _atlas(region: Rect2, sheet: Texture2D) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = sheet
	t.region = region
	return t


func _refresh_hearts() -> void:
	if not _ready_done:
		return
	for i in _hearts.get_child_count():
		var icon := _hearts.get_child(i) as TextureRect
		# A heart is full when health covers it entirely, half when it covers
		# the first half of it, empty otherwise.
		var region := HEART_EMPTY_REGION
		if health >= i + 1:
			region = HEART_FULL_REGION
		elif health >= i + 0.5:
			region = HEART_HALF_REGION
		icon.texture = _atlas(region, SHEET)


func _refresh_slots() -> void:
	if not _ready_done:
		return
	for i in _slots.get_child_count():
		var icon := _slots.get_child(i) as TextureRect
		icon.texture = (_atlas(SLOT_SELECTED_REGION, SHEET) if i == selected_slot
				else _atlas(SLOT_REGION, SHEET))
		# Scale pivots from the top-left by default, which would shove the slot
		# sideways instead of swelling it in place.
		icon.pivot_offset = icon.custom_minimum_size * 0.5
		_refresh_item(icon, held_item_at(i), inventory.count_at(i) if inventory else 0)
	_animate_selection()


## What the player is holding, "" if the slot is empty or nothing is selected.
func held_item() -> String:
	return held_item_at(selected_slot)


func held_item_at(index: int) -> String:
	return inventory.item_at(index) if inventory else ""


## Borrows the one bag that outlives the scene. The exported loadout is what it
## gets filled with the first time the game asks for it; every HUD after that --
## a new scene's, after walking through a door -- is handed the same bag with
## whatever is in it, so stock does not reappear on the way indoors.
func _load_loadout() -> void:
	if inventory:
		inventory.changed.disconnect(_on_inventory_changed)
	inventory = PlayerState.take_inventory(
			maxi(inventory_size, slot_items.size()), _fill_starting_loadout)
	inventory.changed.connect(_on_inventory_changed)
	if _panel:
		_panel.bind(self)


func _fill_starting_loadout(bag: Inventory) -> void:
	for i in slot_items.size():
		var count := slot_counts[i] if i < slot_counts.size() else 1
		bag.set_slot(i, slot_items[i], count)


func _on_inventory_changed(_slot: int) -> void:
	_refresh_slots()
	held_item_changed.emit(held_item())


## The icon lives inside its slot, so it inherits the slot's swell and shrink
## for free instead of needing its own tween.
func _refresh_item(slot: TextureRect, item: String, count: int) -> void:
	var icon := slot.get_node_or_null("Item") as TextureRect
	var label := slot.get_node_or_null("Count") as Label
	var entry := ItemDB.info(item)
	if entry.is_empty():
		if icon:
			icon.queue_free()
		if label:
			label.queue_free()
		return
	if icon == null:
		icon = TextureRect.new()
		icon.name = "Item"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		# A TextureRect takes its minimum size from its texture, so without
		# this it snaps straight back to the sprite's full size.
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.add_child(icon)
	var region: Rect2 = entry["region"]
	icon.texture = _atlas(region, entry["sheet"])
	var size := (region.size * item_icon_scale * float(entry["scale"])).round()
	icon.size = size
	icon.position = ((slot.custom_minimum_size - size) * 0.5).round()
	if count <= 1:
		if label:
			label.queue_free()
		return
	if label == null:
		label = Label.new()
		label.name = "Count"
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		label.add_theme_font_override("font", UIFont.title())
		label.add_theme_font_size_override("font_size", UIFont.SIZE)
		label.add_theme_constant_override("outline_size", 3)
		label.add_theme_color_override("font_outline_color", Color("5a3d3d"))
		label.add_theme_color_override("font_color", Color("fff4dc"))
		label.size = Vector2(28, 14)
		label.position = Vector2(slot.custom_minimum_size.x - 31, slot.custom_minimum_size.y - 15)
		slot.add_child(label)
	label.text = str(count)


## Swell the held slot and shrink the rest. TRANS_BACK overshoots and settles,
## which is what sells the bounce; a linear tween reads as machinery.
func _animate_selection() -> void:
	if _pop_tween and _pop_tween.is_valid():
		_pop_tween.kill()
	_pop_tween = create_tween().set_parallel(true)
	for i in _slots.get_child_count():
		var icon := _slots.get_child(i) as Control
		var target := Vector2.ONE * (selected_scale if i == selected_slot
				else unselected_scale)
		_pop_tween.tween_property(icon, "scale", target, pop_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Centre the scaled bars along the bottom edge. The scaler is anchored to the
## bottom-centre and draws from its own top-left, so both offsets are measured
## back from that corner. Sizes come from the plates we just set rather than
## from the laid-out rect, which is not valid until the next frame.
func _reposition() -> void:
	if not _ready_done:
		return
	var w := maxf(_heart_plate.custom_minimum_size.x + heart_indent,
			_hotbar_plate.custom_minimum_size.x) * ui_scale
	# The gap between the two plates counts towards the stack's height; leaving
	# it out hangs that much of the hotbar off the bottom of the screen.
	var h := (_heart_plate.custom_minimum_size.y + _hotbar_plate.custom_minimum_size.y
			+ PLATE_GAP) * ui_scale
	# Offsets are measured from the anchors (bottom-centre); `position` would be
	# measured from the parent's top-left instead and land off-screen. The
	# scaler is a zero-sized transform holder, so all four match.
	var x := -roundf(w * 0.5)
	var y := -h - bottom_margin
	_scaler.offset_left = x
	_scaler.offset_right = x
	_scaler.offset_top = y
	_scaler.offset_bottom = y


func set_max_hearts(value: int) -> void:
	max_hearts = maxi(value, 1)
	rebuild()


func set_health(value: float) -> void:
	health = clampf(value, 0.0, float(max_hearts))
	_refresh_hearts()


func set_slot_count(value: int) -> void:
	slot_count = maxi(value, 1)
	rebuild()


func set_heart_indent(value: int) -> void:
	heart_indent = maxi(value, 0)
	rebuild()


func set_ui_scale(value: int) -> void:
	ui_scale = clampi(value, 1, 8)
	rebuild()


func set_slot_items(value: Array[String]) -> void:
	slot_items = value
	if _ready_done:
		_load_loadout()
		_on_inventory_changed(-1)


func set_selected_slot(value: int) -> void:
	var before := held_item() if _ready_done else ""
	selected_slot = clampi(value, -1, slot_count - 1)
	_refresh_slots()
	if not _ready_done:
		return
	slot_selected.emit(selected_slot)
	var now := held_item()
	if now != before:
		held_item_changed.emit(now)
