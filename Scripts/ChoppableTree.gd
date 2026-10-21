class_name ChoppableTree
extends StaticBody2D

## A tree the axe can bring down. Each chop shakes it; the last one fells it,
## and what is left is a stump that one more chop clears away. Felling gives
## wood and, sometimes, the tree's own seed; the stump gives a little more wood.
##
## Comes in four kinds -- oak, birch, cherry blossom and pine -- picked with
## `species`. The oak has the pack's hand-drawn shake and fall; the others only
## come as still sprites, so their shake and fall are tweened.
##
## Paint it: the tileset's "Trees" scene-collection source holds a scene per
## kind, so the tile brush on a y-sorted TileMapLayer drops real trees, each its
## own node. The node's origin is the centre of the cell it was painted in, which
## is also what it depth-sorts by; the trunk stands a little below that.
## Placing a scene by hand works too, as long as it sits on a cell centre.
##
## A tree can also start life as a seed the player planted. It then grows
## through four young stages -- planted seed, sprout, sapling, young tree --
## before it is a full tree that gives wood. A stage takes `grow_seconds` on the
## map, and every night slept moves it on one more. Young trees have no
## collision, and the axe simply pulls one up, handing the seed back.
##
## What the axe has done to it, and how far it has grown, is kept in
## PlayerState, keyed by that cell, so a half-chopped tree, a stump, a cleared
## cell or a sapling is still that way when the player comes back to the map.

## Emitted once the tree comes down, and again when the stump is cleared.
signal felled(stump: bool)

const OAK_SHEET := preload("res://Assets/Objects/Tree_Sprites.png")
const OAK_FALL_SHEET := preload("res://Assets/Objects/Tree_Fall.png")
# Every frame is laid on one 64x48 canvas with the trunk's foot at FOOT, so a
# single anchor serves every kind and every animation. The oak's fall sheet is
# drawn that way already; everything else is padded onto it.
const CANVAS := Vector2(64, 48)
const FOOT := Vector2(40, 42)
const OAK_FRAME := 48
const OAK_FOOT := Vector2(24, 42)
const OAK_FALL_FRAMES := 13
# How far below the cell centre (the origin) the trunk meets the ground.
const FOOT_DROP := Vector2(0, 6)
const TILE := 16

const OAK_YOUNG_SHEET := preload("res://Assets/Objects/Trees_Oak.png")
# The four young stages; MATURE is the full tree.
const YOUNG_STAGES := 4
const MATURE := YOUNG_STAGES

# Per kind: what it drops, and for the still-sprite kinds, where the standing
# tree and the stump are on their sheet and where each meets the ground there.
# `young` is each young stage as [region, foot] on the kind's sheet (the oak's
# on OAK_YOUNG_SHEET). Measured off the art; the seed and sprout stages have no
# trunk, so they are centred on the sprite instead.
const SPECIES := {
	"oak": {"seed": ItemDB.ACORN, "young": [
			[Rect2(2, 20, 10, 11), Vector2(7, 30)], [Rect2(2, 37, 10, 10), Vector2(7, 46)],
			[Rect2(18, 16, 12, 15), Vector2(24, 28)], [Rect2(49, 17, 14, 29), Vector2(56, 44)]]},
	"birch": {"seed": ItemDB.BIRCH_POD, "sheet": preload("res://Assets/Objects/Trees_Birch.png"),
			"tree": Rect2(84, 16, 24, 31), "tree_foot": Vector2(96, 45),
			"stump": Rect2(35, 52, 10, 10), "stump_foot": Vector2(40, 61), "young": [
			[Rect2(17, 35, 13, 12), Vector2(24, 46)], [Rect2(34, 37, 10, 10), Vector2(39, 46)],
			[Rect2(33, 16, 14, 15), Vector2(40, 29)], [Rect2(65, 18, 14, 29), Vector2(72, 45)]]},
	"cherry": {"seed": ItemDB.CHERRY_PIT, "sheet": preload("res://Assets/Objects/Trees_Cherry.png"),
			"tree": Rect2(84, 16, 24, 31), "tree_foot": Vector2(96, 45),
			"stump": Rect2(67, 52, 10, 10), "stump_foot": Vector2(72, 61), "young": [
			[Rect2(18, 36, 10, 10), Vector2(23, 45)], [Rect2(34, 37, 10, 10), Vector2(39, 46)],
			[Rect2(34, 16, 12, 15), Vector2(40, 28)], [Rect2(65, 18, 14, 29), Vector2(72, 45)]]},
	"pine": {"seed": ItemDB.PINECONE, "sheet": preload("res://Assets/Objects/Trees_Pine.png"),
			"tree": Rect2(83, 16, 26, 31), "tree_foot": Vector2(96, 45),
			"stump": Rect2(34, 52, 12, 9), "stump_foot": Vector2(40, 60), "young": [
			[Rect2(18, 35, 12, 12), Vector2(24, 46)], [Rect2(34, 37, 10, 10), Vector2(39, 46)],
			[Rect2(50, 17, 12, 14), Vector2(56, 29)], [Rect2(64, 22, 16, 25), Vector2(72, 45)]]},
}

