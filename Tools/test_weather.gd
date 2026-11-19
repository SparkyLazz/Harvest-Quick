extends SceneTree

## Checks the weather: that a day's sky is the same answer every time it is
## asked, that the seasons get roughly the rain they are meant to, that rain
## waters the farm and grows what it waters, and that the clock's window and the
## rain layer both follow the sky.
##   godot --headless --path . --script Tools/test_weather.gd

var _fails := 0

func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1

func _initialize() -> void:
	# Autoloads are attached to the root after the main loop starts.
	await process_frame
	var state := root.get_node("PlayerState")
	var weather := root.get_node("Weather")

	# --- the roll ------------------------------------------------------------
	# The whole design rests on this: nothing is stored, so asking twice has to
	# give the same answer or the farm and the clock would drift apart.
	var twice := true
	for day in range(1, 400):
		if weather.rolled_for(day) != weather.rolled_for(day):
			twice = false
	check(twice, "a day's weather is the same answer every time it is asked")
	check(weather.rolled_for(1) == weather.CLEAR, "day 1 is always clear")

	# Not a fixed share -- it is a roll -- but a season that never rains, or one
	# that rains most days, would mean the mixer is not spreading.
	var seen := {}
	for season in 4:
		var wet := 0
		var storms := 0
		# One whole season of each, taken from year 1.
		for i in Calendar.DAYS_PER_SEASON:
			var day := season * Calendar.DAYS_PER_SEASON + i + 1
			var kind: int = weather.rolled_for(day)
			seen[kind] = true
			if weather.is_wet(kind):
				wet += 1
			if kind == weather.STORM:
				storms += 1
		var name_ := Calendar.SEASONS[season]
		if weather.RAIN_CHANCE[season] == 0.0:
			check(wet == 0, "%s never rains (%d wet days)" % [name_, wet])
		else:
			var share: float = float(wet) / Calendar.DAYS_PER_SEASON
			check(share > 0.0 and share < 0.6,
					"%s rains on %d of its 28 days (%d of them storms)" % [name_, wet, storms])
	check(seen.has(weather.CLEAR) and seen.has(weather.RAIN) and seen.has(weather.STORM),
			"all three skies turn up in the first year")

	# --- forcing -------------------------------------------------------------
	weather.forced = weather.RAIN
	check(weather.today() == weather.RAIN and weather.is_wet_today(),
			"a forced sky overrides the day")
	weather.forced = 99
	check(weather.forced == -1, "a kind that is not a kind falls back to the calendar")

	# --- the farm ------------------------------------------------------------
	state.autosave = false
	state.reset()
	var scene: Node = load("res://Scenes/Dev.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var farm = scene.get_node("Farm")
	var plate = scene.get_node("HUD").get_node("Screen/Clock")
	var rain = scene.get_node("Rain")

	var plot := Vector2i(3, 3)
	var dry_plot := Vector2i(4, 3)
	farm._on_tilled(plot)
	farm._on_tilled(dry_plot)
	check(farm.plant(plot, "carrot"), "a carrot goes in")

	weather.forced = weather.CLEAR
	check(not farm.is_wet(plot), "a clear day leaves the soil dry")

	weather.forced = weather.RAIN
	check(farm.is_wet(plot) and farm.is_wet(dry_plot),
			"rain wets every tilled cell, crop or no crop")
	var fresh := Vector2i(5, 3)
	farm._on_tilled(fresh)
	check(farm.is_wet(fresh), "soil hoed in the rain comes up wet")

	# A night under the rain grows the crop exactly as a watered one would.
	var grown_before: int = farm._crops[plot]["grown"]
	weather.forced = weather.RAIN
	state.sleep()
	await process_frame
	check(farm._crops[plot]["grown"] == grown_before + 1,
			"a night of rain grows the crop (%d -> %d)" % [grown_before, farm._crops[plot]["grown"]])
	check(farm.is_wet(plot), "and the morning is still wet, because it is still raining")

	# The sky clearing does not dry what it already wet: the rain that fell is
	# still in the soil, so the night that follows still grows the crop. It is
	# the morning after that one -- dry day, dry night -- that grows nothing.
	weather.forced = weather.CLEAR
	var grown_wet: int = farm._crops[plot]["grown"]
	state.sleep()
	await process_frame
	check(farm._crops[plot]["grown"] == grown_wet + 1,
			"yesterday's rain still grows tonight's crop")
	check(not farm.is_wet(plot), "and the soil is dry in the clear morning")
	var grown_dry: int = farm._crops[plot]["grown"]
	state.sleep()
	await process_frame
	check(farm._crops[plot]["grown"] == grown_dry,
			"a clear night after a dry day grows nothing")

	# --- the clock's window --------------------------------------------------
	# At midday: the sheet has no orange storm cloud, so dawn and dusk show the
	# plain rain picture for both and only the daylight hours tell them apart.
	state.minutes = 12 * 60
	weather.forced = weather.CLEAR
	plate.refresh(false)
	var clear_region: Rect2 = (plate._picture.texture as AtlasTexture).region
	weather.forced = weather.RAIN
	plate.refresh(false)
	var rain_region: Rect2 = (plate._picture.texture as AtlasTexture).region
	weather.forced = weather.STORM
	plate.refresh(false)
	var storm_region: Rect2 = (plate._picture.texture as AtlasTexture).region
	check(clear_region != rain_region, "the clock's window changes picture when it rains")
	check(rain_region != storm_region, "and again for a storm")
	# Read off the plate, not off the class: a tool script run with --script is
	# compiled before the autoloads exist, so naming ClockPlate here would drag
	# it in early and fail on the PlayerState inside it.
	check(rain_region.position.y == plate.RAIN_ROW * plate.ICON_CELL + plate.ICON_INSET,
			"the rainy picture comes from the sheet's wet row")
	# The window is 34x34 and the regions are cut from inside a 48px cell, so a
	# column that ran off the sheet would read as a torn picture.
	var sheet: Texture2D = plate.ICONS
	check(storm_region.end.x <= sheet.get_width() and storm_region.end.y <= sheet.get_height(),
			"every picture is inside the sheet")

	# --- the rain layer ------------------------------------------------------
	var falling := func() -> bool:
		for entry in rain._sheets:
			if not entry["node"].emitting:
				return false
		return true
	# Set without the fade, the way a scene loading into a wet day does it, so
	# the wash can be read at its settled value instead of mid-tween.
	rain.set_kind(weather.CLEAR, false)
	await process_frame
	check(not falling.call(), "no drops fall on a clear day")
	check(rain._tint.color.a == 0.0, "and nothing is drawn over the world")
	rain.set_kind(weather.RAIN, false)
	await process_frame
	check(falling.call(), "both sheets fall when it rains")
	check(rain._tint.color.a > 0.0, "and an overcast wash goes over the world")
	check(rain.layer > 0 and rain.layer < scene.get_node("HUD").layer,
			"the rain is over the world and under the HUD")
	check(rain._flash_timer.is_stopped(), "no lightning in plain rain")
	var rain_wash: float = rain._tint.color.a
	rain.set_kind(weather.STORM, false)
	await process_frame
	check(rain._tint.color.a > rain_wash, "a storm draws a darker sky than plain rain")
	check(not rain._flash_timer.is_stopped(), "a storm books its lightning")
	# The sky following the calendar again has to reach the layer on its own.
	weather.forced = weather.CLEAR
	await process_frame
	check(rain.kind() == weather.CLEAR and not falling.call(),
			"the rain layer follows the weather's own signal")

	weather.forced = -1
	print("weather: ", "all passed" if _fails == 0 else "%d FAILED" % _fails)
	quit(1 if _fails > 0 else 0)
