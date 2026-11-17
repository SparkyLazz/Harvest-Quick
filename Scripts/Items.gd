class_name ItemDB
extends RefCounted

## What an item id means: its name, its icon, how it stacks and what it does.
## Tools are single items; every crop gives a "<crop>_seed" and a "<crop>"
## (the harvested produce), both cut from the pack's item sheet. Materials are
## what the world gives up to tools, like wood off any felled tree. Tree seeds
## are what each kind of tree drops; planted in open grass they grow into that
## kind of tree.
##
## An item can wear two icons: the one in its inventory slot, and the one it
## shows when it pops out of the world. Materials use the pack's outlined
## sprites for the pop, whose cream halo keeps them readable against grass.

const SHEET := preload("res://Assets/Items/All_Items.png")
const EMOJI := preload("res://Assets/UI/Emoji.png")
# Dropped-item sprites with their halo, and the same with it cleared for slots
# (Tools/strip_halo.py makes the second from the first).
const DROP_SHEET := preload("res://Assets/Items/Wood_Items.png")
const DROP_SHEET_PLAIN := preload("res://Assets/Items/Wood_Items_Plain.png")
const CELL := 16
const MAX_STACK := 99
const SEED_SUFFIX := "_seed"

## What the shipping bin pays for a tree's seed. Kept low: trees drop them for
## free, and planting them back is the better use.
const TREE_SEED_PRICE := 5

const HOE := "hoe"
const WATERING_CAN := "watering_can"
const AXE := "axe"
const WOOD := "wood"
const ACORN := "acorn"
const BIRCH_POD := "birch_pod"
const CHERRY_PIT := "cherry_pit"
const PINECONE := "pinecone"

# Tool icons come off the emoji sheet. They are drawn for a 32px cell, twice the
# size of the 16px crop icons, so half size brings them in line with those.
const TOOLS := {
	HOE: {"name": "Hoe", "region": Rect2(164, 769, 25, 30), "scale": 0.5},
	WATERING_CAN: {"name": "Watering Can", "region": Rect2(193, 773, 30, 24), "scale": 0.5},
	AXE: {"name": "Axe", "region": Rect2(133, 769, 25, 31), "scale": 0.5},
}

const TOOL_TEXT := {
	HOE: "Breaks up grass into tilled soil you can plant in. Costs stamina.",
	WATERING_CAN: "Waters tilled soil. Crops only grow while the soil is wet.",
	AXE: "Chops trees for wood, breaks flowers, mushrooms and fences, and turns hoed soil back into grass. Costs stamina.",
}

# Materials pop out of the world as the outlined sprite at `drop`, a 16px cell
# of the drop sheet (one row per kind of wood). Wood shows the emoji sheet's log
# in its slot, drawn for a 32px cell like the tools; the rest show their own
# sprite with the halo cleared.
const MATERIALS := {
	WOOD: {"name": "Wood", "drop": Vector2i(3, 2), "text": "Logs from a felled tree.",
			"sheet": EMOJI, "region": Rect2(132, 677, 24, 24), "scale": 0.5, "price": 2},
}

# Tree seeds, drawn the same way as materials. `tree` is the ChoppableTree
# species each one grows into.
const TREE_SEEDS := {
	ACORN: {"name": "Acorn", "drop": Vector2i(0, 2), "tree": "oak", "tree_name": "an oak"},
	BIRCH_POD: {"name": "Birch Seed Pod", "drop": Vector2i(0, 1), "tree": "birch", "tree_name": "a birch"},
	CHERRY_PIT: {"name": "Cherry Pit", "drop": Vector2i(0, 0), "tree": "cherry",
			"tree_name": "a cherry blossom tree"},
	PINECONE: {"name": "Pinecone", "drop": Vector2i(0, 3), "tree": "pine", "tree_name": "a pine"},
}

## Every id asked about so far, worked out once. `info` sits under every stack
## count, every slot redraw and the tile cursor's per-frame check, so building
## a fresh dictionary per call was the busiest allocation in the game.
static var _info_cache := {}


## Returns {name, sheet, region, scale, drop_sheet, drop_region, max_stack, kind,
## crop, price, cost} or {} for an unknown id. `sheet`/`region`/`scale` are the
## slot icon and `drop_*` the one shown when the item pops out of the world.
## `kind` is "tool", "seed", "crop", "material" or "tree_seed"; `crop` is only
## set for seeds and crops, and `tree` -- the species it grows -- for tree seeds.
## `price` is what the shipping bin pays for one (0: it will not take it) and
## `cost` what the seed shop charges (0: not sold there).
##
## The dictionary is shared between callers and read-only: copy it with
## `duplicate()` before changing anything in it.
static func info(id: String) -> Dictionary:
	var cached: Variant = _info_cache.get(id)
	if cached != null:
		return cached
	var entry := _look_up(id)
	entry.make_read_only()
	_info_cache[id] = entry
	return entry


