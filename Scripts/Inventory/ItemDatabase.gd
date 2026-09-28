class_name ItemDatabase
extends Node

## The roster of every item in the game, autoloaded as [code]ItemDb[/code].
## The class is named as well as autoloaded, so cells such as
## [constant COIN_CELL] can be reached from a constant somewhere else.
##
## Icons all come out of one 320x1376 sheet of 32x32 emoji, ten to a row.
## Rather than cutting out a PNG per item, each definition names its cell
## and the database wraps that cell in an [AtlasTexture]. The sheet is
## loaded once and every icon is a window onto it, so adding an item costs
## one line here and no new files.
##
## Cells are given as [code]Vector2i(column, row)[/code], counting from the
## top-left of the sheet. [constant SHEET_COLUMNS] is only used to check
## them, so a typo shows up as a warning on startup instead of a blank
## square in the inventory.
##
## A caveat on the starter tools: the sheet is a general emoji set and has
## no hoe and no axe in it. [code]hoe[/code] and [code]axe[/code] borrow
## the two nearest tool icons — the pick-and-hammer and the hammer — so
## the inventory reads correctly until proper tool art exists. Swapping
## them later is a matter of changing their cell below.

const SHEET: Texture2D = preload("res://Assets/UI/Item/Emoji spritesheet.png")
## Side of one icon on the sheet, in pixels.
const ICON_SIZE: int = 32
const SHEET_COLUMNS: int = 10
const SHEET_ROWS: int = 43
## Cell of the coin, which is money rather than an item and so has no
## entry in the roster. The profile panel draws its money field with it.
const COIN_CELL := Vector2i(6, 10)

var _items: Dictionary[StringName, ItemData] = {}
var _icons: Dictionary[Vector2i, AtlasTexture] = {}

func _ready() -> void:
	_register_tools()
	_register_seeds_and_crops()
	_register_resources()

## The definition for [param id], or null if nothing is registered under
## it. Callers that draw an item should handle null rather than assume;
## a slot holding an unknown id is a bug worth seeing, not one to crash on.
func get_item(id: StringName) -> ItemData:
	return _items.get(id)

func has_item(id: StringName) -> bool:
	return _items.has(id)

func get_icon(id: StringName) -> Texture2D:
	var item := get_item(id)
	return item.icon if item != null else null

func get_display_name(id: StringName) -> String:
	var item := get_item(id)
	return item.display_name if item != null else String(id)

## Every registered id, in the order they were registered.
func all_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(_items.keys())
	return ids

# --- Roster ------------------------------------------------------------

func _register_tools() -> void:
	# Row 24 of the sheet is the tool row: key, clipboard, pencil, knife,
	# pick-and-hammer, hammer, watering can, water drop.
	_add(&"hoe", "Hoe", Vector2i(4, 24), 1, ItemData.Category.TOOL,
		"Turns grass into soil you can plant in.")
	_add(&"axe", "Axe", Vector2i(5, 24), 1, ItemData.Category.TOOL,
		"Fells trees and splits them into logs.")
	_add(&"watering_can", "Watering Can", Vector2i(6, 24), 1, ItemData.Category.TOOL,
		"Waters a tile of soil. Refill it at the sea.")
	_add(&"scythe", "Scythe", Vector2i(3, 24), 1, ItemData.Category.TOOL,
		"Cuts grass and clears weeds.")

func _register_seeds_and_crops() -> void:
	_add(&"seeds", "Seeds", Vector2i(0, 15), 99, ItemData.Category.SEED,
		"Sow into watered soil.")
	_add(&"turnip", "Turnip", Vector2i(3, 17), 99, ItemData.Category.CROP,
		"Quick to grow, quick to sell.")
	_add(&"carrot", "Carrot", Vector2i(5, 16), 99, ItemData.Category.CROP,
		"Sweeter after a cold night.")
	_add(&"corn", "Corn", Vector2i(4, 16), 99, ItemData.Category.CROP,
		"Keeps cropping all summer.")
	_add(&"tomato", "Tomato", Vector2i(7, 16), 99, ItemData.Category.CROP,
		"Heavy on the vine.")
	_add(&"cabbage", "Cabbage", Vector2i(0, 17), 99, ItemData.Category.CROP,
		"Takes its time and pays for it.")
	_add(&"pumpkin", "Pumpkin", Vector2i(2, 17), 99, ItemData.Category.CROP,
		"The last crop before the frost.")
	_add(&"wheat", "Wheat", Vector2i(1, 17), 99, ItemData.Category.CROP,
		"Threshes into flour, or into seed.")
	_add(&"strawberry", "Strawberry", Vector2i(7, 15), 99, ItemData.Category.CROP,
		"Worth more than it weighs.")
	_add(&"apple", "Apple", Vector2i(0, 16), 99, ItemData.Category.CROP,
		"Shaken down from an orchard tree.")
	_add(&"mushroom", "Mushroom", Vector2i(4, 15), 99, ItemData.Category.CROP,
		"Found in the shade after rain.")

func _register_resources() -> void:
	_add(&"wood", "Wood", Vector2i(4, 21), 99, ItemData.Category.RESOURCE,
		"Split from a felled tree.")
	_add(&"plank", "Plank", Vector2i(5, 21), 99, ItemData.Category.RESOURCE,
		"Sawn and ready to build with.")
	_add(&"stick", "Stick", Vector2i(6, 21), 99, ItemData.Category.RESOURCE,
		"Kindling, handles, fence rails.")
	_add(&"stone", "Stone", Vector2i(7, 21), 99, ItemData.Category.RESOURCE,
		"Prised out of the hillside.")
	_add(&"fibre", "Fibre", Vector2i(1, 21), 99, ItemData.Category.RESOURCE,
		"Cut grass, good for rope.")

# --- Building ----------------------------------------------------------

func _add(
		id: StringName,
		label: String,
		cell: Vector2i,
		max_stack: int,
		category: ItemData.Category,
		description: String) -> void:
	if _items.has(id):
		push_error("ItemDatabase: duplicate item id '%s'." % id)
		return
	_items[id] = ItemData.create(id, label, icon_at(cell), max_stack, category, description)

## An [AtlasTexture] onto one cell of the sheet, reused between items that
## share a cell. Public because a few icons — the coin on the money field
## — are wanted without an item behind them.
func icon_at(cell: Vector2i) -> AtlasTexture:
	if cell.x < 0 or cell.x >= SHEET_COLUMNS or cell.y < 0 or cell.y >= SHEET_ROWS:
		push_error("ItemDatabase: cell %s is off the icon sheet." % cell)
		return null

	var cached: AtlasTexture = _icons.get(cell)
	if cached != null:
		return cached

	var icon := AtlasTexture.new()
	icon.atlas = SHEET
	icon.region = Rect2(cell * ICON_SIZE, Vector2i(ICON_SIZE, ICON_SIZE))
	# The sheet has transparent gaps between icons; without this, a slot
	# drawing the icon at anything but native size bleeds a neighbour's
	# pixels in along the edge.
	icon.filter_clip = true
	_icons[cell] = icon
	return icon
