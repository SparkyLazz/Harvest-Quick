@tool
class_name AreaExit
extends Node2D

## A spot that takes the player somewhere else.
##
## Stand on it and the screen goes dark, the player is set down at [member
## arrival], and it comes back. The walk is not simulated and nothing is
## loaded — on one map this is a teleport with a curtain drawn over it, which
## is all a Harvest Moon doorway ever was.
##
## It is a rectangle of tiles tested against the player's position rather than
## an [Area2D], for two reasons. The doorway is tile-shaped and the rest of
## this game thinks in tiles, so a span in tiles is the natural way to say how
## wide a path's mouth is. And an [Area2D] would announce the player arriving
## inside the exit at the far end as though they had just walked into it,
## which is a loop — see [method resync], which is how this avoids it instead.
##
## The arrival is best put a tile or two clear of the exit at the other end,
## so walking back the way you came is what returns you rather than something
## that happens the instant you land.

## Emitted when the player has gone through, once the screen is clear again.
signal travelled

## Where the player comes out. Any [Node2D] — a [Marker2D] is the tidy choice.
@export var arrival: NodePath

## How wide and deep the doorway is, in tiles, centred on this node.
@export var span: Vector2i = Vector2i(4, 1):
	set(value):
		span = Vector2i(maxi(value.x, 1), maxi(value.y, 1))
		queue_redraw()

## Which way the player faces on arriving. One of the facings the player's
## sheet is filed under: down, up, left or right.
@export_enum("down", "up", "left", "right") var facing: String = "down"

## Turns the doorway off without removing it.
@export var enabled: bool = true

## Pixels to a tile. Only used to turn [member span] into a rectangle, and
## only when the map cannot be asked.
const CELL: float = 16.0

## Whether the player was inside the doorway last time it was looked at.
## Travel happens on the step *in*, so standing still on an exit does not keep
## firing it.
var _inside: bool = false
var _player: Node2D

func _ready() -> void:
	add_to_group("area_exits")
	if Engine.is_editor_hint():
		return
	set_process(true)

func _process(_delta: float) -> void:
	if Engine.is_editor_hint() or not enabled:
		return
	var player := _find_player()
	if player == null:
		return
	var here := rect().has_point(player.global_position)
	if here and not _inside:
		_inside = true
		_travel(player)
	elif not here:
		_inside = false

## The ground this doorway covers, in global space.
func rect() -> Rect2:
	var size := Vector2(span) * CELL
	return Rect2(global_position - size * 0.5, size)

## Takes note of where the player is without acting on it.
##
## Called on every exit the moment the player is set down somewhere new. The
## player may well have landed inside an exit — the one at the far end of the
## path they just walked — and without this that would read as them stepping
## into it, which would send them straight back, and back again, for ever.
func resync() -> void:
	var player := _find_player()
	_inside = player != null and rect().has_point(player.global_position)

func _travel(player: Node2D) -> void:
	var to := get_node_or_null(arrival) as Node2D
	if to == null:
		push_warning("AreaExit at %s has no arrival set." % global_position)
		return
	var curtain := get_tree().get_first_node_in_group("transition") as ScreenTransition
	if curtain == null or curtain.is_busy():
		return

	# Held still for the whole crossing, so a key still down when the screen
	# goes dark does not walk them out of the arrival before they can see it.
	if player.has_method("set_frozen"):
		player.set_frozen(true)
	await curtain.cross(_arrive.bind(player, to.global_position))
	if player.has_method("set_frozen"):
		player.set_frozen(false)
	travelled.emit()

## Sets the player down at [param at]. Runs while the screen is black.
func _arrive(player: Node2D, at: Vector2) -> void:
	player.global_position = at
	if player.has_method("face"):
		player.face(facing)
	# The camera leads the player by a smoothed lag, so without this it
	# travels the whole map on its own while the screen is clearing — the
	# player would arrive and then watch the ground slide under them.
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.reset_smoothing()
	for exit in get_tree().get_nodes_in_group("area_exits"):
		(exit as AreaExit).resync()

func _find_player() -> Node2D:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

## Drawn in the editor only, so a doorway can be placed by eye.
func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var size := Vector2(span) * CELL
	var r := Rect2(-size * 0.5, size)
	draw_rect(r, Color(0.4, 0.9, 1.0, 0.25))
	draw_rect(r, Color(0.4, 0.9, 1.0, 0.9), false, 1.0)
