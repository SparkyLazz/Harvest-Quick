class_name ItemData
extends Resource

## One kind of thing that can sit in a slot.
##
## This is the description of an item, not an item: every watering can in the
## world points at the same [ItemData]. Nothing here changes while the game
## runs, so the resource can be shared freely and saved by path.
##
## A tool is an item whose [member action] names a set of animations on the
## player's sheet. The player plays "<action>_<facing>", so [code]&"hoe"[/code]
## reaches hoe_down, hoe_up, hoe_left and hoe_right. An item with no action is
## simply carried.

## Short name this item is filed under. Saves and recipes refer to items by
## this rather than by resource path, so it survives the file being moved.
@export var id: StringName = &""

## What the item is called on screen.
@export var display_name: String = ""

## A line or two about it, for a shop page or a tooltip. Empty for anything
## that explains itself, which is most of what sits in a slot — the description
## is for the things a player is deciding between, not for everything.
@export_multiline var description: String = ""

## The picture in the slot. Normally an [AtlasTexture] cut from the emoji
## sheet in Assets/UI/Objects, whose cells are 32x32.
@export var icon: Texture2D

## The animation set the player uses when swinging this, or empty for
## something that is only carried.
@export var action: StringName = &""

## How many fit in one slot. Tools are one apiece.
@export var stack_size: int = 1

## Whether swinging this does anything.
func is_tool() -> bool:
	return action != &""
