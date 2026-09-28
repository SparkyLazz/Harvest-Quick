class_name ItemData
extends Resource

## One kind of thing that can sit in an inventory slot: a hoe, a turnip,
## a log.
##
## Item definitions are built in code by [ItemDatabase] rather than saved
## as .tres files. There is one line per item there, the icons all come
## out of the same sheet, and the whole roster fits on a screen — which is
## easier to read and to edit than a folder of near-identical resources.
##
## An [ItemData] is shared: every stack of turnips in the game points at
## the same one. Nothing here changes while the game runs, so treat it as
## read-only.

## Broad grouping, used for sorting and for deciding what a slot will
## accept. Nothing enforces it yet.
enum Category {
	TOOL,      ## Held and used; does not stack.
	SEED,      ## Planted into tilled soil.
	CROP,      ## Harvested produce.
	RESOURCE,  ## Raw material such as wood or stone.
	MISC,      ## Anything else.
}

## Stable key used everywhere else to refer to this item. Slots store the
## id, not the [ItemData], so a saved game stays readable and survives the
## roster being reordered.
@export var id: StringName = &""
## Name shown to the player.
@export var display_name: String = ""
## 32x32 icon, an [AtlasTexture] cut from the emoji sheet.
@export var icon: Texture2D
## Most of this item one slot can hold. 1 means it never stacks.
@export var max_stack: int = 99
@export var category: Category = Category.MISC
## One-line flavour or explanation, shown under the inventory grid.
@export_multiline var description: String = ""

static func create(
		item_id: StringName,
		name: String,
		item_icon: Texture2D,
		stack: int,
		item_category: Category,
		text: String) -> ItemData:
	var item := ItemData.new()
	item.id = item_id
	item.display_name = name
	item.icon = item_icon
	item.max_stack = maxi(stack, 1)
	item.category = item_category
	item.description = text
	return item

func is_stackable() -> bool:
	return max_stack > 1
