class_name CropData
extends Resource

## One kind of crop: what it looks like growing, how long it takes, and what
## it leaves behind.
##
## The artist drew every crop as one row of the sheet in Assets/Plants, read
## left to right: scattered seed, then sprout, then bigger, ending at ripe.
## So a crop is very nearly just a row number, and this says which row and
## how slowly to walk along it.
##
## A few crops end up taller than the tile they stand in. The artist drew
## their upper halves on the row above, in the same columns, which is why
## [member topper_row] exists — the plant is still one tile of ground, it
## simply has a second picture floating over the tile to the north.

## Short name this crop is filed under, for saves and recipes.
@export var id: StringName = &""

## What it is called on screen.
@export var display_name: String = ""

@export_group("Sheet")
## Which row of the plant sheet this crop grows along.
@export var sheet_row: int = 0

## The row holding its upper half, for a crop too tall for one tile, or -1
## when it never outgrows its own square.
@export var topper_row: int = -1

## How many pictures there are, counting the scattered seed as the first.
## The ripe one is the last, so a six-stage crop is ripe at stage five.
@export var stages: int = 6

@export_group("Growing")
## Which seasons this will grow in, as flags in [enum Season.Of] order.
##
## The reason the shop has a right-hand page at all. A seed is a bet taken five
## or ten days before it pays, and the first thing that can make the bet
## impossible is the calendar: winter takes most of the catalogue off the table,
## and a player who finds that out by planting has found it out too late.
##
## Defaults to every season, so a crop that says nothing behaves as it did
## before this existed.
@export_flags("Spring", "Summer", "Autumn", "Winter") var seasons: int = 15

## Days each stage is held before the next. Growth only counts on days the
## crop was watered, unless [member needs_water] is off.
@export var days_per_stage: int = 1

## Whether a dry day is a wasted one. Off, the crop grows regardless, which
## is how a weed or a wild plant would behave.
@export var needs_water: bool = true

@export_group("Harvest")
## What picking it puts in the satchel.
@export var produce: ItemData

## How many, per plant.
@export var produce_count: int = 1

## Whether the plant survives being picked and goes back a stage or two, the
## way a berry bush does, rather than being pulled up whole.
@export var regrows: bool = false

## Which stage a regrowing crop drops back to once picked.
@export var regrow_stage: int = 3

## How many days from sowing to ripe, if it is watered every day. What the
## player is really buying, and what has to be set against how much of the
## season is left.
func days_to_ripe() -> int:
	return maxi(stages - 1, 0) * maxi(days_per_stage, 1)

## Whether this will grow in [param season].
func grows_in(season: Season.Of) -> bool:
	return Season.in_mask(seasons, season)

## The seasons it grows in, spelled out — "Spring, Autumn", or "All year".
func season_names() -> String:
	return Season.names_in_mask(seasons)

## The last stage, the one at which the crop can be picked.
func ripe_stage() -> int:
	return maxi(stages - 1, 0)

## Whether [param stage] is ready to pick.
func is_ripe(stage: int) -> bool:
	return stage >= ripe_stage()