@export_enum("oak", "birch", "cherry", "pine") var species: String = "oak"

@export_group("Chopping")
## Chops it takes to fell the tree.
@export_range(1, 20) var hits_to_fell: int = 3
## Wood the tree gives when it comes down.
@export_range(0, 99) var wood: int = 3
## Chance the tree also drops its seed when it comes down.
@export_range(0.0, 1.0, 0.05) var seed_chance: float = 0.5
## Wood the stump gives when it is cleared.
@export_range(0, 99) var stump_wood: int = 1

@export_group("Growing")
## Seconds on the map each young stage takes. Each night slept counts as one
## stage too.
@export_range(1.0, 600.0, 1.0, "or_greater") var grow_seconds: float = 30.0

@export_group("Look")
## Playback speed of the shake when a chop lands, in frames per second.
@export_range(1.0, 30.0, 0.5) var shake_fps: float = 12.0
## Playback speed of the fall, in frames per second.
@export_range(1.0, 30.0, 0.5) var fall_fps: float = 12.0

# One set of frames per kind, shared by every tree of that kind.
static var _frames := {}

var _sprite: AnimatedSprite2D
var _hits := 0
var _stump := false
var _falling := false
var _stage := MATURE
## This tree's entry in the map's record: {hits, stump, gone}, plus
## {stage, progress, day, planted} for one grown from a seed.
var _state: Dictionary = {}


func _ready() -> void:
	if not SPECIES.has(species):
		push_warning("ChoppableTree: unknown species '%s', growing an oak." % species)
		species = "oak"
	_sprite = _make_sprite()
	add_child(_sprite)
	_sprite.animation_finished.connect(_on_animation_finished)
	_sprite.play(&"idle")

	var trees: Dictionary = PlayerState.world_for(_map())["trees"]
	var cell := _own_cell()
	if not trees.has(cell):
		trees[cell] = {"hits": 0, "stump": false, "gone": false}
	_state = trees[cell]
	if _state["gone"]:
		_remove()
		return
	_hits = _state["hits"]
	if _state.has("stage"):
		# Catch up on the nights slept while the map was not loaded.
		_stage = mini(_state["stage"] + PlayerState.day - _state["day"], MATURE)
		_state["stage"] = _stage
		_state["day"] = PlayerState.day
		PlayerState.day_changed.connect(_on_day_changed)
	if _state["stump"]:
		_show_stump()
	_show_stage()
	add_to_group(&"choppable")


func _process(delta: float) -> void:
	if _stage >= MATURE or not _state.has("stage"):
		return
	_state["progress"] += delta
	if _state["progress"] >= grow_seconds:
		_state["progress"] = 0.0
		_grow()