static func _look_up(id: String) -> Dictionary:
	if TOOLS.has(id):
		var tool: Dictionary = TOOLS[id]
		return _entry(tool["name"], EMOJI, tool["region"], 1, "tool", "", tool["scale"])
	if MATERIALS.has(id):
		var entry := _outlined(MATERIALS[id], "material")
		entry["price"] = MATERIALS[id].get("price", 0)
		return entry
	if TREE_SEEDS.has(id):
		var entry := _outlined(TREE_SEEDS[id], "tree_seed")
		entry["tree"] = TREE_SEEDS[id]["tree"]
		entry["price"] = TREE_SEED_PRICE
		return entry
	if id.ends_with(SEED_SUFFIX):
		var crop := id.trim_suffix(SEED_SUFFIX)
		if CropDB.CROPS.has(crop):
			var entry := _entry(CropDB.CROPS[crop]["name"] + " Seeds", SHEET,
					_cell_region(0, CropDB.CROPS[crop]["row"]), MAX_STACK, "seed", crop)
			# Sold back at half what they cost, as in Stardew: unwanted packets
			# are worth something, and buying to sell can never pay.
			entry["cost"] = CropDB.CROPS[crop]["seed"]
			entry["price"] = CropDB.CROPS[crop]["seed"] / 2
			return entry
	if CropDB.CROPS.has(id):
		var entry := _entry(CropDB.CROPS[id]["name"], SHEET,
				_cell_region(1, CropDB.CROPS[id]["row"]), MAX_STACK, "crop", id)
		entry["price"] = CropDB.CROPS[id]["price"]
		return entry
	return {}


static func display_name(id: String) -> String:
	return info(id).get("name", id)


## "Tool", "Seed", "Crop" or "Material", for the tooltip's second line.
static func kind_label(id: String) -> String:
	return String(info(id).get("kind", "")).capitalize()


## A sentence or two of detail for the tooltip.
static func describe(id: String) -> String:
	var entry := info(id)
	var sells := " Sells for %d." % sell_price(id) if sell_price(id) > 0 else ""
	match entry.get("kind", ""):
		"tool":
			return TOOL_TEXT.get(id, "")
		"seed":
			var crop: String = entry["crop"]
			return "Plant in tilled soil and water it every day. Ripens after %d days. Grows in %s." \
					% [CropDB.days_to_ripen(crop), CropDB.seasons_text(crop)]
		"crop":
			return "Fresh from the field." + sells
		"material":
			return MATERIALS[id]["text"] + sells
		"tree_seed":
			return "Plant it in open grass and it grows into %s." % TREE_SEEDS[id]["tree_name"] + sells
	return ""


## What the shipping bin pays for one; 0 for things it will not take, like tools.
static func sell_price(id: String) -> int:
	return info(id).get("price", 0)


## What the seed shop charges for one; 0 for things it does not sell.
static func buy_price(id: String) -> int:
	return info(id).get("cost", 0)


## What a whole inventory would fetch in the shipping bin.
static func value_of(inv: Inventory) -> int:
	var total := 0
	if inv != null:
		for i in inv.size():
			total += sell_price(inv.item_at(i)) * inv.count_at(i)
	return total


static func seed_id(crop: String) -> String:
	return crop + SEED_SUFFIX


static func is_seed(id: String) -> bool:
	return info(id).get("kind", "") == "seed"


static func is_tree_seed(id: String) -> bool:
	return TREE_SEEDS.has(id)


static func max_stack(id: String) -> int:
	return info(id).get("max_stack", MAX_STACK)


## An item off the outlined drop sheet: it pops out as the sprite at `drop`, and
## sits in its slot as the halo-less copy unless it names a slot icon of its own.
static func _outlined(def: Dictionary, kind: String) -> Dictionary:
	var drop := _cell_region(def["drop"].x, def["drop"].y)
	var entry := _entry(def["name"], def.get("sheet", DROP_SHEET_PLAIN), def.get("region", drop),
			MAX_STACK, kind, "", def.get("scale", 1.0))
	entry["drop_sheet"] = DROP_SHEET
	entry["drop_region"] = drop
	return entry


static func _cell_region(column: int, row: int) -> Rect2:
	return Rect2(column * CELL, row * CELL, CELL, CELL)


static func _entry(item_name: String, sheet: Texture2D, region: Rect2, stack: int,
		kind: String, crop: String, icon_scale: float = 1.0) -> Dictionary:
	return {
		"name": item_name,
		"sheet": sheet,
		"region": region,
		"scale": icon_scale,
		"drop_sheet": sheet,
		"drop_region": region,
		"max_stack": stack,
		"kind": kind,
		"crop": crop,
		"price": 0,
		"cost": 0,
	}
