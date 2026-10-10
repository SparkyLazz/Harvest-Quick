class_name CropDB
extends RefCounted

## What each crop looks like and how fast it grows. The plant sheet and the item
## sheet share a row per crop, so one `row` finds the growth sprites, the seed
## packet and the harvested produce.
##
## Every stage is one column: seeds on the ground, a planted seed, then the
## growing plant. `seconds` is how long one stage takes *while the soil is wet*;
## a crop ripens after (stages - 1) stages' worth of watered time.

## The same sprites twice: dry soil, and the soil darkened after watering.
const SHEET := preload("res://Assets/Farm/Farming_Plants_V2.png")
const SHEET_WATERED := preload("res://Assets/Farm/Farming_Plants_V2_Watered.png")
const CELL := 16

const CROPS := {
	"corn": {"name": "Corn", "row": 1, "stages": 7, "seconds": 3.5},
	"carrot": {"name": "Carrot", "row": 2, "stages": 6, "seconds": 2.5},
	"cauliflower": {"name": "Cauliflower", "row": 3, "stages": 6, "seconds": 4.5},
	"tomato": {"name": "Tomato", "row": 4, "stages": 6, "seconds": 4.0},
	"eggplant": {"name": "Eggplant", "row": 5, "stages": 6, "seconds": 4.5},
	"bluebell": {"name": "Bluebell", "row": 6, "stages": 6, "seconds": 2.5},
	"lettuce": {"name": "Lettuce", "row": 7, "stages": 6, "seconds": 2.5},
	"wheat": {"name": "Wheat", "row": 8, "stages": 6, "seconds": 3.0},
	"pumpkin": {"name": "Pumpkin", "row": 9, "stages": 6, "seconds": 5.5},
	"turnip": {"name": "Turnip", "row": 10, "stages": 6, "seconds": 2.5},
	"rose": {"name": "Rose", "row": 11, "stages": 6, "seconds": 5.0},
	"beet": {"name": "Beet", "row": 12, "stages": 6, "seconds": 4.0},
	"starfruit": {"name": "Starfruit", "row": 13, "stages": 6, "seconds": 6.0},
	"cucumber": {"name": "Cucumber", "row": 14, "stages": 6, "seconds": 4.5},
}

static func stage_count(crop: String) -> int:
	return CROPS[crop]["stages"]


static func seconds_per_stage(crop: String) -> float:
	return CROPS[crop]["seconds"]


## The sprite for one growth stage. Corn's last two stages are two tiles tall and
## stand in the rows above its row, so the rect is not always 16x16.
static func stage_region(crop: String, stage: int) -> Rect2:
	var row: int = CROPS[crop]["row"]
	if crop == "corn" and stage >= 5:
		return Rect2(stage * CELL, 0, CELL, CELL * 2)
	return Rect2(stage * CELL, row * CELL, CELL, CELL)
