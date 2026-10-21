extends SceneTree

## The props are tiles: paintable, tagged with what they do, and the ones that
## open carry their own frame layout.
##   godot --headless --path . --script Tools/test_props.gd

const CHEST_SOURCE := 23

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func done() -> void:
	print("")
	print("FAILURES: ", _fails)
	quit(1 if _fails > 0 else 0)

func _initialize() -> void:
	await process_frame
	var ts: TileSet = load("res://Tilemaps/Terrains.tres")

	# --- the data layers the props describe themselves with ------------------
	var names := []
	for i in ts.get_custom_data_layers_count():
		names.append(ts.get_custom_data_layer_name(i))
	check(names == ["interact", "frames", "step", "frame", "breakable", "drop"], "data layers are %s" % [names])

	# --- the chest is a tileset source, not a node ---------------------------
	var chest := ts.get_source(CHEST_SOURCE) as TileSetAtlasSource
	check(chest != null, "the chest is source %d" % CHEST_SOURCE)
	if chest == null:
		done(); return
	check(chest.get_tiles_count() == 10, "10 frames: five, in two styles")

	var tall := 0
	var solid := 0
	var tagged: Array[Vector2i] = []
	for i in chest.get_tiles_count():
		var c := chest.get_tile_id(i)
		if chest.get_tile_size_in_atlas(c) == Vector2i(1, 2):
			tall += 1
		var d := chest.get_tile_data(c, 0)
		if d.get_collision_polygons_count(0) > 0:
			solid += 1
		if str(d.get_custom_data("interact")) != "":
			tagged.append(c)
	check(tall == 10, "every frame is one cell wide and two tall")
	check(solid == 10, "every frame has a hitbox")
	check(tagged.size() == 10, "every frame is tagged, so an open chest can be shut")

	var first := chest.get_tile_data(Vector2i(1, 0), 0)
	check(str(first.get_custom_data("interact")) == "chest", "it says 'chest'")
	check(int(first.get_custom_data("frames")) == 5, "with 5 frames")
	check(int(first.get_custom_data("step")) == 3, "spaced 3 columns apart")
	check(first.y_sort_origin == 8, "sorting on the floor under it")
	# Where a tall tile actually draws cannot be worked out from the zoom and
	# the region alone -- two different formulas were tried here and both were
	# wrong, which is what left the chest sitting a cell low. The value below
	# was established by rendering the chest beside a 1x1 dresser and measuring
	# the difference between frames (Tools/sweep.py), not by reasoning. Rerun
	# that if the art or the tile size ever changes.
	check(first.texture_origin == Vector2i(0, 8),
			"the measured draw offset is +8 (got %s)" % first.texture_origin)

	# --- the other two props still answer ------------------------------------
	var furn := ts.get_source(22) as TileSetAtlasSource
	check(str(furn.get_tile_data(Vector2i(3, 2), 0).get_custom_data("interact")) == "wardrobe",
			"the dresser still says 'wardrobe'")
	check(str(furn.get_tile_data(Vector2i(0, 1), 0).get_custom_data("interact")) == "bed",
			"the bed still says 'bed'")
	check(furn.get_tile_data(Vector2i(3, 2), 0).get_collision_polygons_count(0) > 0,
			"and both have hitboxes")

	# --- painting one and opening it -----------------------------------------
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	root.add_child(layer)
	var anim := PropAnimator.new()
	anim.frame_time = 0.01
	root.add_child(anim)

	var spot := Vector2i(4, 4)
	layer.set_cell(spot, CHEST_SOURCE, Vector2i(1, 0), 0)
	var said := PropAnimator.describe(layer, spot)
	check(said.get("verb") == "chest" and said.get("frames") == 5,
			"a painted chest describes itself")
	check(PropAnimator.frame_at(Vector2i(1, 0), 3, 4) == Vector2i(13, 0),
			"the last frame works out to column 13")
	check(anim.can_animate(layer, spot), "it can move")
	check(not anim.is_open(layer, spot), "and starts shut")
	check(not anim.can_animate(layer, Vector2i(9, 9)), "bare ground cannot")

	anim.play(layer, spot, true)
	var opened: Array = await anim.finished
	check(layer.get_cell_atlas_coords(spot) == Vector2i(13, 0),
			"opening ends on the last frame (%s)" % layer.get_cell_atlas_coords(spot))
	check(anim.is_open(layer, spot), "and the tile itself now reads as open")
	var mid := PropAnimator.describe(layer, spot)
	check(mid.get("base") == Vector2i(1, 0),
			"an open chest still points back at its first frame")
	check(opened[1] == true, "the signal says so too")

	anim.play(layer, spot, false)
	await anim.finished
	check(layer.get_cell_atlas_coords(spot) == Vector2i(1, 0), "shutting returns to frame 0")
	check(not anim.is_open(layer, spot), "and it is shut again")

	# Opening twice must not run the frames backwards from the end.
	anim.play(layer, spot, true)
	await anim.finished
	anim.play(layer, spot, true)
	await process_frame
	check(layer.get_cell_atlas_coords(spot) == Vector2i(13, 0),
			"opening an open chest leaves it alone")
	anim.close_all(layer)
	check(layer.get_cell_atlas_coords(spot) == Vector2i(1, 0), "close_all puts it back")

	# Toggling is what the use key calls.
	check(anim.toggle(layer, spot), "toggle opens it")
	await anim.finished
	check(anim.is_open(layer, spot), "it is open")
	check(anim.toggle(layer, spot), "toggle again shuts it")
	await anim.finished
	check(not anim.is_open(layer, spot), "it is shut")

	# --- the real scene: walk up to one and press use ------------------------
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 8:
		await process_frame
	var scene := current_scene
	var props := scene.get_node("Props") as TileMapLayer
	var player: Node2D = scene.find_child("Player", true, false)
	check(player != null, "the house is up with a player in it")

	var here := Vector2i(14, 4)
	props.set_cell(here, CHEST_SOURCE, Vector2i(1, 0), 0)
	check(str(props.get_cell_tile_data(here).get_custom_data("interact")) == "chest",
			"a chest painted at %s reads as a chest" % here)

	# Stand on the cell below and look up at it, as a player would.
	player.global_position = props.to_global(props.map_to_local(here + Vector2i.DOWN))
	player._facing = "up"
	check(player.facing_cell() == here, "standing below, the player faces it")
	check(player.interaction_ahead() == "chest", "and it offers 'chest'")

	# A prop's hitbox is the floor IN FRONT of it -- the cell below, since
	# everything faces the camera. Standing there is enough; the chest does not
	# have to be stepped into and the facing does not have to be lined up.
	var front := PropAnimator.front_of(here)
	check(front == here + Vector2i(0, 1), "the front of a prop is the cell below it")

	player.global_position = props.to_global(props.map_to_local(front))
	for facing in ["up", "down", "left", "right"]:
		player._facing = facing
		check(player.interaction_ahead() == "chest",
				"standing in front facing %s still reaches it" % facing)
	check(player.prop_in_reach() == here, "and it resolves to the chest's cell")

	# Behind it is plain floor and must stay silent: the chest's art reaches 0px
	# above its own cell when shut, so claiming that cell would put the hitbox
	# behind the chest -- which is the thing being fixed.
	var behind := here - Vector2i(0, 1)
	check(props.get_cell_tile_data(behind) == null, "the cell behind holds no tile")
	player.global_position = props.to_global(props.map_to_local(behind))
	player._facing = "up"
	check(player.interaction_ahead() == "",
			"standing behind it reaches nothing")

	# Two cells away is out of reach.
	player.global_position = props.to_global(props.map_to_local(here + Vector2i(0, 2)))
	player._facing = "down"
	check(player.interaction_ahead() == "", "two cells in front is too far")

	# Put the player back below for the rest of the checks.
	player.global_position = props.to_global(props.map_to_local(here + Vector2i.DOWN))
	player._facing = "up"

	check(player._try_interact(Vector2.ZERO), "use is taken by the chest")
	# Wait for the run to finish, not just for the last frame to appear: the
	# cell reaches it one callback before the animator is free again.
	await player._prop_anim.finished
	check(props.get_cell_atlas_coords(here) == Vector2i(13, 0),
			"the lid runs to its last frame (%s)" % props.get_cell_atlas_coords(here))
	check(not player._prop_anim.is_moving(here), "and the animator is free again")
	# Opening the chest puts the storage window up, and no prompt shows through
	# a window.
	check(player._hud == null or not player._hud.is_storage_open()
			or player.interaction_ahead() == "",
			"no prompt reads through the open window")

	# The lid belongs to the window: closing one closes the other, whichever
	# way the window was dismissed. Escape is the case that matters, since it
	# never touches the chest.
	if player._hud != null:
		player._hud.close_storage()
		if player._prop_anim.is_moving(here):
			await player._prop_anim.finished
		check(props.get_cell_atlas_coords(here) == Vector2i(1, 0),
				"closing the window shuts the lid (%s)" % props.get_cell_atlas_coords(here))
	check(player.interaction_ahead() == "chest", "and the chest still offers itself")

	# Pressing again mid-travel must not be eaten.
	player._try_interact(Vector2.ZERO)
	check(player._prop_anim.is_moving(here), "it is moving")
	check(not player._try_interact(Vector2.ZERO),
			"a press while the lid travels is refused, not swallowed")
	await player._prop_anim.finished
	check(props.get_cell_atlas_coords(here) == Vector2i(13, 0),
			"and the lid finishes its run (%s)" % props.get_cell_atlas_coords(here))

	done()
