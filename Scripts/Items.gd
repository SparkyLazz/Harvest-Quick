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
			"sheet": EMOJI, "region": Rect2(132, 677, 24, 24), "scale": 0.5},
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

## Returns {name, sheet, region, scale, drop_sheet, drop_region, max_stack, kind,
## crop} or {} for an unknown id. `sheet`/`region`/`scale` are the slot icon and
## `drop_*` the one shown when the item pops out of the world.
## `kind` is "tool", "seed", "crop", "material" or "tree_seed"; `crop` is only
## set for seeds and crops, and `tree` -- the species it grows -- for tree seeds.
static func info(id: String) -> Dictionary:
	if TOOLS.has(id):
		var tool: Dictionary = TOOLS[id]
		return _entry(tool["name"], EMOJI, tool["region"], 1, "tool", "", tool["scale"])
	if MATERIALS.has(id):
		return _outlined(MATERIALS[id], "material")
	if TREE_SEEDS.has(id):
		var entry := _outlined(TREE_SEEDS[id], "tree_seed")
		entry["tree"] = TREE_SEEDS[id]["tree"]
		return entry
	if id.ends_with(SEED_SUFFIX):
		var crop := id.trim_suffix(SEED_SUFFIX)
		if CropDB.CROPS.has(crop):
			return _entry(CropDB.CROPS[crop]["name"] + " Seeds", SHEET,
					_cell_region(0, CropDB.CROPS[crop]["row"]), MAX_STACK, "seed", crop)
	if CropDB.CROPS.has(id):
		return _entry(CropDB.CROPS[id]["name"], SHEET,
				_cell_region(1, CropDB.CROPS[id]["row"]), MAX_STACK, "crop", id)
	return {}


static func display_name(id: String) -> String:
	return info(id).get("name", id)


## "Tool", "Seed", "Crop" or "Material", for the tooltip's second line.
static func kind_label(id: String) -> String:
	return String(info(id).get("kind", "")).capitalize()


## A sentence or two of detail for the tooltip.
static func describe(id: String) -> String:
	var entry := info(id)
	match entry.get("kind", ""):
		"tool":
			return TOOL_TEXT.get(id, "")
		"seed":
			var crop: String = entry["crop"]
			var seconds := (CropDB.stage_count(crop) - 1) * CropDB.seconds_per_stage(crop)
			return "Plant in tilled soil and keep it watered. Ripens after about %d seconds of watering." 					% roundi(seconds)
		"crop":
			return "Fresh from the field."
		"material":
			return MATERIALS[id]["text"]
		"tree_seed":
			return "Plant it in open grass and it grows into %s." % TREE_SEEDS[id]["tree_name"]
	return ""


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
	}
