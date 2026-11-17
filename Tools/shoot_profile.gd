extends SceneTree

## Saves the profile window, one frame per tab, to the folder given after `--`:
##   godot --path . --script Tools/shoot_profile.gd -- <out dir>
## Run it windowed; headless draws nothing to save.

func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 \
			else "res://Tools"
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var hud: Node = current_scene.find_child("HUD", true, false)
	hud.inventory.set_slot(1, "carrot", 12)
	hud.inventory.set_slot(2, "tomato", 3)
	hud._panel.open()
	for tab in 3:
		hud._panel._show_tab(tab)
		for i in 20:
			await process_frame
		root.get_texture().get_image().save_png(out.path_join("profile_%d.png" % tab))
	# Poked, mid-bounce: the cat must stay inside its frame.
	hud._panel._show_tab(0)
	hud._panel._poke_cat()
	await create_timer(0.08).timeout
	root.get_texture().get_image().save_png(out.path_join("profile_poke.png"))
	print("done")
	quit()
