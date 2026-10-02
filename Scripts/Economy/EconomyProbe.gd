extends Node

## The tuning bench for the economy. Not part of the game.
##
## An economy is a pile of numbers that only mean something together, and the
## only honest way to know whether [member Debt.lawyer_fee] is out of reach is
## to play eighty days against it. This does that in about a second, which is
## the difference between tuning the squeeze and guessing at it.
##
## It is deliberately not an autoload, because it ends with
## [method SceneTree.quit] and would otherwise shut the game on launch. To run
## it, add this line under [code]Inventory[/code] in project.godot, run the
## project headless, and take the line back out:
## [codeblock]
## EconomyProbe="*res://Scripts/Economy/EconomyProbe.gd"
## [/codeblock]
## A plain [code]-s[/code] script will not do: the autoloads it leans on are
## not registered that way, so [code]Wallet[/code] and the rest come back nil.

func _ready() -> void:
	await get_tree().process_frame
	# A day's takings, tried at three levels: a farm that cannot keep up, one
	# that just about can, and one doing well enough to buy its way out.
	_run("struggling farm", 120, false)
	_run("steady farm", 260, false)
	_run("good farm, hoards for the lawyer", 260, true)
	_glut()
	get_tree().quit()

func _run(label: String, wage: int, buy_lawyer: bool) -> void:
	var run_seed := 20261002
	Wallet.reset()
	Hearts.reset()
	Market.open(run_seed, 80)
	Debt.open(run_seed)

	print("\n==============================================================")
	print("  %s — earns %d a day" % [label, wage])
	print("  purse %d   debt %d   lawyer %d   hearts %.1f" % [
		Wallet.coins, Debt.owed, Debt.lawyer_fee, Hearts.hearts()])
	print("==============================================================")

	var conn: Array[Callable] = []

	var on_paid := func(amt: int, left: int) -> void:
		print("  phase %d  day %2d  PAID %5d   principal %5d   purse %5d" % [
			Debt.phase, Market.day(), amt, left, Wallet.coins])
	var on_missed := func(short: int, taken: int, ph: int) -> void:
		print("  phase %d  day %2d  MISSED by %d (he took %d) -> %.1f hearts, principal now %d" % [
			ph, Market.day(), short, taken, Hearts.hearts(), Debt.owed])
	var on_gambled := func(added: int, owed: int) -> void:
		print("           day %2d  mother lost %d -> debt %d, next rent %d" % [
			Market.day(), added, owed, Debt.installment])
	var on_collapsed := func(ph: int) -> void:
		print("\n  >>> COLLAPSED in phase %d, day %d. missed %d phases, sank %d in interest." % [
			ph, Market.day(), Debt.phases_missed, Debt.interest_paid])

	Debt.paid.connect(on_paid)
	Debt.missed.connect(on_missed)
	Debt.mother_gambled.connect(on_gambled)
	Debt.collapsed.connect(on_collapsed)
	conn = [on_paid, on_missed, on_gambled, on_collapsed]

	for day in range(1, 81):
		Market.advance_to(day)
		Wallet.earn(wage, &"test")
		if buy_lawyer and Debt.can_hire_lawyer():
			Debt.hire_lawyer()
			print("\n  >>> LAWYER HIRED day %d, phase %d. sank %d in interest, %.1f hearts left." % [
				day, Debt.phase, Debt.interest_paid, Hearts.hearts()])
			break
		if not Debt.advance_to(day):
			break
	# Asked of the real state rather than of a flag set in the handlers above:
	# a GDScript lambda captures a local by value, so a `done = true` inside one
	# never reaches this scope and every run reported two endings.
	if not Debt.settled and not Hearts.is_empty():
		print("\n  >>> survived 80 days, never won. %.1f hearts, sank %d, still owes %d." % [
			Hearts.hearts(), Debt.interest_paid, Debt.owed])

	# These are autoloads that outlive a run, so a connection left behind would
	# make the next run print everything twice.
	Debt.paid.disconnect(conn[0])
	Debt.missed.disconnect(conn[1])
	Debt.mother_gambled.disconnect(conn[2])
	Debt.collapsed.disconnect(conn[3])

func _glut() -> void:
	print("\n=== supply: what dumping does to a price ===")
	for lot in [1, 5, 10, 20, 40]:
		Market.open(7, 20)
		var unit := Market.price(&"carrot")
		var got := Market.sell(&"carrot", lot)
		print("  %2d carrots at %d each -> %4d (%.1f each), next one %d" % [
			lot, unit, got, got / float(lot), Market.price(&"carrot")])
