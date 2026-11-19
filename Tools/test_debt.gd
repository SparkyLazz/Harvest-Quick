extends SceneTree

## Checks the debt: the minimum, paying, the weekly settlement (fee, strike,
## interest), the three strikes that end the game, the collector turning up on
## Sundays only, the bill's buttons, and the whole lot surviving a save.
##   godot --headless --path . --script Tools/test_debt.gd
##
## The numbers are checked against `Docs/GAME_DESIGN.md` §4 by hand, not
## against the code's own constants, so a constant changed by accident fails
## here instead of quietly redefining what the game is.

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	# Autoloads are attached to the root after the main loop starts, and Debt
	# binds itself a frame later still.
	await process_frame
	await process_frame
	var state := root.get_node("PlayerState")
	var debt := root.get_node("Debt")
	var ending := root.get_node("EndingScreen")
	# No post while this runs: Mom writes on even weeks and her letters go
	# straight onto the balance, which would make every figure below a figure
	# about the post as well as about the debt. `test_mail` checks the two
	# together, and checks that the week is settled before she is added.
	root.get_node("Mail").delivering = false
	state.autosave = false
	state.save_path = "user://test_debt.dat"
	state.delete_save()
	state.reset()

	# --- the minimum ---------------------------------------------------------
	check(debt.START_DEBT == 1000, "the debt starts at 1000")
	check(debt.minimum_for(1, 1000) == 48, "week 1 wants 48 (40 + 8)")
	check(debt.minimum_for(16, 1000) == 168, "week 16 wants 168 (40 + 8*16)")
	# 4% takes over once the debt has grown past the step: at week 1, 4% of
	# 5000 is 200, which beats 48.
	check(debt.minimum_for(1, 5000) == 200, "4% of the debt wins when it is bigger")
	check(debt.minimum_for(40, 30) == 30, "the last payment is never more than is owed")
	check(debt.minimum_for(5, 0) == 0, "a cleared debt wants nothing")

	# --- the collector's day -------------------------------------------------
	check(Calendar.weekday(7) == "Sun", "day 7 is a Sunday")
	check(debt.is_collection_day(7) and debt.is_collection_day(14),
			"he comes on Sundays")
	check(not debt.is_collection_day(1) and not debt.is_collection_day(8),
			"and on no other day")

	# --- paying --------------------------------------------------------------
	check(state.coins == state.START_COINS, "the purse opens at 200")
	check(debt.pay(48) == 48, "paying 48 takes 48")
	check(debt.balance == 952 and state.coins == 152,
			"off the debt and out of the purse (%d, %d)" % [debt.balance, state.coins])
	check(debt.still_due() == 0 and debt.is_settled_for_week(),
			"the week's minimum is covered")
	check(debt.pay(9999) == 152, "paying more than the purse holds pays what it holds")
	check(state.coins == 0 and debt.balance == 800, "which is all of it")
	check(debt.pay(10) == 0, "an empty purse pays nothing")

	# --- a week met ----------------------------------------------------------
	state.reset()
	var settlements: Array[Dictionary] = []
	debt.settled.connect(func(week: int, due: int, paid: int, met: bool, fee: int, strikes: int) -> void:
		settlements.append({"week": week, "due": due, "paid": paid, "met": met,
				"fee": fee, "strikes": strikes}))
	debt.pay(48)
	_sleep_to(state, 8)
	check(settlements.size() == 1 and settlements[0]["met"],
			"the week settles once, and it was met")
	check(debt.strikes == 0, "no strike for a week paid")
	# 1000 - 48 = 952, +1% interest = 961.52, rounded to whole coins = 962. The
	# game owes whole numbers; econ_sim carries the fraction, so the two drift
	# by a coin or two over a run. That is the game being roundable, not the
	# rules differing.
	check(debt.balance == 962, "interest runs on what is left (got %d)" % debt.balance)
	check(debt.week == 2 and debt.paid_this_week == 0, "the new week opens at zero")

	# --- a week missed -------------------------------------------------------
	state.reset()
	settlements.clear()
	_sleep_to(state, 8)
	check(settlements.size() == 1 and not settlements[0]["met"], "an unpaid week is missed")
	check(debt.strikes == 1, "and costs a strike")
	# Fee is 10% of the whole minimum (48 -> 5), not of the shortfall, then
	# interest on 1005.
	check(settlements[0]["fee"] == 5, "the late fee is 10%% of the minimum (got %d)"
			% settlements[0]["fee"])
	check(debt.balance == 1015, "fee then interest (got %d)" % debt.balance)

	# --- a week half paid ----------------------------------------------------
	# Paying something is not nothing -- it comes off the debt -- but it does
	# not buy off the strike. That is how econ_sim plays it.
	state.reset()
	settlements.clear()
	debt.pay(20)
	var before: int = debt.balance
	_sleep_to(state, 8)
	check(before == 980, "the part payment came off the debt")
	check(not settlements[0]["met"] and debt.strikes == 1,
			"but a part payment is still a missed week")

	# --- three strikes -------------------------------------------------------
	state.reset()
	var lost := [false]
	debt.lost.connect(func() -> void: lost[0] = true)
	_sleep_to(state, 8)
	_sleep_to(state, 15)
	check(debt.strikes == 2 and not lost[0], "two missed weeks, farm still yours")
	_sleep_to(state, 22)
	check(debt.strikes == 3 and lost[0], "the third strike loses the farm")
	check(debt.lost_farm, "and it stays lost")
	check(ending.is_open(), "the ending screen is up")
	# It pauses the tree; the rest of the suite needs it running again.
	paused = false
	ending.visible = false
	check(debt.pay(100) == 0, "a lost game takes no more payments")
	var strikes_then: int = debt.strikes
	_sleep_to(state, 29)
	check(debt.strikes == strikes_then, "and settles no more weeks")

	# --- the save ------------------------------------------------------------
	state.reset()
	debt.pay(30)
	debt.strikes = 2
	var saved_balance: int = debt.balance
	check(state.save_game(), "the game saves")
	debt.reset()
	check(debt.balance == debt.START_DEBT and debt.strikes == 0, "the debt is wiped")
	check(state.load_game(), "the game loads")
	check(debt.balance == saved_balance and debt.strikes == 2 and debt.paid_this_week == 30,
			"and the debt came back whole (%d, %d, %d)"
			% [debt.balance, debt.strikes, debt.paid_this_week])
	state.delete_save()

	# --- the collector and his bill ------------------------------------------
	state.reset()
	var scene: Node = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var collector = scene.get_node("Collector")
	var hud = scene.get_node("HUD")
	var player = scene.get_node("Player")
	check(not collector.visible, "he is not there on a Monday")
	_jump_to_sunday(state, debt)
	await process_frame
	check(collector.visible and collector.interact_verb() == "collector",
			"he is there on Sunday")

	player.global_position = collector.global_position + Vector2(0, -16)
	await process_frame
	check(player.interaction_ahead() == "collector",
			"standing beside him, he is what using would use")
	# He says his piece first (step 5); the bill is what the conversation ends
	# in. `test_town` checks the talking, this only needs to get past it.
	check(player._try_interact(Vector2.ZERO), "and using him starts him talking")
	var talk := root.get_node("Dialogue")
	while talk.advance():
		pass
	await process_frame
	check(hud.is_debt_open(), "which ends in the bill")
	check(hud.is_inventory_open(), "the bill stands the player still, like any window")

	var panel = hud._debt
	check(panel._owed.text == str(debt.balance), "the bill says what is owed")
	check(panel._due.text == str(debt.still_due()), "and what this week wants")
	check(not panel._pay_min.disabled, "PAY MINIMUM is live with 200 in the purse")
	check(panel._pay_all.disabled, "PAY ALL is not: 200 does not cover 1000")
	panel._pay_min.pressed.emit()
	check(debt.still_due() == 0 and panel._pay_min.disabled,
			"paying the minimum settles the week and greys the button")
	hud.close_debt()
	await process_frame
	check(not hud.is_debt_open() and not hud.is_inventory_open(),
			"Esc-ing the bill frees the player")

	# Cleared debts need no collector.
	state.earn(debt.balance)
	check(debt.pay_off() > 0 and debt.balance == 0, "the whole debt can be paid off")
	await process_frame
	check(not collector.visible, "he stops coming once the debt is paid off")
	check(panel._pay_min.disabled and panel._pay_all.disabled,
			"and the bill has nothing left to ask for")

	print("debt: ", "all passed" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)


## Sleeps night by night until `day`, so every week turn in between is settled
## exactly as it would be in play.
func _sleep_to(state: Node, day: int) -> void:
	while state.day < day:
		state.sleep()


func _jump_to_sunday(state: Node, debt: Node) -> void:
	while not debt.is_collection_day(state.day):
		state.sleep()