## How the record for a tree planted from a seed starts out. The tile that
## spawns it is painted after this goes into the map's record.
static func planted_state(scene_id: int) -> Dictionary:
	return {"hits": 0, "stump": false, "gone": false, "stage": 0, "progress": 0.0,
			"day": PlayerState.day, "planted": scene_id}


## Still growing: no wood yet, and nothing in the way.
func is_young() -> bool:
	return _stage < MATURE


func stage() -> int:
	return _stage


func _grow() -> void:
	_stage = mini(_stage + 1, MATURE)
	_state["stage"] = _stage
	_show_stage()
	# A little stretch up from the roots, as the crops do.
	_sprite.scale = Vector2(1.0, 0.82)
	create_tween().tween_property(_sprite, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_day_changed(_day: int) -> void:
	if is_young():
		_state["day"] = PlayerState.day
		_grow()


## The look and the hitbox for the current stage. Only a full tree blocks.
func _show_stage() -> void:
	var trunk := get_node_or_null("Trunk") as CollisionShape2D
	if trunk != null:
		trunk.set_deferred("disabled", is_young())
	if is_young():
		_sprite.play(&"young_%d" % _stage)
	elif not _stump and not _falling:
		_sprite.play(&"idle")


## The grid cell this tree stands in, on `layer`'s grid.
func cell_on(layer: TileMapLayer) -> Vector2i:
	return layer.local_to_map(layer.to_local(global_position))


func is_stump() -> bool:
	return _stump


## False while it is mid-fall, so a swing can't land on a tree already going.
func can_chop() -> bool:
	return not _falling


## Lands one chop. Returns what it gave, as a list of {item, amount} -- empty
## when the chop only shook it.
func chop() -> Array[Dictionary]:
	var drops: Array[Dictionary] = []
	if not can_chop():
		return drops
	if is_young():
		# Too small to give wood: it comes up whole, seed and all.
		_state["gone"] = true
		_remove()
		_add_drop(drops, SPECIES[species]["seed"], 1)
		return drops
	if _stump:
		_state["gone"] = true
		felled.emit(true)
		_remove()
		_add_drop(drops, ItemDB.WOOD, stump_wood)
		return drops
	_hits += 1
	_state["hits"] = _hits
	if _hits < hits_to_fell:
		_shake()
		return drops
	# Recorded as a stump straight away: the wood is already handed out, so
	# leaving mid-fall must not bring a whole tree back.
	_state["stump"] = true
	_falling = true
	_fall()
	felled.emit(false)
	_add_drop(drops, ItemDB.WOOD, wood)
	if randf() < seed_chance:
		_add_drop(drops, SPECIES[species]["seed"], 1)
	return drops


func _add_drop(drops: Array[Dictionary], item: String, amount: int) -> void:
	if amount > 0:
		drops.append({"item": item, "amount": amount})


func _is_oak() -> bool:
	return species == "oak"


func _shake() -> void:
	if _is_oak():
		_sprite.play(&"shake")
		return
	# A quick rock about the foot, dying away.
	var tween := create_tween()
	for angle in [0.06, -0.045, 0.025, 0.0]:
		tween.tween_property(_sprite, "rotation", angle, 1.0 / shake_fps)


func _fall() -> void:
	if _is_oak():
		_sprite.play(&"fall")
		return
	# The still-sprite kinds have no drawn fall: the stump appears in place
	# while a copy of the standing tree tips over about its foot and fades.
	var falling := _make_sprite()
	add_child(falling)
	_sprite.play(&"stump")
	var direction := -1.0 if randf() < 0.5 else 1.0
	var seconds := OAK_FALL_FRAMES / fall_fps
	var tween := create_tween().set_parallel(true)
	tween.tween_property(falling, "rotation", direction * 1.45, seconds * 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(falling, "modulate:a", 0.0, seconds * 0.4).set_delay(seconds * 0.6)
	tween.chain().tween_callback(_on_tween_fall_done.bind(falling))


func _on_tween_fall_done(falling: Node) -> void:
	falling.queue_free()
	_falling = false
	_stump = true


func _on_animation_finished() -> void:
	match _sprite.animation:
		&"shake":
			_sprite.play(&"idle")
		&"fall":
			# The fall ends on the stump, so it simply stays on that frame.
			_falling = false
			_stump = true


## Straight to the stump, for one left from an earlier visit.
func _show_stump() -> void:
	_stump = true
	if _is_oak():
		_sprite.animation = &"fall"
		_sprite.frame = OAK_FALL_FRAMES - 1
		_sprite.stop()
	else:
		_sprite.play(&"stump")


## Takes the tree off the map. A painted tree is erased from its layer, which
## frees this node; otherwise the layer would simply paint it back.
func _remove() -> void:
	remove_from_group(&"choppable")
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	var layer := get_parent() as TileMapLayer
	if layer != null:
		layer.erase_cell.call_deferred(_own_cell())
	else:
		queue_free()


func _own_cell() -> Vector2i:
	var layer := get_parent() as TileMapLayer
	if layer != null:
		return layer.local_to_map(position)
	return Vector2i((global_position / TILE).floor())


## The scene this tree belongs to: the first ancestor that is a scene file.
func _map() -> Node:
	var node := get_parent()
	while node != null and node.scene_file_path.is_empty():
		node = node.get_parent()
	return node


## A sprite pivoting on the trunk's foot, so a tween rocks or tips the tree
## about the ground rather than its middle.
func _make_sprite() -> AnimatedSprite2D:
	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = _build_frames()
	sprite.centered = false
	sprite.position = FOOT_DROP
	sprite.offset = -FOOT
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return sprite


func _build_frames() -> SpriteFrames:
	if not _frames.has(species):
		var frames := SpriteFrames.new()
		frames.remove_animation(&"default")
		if _is_oak():
			_add_frame(frames, &"idle", OAK_SHEET, Rect2(0, 0, OAK_FRAME, OAK_FRAME), OAK_FOOT)
			for i in 4:
				var cell := Vector2(i * OAK_FRAME, OAK_FRAME)
				_add_frame(frames, &"shake", OAK_SHEET, Rect2(cell, Vector2.ONE * OAK_FRAME), cell + OAK_FOOT)
			for i in OAK_FALL_FRAMES:
				var cell := Vector2(i * CANVAS.x, 0)
				_add_frame(frames, &"fall", OAK_FALL_SHEET, Rect2(cell, CANVAS), cell + FOOT)
		else:
			var kind: Dictionary = SPECIES[species]
			_add_frame(frames, &"idle", kind["sheet"], kind["tree"], kind["tree_foot"])
			_add_frame(frames, &"stump", kind["sheet"], kind["stump"], kind["stump_foot"])
		var young_sheet: Texture2D = OAK_YOUNG_SHEET if _is_oak() else SPECIES[species]["sheet"]
		var young: Array = SPECIES[species]["young"]
		for i in young.size():
			_add_frame(frames, &"young_%d" % i, young_sheet, young[i][0], young[i][1])
		for anim in frames.get_animation_names():
			frames.set_animation_loop(anim, anim != &"shake" and anim != &"fall")
		_frames[species] = frames
	var frames: SpriteFrames = _frames[species]
	if frames.has_animation(&"shake"):
		frames.set_animation_speed(&"shake", shake_fps)
		frames.set_animation_speed(&"fall", fall_fps)
	return frames


## Adds `region` of `sheet` as a frame, padded onto the shared canvas so that
## `foot` -- where the trunk meets the ground, in sheet coordinates -- lands on
## FOOT.
func _add_frame(frames: SpriteFrames, anim: StringName, sheet: Texture2D, region: Rect2,
		foot: Vector2) -> void:
	if not frames.has_animation(anim):
		frames.add_animation(anim)
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	atlas.margin = Rect2(FOOT - (foot - region.position), CANVAS - region.size)
	frames.add_frame(anim, atlas)
