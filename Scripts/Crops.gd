class_name CropDB
extends RefCounted

## What each crop looks like and how fast it grows. The plant sheet and the item
## sheet share a row per crop, so one `row` finds the growth sprites, the seed
## packet and the harvested produce.
##
## Every stage is one column: seeds on the ground, a planted seed, then the
## growing plant. Crops grow overnight, as in Stardew: `days` is how many nights
## the soil has to have been watered before the crop is ripe, and the stages in
## between are spread evenly over those nights.

## The same sprites twice: dry soil, and the soil darkened after watering.
const SHEET := preload("res://Assets/Farm/Farming_Plants_V2.png")
const SHEET_WATERED := preload("res://Assets/Farm/Farming_Plants_V2_Watered.png")
const CELL := 16

const CROPS := {
	"corn": {"name": "Corn", "row": 1, "stages": 7, "days": 10},
	"carrot": {"name": "Carrot", "row": 2, "stages": 6, "days": 4},
	"cauliflower": {"name": "Cauliflower", "row": 3, "stages": 6, "days": 10},
	"tomato": {"name": "Tomato", "row": 4, "stages": 6, "days": 8},
	"eggplant": {"name": "Eggplant", "row": 5, "stages": 6, "days": 5},
	"bluebell": {"name": "Bluebell", "row": 6, "stages": 6, "days": 5},
	"lettuce": {"name": "Lettuce", "row": 7, "stages": 6, "days": 5},
	"wheat": {"name": "Wheat", "row": 8, "stages": 6, "days": 4},
	"pumpkin": {"name": "Pumpkin", "row": 9, "stages": 6, "days": 12},
	"turnip": {"name": "Turnip", "row": 10, "stages": 6, "days": 4},
	"rose": {"name": "Rose", "row": 11, "stages": 6, "days": 7},
	"beet": {"name": "Beet", "row": 12, "stages": 6, "days": 6},
	"starfruit": {"name": "Starfruit", "row": 13, "stages": 6, "days": 13},
	"cucumber": {"name": "Cucumber", "row": 14, "stages": 6, "days": 8},
}

static func stage_count(crop: String) -> int:
	return CROPS[crop]["stages"]


## Watered nights from planting to ripe.
static func days_to_ripen(crop: String) -> int:
	return CROPS[crop]["days"]


## Which stage a crop shows after `grown` watered nights. The first stage is the
## day it goes in; the last is ripe, reached on exactly `days`.
static func stage_after(crop: String, grown: int) -> int:
	var last := stage_count(crop) - 1
	if grown >= days_to_ripen(crop):
		return last
	return grown * last / days_to_ripen(crop)


## The sprite for one growth stage. Corn's last two stages are two tiles tall and
## stand in the rows above its row, so the rect is not always 16x16.
static func stage_region(crop: String, stage: int) -> Rect2:
	var row: int = CROPS[crop]["row"]
	if crop == "corn" and stage >= 5:
		return Rect2(stage * CELL, 0, CELL, CELL * 2)
	return Rect2(stage * CELL, row * CELL, CELL, CELL)
