class_name PlaceableData
extends ItemData

## An item that stops being an item and becomes part of the world.
##
## A tool is swung and stays in hand; this is set down and leaves the satchel
## for good. Everything a slot needs is already on [ItemData] — the icon, the
## name, how many stack — so what is added here is only what putting it down
## requires: the thing to spawn, how much room it takes, and what it is
## allowed to stand on.
##
## A placeable never names an [member ItemData.action], so [method
## ItemData.is_tool] is false for it and the swing code passes it by. The two
## kinds of item are told apart by type rather than by a flag, which means a
## slot holding one cannot accidentally be treated as the other.

## Where a thing is allowed to stand.
enum Surface {
	## Walkable ground that is not farm plot. Nearly everything.
	GROUND,
	## Bare soil — ground the hoe has been over. For anything that belongs
	## on a worked field rather than on grass.
	FARM,
	## Open water, for bridges and jetties.
	WATER,
}

## What to put in the world. The scene's origin is taken to be the bottom
## edge of the tile it stands on, so it sorts against the player the same way
## the player sorts against everything else.
@export var scene: PackedScene

## How many tiles it covers, counting right and down from the tile aimed at.
@export var footprint: Vector2i = Vector2i.ONE

## What it may be set down on.
@export var surface: Surface = Surface.GROUND

## How far above the tile's bottom edge the thing sorts from, in pixels.
##
## Everything set down stands on the bottom edge of its tile, because that is
## where a chest or a fence meets the ground and it is the point the player's
## own feet sort against. A plant is different: the player walks over it, and
## from a tile whose bottom edge is below their feet the plant would be drawn
## in front of them — a carrot growing out of their chest.
##
## Lifting the sort point to the top of the tile fixes that without moving
## the picture, which the scene shifts back down by the same amount. Sixteen
## is one tile; zero is the bottom edge, and right for anything solid.
@export var sort_lift: float = 0.0

## Whether picking it back up returns this item. Off for anything that is
## consumed by being placed.
@export var recoverable: bool = true

## Every tile [param origin] would cover.
func tiles_from(origin: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in maxi(footprint.x, 1):
		for y in maxi(footprint.y, 1):
			tiles.append(origin + Vector2i(x, y))
	return tiles
