class_name MenuTheme
extends RefCounted

## Shared look for the menu: the lettering, the icons on its buttons and
## the coloured discs that mark what kind of thing an item is. Nothing
## here is ever instanced — every entry point is static, and the menu's
## parts call into it instead of each carrying their own copy of the same
## colours. The scrollbar has enough of its own to say that it lives in
## [PixelScrollBar] instead.
##
## Button icons come out of one 192x480 sheet of 32x32 cells, six to a
## row. The cells pair up: an even column is the raised, resting face of a
## button and the odd column beside it is the same icon pressed flat. That
## is why [method icon] takes a cell and [method pressed_icon] just steps
## one column to the right — a tab's two states are one entry, not two.
##
## The round button sheets are read the same way: thirteen colours down
## the rows, the button's states across the columns. Only the resting
## column is used, because the discs the menu draws are labels rather
## than things to press.

const FONT: Font = preload("res://Assets/UI/Fonts/pixelFont-4-7x7-sproutLands.ttf")
const FONT_SIZE: int = 9
## Lettering on a dark panel.
const TEXT_LIGHT := Color(0.953, 0.898, 0.761)
## Lettering on a dark panel, for the quieter half of a label.
##
## A mid-brown here would sit almost exactly on the panel it is written
## on — the two are within a few percent of the same lightness, and the
## words disappear. Anything secondary on a dark panel steps down from
## the brightest cream to a slightly warmer one rather than towards the
## background, so it stays legible while still reading as the quieter of
## the two.
const TEXT_DIM := Color(0.910, 0.812, 0.651)
## Lettering on a light plaque, and the colour of the art's darkest line.
const TEXT_DARK := Color(0.565, 0.384, 0.365)
## The quieter half of a label on a light plaque.
const TEXT_DARK_SOFT := Color(0.667, 0.475, 0.349)

## Block a reading is written on, so the words sit on their own light
## ground instead of on the panel. Nine-sliced, like every other panel
## here: only flat colour in the middle stretches.
const PLAQUE: Texture2D = preload("res://Assets/UI/Panels/Panel_Cream.png")
## Size of the corner artwork in [constant PLAQUE].
const PLAQUE_MARGIN: int = 10

const BUTTON_SHEET: Texture2D = preload("res://Assets/UI/Buttons/Icon_Buttons.png")
const BUTTON_SIZE: int = 32
const BUTTON_SHEET_COLUMNS: int = 6
const BUTTON_SHEET_ROWS: int = 15

## Cells on the button sheet, by what the menu uses them for. Each names
## the raised face; the pressed one is the cell to its right.
const ICON_BAG := Vector2i(2, 10)      ## Basket — the inventory tab.
const ICON_ALMANAC := Vector2i(0, 12)  ## Sprout — the almanac tab.
## House — the farm tab. The sheet also has a winner's podium, which is
## the more literal reading of "stats", but it is three numerals stacked
## on three steps and at this size that is a smudge. A house is one
## silhouette and carries the same meaning here, since what the tab holds
## is the state of the farm.
const ICON_FARM := Vector2i(4, 5)
const ICON_CLOSE := Vector2i(4, 0)     ## Cross — shuts the menu.

## Coloured discs, for marking what kind of thing an item is. Both sheets
## run the same thirteen colours down their rows; the columns are the
## button's states, of which the menu only wants the resting one.
const ROUND_MEDIUM: Texture2D = preload("res://Assets/UI/Buttons/Round_Medium.png")
const ROUND_SMALL: Texture2D = preload("res://Assets/UI/Buttons/Round_Small.png")
const ROUND_MEDIUM_SIZE: int = 32
const ROUND_SMALL_SIZE: int = 16
const ROUND_COLOURS: int = 13

## Which row of the round sheets stands for each kind of item. Chosen to
## be told apart at a glance rather than to be pretty together: steel
## blue for tools, seed yellow, leaf green for crops, timber brown.
const CATEGORY_COLOUR: Dictionary = {
	ItemData.Category.TOOL: 5,
	ItemData.Category.SEED: 9,
	ItemData.Category.CROP: 7,
	ItemData.Category.RESOURCE: 3,
	ItemData.Category.MISC: 11,
}

