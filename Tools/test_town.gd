extends SceneTree

## Checks step 5: the dialogue system on its own, what the townsfolk say in
## which state, the town map itself, the ferry both ways, and the collector
## talking before he hands over the bill.
##   godot --headless --path . --script Tools/test_town.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	var debt := root.get_node("Debt")
	var weather := root.get_node("Weather")
	var talk := root.get_node("Dialogue")
	state.autosave = false
	state.reset()

	# --- the dialogue system, with nobody in it ------------------------------
	check(not talk.is_talking(), "nothing is being said to start with")
	talk.say("SOMEONE", ["ONE.", "TWO.", "THREE."])
	check(talk.is_talking() and talk.speaker == "SOMEONE", "a conversation starts")
	check(talk.current_line() == "ONE.", "on its first line")
	check(talk.advance() and talk.current_line() == "TWO.", "and moves on")
	check(talk.advance() and talk.current_line() == "THREE.", "line by line")
	check(not talk.advance(), "the last line ends it")
	check(not talk.is_talking() and talk.speaker.is_empty(), "and nobody is speaking after")

	talk.say("SOMEONE", ["", "   ", "REAL."])
	check(talk.lines.size() == 1 and talk.current_line() == "REAL.",
			"blank lines are dropped, not shown")
	talk.say("NOBODY", [])
	check(not talk.is_talking(), "saying nothing says nothing")
	talk.say("A", ["X."])
	talk.say("B", ["Y."])
	check(talk.speaker == "B" and talk.current_line() == "Y.",
			"a new conversation replaces the one up")
	talk.stop()
	check(not talk.is_talking(), "and stop ends it")

	# --- what the townsfolk say ----------------------------------------------
	# The town's layout is drawn by hand in the editor (TECH_NOTES 5b), so
	# there may not be a scene at all while one is being started. Everything
	# that does not need the town -- which is most of this suite -- then runs
	# on the farm instead, with the people stood in it by hand, and the few
	# checks that do need it say they were skipped rather than going red over
	# a file that is meant to be missing.
	var town_path := "res://Scenes/City.tscn"
	var has_town := ResourceLoader.exists(town_path)
	var scene: Node = (load(town_path) if has_town
			else load("res://Scenes/Dev.tscn")).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var seller = _person(scene, "seller")
	var lawyer = _person(scene, "lawyer")
	var neighbour = _person(scene, "neighbour")
	var player = scene.get_node("Player")
	var hud = scene.get_node("HUD")
	if not has_town:
		print("  SKIP  %s does not exist yet -- running on the farm instead" % town_path)

	check(seller.display_name() == "THE SEED SELLER"
			and lawyer.display_name() == "THE LAWYER"
			and neighbour.display_name() == "THE NEIGHBOUR", "everyone has a name")
	check(seller.tint() != neighbour.tint() and neighbour.tint() != lawyer.tint(),
			"and a colour of their own, since they share one sprite")

	# The neighbour reads the state of the game. Worst news first.
	weather.forced = weather.CLEAR
	debt.strikes = 0
	var easy: Array = neighbour._lines_for()
	debt.strikes = 1
	var warned: Array = neighbour._lines_for()
	debt.strikes = 2
	var dire: Array = neighbour._lines_for()
	debt.strikes = 0
	check(easy != warned and warned != dire, "the neighbour says three different things by strikes")
	check(" ".join(dire).contains("ASKING WHAT THE FARM IS WORTH"),
			"and the worst of them when two are against you")
	weather.forced = weather.RAIN
	check(neighbour._lines_for() != easy, "rain gets its own line")
	weather.forced = weather.CLEAR

	# The seller knows the season; winter has nothing for you.
	var spring: Array = seller._lines_for()
	state.day = 85            # Winter 1
	var winter: Array = seller._lines_for()
	check(str(spring[0]).contains("SPRING") and str(winter[0]).contains("NOTHING GROWS"),
			"the seller sells the season, and nothing in Winter")
	state.day = 1

	# The lawyer's price is the one in the design doc, and he says when.
	var pitch: Array = lawyer._lines_for()
	var whole := " ".join(pitch)
	check(whole.contains("TEN THOUSAND"), "the lawyer wants ten thousand")
	check(whole.contains("PROOF"), "and proof she signed as you")
	# With nothing gathered he sends you away to wait for her letters. The rest
	# of what he says -- the count, what is still wanting, the fee -- belongs
	# to the case, and `test_lawyer` checks it.
	check(whole.contains("HER OWN LETTERS"), "and on day one, that they come first")

	# --- every written line fits the bubble ----------------------------------
	# The plate is the pack's and is never stretched, so one line of speech is
	# as wide as it is drawn. A line too long to read is a failing test here
	# rather than a sentence cut off in play.
	var too_long: Array[String] = []
	var counted := 0
	for speaker in [seller, lawyer, neighbour]:
		for strikes in [0, 1, 2]:
			debt.strikes = strikes
			for season_day in [1, 29, 57, 71, 85]:
				state.day = season_day
				for line in speaker._lines_for():
					counted += 1
					# Through the box, never by its class name: a --script test
					# compiles before the autoloads exist, and naming
					# DialogueBox here breaks it over the `Dialogue` inside
					# (TECH_NOTES §9).
					if not hud._dialogue.fits(line):
						too_long.append(line)
	debt.strikes = 0
	state.day = 1
	check(too_long.is_empty(), "all %d of the townsfolk's lines fit the bubble%s"
			% [counted, "" if too_long.is_empty() else " (worst: %s)" % too_long[0]])

	# --- talking to one ------------------------------------------------------
	player.global_position = neighbour.global_position + Vector2(-16, 0)
	await process_frame
	check(player.interaction_ahead() == "neighbour", "standing by him, he is what using would use")
	check(player._try_interact(Vector2.ZERO), "and using him works")
	check(talk.is_talking() and talk.speaker == "THE NEIGHBOUR", "he starts talking")
	check(talk.portrait != null and talk.portrait_tint == neighbour.tint(),
			"with his own face in the frame")
	check(hud.is_dialogue_open(), "the box is up")
	check(hud.is_inventory_open(), "which stands the player still and stops the clock")
	talk.stop()
	await process_frame
	check(not hud.is_dialogue_open() and not hud.is_inventory_open(), "and ending it frees them")

	# The seller opens his stall once he has finished speaking, not over it.
	player.global_position = seller.global_position + Vector2(-16, 0)
	await process_frame
	check(player._try_interact(Vector2.ZERO) and talk.is_talking(), "the seller talks first")
	check(not hud.is_storage_open(), "the stall is not up while he is speaking")
	while talk.advance():
		pass
	await process_frame
	check(hud.is_storage_open(), "and opens once he is done")
	hud.close_storage()

	# --- what the town scene has to have -------------------------------------
	if has_town:
		# The *layout* is the developer's, so nothing here measures it: no
		# size, no house count, no cell is named. What is checked is the
		# contract the code needs from whatever map is drawn, which is the
		# part a repaint can break without anyone noticing.
		var grass := scene.get_node_or_null("Grass Layer") as TileMapLayer
		check(grass != null, "there is a 'Grass Layer' for the grid to come off")
		check(grass != null and not grass.get_used_cells().is_empty(),
				"and something painted on it to stand on")
		check(scene.get_node_or_null("FromFarm") is Marker2D,
				"there is a 'FromFarm' marker to land on")
		check(scene.get_node_or_null("Ferry/Door") != null, "and a ferry to leave by")
		# Found by the group, not by walking the children: it should not
		# matter whether the people are tucked under a node of their own.
		for who in ["seller", "lawyer", "neighbour"]:
			var found := false
			for node in root.get_tree().get_nodes_in_group(&"interactable"):
				if node.is_inside_tree() and scene.is_ancestor_of(node) 						and str(node.interact_verb()) == who:
					found = true
			check(found, "the %s is standing in it" % who)

		# Hoeing the square is not a thing you can do: no Farm, no tilling.
		check(scene.get_node_or_null("Farm") == null, "the town has no farm")
		var before := grass.get_used_cells().size()
		player.global_position = grass.to_global(
				grass.map_to_local(grass.get_used_rect().position + Vector2i(1, 1)))
		player._facing = "down"
		player._land_hoe_hit()
		check(grass.get_used_cells().size() == before,
				"so the hoe does not dig the town up")

		var city_door := scene.get_node("Ferry/Door")
		check(city_door.target_scene == "res://Scenes/Dev.tscn"
				and city_door.spawn_point == &"FromTown",
				"the town's ferry goes to the farm")
	else:
		print("  SKIP  the town scene's own checks: there is no town scene yet")

	# --- the farm's side of the ferry ----------------------------------------
	root.remove_child(scene)
	scene.free()

	var farm: Node = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(farm)
	await process_frame
	var farm_door := farm.get_node("Ferry/Door")
	check(farm_door.target_scene == town_path
			and farm_door.spawn_point == &"FromFarm",
			"the farm's ferry points at the town, scene or no scene")
	check(farm.get_node_or_null("FromTown") != null, "with somewhere to land on the way back")

	# --- the collector talks before he bills ---------------------------------
	state.reset()
	var collector = farm.get_node("Collector")
	var farm_hud = farm.get_node("HUD")
	while not debt.is_collection_day(state.day):
		state.sleep()
	await process_frame
	check(collector.visible, "he is there on Sunday")
	check(collector.interact(null) and talk.speaker == "THE DEBT COLLECTOR",
			"and he says his piece first")
	check(not farm_hud.is_debt_open(), "the bill is not up while he is talking")
	while talk.advance():
		pass
	await process_frame
	check(farm_hud.is_debt_open(), "and comes up when he has finished")
	farm_hud.close_debt()

	# What he says follows the strikes, like the neighbour's.
	var opening: Array = collector._lines()
	debt.strikes = 2
	var last_warning: Array = collector._lines()
	debt.strikes = 0
	debt.pay(debt.minimum())
	var paid: Array = collector._lines()
	check(opening != last_warning and last_warning != paid,
			"he has a different line for a first week, a last warning and a paid one")
	check(str(paid[0]).contains("PAID"), "and he notices when you have already paid")
	var long_lines: Array[String] = []
	for set_ in [opening, last_warning, paid]:
		for line in set_:
			if not farm_hud._dialogue.fits(str(line)):
				long_lines.append(str(line))
	check(long_lines.is_empty(), "and every line of his fits the bubble too")

	print("town: ", "all passed" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## The person with this verb in `scene`, or one stood in it for the occasion.
## The town may not exist yet -- its map is drawn by hand -- and what everyone
## says is worth checking either way.
func _person(scene: Node, who: String) -> Node:
	for node in scene.get_tree().get_nodes_in_group(&"interactable"):
		if node.is_inside_tree() and scene.is_ancestor_of(node) \
				and str(node.interact_verb()) == who:
			return node
	# Loaded by path, not by class name: a --script test compiles before the
	# autoloads exist, and `Townsfolk` reaches several of them (TECH_NOTES 9).
	var made: Node = load("res://Scripts/Townsfolk.gd").new()
	made.name = "Townsfolk" + who.capitalize()
	made.person = who
	# Stood four tiles apart along an empty row, and well clear of the farm's
	# own mailbox and collector: reach is a cell either way, so people any
	# closer together would answer for each other.
	made.position = Vector2(40 + 64 * ["seller", "lawyer", "neighbour"].find(who), 40)
	scene.add_child(made)
	return made
