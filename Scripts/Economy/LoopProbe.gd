extends Node

## A smoke test for the loop, driven against the real farm scene.
##
## The economy is four autoloads and two scene nodes that only mean anything
## wired together, and every bug so far has been in the wiring rather than in any
## one of them: a shop that missed the first morning because it was built after
## the signal, a crate the world had not adopted, a market that bought back its
## own seed corn. None of those show up in a unit test of the piece that was
## wrong. This presses the actual buttons in the actual scene.
##
## Not an autoload, because it ends with [method SceneTree.quit]. To run it, add
## this line under [code]Inventory[/code] in project.godot, run the project, then
## take the line back out:
## [codeblock]
## LoopProbe="*res://Scripts/Economy/LoopProbe.gd"
## [/codeblock]
## Run without --headless and with HQ_SHOT set to a .png path to also get a
## picture of the shop, which is the only way to catch a panel that is laid out
## correctly and draws wrongly.

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var run := get_tree().get_first_node_in_group("run")
	var crate: ShippingCrate = null
	for node in get_tree().get_nodes_in_group("world_objects"):
		for child in node.get_children():
			if child is ShippingCrate:
				crate = child
	var clock := get_tree().get_first_node_in_group("day_night")

	print("\n--- wiring ---")
	print("Run node:        %s" % ("found" if run != null else "MISSING"))
	print("ShippingCrate:   %s" % ("found at %s" % crate.global_position if crate != null else "MISSING"))
	print("Day clock:       %s" % ("found" if clock != null else "MISSING"))
	if run == null or crate == null or clock == null:
		get_tree().quit()
		return

	var shop := _find_shop()
	print("ShopPanel:       %s" % ("found, open=%s" % shop.is_open() if shop != null else "MISSING"))

	# A look at it, because a panel laid out in code and never seen is a panel
	# that renders as a broken box. Needs a real renderer, so this does nothing
	# under --headless.
	var jump := int(OS.get_environment("HQ_DAY"))
	if jump > 1:
		# Jumped straight to a day so the shop can be seen in a season that is
		# otherwise twenty-eight days away.
		for d in range(2, jump + 1):
			# Kept solvent on the way, so the jump arrives in winter with a live
			# run rather than one that collapsed in spring.
			Wallet.earn(4000, &"probe")
			clock.day_passed.emit(d)
		shop.close()
		shop.open()
		print("jumped to day %d (%s)" % [jump, Season.label(jump)])

	if OS.get_environment("HQ_NEWS") != "":
		var paper: NewsPanel = null
		var st: Array[Node] = [get_tree().current_scene]
		while not st.is_empty():
			var n: Node = st.pop_back()
			if n is NewsPanel:
				paper = n
			st.append_array(n.get_children())
		if paper != null:
			shop.close()
			paper._today_override = shop._today_override
			paper.open()
			print("--- the paper carries %d stories ---" % paper._stories.size())
			for st2 in paper._stories:
				print("  %-42s %s" % [st2["head"], st2["body"].substr(0, 90)])

	var paper2: NewsPanel = null
	var st3: Array[Node] = [get_tree().current_scene]
	while not st3.is_empty():
		var n3: Node = st3.pop_back()
		if n3 is NewsPanel:
			paper2 = n3
		st3.append_array(n3.get_children())
	print("
--- the HUD column ---")
	for node in get_tree().current_scene.find_children("*", "Control", true, false):
		if node is HudButton:
			var box := Rect2(node.position, node.custom_minimum_size * node.scale)
			print("  %-14s covers y %.0f..%.0f  -> %s  (found %s)" % [
				node.name, box.position.y, box.end.y, node.panel_type,
				"yes" if node._panel != null else "NO PANEL"])

	print("
--- where does the window actually land? ---")
	shop.close()
	for _w0 in 15:
		await get_tree().process_frame
	shop.open()
	for _w1 in 40:
		await get_tree().process_frame
	var vp := shop.get_viewport_rect().size
	var fr: Control = shop._frame
	print("  viewport %s, centre %s" % [vp, vp * 0.5])
	print("  panel position %s pivot %s scale %s" % [
		shop.position, shop.pivot_offset, shop.scale])
	print("  frame drawn at %s size %s -> centre %s" % [
		fr.global_position, fr.size * shop.scale,
		fr.global_position + fr.size * shop.scale * 0.5])

	if OS.get_environment("HQ_DIAL") != "":
		print("
--- the stamina dial ---")
		var dial: StaminaDial = null
		var sta: Stamina = get_tree().get_first_node_in_group("stamina")
		for node in get_tree().current_scene.find_children("*", "Sprite2D", true, false):
			if node is StaminaDial:
				dial = node
		print("  dial %s, pool %s, bound %s" % [
			"found" if dial != null else "MISSING",
			"found" if sta != null else "MISSING",
			dial._stamina != null if dial != null else false])
		print("  at rest:        alpha %.2f  wanted %s  full %.2f" % [
			dial.modulate.a, dial._wanted, sta.fraction()])
		sta.spend(&"hoe")
		await get_tree().process_frame
		print("  after a swing:  alpha %.2f  wanted %s  full %.2f" % [
			dial.modulate.a, dial._wanted, sta.fraction()])
		for _s in 40:
			await get_tree().process_frame
		print("  half a second:  alpha %.2f  wanted %s  full %.2f" % [
			dial.modulate.a, dial._wanted, sta.fraction()])
		# long enough for the delay, the refill and the linger
		for _s2 in 400:
			await get_tree().process_frame
		print("  well rested:    alpha %.2f  wanted %s  full %.2f  linger %.2f" % [
			dial.modulate.a, dial._wanted, sta.fraction(), dial._linger_left])

	print("
--- the column buttons ---")
	var cart2: HudButton = null
	var rep: HudButton = null
	for node in get_tree().current_scene.find_children("*", "Control", true, false):
		if node is HudButton:
			if node.panel_type == &"ShopPanel":
				cart2 = node
			else:
				rep = node
	shop.close()
	paper2.close()
	print("  start:          shop %s, paper %s" % [shop.is_open(), paper2.is_open()])
	cart2.activate()
	print("  cart pressed:   shop %s, paper %s" % [shop.is_open(), paper2.is_open()])
	rep.activate()
	print("  report pressed: shop %s, paper %s" % [shop.is_open(), paper2.is_open()])
	cart2.activate()
	print("  cart pressed:   shop %s, paper %s" % [shop.is_open(), paper2.is_open()])
	cart2.activate()
	print("  cart again:     shop %s, paper %s" % [shop.is_open(), paper2.is_open()])
	shop.open()

	print("
--- clicking the X for real ---")
	shop.open()
	for _x in 25:
		await get_tree().process_frame
	# Found by walking the header rather than by remembering where it was put.
	var xbtn: Control = null
	for node in shop.find_children("*", "TextureRect", true, false):
		if node.tooltip_text == "Close":
			xbtn = node
	if xbtn == null:
		print("  NO CLOSE BUTTON FOUND")
	else:
		var spot := xbtn.get_global_rect().get_center()
		print("  X sits at %s, shop open %s" % [spot, shop.is_open()])
		for down in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = down
			ev.position = spot
			ev.global_position = spot
			Input.parse_input_event(ev)
			await get_tree().process_frame
		for _x2 in 20:
			await get_tree().process_frame
		print("  after a real click: open %s, drawing %s, alpha %.2f" % [
			shop.is_open(), shop.visible, shop.modulate.a])
		for _x3 in 60:
			await get_tree().process_frame
		print("  a full second on:   open %s, drawing %s, alpha %.2f" % [
			shop.is_open(), shop.visible, shop.modulate.a])

	print("
--- does it come back by itself? ---")
	shop.close()
	for _d in 10:
		await get_tree().process_frame
	clock.day_passed.emit(2)
	clock.day_passed.emit(3)
	for _d2 in 10:
		await get_tree().process_frame
	print("  two mornings later, shop open: %s" % shop.is_open())

	print("
--- the corner buttons ---")
	shop.open()
	print("  shop open %s, paper open %s" % [shop.is_open(), paper2.is_open()])
	shop.close_pressed.emit()
	print("  after X:      shop %s, paper %s" % [shop.is_open(), paper2.is_open()])
	# The node must actually stop drawing once the shutting animation is over,
	# not merely be flagged shut.
	for _w in 20:
		await get_tree().process_frame
	print("  a moment on:  is_open %s, still drawing %s" % [
		shop.is_open(), shop.visible])
	shop.open()

	var shelf_pick := OS.get_environment("HQ_SHELF")
	if shelf_pick != "":
		shop._shelf = int(shelf_pick)
		shop.rebuild()

	if shop != null and not DisplayServer.get_name() == "headless":
		# The farm ships with its HUD switched off, so nothing in it draws —
		# hotbar included. Flipped here only, at runtime, so the scene on disk
		# keeps whatever the author meant by that.
		var hud := shop.get_parent()
		while hud != null and not (hud is CanvasLayer):
			hud = hud.get_parent()
		if hud != null and not hud.visible:
			hud.visible = true
			print("HUD was hidden in the scene; shown for this shot only")
		else:
			print("HUD is visible in the scene")
		# Shut and reopened here, because the store lets itself in at the top of
		# the run and its arrival is long over by the time this runs. Skipped
		# when the paper is the thing being photographed.
		var want_paper := OS.get_environment("HQ_NEWS") != ""
		var subject: TwoPagePanel = paper2 if want_paper else shop
		var hidden: TwoPagePanel = shop if want_paper else paper2
		hidden.close()
		subject.close()
		for _c in 15:
			await RenderingServer.frame_post_draw
		subject.open()
		var waits := int(OS.get_environment("HQ_FRAMES"))
		if waits <= 0:
			waits = 30
		for _f in waits:
			await RenderingServer.frame_post_draw
		print("  %s: scale %s alpha %.2f after %d frames" % [
			subject.name, subject.scale, subject.modulate.a, waits])
		var sf: Control = subject._frame
		print("  %s frame centre %s (screen centre %s)" % [
			subject.name, sf.global_position + sf.size * subject.scale * 0.5,
			subject.get_viewport_rect().size * 0.5])
		var shot := get_viewport().get_texture().get_image()
		var out := OS.get_environment("HQ_SHOT")
		if out != "":
			shot.save_png(out)
			print("screenshot -> %s (%dx%d)" % [out, shot.get_width(), shot.get_height()])

	# The player reaches things through WorldObjects, not by touching them, so a
	# crate the world has not adopted is a crate no press will ever find.
	var world := get_tree().get_first_node_in_group("world_objects")
	var tiles: Array = crate.tiles()
	var found = world.at(tiles[0]) if not tiles.is_empty() else null
	print("crate occupies %s; world.at() returns %s" % [
		tiles, "the crate" if found == crate else "%s <- WRONG" % found])

	print("\n--- the empty-shelf notice ---")
	shop.open()
	shop._shelf = 1
	shop.rebuild()
	await get_tree().process_frame
	print("  text %s" % [shop._empty.text])
	print("  visible %s  in tree %s  size %s  global %s" % [
		shop._empty.visible, shop._empty.is_inside_tree(),
		shop._empty.size, shop._empty.global_position])
	print("  modulate %s  parent %s" % [
		shop._empty.modulate, shop._empty.get_parent().get_class()])
	shop._shelf = 0
	shop.rebuild()

	print("\n--- does the window move when the tab does? ---")
	shop.open()
	for shelf in [0, 1, 2]:
		shop._shelf = shelf
		shop.rebuild()
		await get_tree().process_frame
		shop._centre()
		print("  %-8s frame %s   window at %s" % [
			["Crops", "Animals", "Deco"][shelf], shop._frame.size, shop.position])
	shop._shelf = 0
	shop.rebuild()

	print("\n--- the cart button ---")
	var cart: HudButton = null
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is HudButton:
			cart = node
		stack.append_array(node.get_children())
	if cart == null:
		print("  MISSING")
	else:
		print("  found at %s, idle alpha %.2f" % [cart.position, cart.modulate.a])
		var before := shop.is_open()
		shop.toggle()
		print("  toggle -> shop visible %s (was %s)" % [shop.is_open(), before])
		shop.open()

	print("\n--- what can actually be planted, season by season ---")
	for probe_day in [1, 29, 57, 85]:
		var was: int = shop._today_override
		shop._today_override = probe_day
		var ok: Array[String] = []
		for entry in Market.stock(0):
			if shop.refusal(entry["id"]) == "":
				ok.append("%s %dg" % [
					entry["item"].display_name.replace(" Seeds", ""), entry["price"]])
		shop._today_override = was
		print("  %s (%d available)" % [Season.label(probe_day), ok.size()])
		print("      %s" % ", ".join(ok))

	print("\n--- the shelves ---")
	for shelf in [0, 1, 2]:
		var names: Array[String] = []
		for entry in Market.stock(shelf):
			names.append(entry["item"].display_name)
		print("  %-8s %s" % [["Crop", "Animals", "Deco"][shelf],
			", ".join(names) if not names.is_empty() else "(empty)"])

	print("\n--- the shop ---")
	if shop != null:
		for entry in Market.stock():
			print("  %-18s %d g" % [entry["item"].display_name, entry["price"]])
		var cauli_seed := load("res://Assets/Crops/CauliflowerSeeds.tres") as ItemData
		var had := _count(cauli_seed)
		print("purse %d, cauliflower seeds held %d" % [Wallet.coins, had])
		var got := shop.buy(&"cauliflower_seeds", 5)
		print("bought %d -> purse %d, now hold %d" % [got, Wallet.coins, _count(cauli_seed)])
		# Far more than the purse covers, to prove it stops rather than overdraws.
		var greedy := shop.buy(&"cauliflower_seeds", 9999)
		print("tried to buy 9999 -> got %d, purse %d (must not go below 0)" % [
			greedy, Wallet.coins])

	# First, because the starter kit holds tools and seeds but no produce, so the
	# satchel is already in the state this is meant to test — and because after a
	# shipment the crate is busy with its lid for a moment and would swallow it.
	print("\n--- an empty press ---")
	crate.nothing_to_ship.connect(func() -> void: print("crate: nothing to ship"))
	print("anything to ship? %s" % crate.has_anything_to_ship())
	crate.interact()

	print("\n--- selling ---")
	var carrot := load("res://Assets/Crops/Carrot.tres") as ItemData
	var cauli := load("res://Assets/Crops/Cauliflower.tres") as ItemData
	var seeds := load("res://Assets/Crops/CarrotSeeds.tres") as ItemData
	Inventory.add(carrot, 12)
	Inventory.add(cauli, 3)
	var seeds_before := _count(seeds)
	print("satchel: 12 carrot, 3 cauliflower, %d carrot seeds" % seeds_before)
	print("carrot %d each, cauliflower %d each" % [
		Market.price(&"carrot"), Market.price(&"cauliflower")])
	print("purse before: %d" % Wallet.coins)
	crate.shipped.connect(func(items: int, paid: int) -> void:
		print("crate shipped %d items for %d" % [items, paid]))
	crate.interact()
	print("purse after:  %d" % Wallet.coins)
	print("carrots left in satchel: %d (want 0)" % _count(carrot))
	print("seeds left in satchel:   %d (want %d — the town must not buy seed corn)" % [
		_count(seeds), seeds_before])

	print("anything to ship now? %s" % crate.has_anything_to_ship())

	print("\n--- the day clock driving the economy ---")
	print("day %d, phase %d, next knock day %d, rent %d" % [
		run.day, Debt.phase, Debt.next_visit, Debt.installment])
	Debt.missed.connect(func(short: int, took: int, ph: int) -> void:
		print("  MISSED phase %d by %d (he took %d) -> %.1f hearts" % [
			ph, short, took, Hearts.hearts()]))
	Debt.paid.connect(func(amt: int, left: int) -> void:
		print("  PAID %d, principal %d" % [amt, left]))
	for day in range(2, 16):
		clock.day_passed.emit(day)
		if day == 7 or day == 14:
			print("  day %d: carrot now %d, purse %d, hearts %.1f" % [
				day, Market.price(&"carrot"), Wallet.coins, Hearts.hearts()])
	print("market thinks it is day %d, run thinks day %d" % [Market.day(), run.day])
	get_tree().quit()

func _find_shop() -> ShopPanel:
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is ShopPanel:
			return node
		stack.append_array(node.get_children())
	return null

func _count(item: ItemData) -> int:
	var n := 0
	for i in Inventory.SLOT_COUNT:
		if Inventory.item_at(i) == item:
			n += Inventory.count_at(i)
	return n
