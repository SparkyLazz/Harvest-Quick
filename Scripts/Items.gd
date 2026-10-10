class_name ItemDB
extends RefCounted

## What an item id means: its name, its icon, how it stacks and what it does.
## Tools are single items; every crop gives a "<crop>_seed" and a "<crop>"
## (the harvested produce), both cut from the pack's item sheet.

const SHEET := preload("res://Assets/Items/All_Items.png")
const EMOJI := preload("res://Assets/UI/Emoji.png")
const CELL := 16
const MAX_STACK := 99
const SEED_SUFFIX := "_seed"

const HOE := "hoe"
const WATERING_CAN := "watering_can"

# Tool icons come off the emoji sheet. They are drawn for a 32px cell, twice the
# size of the 16px crop icons, so half size brings them in line with those.
const TOOLS := {
	HOE: {"name": "Hoe", "region": Rect2(164, 769, 25, 30), "scale": 0.5},
	WATERING_CAN: {"name": "Watering Can", "region": Rect2(193, 773, 30, 24), "scale": 0.5},
}

const TOOL_TEXT := {
	HOE: "Breaks up grass into tilled soil you can plant in. Costs stamina.",
	WATERING_CAN: "Waters tilled soil. Crops only grow while the soil is wet.",
}

## Returns {name, sheet, region, scale, max_stack, kind, crop} or {} for an unknown id.
## `kind` is "tool", "seed" or "crop"; `crop` is only set for the last two.
static func info(id: String) -> Dictionary:
	if TOOLS.has(id):
		var tool: Dictionary = TOOLS[id]
		return _entry(tool["name"], EMOJI, tool["region"], 1, "tool", "", tool["scale"])
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


## "Tool", "Seed" or "Crop", for the tooltip's second line.
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
	return ""


static func seed_id(crop: String) -> String:
	return crop + SEED_SUFFIX


static func is_seed(id: String) -> bool:
	return info(id).get("kind", "") == "seed"


static func max_stack(id: String) -> int:
	return info(id).get("max_stack", MAX_STACK)


static func _cell_region(column: int, row: int) -> Rect2:
	return Rect2(column * CELL, row * CELL, CELL, CELL)


static func _entry(item_name: String, sheet: Texture2D, region: Rect2, stack: int,
		kind: String, crop: String, icon_scale: float = 1.0) -> Dictionary:
	return {
		"name": item_name,
		"sheet": sheet,
		"region": region,
		"scale": icon_scale,
		"max_stack": stack,
		"kind": kind,
		"crop": crop,
	}
