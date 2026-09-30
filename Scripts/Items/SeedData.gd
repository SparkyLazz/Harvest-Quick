class_name SeedData
extends PlaceableData

## A packet of seeds.
##
## Planting is placing. A seed goes into a square of ground the hoe has been
## over, one to a tile, and is refused where something already stands — which
## is [WorldObjects] word for word, so this is a [PlaceableData] with a crop
## attached rather than a second, nearly identical thing.
##
## That also means seeds inherit everything placement already knows: the
## green square showing where they would land, the rule about staying on the
## player's own height, and the boundary of the farm.

## What grows out of it.
@export var crop: CropData

func _init() -> void:
	# The ground a seed wants is bare soil, not grass — which is exactly what
	# [enum PlaceableData.Surface] FARM means. Set here rather than left to
	# each seed resource, because a seed that could be planted on grass would
	# simply be a bug.
	surface = Surface.FARM
	# Seeds are not dug back up.
	recoverable = false
