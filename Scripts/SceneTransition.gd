extends CanvasLayer

## Screen fade for moving between scenes, the way stepping into a building works
## in Harvest Moon: the picture goes to black, the world is swapped underneath,
## and it comes back up somewhere else.
##
##   SceneTransition.go_to("res://Scenes/PlayerHouse.tscn", &"FrontDoor")
##
## Registered as an autoload, so the black it draws outlives the scene it was
## called from -- a fade owned by the departing scene would be freed halfway
## through, and the swap would show as a hard cut.
##
## The tree is paused for the whole move so nothing walks on while the screen is
## black. This node and its tween both ignore that pause, so the fade still
## runs; everything else is held still.

## Emitted once the new scene is up and the picture is back.
signal arrived

const FADE_OUT := 0.3
const FADE_IN := 0.3

var _shade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shade = ColorRect.new()
	_shade.name = "Shade"
	_shade.color = Color.BLACK
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.modulate.a = 0.0
	_shade.visible = false
	add_child(_shade)


## True while a fade is running; anything that starts one should wait.
func is_busy() -> bool:
	return _busy


## Fades out, swaps to `scene_path`, stands the player on the Marker2D named
## `spawn_point` if the destination has one, then fades back in. Calls made
## while a move is already running are ignored, so two doors cannot fight.
##
## `during` runs once the screen is black and before the old scene goes, so
## anything listening in the scene being left still hears it -- passing out on
## the farm sleeps the night through while the crops can still grow.
func go_to(scene_path: String, spawn_point: StringName = &"",
		during: Callable = Callable()) -> void:
	if _busy:
		return
	_busy = true
	var tree := get_tree()
	tree.paused = true

	await _fade_to(1.0, FADE_OUT)
	if during.is_valid():
		during.call()

	if tree.change_scene_to_file(scene_path) != OK:
		push_error("SceneTransition: could not load '%s'." % scene_path)
		tree.paused = false
		await _fade_to(0.0, FADE_IN)
		_busy = false
		return

	# The swap is deferred to the end of the frame, so the new tree is only
	# there to be adjusted on the frame after that.
	await tree.process_frame
	await tree.process_frame
	_place_player(spawn_point)

	tree.paused = false
	await _fade_to(0.0, FADE_IN)
	_busy = false
	arrived.emit()


## Fades out, runs `during`, waits a beat, then fades back in -- for things
## that happen between one blink and the next, like sleeping the night through.
## The scene stays where it is; only the picture goes away.
func fade_through(during: Callable, hold: float = 0.35) -> void:
	if _busy:
		return
	_busy = true
	var tree := get_tree()
	tree.paused = true
	await _fade_to(1.0, FADE_OUT)
	if during.is_valid():
		during.call()
	await _hold(hold)
	tree.paused = false
	await _fade_to(0.0, FADE_IN)
	_busy = false
	arrived.emit()


func _hold(seconds: float) -> void:
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(seconds)
	await tween.finished


func _fade_to(alpha: float, seconds: float) -> void:
	_shade.visible = true
	var tween := create_tween()
	# Without this the tween is held by the same pause it is covering for.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_shade, "modulate:a", alpha, seconds)
	await tween.finished
	_shade.visible = alpha > 0.0


func _place_player(spawn_point: StringName) -> void:
	if spawn_point.is_empty():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var marker := scene.find_child(String(spawn_point), true, false) as Node2D
	if marker == null:
		push_warning("SceneTransition: no spawn point '%s' in %s." % [spawn_point, scene.name])
		return
	var player := scene.find_child("Player", true, false) as Node2D
	if player == null:
		return
	player.global_position = marker.global_position
	# The camera eases towards the player, so left alone it sweeps in across the
	# whole room from wherever it happened to start.
	var camera := player.find_child("Camera2D", true, false) as Camera2D
	if camera != null:
		camera.reset_smoothing()
