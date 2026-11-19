class_name Rain
extends CanvasLayer

## The rain you see: two sheets of falling streaks, an overcast tint over the
## world, and lightning when it is a storm.
##
## There is no rain art in either Sprout Lands pack, so none is used. A drop is
## a few pixels of white-blue made in code (`_streak`), thrown by a
## GPUParticles2D and turned to point along its own velocity, which is what
## makes it a streak rather than a dot. Two sheets are emitted, a faint slow one
## for distance and a brighter fast one for the near field, so the rain has some
## depth to it instead of reading as one flat curtain.
##
## This is a CanvasLayer, so it is drawn in screen space and does not have to
## chase the camera: layer 5 puts it over the world (layer 0) and under the HUD
## (layer 10) and the scene fade (layer 128). Everything is sized to the window
## and resized with it.
##
## The world is seen through a 4x camera, so a one-pixel drop would be four
## times finer than everything around it. The streaks are scaled up to match the
## chunk of the art instead -- see SCALE.
##
## Only outdoor scenes carry one of these. Weather decides whether it is running.

## How wide a drop is drawn, in screen pixels, near sheet and far sheet. The
## world's art is drawn at 4 screen pixels per art pixel, so these keep the rain
## on roughly the same grid as everything else.
const SCALE_NEAR := Vector2(3.0, 4.5)
const SCALE_FAR := Vector2(1.5, 2.5)
## Drops in each sheet at a 640x360 window; scaled by area for bigger ones, so
## a maximised window is not noticeably emptier than a small one.
const COUNT_NEAR := 95
const COUNT_FAR := 200
const REFERENCE_AREA := 640.0 * 360.0
## How far off the top drops are born, and how far past each side the sheet
## reaches, so the slant has somewhere to come from.
const SPAWN_ABOVE := 48.0
const SIDE_BLEED := 140.0
## How far the rain leans, as a share of its fall. The streaks are turned to
## point along this on their own.
const LEAN := 0.22

## The overcast wash over the world, and how far it is taken in a storm. It has
## to be darker than the art it lies over or it washes the colour out instead of
## clouding it: the first try was a mid blue-grey, and at a strength you could
## see at all the farm went pale rather than overcast. This is a deep blue, laid
## on thin.
const TINT := Color(0.13, 0.18, 0.34)
const TINT_ALPHA_RAIN := 0.20
const TINT_ALPHA_STORM := 0.36
## How long the sky takes to close over or clear, in seconds.
const FADE := 1.6

## Seconds between lightning, picked from this range.
const FLASH_GAP := Vector2(7.0, 18.0)
const FLASH_COLOR := Color(0.85, 0.88, 1.0)
## Enough to read through the storm's own dark wash, which is still drawn under
## it: at 0.45 a flash was barely a flicker over a 0.36 sky.
const FLASH_ALPHA := 0.6

## Drawn over the world, under the HUD.
const LAYER := 5

static var _streak_texture: ImageTexture

## How fast each sheet falls, in screen pixels per second.
const SPEED_NEAR := 330.0
const SPEED_FAR := 190.0

var _tint: ColorRect
var _flash: ColorRect
## One entry per sheet: {node, count, speed}. `_resize` needs the count and the
## speed again, so they are kept beside the node rather than written twice.
var _sheets: Array[Dictionary] = []
var _flash_timer: Timer
var _fade: Tween
var _kind := Weather.CLEAR


func _ready() -> void:
	layer = LAYER

	_tint = _wash(TINT)
	_tint.color.a = 0.0
	_sheet(COUNT_FAR, SCALE_FAR, SPEED_FAR, Color(0.78, 0.86, 1.0, 0.33))
	_sheet(COUNT_NEAR, SCALE_NEAR, SPEED_NEAR, Color(0.90, 0.95, 1.0, 0.62))
	# Over the drops: lightning lights the rain as well as the ground.
	_flash = _wash(FLASH_COLOR)
	_flash.color.a = 0.0

	_flash_timer = Timer.new()
	_flash_timer.one_shot = true
	_flash_timer.timeout.connect(_strike)
	add_child(_flash_timer)

	_resize(_screen())
	get_viewport().size_changed.connect(func() -> void: _resize(_screen()))
	Weather.changed.connect(set_kind)
	set_kind(Weather.today(), false)


