extends SceneTree

## Writes a **blank** `Scenes/City.tscn`: the nodes the code needs, wired up,
## and almost nothing drawn.
##
##   godot --headless --path . --script Tools/new_city_scene.gd
##   python -I Tools/fix_city_uids.py        # always, straight after
##
## This is a frame, not a town. The town's layout is drawn by hand in the
## editor (`Docs/GAME_DESIGN.md` 4c, decided 2026-11-19) -- an earlier version
## of this script generated a whole one and it read as generated: houses
## standing on grass with their doors opening onto nothing. What is left here
## is only the part that is plumbing rather than design:
##
##   - the six layers, named as the farm names them, with the tileset on them
##   - a small patch of ground to stand on, and water round it
##   - `FromFarm`, the ferry back, the three people, the player and the HUD
##
## Everything it draws is meant to be painted over or erased. The patch is
## grass over soil, the way the farm is, so a path is made by rubbing the grass
## out rather than by adding anything.
##
## **It refuses to run while the scene exists**, so it can never take a
## hand-drawn map with it. Delete `Scenes/City.tscn` first if you really want a
## blank one back.

const OUT := "res://Scenes/City.tscn"
const TILESET := "res://Tilemaps/Terrains.tres"

## Tile sources, as `Tilemaps/Terrains.tres` numbers them.
const SRC_WATER := 24
## Terrain set 0's terrains, by index.
const TERRAIN_SET := 0
const T_GRASS := 4
const T_SOIL := 0

## The patch to stand on. Small on purpose: it is somewhere to start painting
## from, not a map.
const LAND := Rect2i(0, 1, 14, 10)
## How far the water reaches past it.
const SEA := 12

## Where the farm's ferry puts the player down, and where the ferry back sits.
const ARRIVE := Vector2i(2, 5)
const FERRY_CELL := Vector2i(0, 5)
const FARM_SCENE := "res://Scenes/Dev.tscn"
const FARM_SPAWN := &"FromTown"

## The three people, stood in a row out of each other's reach. Move them to
## their doors once there are doors.
const FOLK: Array = [
	["seller", Vector2i(6, 4)],
	["lawyer", Vector2i(9, 4)],
	["neighbour", Vector2i(12, 4)],
]

const TILE := 16


func _initialize() -> void:
	await process_frame
	if ResourceLoader.exists(OUT):
		print("%s already exists -- refusing to overwrite a hand-drawn map." % OUT)
		print("Delete it first if you really want a blank one back.")
		quit()
		return
	var tile_set: TileSet = load(TILESET)
	if tile_set == null:
		push_error("No TileSet at " + TILESET)
		quit(1)
		return

	var root := Node2D.new()
	root.name = "City"
	root.y_sort_enabled = true

	# The farm's layer names, in the farm's order. Player and Townsfolk find
	# "Grass Layer" by that name; the rest are here so the two maps are built
	# the same way, and any of them may be left empty.
	var water := _layer(root, "Water Layer", tile_set, false)
	water.collision_enabled = false
	var ground := _layer(root, "Soil Layer", tile_set, false)
	var grass := _layer(root, "Grass Layer", tile_set, false)
	_layer(root, "Decorations", tile_set, true)
	_layer(root, "Buildings", tile_set, true)
	_layer(root, "Props", tile_set, true)

	for y in range(LAND.position.y - SEA, LAND.end.y + SEA):
		for x in range(LAND.position.x - SEA, LAND.end.x + SEA):
			water.set_cell(Vector2i(x, y), SRC_WATER, Vector2i.ZERO)
	ground.set_cells_terrain_connect(_cells(LAND), TERRAIN_SET, T_SOIL, false)
	grass.set_cells_terrain_connect(_cells(LAND), TERRAIN_SET, T_GRASS, false)

	for node in [water, ground, grass, root.get_node("Decorations"),
			root.get_node("Buildings"), root.get_node("Props")]:
		node.owner = root

	var folk_script: Script = load("res://Scripts/Townsfolk.gd")
	for entry in FOLK:
		var who := Node2D.new()
		who.name = "Townsfolk" + String(entry[0]).capitalize()
		who.set_script(folk_script)
		who.set("person", entry[0])
		who.position = _centre(entry[1])
		root.add_child(who)
		who.owner = root

	var arrive := Marker2D.new()
	arrive.name = "FromFarm"
	arrive.position = _centre(ARRIVE)
	root.add_child(arrive)
	arrive.owner = root

	_ferry(root, FERRY_CELL, FARM_SCENE, FARM_SPAWN)

	var player: Node = load("res://Scenes/Player.tscn").instantiate()
	player.name = "Player"
	player.position = _centre(ARRIVE)
	root.add_child(player)
	player.owner = root

	var hud: Node = load("res://Scenes/HUD.tscn").instantiate()
	hud.name = "HUD"
	root.add_child(hud)
	hud.owner = root

	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		push_error("could not pack the city")
		quit(1)
		return
	var err := ResourceSaver.save(packed, OUT)
	if err != OK:
		push_error("could not save %s: %s" % [OUT, error_string(err)])
		quit(1)
		return
	print("wrote ", OUT, " -- a frame, not a town. Paint it.")
	print("NOW RUN: python -I Tools/fix_city_uids.py   (a headless save drops every uid)")
	quit()


func _layer(root: Node2D, name_: String, tile_set: TileSet, sorted: bool) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = name_
	layer.tile_set = tile_set
	layer.y_sort_enabled = sorted
	root.add_child(layer)
	return layer


static func _cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out


## A boat at the shore with a door on it: walking into it sails. The Area2D is
## built here rather than instanced from `Door.tscn` so its collision shape can
## be sized without expanding the instance when the scene is packed.
func _ferry(root: Node2D, cell: Vector2i, target: String, spawn: StringName) -> void:
	var ferry := Node2D.new()
	ferry.name = "Ferry"
	ferry.position = _centre(cell)
	root.add_child(ferry)
	ferry.owner = root

	var boat := Sprite2D.new()
	boat.name = "Boat"
	boat.texture = UISkin.atlas(load("res://Assets/Objects/Boats.png"), Rect2(0, 0, 48, 32))
	boat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ferry.add_child(boat)
	boat.owner = root

	var door := Area2D.new()
	door.name = "Door"
	door.collision_layer = 0
	door.collision_mask = 1
	door.set_script(load("res://Scripts/Door.gd"))
	door.set("target_scene", target)
	door.set("spawn_point", spawn)
	ferry.add_child(door)
	door.owner = root

	var shape := CollisionShape2D.new()
	# Named, or Godot invents one ("@CollisionShape2D@14") when the scene is
	# packed, and the node reads as machine spill in the editor's tree.
	shape.name = "CollisionShape2D"
	var box := RectangleShape2D.new()
	# Wide enough to catch a player walking off the shore at any height.
	box.size = Vector2(14, 40)
	shape.shape = box
	door.add_child(shape)
	shape.owner = root


static func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * TILE + TILE * 0.5, cell.y * TILE + TILE * 0.5)
