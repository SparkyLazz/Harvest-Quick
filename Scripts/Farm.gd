class_name Farm
extends Node2D

## Everything that lives on tilled soil: seeds, watering, growth and harvest.
##
## Soil counts as tilled once the player's hoe reports it. Watering wets a cell
## until the next morning, and crops grow overnight: each night a crop's soil
## was wet counts as one day grown, and then every cell dries out for the new
## day. So the loop is: hoe, plant, water, sleep, water, sleep... harvest. A
## watered crop swaps to the pack's watered version of its sprite; the soil is
## part of that sprite, so bare soil shows nothing but the splash.
##
## Plants are added as siblings of this node so they depth-sort against the
## player (the parent needs y_sort_enabled).
##
## The plots outlast the scene: on the way out they are written to PlayerState's
## record of this map, stamped with the day, and on the way back in they are
## planted again. Nights slept while the map was not loaded are caught up then:
## the first of them grows whatever was watered, and the rest find dry soil.

signal crop_planted(cell: Vector2i, crop: String)
signal cell_watered(cell: Vector2i)
signal crop_harvested(cell: Vector2i, crop: String, amount: int)

@export_group("Scene")
## Layer that supplies the grid. Defaults to a sibling named "Grass Layer".
@export var ground_layer_path: NodePath = ^"../Grass Layer"
## Player whose `tilled` signal marks soil as farmable.
@export var player_path: NodePath = ^"../Player"

@export_group("Look")
## Playback speed of the water drops, in frames per second.
@export_range(1.0, 30.0, 0.5) var drops_fps: float = 14.0
## How many drops rain onto a plant when it is watered.
@export_range(1, 16) var drops_count: int = 6
## Seconds over which the drops are spread, so they patter rather than land at once.
@export_range(0.0, 1.0, 0.05) var drops_spread: float = 0.3

const DROPS_SHEET := preload("res://Assets/Farm/Water_Drops.png")
const DROPS_FRAME := 48
const DROPS_FRAMES := 9
# Where a drop lands inside its 48x48 frame, so the frame can be placed with that
# point on the target. Frames 0-2 are the drop in the air, 3 on are the splash.
const DROPS_GROUND := Vector2(18, 34)
const DROPS_AIR_FRAMES := 3
# How far above its mark a drop starts, in pixels.
const DROPS_FALL := 7.0

static var _drops_frames: SpriteFrames

var _layer: TileMapLayer
var _tile := Vector2.ONE * 16.0
var _tilled := {}      # Vector2i -> true
var _crops := {}       # Vector2i -> {crop, stage, grown, sprite}
var _wet := {}         # Vector2i -> true, until the next morning

func _ready() -> void:
	_layer = get_node_or_null(ground_layer_path) as TileMapLayer
	if _layer == null:
		push_warning("Farm: no ground layer at '%s'." % ground_layer_path)
	elif _layer.tile_set:
		_tile = Vector2(_layer.tile_set.tile_size)
	var player := get_node_or_null(player_path)
	if player and player.has_signal("tilled"):
		player.connect("tilled", _on_tilled)
	if player and player.has_signal("untilled"):
		player.connect("untilled", _on_untilled)
	PlayerState.day_changed.connect(_on_day_changed)
	# Deferred: the plants go in beside this node, and the parent is still
	# busy adding its own children while they are readied.
	_restore.call_deferred(PlayerState.world_for(get_parent())["farm"])


func _exit_tree() -> void:
	_save(PlayerState.world_for(get_parent())["farm"])
	for cell in _crops:
		var sprite: Sprite2D = _crops[cell]["sprite"]
		if is_instance_valid(sprite):
			sprite.queue_free()


## Writes the plots into the map's record. Sprites are not kept; they are
## rebuilt from crop and stage when the farm comes back.
func _save(record: Dictionary) -> void:
	var crops := {}
	for cell: Vector2i in _crops:
		var state: Dictionary = _crops[cell]
		crops[cell] = {"crop": state["crop"], "grown": state["grown"]}
	record["tilled"] = _tilled.duplicate()
	record["wet"] = _wet.duplicate()
	record["crops"] = crops
	record["day"] = PlayerState.day


