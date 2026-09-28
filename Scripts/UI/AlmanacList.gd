class_name AlmanacList
extends Control

## The almanac tab: every item the game knows about, each one sitting in
## a cell of the same art the bag uses, grouped by what kind of thing it
## is, with how many of it the player is carrying.
##
## The list is built from [ItemDatabase] rather than from a table of its
## own, so an item added to the roster turns up here without anything
## being written twice. It is also the tab that makes the scrollbar earn
## its place: the roster is longer than the panel whatever is in the bag.
##
## Every kind of item has a colour, and it is shown twice: once large on
## the heading that opens the group, and again as a small disc on each
## row. The heading alone would do while it is on screen, but the list is
## taller than the panel — scroll past a heading and the discs are what
## is left to say what you are looking at.
##
## Held counts are read off the inventory's own signal, so picking
## something up while the tab is open moves the number beside it.

## Height of one item's row: a cell of slot art with a little air.
const ROW_HEIGHT: int = 38
## Height of a category heading, the gap above it included.
const HEADING_HEIGHT: int = 34
## Icons are drawn this size inside their cell, down from their native 32.
const ICON_SIZE: int = 22

## Headings, in the order the tab lists them.
const GROUPS: Array = [
	[ItemData.Category.TOOL, "TOOLS"],
	[ItemData.Category.SEED, "SEEDS"],
	[ItemData.Category.CROP, "CROPS"],
	[ItemData.Category.RESOURCE, "MATERIALS"],
	[ItemData.Category.MISC, "OTHER"],
]

## Cell art each item is framed in. The bag's own art, so an item looks
## the same here as it does in the hand.
@export var slot_texture: Texture2D = preload("res://Assets/UI/Inventory/Slot_Small.png")
@export var padding: int = 4

var _counts: Dictionary[StringName, Label] = {}

func _ready() -> void:
	_build()
	PlayerInventory.inventory.slot_changed.connect(func(_index: int) -> void: _refresh_counts())
	PlayerInventory.inventory.contents_changed.connect(_refresh_counts)
	_refresh_counts()

func _build() -> void:
	var y := 0

	for group in GROUPS:
		var category: ItemData.Category = group[0]
		var ids := _ids_in(category)
		if ids.is_empty():
			continue

		_build_heading(category, group[1], y)
		y += HEADING_HEIGHT

		for id in ids:
			_build_row(id, category, y)
			y += ROW_HEIGHT

	custom_minimum_size = Vector2(custom_minimum_size.x, y + padding)
	size.y = custom_minimum_size.y

func _ids_in(category: ItemData.Category) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in ItemDb.all_ids():
		var item := ItemDb.get_item(id)
		if item != null and item.category == category:
			ids.append(id)
	return ids

## The group's colour, large, with its name beside it.
func _build_heading(category: ItemData.Category, title: String, y: int) -> void:
	var mark := MenuTheme.category_mark(category, true)
	mark.position = Vector2(padding, y + 2)
	add_child(mark)

	var label := MenuTheme.label(title, MenuTheme.TEXT_LIGHT)
	label.position = Vector2(padding + MenuTheme.ROUND_MEDIUM_SIZE, y + 13)
	add_child(label)

## The group's colour again, small, then the item in a cell, its name, its
## line of description, and how many are held.
func _build_row(id: StringName, category: ItemData.Category, y: int) -> void:
	var item := ItemDb.get_item(id)
	var cell: Vector2 = slot_texture.get_size() if slot_texture != null else Vector2(30, 32)

	var mark := MenuTheme.category_mark(category)
	# Level with the middle of the cell beside it.
	mark.position = Vector2(padding + 4, y + (cell.y - MenuTheme.ROUND_SMALL_SIZE) * 0.5)
	add_child(mark)

	var frame_x := padding + 4 + MenuTheme.ROUND_SMALL_SIZE + 6
	var frame := TextureRect.new()
	frame.texture = slot_texture
	frame.size = cell
	frame.position = Vector2(frame_x, y)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	var icon := TextureRect.new()
	icon.texture = item.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.position = ((cell - icon.size) * 0.5).round()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(icon)

	var text_x := frame_x + cell.x + 8
	var name_label := MenuTheme.label(item.display_name, MenuTheme.TEXT_LIGHT)
	name_label.position = Vector2(text_x, y + 3)
	add_child(name_label)

	var description := MenuTheme.label(item.description, MenuTheme.TEXT_DIM)
	description.position = Vector2(text_x, y + 17)
	add_child(description)

	var count := MenuTheme.label("", MenuTheme.TEXT_LIGHT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	MenuTheme.span(count, y + 10, ROW_HEIGHT, 0, padding + 2)
	add_child(count)
	_counts[id] = count

func _refresh_counts() -> void:
	var inventory := PlayerInventory.inventory
	for id in _counts:
		var held := inventory.count_of(id)
		var label: Label = _counts[id]
		# An item you have none of says nothing rather than "0": the
		# roster is a reference, and a column of zeroes reads as noise.
		label.text = "x%d" % held if held > 0 else ""
		label.add_theme_color_override(
			"font_color", MenuTheme.TEXT_LIGHT if held > 0 else MenuTheme.TEXT_DIM)
