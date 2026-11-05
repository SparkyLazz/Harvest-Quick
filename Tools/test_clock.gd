extends SceneTree

## Checks the day clock: how the calendar reads, the clock running and standing
## still behind windows, crops growing overnight only where watered, a farm
## catching up on the nights it was not loaded, and passing out at 2am.
##   godot --headless --path . --script Tools/test_clock.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	# Autoloads are attached to the root after the main loop starts.
	await process_frame
	var state := root.get_node("PlayerState")
	var fade := root.get_node("SceneTransition")

	# --- the calendar --------------------------------------------------------
	check(Calendar.date_text(1) == "Mon 1" and Calendar.season(1) == "Spring",
			"day 1 is Mon 1 Spring")
	check(Calendar.date_text(28) == "Sun 28" and Calendar.season(28) == "Spring",
			"day 28 is the last of Spring (%s)" % Calendar.date_text(28))
	check(Calendar.season(29) == "Summer" and Calendar.day_of_season(29) == 1,
			"day 29 is Summer 1")
	check(Calendar.season(85) == "Winter" and Calendar.year(112) == 1 and Calendar.year(113) == 2,
			"winter starts on day 85 and year 2 on day 113")
	check(Calendar.week(1) == 1 and Calendar.week(7) == 1 and Calendar.week(8) == 2,
			"weeks run Monday to Sunday")
	check(Calendar.time_text(360) == "6:00 am", "6:00 am")
	check(Calendar.time_text(725) == "12:00 pm", "noon reads 12:00 pm, in 10-minute steps")
	check(Calendar.time_text(1500) == "1:00 am", "past midnight reads 1:00 am")

	# --- the clock -----------------------------------------------------------
	var scene: Node = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var hud = scene.get_node("HUD")
	var farm = scene.get_node("Farm")
	var player = scene.get_node("Player")
	check(state.minutes == Calendar.DAY_START, "the first day starts at 6:00")
	state.pass_time(Calendar.SECONDS_PER_MINUTE * 10.0 + 0.001)
	check(state.minutes == Calendar.DAY_START + 10, "7 seconds is ten minutes (got %d)" % state.minutes)
	var plate = hud.get_node("Screen/Clock")
	check(plate._season.text == "Spring" and plate._date.text == "Mon 1",
			"the plate reads '%s' over '%s'" % [plate._season.text, plate._date.text])
	check(plate._season.position.y < plate._date.position.y, "the season is the top line")
	# Each line has its own row, centred: on no day of the year may either one
	# be wider than its box, or it would run into the plate's rim.
	var font: Font = plate._date.get_theme_font("font")
	var px: int = plate._date.get_theme_font_size("font_size")
	var room: float = plate._date.size.x
	var widest := 0.0
	var worst := ""
	for day in range(1, 113):
		for text in [Calendar.date_text(day), Calendar.season(day)]:
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if w > widest:
				widest = w
				worst = text
	check(widest <= room, "every date and season fits its line: widest is '%s', %d of %d px"
			% [worst, widest, room])

	# --- the clock face ------------------------------------------------------
	var names := []
	for m in [6 * 60, 8 * 60, 17 * 60, 20 * 60, 24 * 60, 25 * 60 + 50]:
		names.append(plate.PHASES[plate.phase_at(m)]["name"])
	check(names == ["dawn", "day", "dusk", "night", "late", "late"],
			"the window goes dawn, day, dusk, night, late (%s)" % [names])
	check(plate.arrow_frame_at(Calendar.DAY_START) == 0, "the arrow starts the day pointing up at the sun")
	check(plate.arrow_frame_at(18 * 60) == 2, "it is level at 6pm, where day meets night")
	check(plate.arrow_frame_at(Calendar.PASS_OUT - 1) == 4, "and points down at the moon by 2am")
	var frames := []
	for m in range(Calendar.DAY_START, Calendar.PASS_OUT, 10):
		frames.append(plate.arrow_frame_at(m))
	var sorted_frames := frames.duplicate()
	sorted_frames.sort()
	check(frames == sorted_frames, "the arrow only ever moves down through the day")
	check(plate.heat_at(29, 13 * 60) < plate.heat_at(1, 13 * 60)
			and plate.heat_at(1, 13 * 60) < plate.heat_at(85, 13 * 60),
			"summer reads hotter than spring, and spring hotter than winter")
	check(plate.heat_at(1, 13 * 60) < plate.heat_at(1, 22 * 60),
			"an afternoon is warmer than the night")
	check(plate.phase_name() == "dawn", "the window opens on dawn")
	state.minutes = 8 * 60
	plate.refresh()
	check(plate.phase_name() == "day" and plate._leaving.visible,
			"at 8:00 the dawn picture starts to sink out")
	# Real seconds, not frames: headless runs frames far faster than 60 a second.
	await create_timer(plate.SWAP_TIME + 0.6).timeout
	check(not plate._leaving.visible and plate._picture.position.y <= 0.0
			and is_equal_approx(plate._sky.modulate.a, 1.0),
			"and the sun has risen into place once the swap is over (leaving %s, y %s, sky %s)"
			% [plate._leaving.visible, plate._picture.position.y, plate._sky.modulate.a])

	var before: int = state.minutes
	hud._panel.toggle()
	hud._process(30.0)
	check(state.minutes == before, "the clock stands still while a window is up")
	hud._panel.toggle()
	hud._process(Calendar.SECONDS_PER_MINUTE * 10.0)
	check(state.minutes == before + 10, "and runs again once it is closed")

	# --- crops grow overnight ------------------------------------------------
	var wet := Vector2i(20, 20)
	var dry := Vector2i(21, 20)
	for cell in [wet, dry]:
		farm._on_tilled(cell)
		farm.plant(cell, "carrot")
	var days := CropDB.days_to_ripen("carrot")
	farm.water(wet)
	state.sleep()
	check(farm._crops[wet]["grown"] == 1, "a watered crop grows a day overnight")
	check(farm._crops[dry]["grown"] == 0, "an unwatered one does not")
	check(not farm.is_wet(wet), "and the soil is dry again in the morning")
	state.sleep()
	check(farm._crops[wet]["grown"] == 1, "a night without watering grows nothing")
	for i in days - 1:
		farm.water(wet)
		state.sleep()
	check(farm.is_ripe(wet), "carrots are ripe after %d watered nights" % days)
	check(not farm.is_ripe(dry), "the dry one is still a seed")

	# --- a farm catches up on nights it missed --------------------------------
	var away := Vector2i(22, 20)
	farm._on_tilled(away)
	farm.plant(away, "pumpkin")
	farm.water(away)
	root.remove_child(scene)
	scene.free()
	state.sleep()
	state.sleep()
	state.sleep()
	scene = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	for i in 3:
		await process_frame
	farm = scene.get_node("Farm")
	check(farm.has_crop(away) and farm._crops[away]["grown"] == 1,
			"three nights away grow it once: only the first had wet soil (got %s)"
			% (farm._crops[away]["grown"] if farm.has_crop(away) else "none"))
	check(not farm.is_wet(away), "and it comes back dry")

	# --- passing out ---------------------------------------------------------
	root.remove_child(scene)
	scene.free()
	change_scene_to_file("res://Scenes/Dev.tscn")
	for i in 3:
		await process_frame
	var day: int = state.day
	state.minutes = Calendar.PASS_OUT - 1
	state.pass_time(Calendar.SECONDS_PER_MINUTE)
	await fade.arrived
	var house := current_scene
	check(house != null and house.scene_file_path == state.HOUSE_SCENE, "passing out lands you at home")
	check(state.day == day + 1 and state.minutes == Calendar.DAY_START, "on the next morning at 6:00")
	check(is_equal_approx(state.stamina, state.max_stamina * state.PASS_OUT_STAMINA),
			"with only half your stamina (%.0f of %.0f)" % [state.stamina, state.max_stamina])
	player = house.find_child("Player", true, false)
	var bed := house.find_child("Bed", true, false) as Node2D
	check(player != null and bed != null and player.global_position == bed.global_position,
			"standing beside the bed")

	state.sleep()
	check(is_equal_approx(state.stamina, state.max_stamina), "a proper night in bed fills it")

	print("\n%s (%d failed)" % ["ALL PASSED" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)