func _restore(record: Dictionary) -> void:
	if record.is_empty():
		return
	_tilled.merge(record["tilled"])
	_wet.merge(record["wet"])
	var crops: Dictionary = record["crops"]
	for cell: Vector2i in crops:
		var saved: Dictionary = crops[cell]
		var crop: String = saved["crop"]
		_crops[cell] = {"crop": crop, "grown": saved["grown"],
				"stage": CropDB.stage_after(crop, saved["grown"]), "sprite": _make_sprite(cell)}
	# One night is enough to catch up on: after it everything is dry, and dry
	# soil grows nothing, so any further nights away change nothing.
	if PlayerState.day > record["day"]:
		_pass_night(false)
	for cell: Vector2i in _crops:
		_refresh_sprite(cell)


## A night goes by: every watered crop grows a day, and all the soil dries out
## for the morning. `animate` gives each crop that moved up a stage the little
## stretch, for nights that pass with the farm on screen.
func _pass_night(animate: bool) -> void:
	for cell: Vector2i in _crops:
		if not _wet.has(cell):
			continue
		var state: Dictionary = _crops[cell]
		state["grown"] += 1
		var stage := CropDB.stage_after(state["crop"], state["grown"])
		if stage != state["stage"]:
			state["stage"] = stage
			if animate:
				_squash(state["sprite"])
	_wet.clear()


## How the plots stand right now: {tilled, watered, growing, ripe}. Nothing in
## here needs the breakdown; the profile panel reads it for its rail.
func counts() -> Dictionary:
	var ripe := 0
	for cell: Vector2i in _crops:
		if is_ripe(cell):
			ripe += 1
	return {
		"tilled": _tilled.size(),
		"watered": _wet.size(),
		"growing": _crops.size(),
		"ripe": ripe,
	}


func is_tilled(cell: Vector2i) -> bool:
	return _tilled.has(cell)


func has_crop(cell: Vector2i) -> bool:
	return _crops.has(cell)


func is_wet(cell: Vector2i) -> bool:
	return _wet.has(cell)


func is_ripe(cell: Vector2i) -> bool:
	if not _crops.has(cell):
		return false
	var state: Dictionary = _crops[cell]
	return state["stage"] >= CropDB.stage_count(state["crop"]) - 1


## Puts a seedling in tilled, empty soil. False if the cell cannot take one.
func plant(cell: Vector2i, crop: String) -> bool:
	if not CropDB.CROPS.has(crop) or not is_tilled(cell) or has_crop(cell):
		return false
	_crops[cell] = {"crop": crop, "stage": 0, "grown": 0, "sprite": _make_sprite(cell)}
	_refresh_sprite(cell)
	crop_planted.emit(cell, crop)
	return true


## Wets a tilled cell. False for ground that was never hoed.
func water(cell: Vector2i) -> bool:
	if not is_tilled(cell):
		return false
	_wet[cell] = true
	_refresh_sprite(cell)
	_spawn_drops(cell)
	cell_watered.emit(cell)
	return true


## What a ripe crop here would give, without taking it: {item, amount}, or {}.
func peek_harvest(cell: Vector2i) -> Dictionary:
	if not is_ripe(cell):
		return {}
	return {"item": _crops[cell]["crop"], "amount": 1}


## Pulls up a ripe crop and returns what it gave, {item, amount}, or {} if there
## was nothing ripe. The caller puts the produce in the inventory.
func harvest(cell: Vector2i) -> Dictionary:
	var yield_ := peek_harvest(cell)
	if yield_.is_empty():
		return yield_
	var sprite: Sprite2D = _crops[cell]["sprite"]
	sprite.queue_free()
	_crops.erase(cell)
	float_icon(cell, yield_["item"], yield_["amount"])
	crop_harvested.emit(cell, yield_["item"], yield_["amount"])
	return yield_


func _on_day_changed(_day: int) -> void:
	_pass_night(true)
	for cell: Vector2i in _crops:
		_refresh_sprite(cell)


func _cell_origin(cell: Vector2i) -> Vector2:
	if _layer == null:
		return Vector2(cell) * _tile
	return to_local(_layer.to_global(_layer.map_to_local(cell))) - _tile * 0.5


func _cell_center(cell: Vector2i) -> Vector2:
	return _cell_origin(cell) + _tile * 0.5


## The sprite's origin is the foot of its cell, so its position doubles as its
## depth-sort key and a tall plant still sorts by where it is rooted.
func _make_sprite(cell: Vector2i) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture = AtlasTexture.new()
	get_parent().add_child(sprite)
	sprite.global_position = to_global(_cell_origin(cell) + Vector2(0, _tile.y))
	return sprite


