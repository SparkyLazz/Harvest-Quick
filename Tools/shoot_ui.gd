extends SceneTree

## Saves a frame of each window now that they are all cut from the one plate,
## so the shades can be looked at side by side rather than trusted. Run this
## windowed; headless draws with the dummy renderer and hands back nothing.

func _initialize() -> void:
	await process_frame
	change_scene_to_file("res://Scenes/PlayerHouse.tscn")
	for i in 20:
		await process_frame
	var hud: Node = current_scene.find_child("HUD", true, false)

	await _settle()
	root.get_texture().get_image().save_png("res://Tools/ui_bars.png")

	hud._panel.open()
	await _settle()
	root.get_texture().get_image().save_png("res://Tools/ui_profile.png")

	# The crafting tab, where an unselected tab sits next to the selected one.
	hud._panel._show_tab(1)
	await _settle()
	root.get_texture().get_image().save_png("res://Tools/ui_crafting.png")

	hud._panel._show_tab(2)
	await _settle()
	root.get_texture().get_image().save_png("res://Tools/ui_settings.png")

	hud._panel.close()
	hud.open_storage("demo")
	await _settle()
	root.get_texture().get_image().save_png("res://Tools/ui_storage.png")
	print("done")
	quit()


func _settle() -> void:
	for i in 20:
		await process_frame
