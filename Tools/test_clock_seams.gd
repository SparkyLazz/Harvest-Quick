extends SceneTree

## Nothing behind the clock may show through it at any window size.
##
## The clock is layers -- skies, pictures, dial, empty tube, liquid -- seen
## through holes in one frame. At a window size that scales it by a whole
## number they line up exactly; at any other, each layer rounds to screen
## pixels on its own, and where a layer's edge met the rim's edge exactly a
## one-pixel seam opened onto the background (a dark line down the left of the
## thermometer was the one that got noticed). Tools/cut_clock.py now bleeds
## every layer a pixel under the rim. This draws the clock over magenta at a
## spread of fractional scales and counts magenta inside each opening.
##
## The status sign in the opposite corner is checked the same way: it is two
## plates hung on two posts, and a post that only touched its plates would
## open the same seam where they meet.
##
## Needs a window to render; headless it prints SKIP and passes.
##   godot --path . --script Tools/test_clock_seams.gd

const FACTORS := [1.0, 1.13, 1.25, 1.37, 1.5, 1.67, 1.8, 2.13]
## Dawn (orange sky), day (green), night (blue): every sky the window uses.
const TIMES := [6 * 60 + 30, 13 * 60, 22 * 60]
## The frame's openings in clock pixels (x0, y0, x1, y1), one pixel wider all
## round so a seam on the rim's edge is caught too.
const OPENINGS := {
	"window": Rect2i(9, 9, 36, 36),
	"dial": Rect2i(52, 9, 24, 36),
	"tube": Rect2i(8, 61, 6, 21),
	"bulb": Rect2i(6, 81, 10, 9),
}
const MARGIN := 10
const UI_SCALE := 2

var _fails := 0


func check(ok: bool, what: String) -> void:
	print(("  PASS  " if ok else "  FAIL  "), what)
	if not ok:
		_fails += 1


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		print("  SKIP  clock seams (rendering needs a window)")
		quit(0)
		return
	await process_frame
	var state := root.get_node("PlayerState")
	state.day = 43
	var back := ColorRect.new()
	back.color = Color(1, 0, 1)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	# Loaded rather than named: a --script test cannot name a class that uses
	# autoloads (TECH_NOTES, traps).
	var clock: Control = load("res://Scripts/ClockPlate.gd").new()
	root.add_child(clock)
	for minutes: int in TIMES:
		state.minutes = minutes
		clock.refresh(false)
		for factor: float in FACTORS:
			root.content_scale_factor = factor
			for i in 6:
				await process_frame
			var image := root.get_texture().get_image()
			var found := {}
			for name: String in OPENINGS:
				found[name] = _magenta_in(image, OPENINGS[name], factor)
			var total: int = found.values().reduce(func(a, b): return a + b, 0)
			check(total == 0, "%s at x%.2f: nothing shows through %s"
					% [Calendar.time_text(minutes), factor, found if total else "any opening"])

	# --- the status sign: plates hung on posts -----------------------------------
	clock.queue_free()
	var sign: Control = load("res://Scripts/StatusSign.gd").new()
	root.add_child(sign)
	for factor: float in FACTORS:
		root.content_scale_factor = factor
		for i in 6:
			await process_frame
		sign._place()
		await process_frame
		await process_frame
		var image := root.get_texture().get_image()
		var low_w: int = sign._low_width()
		var top_w: int = sign._top_width()
		# In the sign's own pixels. The post strips run from the top plate's last
		# row to the lower plate's first, kept half a pixel inside the post's
		# sides; the plates are checked inside their chamfered corners.
		var areas := {
			"left post": Rect2(6.5, 30, 2, 5),
			"right post": Rect2(low_w - 10 + 0.5, 30, 2, 5),
			"top plate": Rect2(3, 3, top_w - 6, 25),
			"lower plate": Rect2(3, 37, low_w - 6, 14),
		}
		var found := {}
		for name: String in areas:
			found[name] = _magenta_in_sign(image, sign, areas[name], factor)
		var total: int = found.values().reduce(func(a, b): return a + b, 0)
		check(total == 0, "status sign at x%.2f: nothing shows through %s"
				% [factor, found if total else "its posts or plates"])
	root.content_scale_factor = 1.0
	print("\n%s (%d failed)" % ["ALL PASSED" if _fails == 0 else "FAILURES", _fails])
	quit(1 if _fails > 0 else 0)


## Magenta pixels on screen inside `area`, given in the sign's own pixels.
func _magenta_in_sign(image: Image, sign: Control, area: Rect2, factor: float) -> int:
	var a: Vector2 = (sign.position + area.position * sign.scale) * factor
	var b: Vector2 = (sign.position + area.end * sign.scale) * factor
	var count := 0
	for y in range(int(a.y), mini(int(b.y), image.get_height())):
		for x in range(int(ceil(a.x)), mini(int(b.x), image.get_width())):
			var c := image.get_pixel(x, y)
			if c.r > 0.85 and c.g < 0.15 and c.b > 0.85:
				count += 1
	return count


## Magenta pixels on screen inside `area`, given in clock pixels.
func _magenta_in(image: Image, area: Rect2i, factor: float) -> int:
	var x0 := int(factor * (MARGIN + UI_SCALE * area.position.x))
	var y0 := int(factor * (MARGIN + UI_SCALE * area.position.y))
	var x1 := mini(int(factor * (MARGIN + UI_SCALE * area.end.x)) + 1, image.get_width())
	var y1 := mini(int(factor * (MARGIN + UI_SCALE * area.end.y)) + 1, image.get_height())
	var count := 0
	for y in range(y0, y1):
		for x in range(x0, x1):
			var c := image.get_pixel(x, y)
			if c.r > 0.85 and c.g < 0.15 and c.b > 0.85:
				count += 1
	return count
