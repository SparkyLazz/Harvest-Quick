class_name HudButton
extends Control

## One of the little buttons stacked under the weather panel.
##
## They go in that column because it is already where the farm's standing
## information lives — what the weather is, how warm it is, what day it is — and
## what the merchant is charging, or what the town is saying, is the same kind of
## fact. Buttons floating anywhere else would be more things to look at.
##
## There is nothing shop-shaped or paper-shaped left in here: a button is an icon
## and a window it opens, and the two the farm has differ only by those. Anything
## that knows which is which would have to be written twice.
##
## It keeps the column's manners — the transient HUD the rest of this interface
## follows. Idle is the resting state, because the column sits over the farm and
## a permanently bright button is a permanent hole in the view. It brightens on
## hover, while its window is open, and for a moment when [member notice_on_day]
## says the day has turned and there is something new to read.

## Emitted when it is pressed, after the window has been told.
signal pressed

@export_group("Look")
@export var buttons: Texture2D
## The cell on the button sheet, unpressed and pressed. The sheet is six columns
## of 32-pixel cells in pairs: the even column is the raised face, the odd one
## the same face pushed in.
@export var icon: Rect2 = Rect2(64, 320, 32, 32)
@export var icon_pressed: Rect2 = Rect2(96, 320, 32, 32)
@export var tooltip: String = ""

@export_group("Wiring")
## The window this opens. Left empty, the button finds the first panel of
## [member panel_type] in the scene, so moving the HUD about does not leave a
## stale path behind.
@export var panel_path: NodePath
## Which window to look for when [member panel_path] is empty: "ShopPanel" or
## "NewsPanel".
@export var panel_type: StringName = &"ShopPanel"

@export_group("Fading")
## What it sits at when nothing is happening.
@export_range(0.0, 1.0, 0.01) var idle_alpha: float = 0.45
@export var fade_time: float = 0.25
## Whether a new day is worth brightening for. True for the merchant, who only
## comes in the morning; a paper that flares every dawn is just a flashing light.
@export var notice_on_day: bool = true
## How long it stays bright after that.
@export var notice_time: float = 2.5

var _icon: TextureRect
var _panel: TwoPagePanel
var _fade: Tween

func _ready() -> void:
	_build()
	modulate.a = idle_alpha
	_panel = get_node_or_null(panel_path) as TwoPagePanel
	if _panel == null:
		_panel = _find_panel()
	if _panel != null:
		_panel.opened.connect(func() -> void: _to(1.0))
		_panel.closed.connect(func() -> void: _to(idle_alpha))
	var run := get_tree().get_first_node_in_group("run")
	if run != null and notice_on_day:
		run.day_began.connect(func(_d: int) -> void: _notice())

func _build() -> void:
	_icon = TextureRect.new()
	_icon.texture = _atlas(icon)
	_icon.custom_minimum_size = Vector2(32, 32)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_icon.gui_input.connect(_on_input)
	_icon.mouse_entered.connect(func() -> void: _to(1.0))
	_icon.mouse_exited.connect(func() -> void:
		if _panel == null or not _panel.is_open():
			_to(idle_alpha))
	_icon.tooltip_text = tooltip
	add_child(_icon)
	custom_minimum_size = Vector2(32, 32)

func _on_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT:
		return
	# The pressed face goes on as it goes down and comes off as it comes up, and
	# the press only counts on the way up — so a click dragged off the button
	# still looks like it was let go, and does not fire.
	_icon.texture = _atlas(icon_pressed if button.pressed else icon)
	if button.pressed:
		return
	activate()

## Opens or shuts this button's window. Separate from the click so that anything
## else — a key, a probe — can do what the button does without inventing a mouse.
func activate() -> void:
	pressed.emit()
	if _panel == null:
		return
	# Its sibling may be the one showing, and two windows open at once over the
	# same middle of the screen is one too many.
	var other := _panel.get_node_or_null(_panel.sibling) as TwoPagePanel
	if other != null and other.is_open():
		other.close()
	_panel.toggle()

## Brightens for a moment, because the day has turned.
func _notice() -> void:
	_to(1.0)
	var timer := get_tree().create_timer(notice_time)
	await timer.timeout
	if is_inside_tree() and (_panel == null or not _panel.is_open()):
		_to(idle_alpha)

func _to(alpha: float) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(self, "modulate:a", alpha, fade_time)

func _find_panel() -> TwoPagePanel:
	var stack: Array[Node] = [get_tree().current_scene]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var panel := node as TwoPagePanel
		if panel != null and panel.get_script() != null \
				and panel.get_script().get_global_name() == panel_type:
			return panel
		stack.append_array(node.get_children())
	return null

func _atlas(region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = buttons
	atlas.region = region
	atlas.filter_clip = true
	return atlas
