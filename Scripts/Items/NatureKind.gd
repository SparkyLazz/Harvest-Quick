class_name NatureKind
extends Resource

## One kind of thing the scatter can put on the map.
##
## A kind is nearly all data: a rectangle of a sheet, how big a patch of
## ground it wants, and how often it should turn up. The one thing that is
## not data is whether it sways, because a tree that moves needs a different
## scene from a stone that does not.

## Where it is allowed to grow.
enum On {
	GRASS, ## Any grassed tile.
	SHORE, ## Grass with water next to it.
	WATER, ## Open sea.
}

## Short name, for reading a generated map back.
@export var id: StringName = &""

## The sheet the picture comes from.
@export var sheet: Texture2D

## Which part of it. For a swaying kind this is the first frame, and the rest
## follow to the right.
@export var region: Rect2 = Rect2(0, 0, 16, 16)

## How many frames, for a kind that moves. One is a still picture.
@export var frames: int = 1

## Frames a second, when it moves.
@export var fps: float = 6.0

## How many tiles of ground it stands on.
@export var footprint: Vector2i = Vector2i.ONE

## What ground it wants.
@export var on: On = On.GRASS

## How many tiles of ground it keeps between itself and the edge of the
## height it stands on, or -1 to take the scatter's own
## [member NatureScatter.edge_margin].
##
## Ground cover sets this to zero. A tuft of grass running right up to the
## lip of a hill is the fringe the map is drawn with; a tree doing the same
## has its trunk in the cliff face.
##
## Only read for a kind that grows on grass. A shore kind is *defined* by
## standing at the water's edge and a lily pad floats on open sea, so neither
## has an edge to keep off.
@export var edge_margin: int = -1

## Its share of the scatter, against the other kinds for the same ground. A
## kind at two is twice as likely as one at one.
@export var weight: float = 1.0

## Whether the player is stopped by it.
@export var solid: bool = false

@export_group("Breaking")
## Which tool clears it, or empty for scenery that cannot be removed.
@export var broken_by: StringName = &""
## How many swings.
@export var hits: int = 1
## What it leaves.
@export var drops: Array[ItemData] = []
@export var drop_counts: Array[int] = []

## Whether it needs the animated scene rather than the still one.
func moves() -> bool:
	return frames > 1