## Width of the scrollbar's art, and so of the column it needs.
const SCROLL_WIDTH: int = PixelScrollBar.WIDTH

static var _icons: Dictionary[Vector2i, AtlasTexture] = {}
static var _discs: Dictionary[Vector2i, AtlasTexture] = {}

# --- Lettering ---------------------------------------------------------

## Builds a label in the menu's font. Used everywhere rather than a theme
## resource, because the menu's parts are built in code and a handful of
## overrides is less to keep in step than a .tres nobody opens.
static func label(text: String = "", colour: Color = TEXT_LIGHT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", FONT_SIZE)
	node.add_theme_color_override("font_color", colour)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

## Pins [param control] across its parent's full width, [param left] and
## [param right] pixels in from either edge, at [param top] and
## [param height] tall.
##
## Anchors rather than a position and a size, so a label re-spans on its
## own when its parent is resized — which for anything inside a
## [ScrollContainer] happens after it was built, once the container has
## worked out how much room the scrollbar leaves.
static func span(control: Control, top: float, height: float,
		left: float = 0.0, right: float = 0.0) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 1.0
	control.offset_left = left
	control.offset_right = -right
	control.offset_top = top
	control.offset_bottom = top + height

# --- Button icons ------------------------------------------------------

## The raised face of the button at [param cell].
static func icon(cell: Vector2i) -> AtlasTexture:
	if cell.x < 0 or cell.x >= BUTTON_SHEET_COLUMNS \
			or cell.y < 0 or cell.y >= BUTTON_SHEET_ROWS:
		push_error("MenuTheme: cell %s is off the button sheet." % cell)
		return null

	var cached: AtlasTexture = _icons.get(cell)
	if cached != null:
		return cached

	var texture := AtlasTexture.new()
	texture.atlas = BUTTON_SHEET
	texture.region = Rect2(cell * BUTTON_SIZE, Vector2i(BUTTON_SIZE, BUTTON_SIZE))
	texture.filter_clip = true
	_icons[cell] = texture
	return texture

## The same button pressed flat: the cell one to the right.
static func pressed_icon(cell: Vector2i) -> AtlasTexture:
	return icon(cell + Vector2i.RIGHT)

## A button wearing [param cell]. It reads as pressed while held, and
## [member BaseButton.toggle_mode] makes it stay pressed once picked,
## which is what the tabs want.
static func button(cell: Vector2i, tooltip: String = "") -> TextureButton:
	var node := TextureButton.new()
	node.texture_normal = icon(cell)
	node.texture_hover = pressed_icon(cell)
	node.texture_pressed = pressed_icon(cell)
	node.tooltip_text = tooltip
	node.custom_minimum_size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	node.size = Vector2(BUTTON_SIZE, BUTTON_SIZE)
	return node

## A plaque [param width] by [param height]. Anything shorter than twice
## [constant PLAQUE_MARGIN] is all corner and comes out as a lozenge,
## which is still the right shape — just a rounder one.
static func plaque(width: float, height: float) -> NinePatchRect:
	var rect := NinePatchRect.new()
	rect.texture = PLAQUE
	rect.patch_margin_left = PLAQUE_MARGIN
	rect.patch_margin_top = PLAQUE_MARGIN
	rect.patch_margin_right = PLAQUE_MARGIN
	rect.patch_margin_bottom = PLAQUE_MARGIN
	rect.size = Vector2(width, height)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

# --- Symbols -----------------------------------------------------------

## Cells on the emoji sheet used as labels rather than as items. Picking
## them from the same sheet the items come from keeps one visual language
## across the menu: everything with a picture beside it is drawn in the
## same hand.
const SYMBOL_CALENDAR := Vector2i(1, 24)  ## Clipboard — the date.
const SYMBOL_SPROUT := Vector2i(0, 15)    ## Seedling — the farm itself.
const SYMBOL_STAR := Vector2i(1, 10)      ## Star — how much has been seen.
const SYMBOL_JAR := Vector2i(9, 28)       ## Stoppered jar — what is stored.
const SYMBOL_SUNRISE := Vector2i(0, 32)   ## Sun over the horizon — morning.
const SYMBOL_SUN := Vector2i(2, 31)       ## Sun — the middle of the day.
const SYMBOL_MOON := Vector2i(0, 33)      ## Moon — night.

## The sky for [param phase], so the clock carries the time of day in a
## picture rather than only in a word.
static func phase_symbol(phase: DayNightCycle.Phase) -> Vector2i:
	match phase:
		DayNightCycle.Phase.MORNING: return SYMBOL_SUNRISE
		DayNightCycle.Phase.NOON: return SYMBOL_SUN
		DayNightCycle.Phase.NIGHT: return SYMBOL_MOON
	return SYMBOL_SUN

## An emoji cell drawn at [param side] pixels, ready to place.
static func symbol(cell: Vector2i, side: int = 18) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = ItemDb.icon_at(cell)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.size = Vector2(side, side)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

## Cell a boxed symbol sits in: the bag's own art, so a picture on a
## panel is framed the same way a picture in the bag is.
const SYMBOL_BOX: Texture2D = preload("res://Assets/UI/Inventory/Slot_Small.png")
## Size of the corner artwork in [constant SYMBOL_BOX].
##
## The cell was painted at 30x32 and is drawn here at rather less, which
## a nine-patch can do without showing: the corners keep their own pixels
## and only the flat middle is squeezed, and there is nothing in flat
## colour to go wrong. Seven is the smallest margin that clears the
## cell's border and its inner highlight; eight leaves a pixel in hand.
const SYMBOL_BOX_MARGIN: int = 8
## Side of a boxed symbol.
const SYMBOL_BOX_SIZE: int = 24
## Cell art kept clear around the picture inside a box. Four leaves the
## picture at 16, which is exactly half an emoji cell and so scales
## without landing pixels between pixels.
const SYMBOL_BOX_INSET: int = 4

## A picture in a cell of its own.
##
## Used wherever a symbol would otherwise sit straight on a panel. In a
## menu where every other picture — every item in the bag, every entry in
## the almanac — is framed, the unframed one reads as the picture nobody
## found a home for.
static func boxed_symbol(cell: Vector2i, side: int = SYMBOL_BOX_SIZE) -> NinePatchRect:
	var box := NinePatchRect.new()
	box.texture = SYMBOL_BOX
	box.patch_margin_left = SYMBOL_BOX_MARGIN
	box.patch_margin_top = SYMBOL_BOX_MARGIN
	box.patch_margin_right = SYMBOL_BOX_MARGIN
	box.patch_margin_bottom = SYMBOL_BOX_MARGIN
	box.size = Vector2(side, side)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := symbol(cell, side - SYMBOL_BOX_INSET * 2)
	icon.name = "Icon"
	icon.position = Vector2.ONE * SYMBOL_BOX_INSET
	box.add_child(icon)
	return box

## The picture inside a box, for callers that swap it as the day turns.
static func boxed_icon(box: NinePatchRect) -> TextureRect:
	return box.get_node("Icon") as TextureRect

# --- Category colours --------------------------------------------------

## The resting face of the disc on row [param colour] of the round sheets.
## [param big] picks the 32px sheet over the 16px one.
static func disc(colour: int, big: bool = false) -> AtlasTexture:
	var cell := mini(maxi(colour, 0), ROUND_COLOURS - 1)
	var side := ROUND_MEDIUM_SIZE if big else ROUND_SMALL_SIZE
	var key := Vector2i(side, cell)

	var cached: AtlasTexture = _discs.get(key)
	if cached != null:
		return cached

	var texture := AtlasTexture.new()
	texture.atlas = ROUND_MEDIUM if big else ROUND_SMALL
	texture.region = Rect2(Vector2i(0, cell * side), Vector2i(side, side))
	texture.filter_clip = true
	_discs[key] = texture
	return texture

## The disc standing for [param category].
static func category_disc(category: ItemData.Category, big: bool = false) -> AtlasTexture:
	return disc(CATEGORY_COLOUR.get(category, 0), big)

## A disc drawn in a rect of its own, ready to place. Used where the
## colour is a label rather than something to press.
static func category_mark(category: ItemData.Category, big: bool = false) -> TextureRect:
	var mark := TextureRect.new()
	mark.texture = category_disc(category, big)
	mark.size = mark.texture.get_size()
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return mark