## Dry or watered sheet, and the frame for the crop's current stage.
func _refresh_sprite(cell: Vector2i) -> void:
	if not _crops.has(cell):
		return
	var state: Dictionary = _crops[cell]
	var sprite: Sprite2D = state["sprite"]
	var atlas := sprite.texture as AtlasTexture
	atlas.atlas = CropDB.SHEET_WATERED if _wet.has(cell) else CropDB.SHEET
	atlas.region = CropDB.stage_region(state["crop"], state["stage"])
	sprite.offset = Vector2(0, -atlas.region.size.y)


## A little stretch up from the roots when a plant reaches its next stage.
func _squash(sprite: Sprite2D) -> void:
	sprite.scale = Vector2(1.0, 0.82)
	create_tween().tween_property(sprite, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Rain a few drops onto the plant: each one falls from just above and splashes
## on the leaves, scattered over the body of whatever is growing there (or over
## the soil if nothing is).
func _spawn_drops(cell: Vector2i) -> void:
	if _drops_frames == null:
		_drops_frames = SpriteFrames.new()
		_drops_frames.set_animation_loop(&"default", false)
		for i in DROPS_FRAMES:
			var atlas := AtlasTexture.new()
			atlas.atlas = DROPS_SHEET
			atlas.region = Rect2(i * DROPS_FRAME, 0, DROPS_FRAME, DROPS_FRAME)
			_drops_frames.add_frame(&"default", atlas)
	_drops_frames.set_animation_speed(&"default", drops_fps)

	var origin := _cell_origin(cell)
	var height := _tile.y
	if _crops.has(cell):
		var state: Dictionary = _crops[cell]
		height = CropDB.stage_region(state["crop"], state["stage"]).size.y
	var foot := origin.y + _tile.y
	for i in drops_count:
		var mark := Vector2(origin.x + _tile.x * 0.5 + randf_range(-5.0, 5.0),
				randf_range(foot - height * 0.7, foot - 3.0))
		create_tween().tween_callback(_drop_at.bind(mark)).set_delay(randf() * drops_spread)


func _drop_at(mark: Vector2) -> void:
	var drop := AnimatedSprite2D.new()
	drop.sprite_frames = _drops_frames
	drop.centered = false
	drop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	drop.z_index = 5
	drop.position = mark - DROPS_GROUND + Vector2(0, -DROPS_FALL)
	add_child(drop)
	drop.animation_finished.connect(drop.queue_free)
	drop.play(&"default")
	# The sheet only has a few pixels of fall, so carry the drop the rest of the
	# way down over the frames where it is still in the air.
	create_tween().tween_property(drop, "position:y", mark.y - DROPS_GROUND.y,
			DROPS_AIR_FRAMES / drops_fps).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## The harvested item hops up off the plot and fades, so a pickup is visible even
## though the hotbar may not have a slot on screen for it. The axe borrows it for
## wood, which is why it is public. `order` fans out several pops from one cell
## so they don't land on top of each other. Uses the item's drop icon.
func float_icon(cell: Vector2i, item: String, amount: int, order: int = 0) -> void:
	var entry := ItemDB.info(item)
	if entry.is_empty():
		return
	var holder := Node2D.new()
	holder.z_index = 10
	holder.position = _cell_center(cell) + Vector2(order * 12, -order * 3)
	add_child(holder)
	var icon := Sprite2D.new()
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var atlas := AtlasTexture.new()
	atlas.atlas = entry["drop_sheet"]
	atlas.region = entry["drop_region"]
	icon.texture = atlas
	holder.add_child(icon)
	var label := Label.new()
	label.text = "+%d" % amount
	# Drawn big and scaled down so the glyphs stay sharp under the 4x camera.
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color("3a2a4a"))
	label.scale = Vector2.ONE * 0.18
	label.position = Vector2(6, -6)
	holder.add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(holder, "position:y", holder.position.y - 14.0, 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(holder, "modulate:a", 0.0, 0.3).set_delay(0.45)
	tween.chain().tween_callback(holder.queue_free)


func _on_tilled(cell: Vector2i) -> void:
	_tilled[cell] = true


## Grass has grown back over the cell, so it is no longer a plot.
func _on_untilled(cell: Vector2i) -> void:
	_tilled.erase(cell)
	_wet.erase(cell)
