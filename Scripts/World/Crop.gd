class_name Crop
extends Placed

## A plant in the ground, working its way along its row of the sheet.
##
## Growth is counted in days, not seconds: the clock says a day has passed
## and every crop asks whether it earned it. A crop earns a day by having
## been watered, and watering is forgotten each morning, so a field left
## alone simply stops rather than dying.
##
## The picture is one region of the plant sheet, moved along as the stages
## pass. There are two sheets — dry ground and wet — drawn identically apart
## from the soil, so switching between them is a change of texture and
## nothing else, and the plant never moves a pixel when it is watered.
##
## Crops that outgrow their tile have their upper half drawn on the row above
## in the sheet. That is a second sprite hanging a tile to the north, hidden
## until there is something to show, so the plant still occupies exactly the
## one square it was planted in.

## Emitted when the plant moves to a new stage, with that stage.
signal grew(stage: int)
## Emitted when it becomes ready to pick.
signal ripened
## Emitted when it is picked, with what came off it and how many.
signal harvested(item: ItemData, count: int)

## One cell of the plant sheet.
const CELL := 16

## How far above the plant's own origin an emote appears.
##
## Small, because the origin is already the top of the tile — the plant is
## drawn below it, not around it — so this is clearance over the plant's head
## and not the height of the plant.
const EMOTE_HEIGHT := 4.0

@export var dry_sheet: Texture2D
@export var watered_sheet: Texture2D

@onready var plant: Sprite2D = $Plant
@onready var topper: Sprite2D = $Topper

## What is growing here. Set by [method Placed.placed_as] from the seed, so
## one scene serves every crop there is.
var crop: CropData

## How far along the row, from zero (scattered seed) to [method
## CropData.ripe_stage].
var stage: int = 0

## Whether it has been watered today.
var watered: bool = false

## Days credited towards the next stage.
var _days: int = 0

func _ready() -> void:
	var clock := get_tree().get_first_node_in_group("day_night")
	if clock != null and clock.has_signal("day_passed"):
		clock.day_passed.connect(_on_day_passed)
	_redraw()

## Takes the crop from the seed that was planted.
func placed_as(from: PlaceableData, at: Vector2i) -> void:
	super(from, at)
	var seed_data := from as SeedData
	if seed_data != null:
		crop = seed_data.crop
	_redraw()

## Whether it can be picked.
func is_ripe() -> bool:
	return crop != null and crop.is_ripe(stage)

## Wets the ground, so today counts towards growing.
func water() -> bool:
	if watered:
		return false
	watered = true
	_redraw()
	_say(Emote.HEARTS_BLUE)
	return true

## Picking it. Returns whether anything came off.
##
## A crop that regrows drops back a few stages and stays in the ground; one
## that does not is pulled up, and saying so is left to whoever is holding
## the world — this only reports that it happened.
func harvest() -> bool:
	if not is_ripe() or crop == null or crop.produce == null:
		return false
	var count: int = maxi(crop.produce_count, 1)
	var left := Inventory.add(crop.produce, count)
	if left >= count:
		# Nowhere to put it: leave the crop standing rather than destroying
		# the harvest.
		return false
	harvested.emit(crop.produce, count - left)
	_say(Emote.HEARTS_GREEN)
	if crop.regrows:
		stage = clampi(crop.regrow_stage, 0, crop.ripe_stage())
		_days = 0
		_redraw()
	else:
		var world := get_tree().get_first_node_in_group("world_objects") as WorldObjects
		if world != null:
			var taken := world.remove(origin)
			if taken != null:
				taken.queue_free()
		else:
			queue_free()
	return true

## A crop answers to the watering can and to nothing else. Anything else
## swung at it falls through to [Placed], which will ignore it unless the
## crop has been given a [member Placed.broken_by].
func hit(action: StringName) -> bool:
	if action == &"water":
		return water()
	return super(action)

## A crop takes the can only while it is still thirsty.
func accepts(action: StringName) -> bool:
	if action == &"water":
		return not watered and not is_ripe()
	return super(action)

## Picking is what interacting with a crop means.
func interact() -> bool:
	return harvest()

## A crop is never dug up as an item — it is picked, or it is nothing.
func recover() -> PlaceableData:
	return null

## Pops an emote over the plant.
##
## Hung on the parent rather than on the plant, so a harvest can say thank
## you and be uprooted in the same breath without taking the emote with it.
func _say(region: Rect2) -> void:
	var parent := get_parent()
	if parent == null:
		return
	Emote.pop(parent, global_position + Vector2(0.0, -EMOTE_HEIGHT), region)

## Credits the day if it was earned, and moves the plant along when enough
## have been. Watering is cleared either way, so tomorrow has to be earned
## again.
func _on_day_passed(_day: int) -> void:
	advance_day()

func advance_day() -> void:
	if crop == null or is_ripe():
		watered = false
		_redraw()
		return
	if crop.needs_water and not watered:
		watered = false
		_redraw()
		return
	_days += 1
	watered = false
	if _days >= maxi(crop.days_per_stage, 1):
		_days = 0
		stage = mini(stage + 1, crop.ripe_stage())
		grew.emit(stage)
		if is_ripe():
			ripened.emit()
	_redraw()

## Points both sprites at the right cell of the right sheet.
func _redraw() -> void:
	if plant == null or crop == null:
		return
	var sheet: Texture2D = watered_sheet if watered and watered_sheet != null else dry_sheet
	plant.texture = sheet
	plant.region_enabled = true
	plant.region_rect = Rect2(stage * CELL, crop.sheet_row * CELL, CELL, CELL)

	# The upper half, when the crop has one and this stage has reached it.
	# An empty region is the artist's way of saying "nothing up here yet", so
	# the sprite is simply hidden rather than drawing blank.
	var has_top := crop.topper_row >= 0
	topper.visible = has_top
	if has_top:
		topper.texture = sheet
		topper.region_enabled = true
		topper.region_rect = Rect2(stage * CELL, crop.topper_row * CELL, CELL, CELL)