## Puts the sky into `kind`. With `animate` off it is simply there, which is
## what a scene loading into a wet day wants.
func set_kind(kind: int, animate: bool = true) -> void:
	_kind = kind
	var wet := Weather.is_wet(kind)
	var alpha := 0.0
	if kind == Weather.STORM:
		alpha = TINT_ALPHA_STORM
	elif kind == Weather.RAIN:
		alpha = TINT_ALPHA_RAIN

	if _fade != null:
		_fade.kill()
	if animate:
		_fade = create_tween()
		_fade.tween_property(_tint, "color:a", alpha, FADE)
	else:
		_tint.color.a = alpha

	for entry in _sheets:
		var sheet: GPUParticles2D = entry["node"]
		if wet and not sheet.emitting:
			# Start with a skyful already falling rather than an empty screen
			# filling from the top.
			sheet.restart()
		sheet.emitting = wet

	_flash.color.a = 0.0
	if kind == Weather.STORM:
		_flash_timer.start(randf_range(FLASH_GAP.x, FLASH_GAP.y))
	else:
		_flash_timer.stop()


## What the sky is set to, for tests and debugging.
func kind() -> int:
	return _kind


func _screen() -> Vector2:
	return get_viewport().get_visible_rect().size


## Stretches the wash and the sheets over the window. The emitter sits above the
## top edge, wider than the window on both sides so the slant has a source.
func _resize(screen: Vector2) -> void:
	var width := screen.x + SIDE_BLEED * 2.0
	# A drop must survive the fall from above the top edge to past the bottom.
	var drop := screen.y + SPAWN_ABOVE * 2.0
	var crowd := clampf(screen.x * screen.y / REFERENCE_AREA, 0.5, 3.0)
	for entry in _sheets:
		var sheet: GPUParticles2D = entry["node"]
		var material := sheet.process_material as ParticleProcessMaterial
		material.emission_box_extents = Vector3(width * 0.5, 1.0, 0.0)
		sheet.position = Vector2(screen.x * 0.5, -SPAWN_ABOVE)
		# Long enough to clear the bottom of the window at this speed, with a
		# little over so nothing winks out on screen.
		sheet.lifetime = maxf(0.6, drop / float(entry["speed"]) * 1.25)
		sheet.amount = maxi(8, roundi(float(entry["count"]) * crowd))


## One sheet of rain: `count` drops at a reference window, drawn `scale_range`
## wide, falling at `speed`, in `tone`.
func _sheet(count: int, scale_range: Vector2, speed: float, tone: Color) -> GPUParticles2D:
	var material := ParticleProcessMaterial.new()
	material.particle_flag_disable_z = true
	# Turns each drop to point along its own velocity, which is what makes a
	# streak out of a bar and keeps the lean and the art in agreement without
	# an angle being worked out by hand.
	material.particle_flag_align_y = true
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.direction = Vector3(LEAN, 1.0, 0.0)
	material.spread = 0.0
	material.initial_velocity_min = speed * 0.85
	material.initial_velocity_max = speed * 1.15
	material.gravity = Vector3(LEAN * 120.0, 260.0, 0.0)
	material.scale_min = scale_range.x
	material.scale_max = scale_range.y
	material.color = tone

	var sheet := GPUParticles2D.new()
	sheet.process_material = material
	sheet.texture = _streak()
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sheet.amount = count
	sheet.lifetime = 1.4
	# Born mid-storm: without this the first second of rain is an empty sky.
	sheet.preprocess = 2.0
	sheet.randomness = 0.6
	sheet.emitting = false
	sheet.local_coords = false
	add_child(sheet)
	_sheets.append({"node": sheet, "count": count, "speed": speed})
	return sheet


## A full-screen wash of one colour, used for the overcast tint and the flash.
## A Control under a CanvasLayer anchors to the window, so this follows a
## resize on its own.
func _wash(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect


## One drop: a 1x6 bar of white-blue that fades out towards its tail, so a
## scaled-up streak has a head and does not read as a hard domino.
static func _streak() -> ImageTexture:
	if _streak_texture != null:
		return _streak_texture
	var height := 6
	var image := Image.create(1, height, false, Image.FORMAT_RGBA8)
	for y in height:
		# Brightest at the head (the bottom, the way it falls), thinning behind.
		var along := float(y) / float(height - 1)
		image.set_pixel(0, y, Color(0.88, 0.94, 1.0, lerpf(0.15, 1.0, along)))
	_streak_texture = ImageTexture.create_from_image(image)
	return _streak_texture


## Lightning: a quick double blink, then the next one is booked. The world
## flashes, not the HUD, because this layer sits under it.
func _strike() -> void:
	if _kind != Weather.STORM:
		return
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", FLASH_ALPHA, 0.04)
	tween.tween_property(_flash, "color:a", 0.0, 0.10)
	tween.tween_property(_flash, "color:a", FLASH_ALPHA * 0.7, 0.05).set_delay(0.06)
	tween.tween_property(_flash, "color:a", 0.0, 0.35)
	_flash_timer.start(randf_range(FLASH_GAP.x, FLASH_GAP.y))
