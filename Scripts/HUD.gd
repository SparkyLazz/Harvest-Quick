class_name HUD
extends CanvasLayer

## Heart bar and hotbar drawn from the Sprout Lands UI pack.
##
## The scene holds the two plates and an empty row inside each; this script
## fills those rows, sizes the plates to fit, and scales the whole thing up to
## match the zoomed-in pixel art. Hearts read in halves, so 2.5 draws two full
## hearts and one half.

signal slot_selected(index: int)

const SHEET := preload("res://Assets/UI/Inventory_Spritesheet.png")

# Regions picked off the sheet. The plate is nine-sliced so a bar can hold any
# number of slots; the rest are stamped at native size.
const PLATE_REGION := Rect2(1, 307, 110, 29)
const PATCH_LEFT := 7
const PATCH_TOP := 7
const PATCH_RIGHT := 7
const PATCH_BOTTOM := 8

# Sizes and spacings below are measured off the pack's own
# inventory_example_with_slots.png, so the bars match the reference artwork.
const SLOT_REGION := Rect2(227, 162, 42, 44)
# The darkest of the three slot shades, so the selected one reads as pressed.
const SLOT_SELECTED_REGION := Rect2(323, 162, 42, 44)
const HEART_EMPTY_REGION := Rect2(0, 2, 15, 14)
const HEART_HALF_REGION := Rect2(16, 2, 15, 14)
const HEART_FULL_REGION := Rect2(32, 2, 15, 14)

@export_group("Hearts")
## How many heart icons the bar shows.
@export_range(1, 20) var max_hearts: int = 4: set = set_max_hearts
## Current health in hearts. Halves are drawn with the half-heart sprite.
@export_range(0.0, 20.0, 0.5) var health: float = 4.0: set = set_health

@export_group("Hotbar")
## How many item slots the bar shows.
@export_range(1, 12) var slot_count: int = 7: set = set_slot_count
## Which slot is highlighted. -1 for none.
@export_range(-1, 11) var selected_slot: int = 0: set = set_selected_slot

@export_group("Layout")
## Whole-number zoom for the pixel art. The world runs at 4x.
@export_range(1, 8) var ui_scale: int = 2: set = set_ui_scale
## Padding between a plate's edge and its contents, in source pixels.
@export_range(0, 16) var padding: int = 6
## Gap between hearts, in source pixels.
@export_range(0, 16) var heart_spacing: int = 2
## Gap between slots, in source pixels.
@export_range(0, 16) var slot_spacing: int = 6
## How far the heart plate sits right of the hotbar's left edge, in source
## pixels. The pack's own reference art uses 13.
@export_range(0, 64) var heart_indent: int = 13: set = set_heart_indent
## Distance from the bottom edge of the screen, in screen pixels. Negative
## hangs the bars off the bottom so the plate's lower edge runs off-screen.
@export_range(-300, 300) var bottom_margin: int = -16

@onready var _scaler: Control = $Screen/Scaler
@onready var _heart_row: MarginContainer = $Screen/Scaler/Bars/HeartRow
@onready var _heart_plate: NinePatchRect = $Screen/Scaler/Bars/HeartRow/HeartPlate
@onready var _hearts: HBoxContainer = $Screen/Scaler/Bars/HeartRow/HeartPlate/Hearts
@onready var _hotbar_plate: NinePatchRect = $Screen/Scaler/Bars/HotbarPlate
@onready var _slots: HBoxContainer = $Screen/Scaler/Bars/HotbarPlate/Slots

var _ready_done := false


func _ready() -> void:
	_ready_done = true
	get_viewport().size_changed.connect(_reposition)
	rebuild()


## Rebuilds both rows from scratch. Safe to call at any time.
func rebuild() -> void:
	if not _ready_done:
		return
	# The plates butt up against each other, as they do in the reference art.
	(_scaler.get_node("Bars") as VBoxContainer).add_theme_constant_override("separation", 0)
	_heart_row.add_theme_constant_override("margin_left", heart_indent)
	_build_row(_hearts, max_hearts, HEART_FULL_REGION, heart_spacing)
	_build_row(_slots, slot_count, SLOT_REGION, slot_spacing)
	_fit(_heart_plate, _hearts, max_hearts, HEART_FULL_REGION.size, heart_spacing)
	_fit(_hotbar_plate, _slots, slot_count, SLOT_REGION.size, slot_spacing)
	_refresh_hearts()
	_refresh_slots()
	_scaler.scale = Vector2(ui_scale, ui_scale)
	_reposition()


func _build_row(row: HBoxContainer, count: int, region: Rect2, gap: int) -> void:
	for child in row.get_children():
		child.queue_free()
		row.remove_child(child)
	row.add_theme_constant_override("separation", gap)
	for i in count:
		var icon := TextureRect.new()
		icon.texture = _atlas(region)
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


func _atlas(region: Rect2) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = SHEET
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
		icon.texture = _atlas(region)


func _refresh_slots() -> void:
	if not _ready_done:
		return
	for i in _slots.get_child_count():
		var icon := _slots.get_child(i) as TextureRect
		icon.texture = _atlas(SLOT_SELECTED_REGION if i == selected_slot else SLOT_REGION)


## Centre the scaled bars along the bottom edge. The scaler is anchored to the
## bottom-centre and draws from its own top-left, so both offsets are measured
## back from that corner. Sizes come from the plates we just set rather than
## from the laid-out rect, which is not valid until the next frame.
func _reposition() -> void:
	if not _ready_done:
		return
	var w := maxf(_heart_plate.custom_minimum_size.x + heart_indent,
			_hotbar_plate.custom_minimum_size.x) * ui_scale
	var h := (_heart_plate.custom_minimum_size.y + _hotbar_plate.custom_minimum_size.y) * ui_scale
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


func set_selected_slot(value: int) -> void:
	selected_slot = clampi(value, -1, slot_count - 1)
	_refresh_slots()
	if _ready_done:
		slot_selected.emit(selected_slot)
