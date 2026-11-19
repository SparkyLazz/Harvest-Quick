extends SceneTree

## Checks the way out: the four pieces of evidence and the order they come in,
## that the case cannot be whole before week 12 however it is played, the fee,
## the debt going void, Mom falling silent, the good ending, and the whole lot
## surviving a save.
##   godot --headless --path . --script Tools/test_lawyer.gd
##
## The numbers are checked against `Docs/GAME_DESIGN.md` §4 by hand, not
## against the code's own constants, so a constant changed by accident fails
## here instead of quietly redefining the game.

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
	var mail := root.get_node("Mail")
	var law := root.get_node("Lawyer")
	var ending := root.get_node("EndingScreen")
	state.autosave = false
	state.save_path = "user://test_lawyer.dat"
	state.delete_save()
	state.reset()

	# --- the price ------------------------------------------------------------
	check(law.FEE == 10000, "the lawyer costs ten thousand")
	check(law.EVIDENCE_WEEK == 12, "and the case cannot be whole before week 12")
	check(law.PIECES.size() == 4, "there are four pieces of it")
	check(not law.is_hired and law.gathered_count() == 0, "and none of them on day one")

	# --- the order they come in ----------------------------------------------
	check(not law.can_take("word") and not law.can_take("ledger")
			and not law.can_take("paper"),
			"nobody will give you anything before her letters")
	check(law.piece_from("neighbour").is_empty()
			and law.piece_from("seller").is_empty()
			and law.piece_from("collector").is_empty(),
			"so none of them has anything to hand over yet")

	# Her letters come on their own, three of them, every second week: week 6.
	_play_to(state, debt, 36)
	check(law.has("letters"), "three of her letters make the first piece")
	check(law.gathered_count() == 1, "which nobody had to be asked for")

	check(law.piece_from("neighbour") == "word", "then the neighbour has his word to give")
	check(law.piece_from("seller").is_empty(), "and the seller waits his turn")
	check(law.take("word"), "the neighbour gives it")
	check(law.piece_from("seller") == "ledger", "and now the seller has his ledger")
	check(law.take("ledger"), "which he gives")

	# --- week 12 is a wall, not a warning ------------------------------------
	check(Calendar.week(state.day) < law.EVIDENCE_WEEK,
			"it is still only week %d" % Calendar.week(state.day))
	check(law.piece_from("collector").is_empty(),
			"so the collector keeps his copy, however fast you played")
	check(not law.can_take("paper") and not law.is_complete(),
			"and the case cannot be finished early by any route")

	_play_to_week(state, debt, law.EVIDENCE_WEEK)
	check(law.piece_from("collector") == "paper",
			"in week %d he parts with it" % Calendar.week(state.day))
	check(law.take("paper") and law.is_complete(), "and the case is whole")
	check(law.missing_names().is_empty(), "with nothing still wanting")

	# --- the fee -------------------------------------------------------------
	check(not law.can_hire(), "a whole case is not enough: there is still the fee")
	check(not law.hire(), "and he will not start without it")
	state.earn(law.FEE)
	check(law.can_hire(), "with ten thousand in hand he will")
	var owed: int = debt.balance
	check(owed > 0, "there is a debt to undo (%d)" % owed)
	var coins_before: int = state.coins
	check(law.hire(), "he is hired")
	check(state.coins == coins_before - law.FEE, "the fee is gone from the purse")
	check(debt.balance == 0, "and the debt with it")
	check(debt.strikes >= 0, "the strikes stay on the record; they count towards nothing")

	# --- what winning means --------------------------------------------------
	check(law.is_hired, "he stays hired")
	check(ending.is_open(), "the ending is up")
	paused = false
	ending.visible = false
	var letters_then: int = mail.letters.size()
	_play_to(state, debt, state.day + 30)
	check(mail.letters.size() == letters_then,
			"and Mom writes no more (%d letters, still)" % mail.letters.size())
	check(debt.balance == 0 and debt.strikes < debt.STRIKES_TO_LOSE,
			"nothing can take the farm now")
	check(not law.can_hire() and not law.hire(), "and he cannot be hired twice")

	# --- the save ------------------------------------------------------------
	check(state.save_game(), "the game saves")
	law.reset()
	check(not law.is_hired and law.gathered_count() == 0, "the case can be wiped")
	check(state.load_game(), "the game loads")
	check(law.is_hired and law.gathered_count() == 4,
			"and came back whole (%d pieces, hired %s)"
			% [law.gathered_count(), law.is_hired])
	state.delete_save()

	# --- the people say the right thing --------------------------------------
	state.reset()
	var scene: Node = load("res://Scenes/City.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var lawyer_npc := _person(scene, "lawyer")
	var neighbour := _person(scene, "neighbour")
	var hud = scene.get_node("HUD")

	var cold := " ".join(lawyer_npc._lines_for())
	check(cold.contains("TEN THOUSAND") and cold.contains("HER OWN LETTERS"),
			"with nothing gathered he names the price and what to bring")
	law._have = {"letters": true, "word": true}
	var partway := " ".join(lawyer_npc._lines_for())
	check(partway.contains("2 OF THE FOUR"), "partway through he counts what he has")
	check(partway.contains("THE SELLER'S LEDGER"), "and names what is still wanting")
	law._have = {"letters": true, "word": true, "ledger": true, "paper": true}
	var whole := " ".join(lawyer_npc._lines_for())
	check(whole.contains("THE CASE IS WHOLE") and whole.contains("SHORT"),
			"with the case whole and the purse light, he says how light")
	state.earn(law.FEE)
	check(" ".join(lawyer_npc._lines_for()).contains("AND I BEGIN"),
			"and with the fee in hand, that he will begin")

	# Every line of his, in every state, still has to fit the bubble.
	var too_long: Array[String] = []
	for line in lawyer_npc._lines_for():
		if not hud._dialogue.fits(line):
			too_long.append(line)
	for line in lawyer_npc._hired_lines():
		if not hud._dialogue.fits(line):
			too_long.append(line)
	for id in ["word", "ledger"]:
		for line in neighbour._handing_over_lines(id):
			if not hud._dialogue.fits(line):
				too_long.append(line)
	check(too_long.is_empty(), "and every line of the case fits the bubble%s"
			% ("" if too_long.is_empty() else " (worst: %s)" % too_long[0]))

	print("lawyer: ", "all passed" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## Sleeps to `day`, paying the collector on the way so the farm survives it.
func _play_to(state: Node, debt: Node, day: int) -> void:
	while state.day < day:
		if debt.is_collection_day(state.day):
			state.earn(debt.minimum())
			debt.pay(debt.minimum())
		state.sleep()


func _play_to_week(state: Node, debt: Node, week: int) -> void:
	while Calendar.week(state.day) < week:
		if debt.is_collection_day(state.day):
			state.earn(debt.minimum())
			debt.pay(debt.minimum())
		state.sleep()


## The person with this verb in `scene`. Loaded by path, never by class name:
## a --script test compiles before the autoloads exist (TECH_NOTES §9).
func _person(scene: Node, who: String) -> Node:
	for node in scene.get_tree().get_nodes_in_group(&"interactable"):
		if node.is_inside_tree() and scene.is_ancestor_of(node) \
				and str(node.interact_verb()) == who:
			return node
	var made: Node = load("res://Scripts/Townsfolk.gd").new()
	made.person = who
	scene.add_child(made)
	return made
