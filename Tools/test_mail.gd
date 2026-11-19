extends SceneTree

## Checks the post: what arrives and when, that Mom's letters cost what §4 says
## and cost it the moment they land, that the week is settled before she is
## added to it, that nothing arrives twice, and that the box, the window and
## the save all agree.
##   godot --headless --path . --script Tools/test_mail.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	# Autoloads attach after the main loop starts; Debt and Mail bind a frame
	# later still.
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	var debt := root.get_node("Debt")
	var mail := root.get_node("Mail")
	state.autosave = false
	state.save_path = "user://test_mail.dat"
	state.delete_save()
	state.reset()

	# --- what Mom's letters cost --------------------------------------------
	check(mail.MOM_EVERY == 2 and mail.MOM_BASE == 80 and mail.MOM_STEP == 30,
			"Mom writes every 2 weeks for 80 + 30 * week")
	var steady := true
	var in_range := true
	for week in range(2, 60, 2):
		if mail.mom_amount(week) != mail.mom_amount(week):
			steady = false
		var base: float = float(mail.MOM_BASE + mail.MOM_STEP * week)
		var got: int = mail.mom_amount(week)
		# The spread is +/- 25%, so a figure outside that band means the mixer
		# is not doing what the doc says it does.
		if got < roundi(base * 0.74) or got > roundi(base * 1.26):
			in_range = false
	check(steady, "a week's letter always costs the same")
	check(in_range, "and always within 25%% of its base (wk 2: %d, wk 16: %d)"
			% [mail.mom_amount(2), mail.mom_amount(16)])

	# --- the opening letter --------------------------------------------------
	check(mail.letters.size() == 1, "one letter is waiting on day one")
	check(mail.letters[0]["from"] == mail.FROM_MOM and mail.letters[0]["debt"] == 0,
			"it is from Mom and costs nothing")
	check(mail.unread() == 1 and mail.has_unread(), "and it is unread")

	# --- Mom's first bill ----------------------------------------------------
	# Unpaid, so week 1 is missed: 1000 + 5 fee = 1005, +1% = 1015, then Mom.
	# Were the letter added first the answer would be 1128, not 1127 -- which
	# is exactly the ordering this checks. The week has to be settled before
	# she is added to it, the way econ_sim plays it.
	var mom_two: int = mail.mom_amount(2)
	while state.day < 8:
		state.sleep()
	check(mail.letters.size() == 2, "Mom writes on the Monday week 2 opens")
	var latest: Dictionary = mail.letters[-1]
	check(latest["id"] == "mom-w2" and latest["debt"] == mom_two,
			"her letter carries week 2's figure (%d)" % latest["debt"])
	check(debt.week == 2, "the week had already turned when it landed")
	check(debt.balance == 1015 + mom_two,
			"settled first, then Mom (got %d, wanted %d)" % [debt.balance, 1015 + mom_two])
	check(not latest["read"], "and nobody has read it yet")

	# She writes every second week, not every week.
	while state.day < 15:
		state.sleep()
	check(mail.letters.size() == 2, "nothing from her in week 3")
	while state.day < 22:
		state.sleep()
	check(mail.letters.size() == 3 and mail.letters[-1]["id"] == "mom-w4",
			"and again in week 4")

	# --- nothing arrives twice ----------------------------------------------
	var had: int = mail.letters.size()
	mail.deliver_due(state.day)
	mail.deliver_due(state.day)
	check(mail.letters.size() == had, "delivering the same day again brings nothing")

	# --- the neighbour's winter warning --------------------------------------
	# The last week of Fall in year 1 opens on day 78.
	check(Calendar.season(78) == "Fall" and Calendar.day_of_season(78) == 22,
			"day 78 opens the last week of Fall")
	while state.day < 78:
		if debt.is_collection_day(state.day):
			# Keep the farm: three missed Sundays would end the run long
			# before Fall.
			state.earn(debt.minimum())
			debt.pay(debt.minimum())
		state.sleep()
	var warning := {}
	for letter in mail.letters:
		if letter["from"] == mail.FROM_NEIGHBOUR:
			warning = letter
	check(not warning.is_empty() and warning["day"] == 78,
			"the neighbour warns about winter in late Fall")
	check(warning["debt"] == 0, "and asks for nothing")

	# --- reading -------------------------------------------------------------
	var unread_before: int = mail.unread()
	check(unread_before > 0, "there is post to read (%d)" % unread_before)
	mail.mark_read(mail.letters[0]["id"])
	check(mail.unread() == unread_before - 1, "reading one marks one read")
	var balance_then: int = debt.balance
	mail.mark_all_read()
	check(mail.unread() == 0, "and the rest can be read in one go")
	check(debt.balance == balance_then, "reading costs nothing -- the money went on delivery")

	# --- the save ------------------------------------------------------------
	var count: int = mail.letters.size()
	check(state.save_game(), "the game saves")
	mail.reset()
	# A reset is a new game, so the box is emptied and day one's post put back
	# in it -- whatever day the old game had reached.
	check(mail.letters.size() == 1 and mail.letters[0]["id"] == "opening",
			"a reset leaves only the opening letter")
	check(state.load_game(), "the game loads")
	check(mail.letters.size() == count, "and the post came back whole (%d)" % mail.letters.size())
	check(mail.unread() == 0, "read letters are still read")
	# The ids came back too, so nothing re-delivers on the next day change.
	mail.deliver_due(state.day)
	check(mail.letters.size() == count, "and nothing arrives again after a load")
	state.delete_save()

	# --- the box and the window ----------------------------------------------
	state.reset()
	check(mail.letters.size() == 1 and mail.letters[0]["id"] == "opening",
			"a new game puts the opening letter back in the box")
	var scene: Node = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var box = scene.get_node("Mailbox")
	var hud = scene.get_node("HUD")
	var player = scene.get_node("Player")
	check(box.interact_verb() == "mailbox", "the box can be used")
	check(box.is_processing(), "and waves while the opening letter is unread")

	player.global_position = box.global_position + Vector2(0, 16)
	await process_frame
	check(player.interaction_ahead() == "mailbox", "standing at it, it is what using would use")
	check(player._try_interact(Vector2.ZERO) and hud.is_mail_open(), "and using it opens the post")
	check(hud.is_inventory_open(), "which stands the player still, like any window")

	var panel = hud._mail
	check(panel._showing == mail.letters[0]["id"],
			"it opens on the oldest unread letter")
	check(mail.letters[0]["read"], "and reading it marks it read")
	await process_frame
	check(not box.is_processing(), "so the box stops waving")
	hud.close_mail()
	check(not hud.is_mail_open() and not hud.is_inventory_open(), "closing frees the player")

	print("mail: ", "all passed" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
