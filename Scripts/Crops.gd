class_name CropDB
extends RefCounted

## What each crop looks like, how fast it grows, when it grows, and what it is
## worth. The plant sheet and the item sheet share a row per crop, so one `row`
## finds the growth sprites, the seed packet and the harvested produce.
##
## Every stage is one column: seeds on the ground, a planted seed, then the
## growing plant. Crops grow overnight, as in Stardew: `days` is how many nights
## the soil has to have been watered before the crop is ripe, and the stages in
## between are spread evenly over those nights.
##
## `seasons` lists the seasons a crop grows in (0 Spring .. 3 Winter; nothing
## grows in Winter). Its seed is only sold then, it can only be planted then,
## and it dies the morning a season starts that is not one of them.
##
## `price` is what the shipping bin pays for one, `seed` what a packet costs.
## They are set so that a tile kept planted earns about what Tools/econ_sim.py
## assumes per day -- Spring ~6, Summer ~9, Fall ~10 -- with a packet at about
## 40% of the crop. That script keeps a copy of this table; change both.

## The same sprites twice: dry soil, and the soil darkened after watering.
const SHEET := preload("res://Assets/Farm/Farming_Plants_V2.png")
const SHEET_WATERED := preload("res://Assets/Farm/Farming_Plants_V2_Watered.png")
const CELL := 16

const SPRING := 0
const SUMMER := 1
const FALL := 2

const CROPS := {
	"corn": {"name": "Corn", "row": 1, "stages": 7, "days": 10, "seasons": [SUMMER, FALL], "price": 95, "seed": 38},
	"carrot": {"name": "Carrot", "row": 2, "stages": 6, "days": 4, "seasons": [SPRING], "price": 24, "seed": 10},
	"cauliflower": {"name": "Cauliflower", "row": 3, "stages": 6, "days": 10, "seasons": [SPRING], "price": 70, "seed": 30},
	"tomato": {"name": "Tomato", "row": 4, "stages": 6, "days": 8, "seasons": [SUMMER], "price": 72, "seed": 28},
	"eggplant": {"name": "Eggplant", "row": 5, "stages": 6, "days": 5, "seasons": [FALL], "price": 50, "seed": 20},
	"bluebell": {"name": "Bluebell", "row": 6, "stages": 6, "days": 5, "seasons": [SPRING], "price": 32, "seed": 14},
	"lettuce": {"name": "Lettuce", "row": 7, "stages": 6, "days": 5, "seasons": [SPRING], "price": 30, "seed": 12},
	"wheat": {"name": "Wheat", "row": 8, "stages": 6, "days": 4, "seasons": [SUMMER, FALL], "price": 32, "seed": 12},
	"pumpkin": {"name": "Pumpkin", "row": 9, "stages": 6, "days": 12, "seasons": [FALL], "price": 130, "seed": 52},
	"turnip": {"name": "Turnip", "row": 10, "stages": 6, "days": 4, "seasons": [SPRING], "price": 22, "seed": 8},
	"rose": {"name": "Rose", "row": 11, "stages": 6, "days": 7, "seasons": [SUMMER], "price": 63, "seed": 26},
	"beet": {"name": "Beet", "row": 12, "stages": 6, "days": 6, "seasons": [FALL], "price": 60, "seed": 24},
	"starfruit": {"name": "Starfruit", "row": 13, "stages": 6, "days": 13, "seasons": [SUMMER], "price": 140, "seed": 60},
	"cucumber": {"name": "Cucumber", "row": 14, "stages": 6, "days": 8, "seasons": [SUMMER], "price": 68, "seed": 26},
}

static func stage_count(crop: String) -> int:
	return CROPS[crop]["stages"]


## Watered nights from planting to ripe.
static func days_to_ripen(crop: String) -> int:
	return CROPS[crop]["days"]


## Does `crop` grow in season `season` (Calendar.season_index)?
static func grows_in(crop: String, season: int) -> bool:
	return CROPS.has(crop) and season in CROPS[crop]["seasons"]


## Every crop that grows in season `season`, in table order.
static func in_season(season: int) -> Array[String]:
	var out: Array[String] = []
	for crop: String in CROPS:
		if grows_in(crop, season):
			out.append(crop)
	return out


## "Spring", "Summer and Fall" -- for descriptions.
static func seasons_text(crop: String) -> String:
	var names: Array[String] = []
	for season: int in CROPS[crop]["seasons"]:
		names.append(Calendar.SEASONS[season])
	return " and ".join(names)


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
