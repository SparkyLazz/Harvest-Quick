extends SceneTree

## Walks every recipe through the crafting detail card and reports the card's
## size for each one. The card jumping as you move down the list is the whole
## bug, so the test is simply: does that number ever change?
##
## Run windowed, so the frames it saves are real.

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var hud: Node = current_scene.find_child("HUD", true, false)
	var panel = hud._panel
	panel.open()
	panel._show_tab(1)
	for i in 10:
		await process_frame

	var card: Control = panel._craft_name.get_parent().get_parent()
	var sizes := {}
	var longest := 0
	var longest_len := 0
	var overflow := 0
	for i in panel._recipes.size():
		panel._select_recipe(i)
		for f in 3:
			await process_frame
		var key := "%dx%d" % [card.size.x, card.size.y]
		sizes[key] = int(sizes.get(key, 0)) + 1
		if panel._craft_body.size.y > panel._craft_body.custom_minimum_size.y:
			overflow += 1
		var body: String = panel._craft_body.text
		print("  %-20s card %s  name %s/%s  body %s/%s" % [panel._craft_name.text, key,
				panel._craft_name.size.y, panel._craft_name.custom_minimum_size.y,
				panel._craft_body.size.y, panel._craft_body.custom_minimum_size.y])
		if body.length() > longest_len:
			longest_len = body.length()
			longest = i

	print("distinct card sizes: %d %s" % [sizes.size(), str(sizes.keys())])
	print("  %s one size for every recipe" % ["PASS" if sizes.size() == 1 else "FAIL"])
	print("  %s no recipe overflows the space reserved for it" % ["PASS" if overflow == 0
			else "FAIL (%d)" % overflow])

	panel._select_recipe(longest)
	for f in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/craft_longest.png")
	panel._select_recipe(0)
	for f in 10:
		await process_frame
	root.get_texture().get_image().save_png("res://Tools/craft_shortest.png")
	print("done")
	quit()
