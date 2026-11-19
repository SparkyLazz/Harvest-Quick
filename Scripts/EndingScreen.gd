extends CanvasLayer

## How the game ends, either way.
##
## An autoload, like the fade, because the ending outlives whatever scene the
## player was in when it landed -- the third strike is settled while they are
## asleep, so the screen is already black and the scene underneath is about to
## be swapped. It draws above the fade (layer 200) and ignores the pause, so it
## is the last thing standing.
##
## There is only one way out of it: a new game. The save is not touched -- a
## lost game stays lost on disk, and loading it brings this screen straight
## back, which is why `_ready` checks the flag as well as the signal.
##
## Two endings so far. **Bad**: three missed payments and the farm is gone.
## **Good**: the lawyer is paid, the debt is void and Mom cannot use your name
## again. The neutral one -- surviving two years without him -- is still open
## (`Docs/GAME_DESIGN.md` §5).
##
## They are the same screen with different words, which is deliberate: an
## ending is an ending, and the only difference the player should feel is what
## it says. The good one is not a fanfare, because the story does not have one
## in it.

const PANEL_BOX := preload("res://Assets/UI/Panel_Plate.tres")
const BUTTON_TEXTURE := preload("res://Assets/UI/Panel_Plate_Dark.png")

const INK := UISkin.TEXT_COLOR
const MUTED := UISkin.MUTED_COLOR

const BASE_SIZE := Vector2(252, 170)
const MAX_FILL := 0.82
## Black, not the windows' warm wash: nothing of the farm should show through.
const BACKDROP := Color(0.04, 0.03, 0.04, 1.0)

const LOST_TITLE := "THE FARM IS GONE"
const LOST_LINES: Array[String] = [
	"THREE PAYMENTS MISSED.",
	"THE COLLECTOR TOOK THE FARM",
	"TO SETTLE WHAT YOUR MOTHER",
	"BORROWED IN YOUR NAME.",
]

const WON_TITLE := "YOUR NAME IS YOUR OWN"
const WON_LINES: Array[String] = [
	"THE LAWYER FILED IT ALL:",
	"HER LETTERS, THEIR WORD, HIS COPY.",
	"THE DEBT IS VOID. SHE CANNOT",
	"SIGN AS YOU AGAIN.",
	"THE FARM IS STILL HERE.",
	"SO ARE YOU.",
]

## Drawn over the scene fade, which is 128.
const LAYER := 200

var _root: Control
var _backdrop: ColorRect
var _window: PanelContainer
var _title: Label
var _lines: VBoxContainer
var _summary: Label


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	get_viewport().size_changed.connect(_recenter)
	# Deferred for the same reason Debt's binding is: PlayerState reads the
	# save in its own `_ready`, and this autoload comes after it, so a game
	# that was already lost has to be noticed a frame later.
	_bind.call_deferred()


func _bind() -> void:
	Debt.lost.connect(_on_lost)
	Lawyer.hired.connect(_on_won)
	# A game that was already over when the save loaded ends again, at once.
	# Winning is checked first: a farm lost after the lawyer cannot happen,
	# but a flag read off disk should not have to be trusted about that.
	if Lawyer.is_hired:
		_on_won()
	elif Debt.lost_farm:
		_on_lost()


func is_open() -> bool:
	return visible


func _on_lost() -> void:
	_show(LOST_TITLE, LOST_LINES, "WEEK %d   OWED %d" % [Debt.week, Debt.balance])


func _on_won() -> void:
	_show(WON_TITLE, WON_LINES, "WEEK %d   DEBT VOID" % Debt.week)


## Puts one of the two endings up and holds the game there.
func _show(title: String, lines: Array[String], summary: String) -> void:
	_title.text = title
	for child in _lines.get_children():
		_lines.remove_child(child)
		child.queue_free()
	for line in lines:
		_lines.add_child(_label(line, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_summary.text = summary
	visible = true
	_recenter()
	# The third strike is settled behind a fade (the player was asleep), and
	# that fade unpauses the tree when it finishes. Pausing before then would
	# simply be undone, so this waits the move out first.
	while SceneTransition.is_busy():
		await get_tree().process_frame
	get_tree().paused = true


## Starts over. The tree has to come back first: `new_game` fades to the
## opening scene, and a paused tree would hold the fade halfway.
func _on_new_game() -> void:
	visible = false
	get_tree().paused = false
	PlayerState.new_game()


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP
	# STOP: nothing behind this screen may be clicked.
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	_window = PanelContainer.new()
	_window.add_theme_stylebox_override("panel", PANEL_BOX)
	_window.custom_minimum_size = BASE_SIZE
	_window.size = BASE_SIZE
	_root.add_child(_window)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_window.add_child(box)

	_title = _label("", INK, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(_title)
	var rule := ColorRect.new()
	rule.color = UISkin.RULE_COLOR
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	# Hand-broken rather than wrapped: the face is 5px capitals and a label
	# only shapes its text once it is on screen, so a wrap worked out at build
	# time comes up a line short (ProfilePanel found this the hard way). The
	# lines are filled in by `_show`, since the two endings have different
	# numbers of them.
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	box.add_child(_lines)
	_summary = _label("", INK, HORIZONTAL_ALIGNMENT_CENTER)
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_summary)

	var again := Button.new()
	again.text = "NEW GAME"
	again.focus_mode = Control.FOCUS_NONE
	again.custom_minimum_size.y = 19
	again.add_theme_font_override("font", UIFont.title())
	again.add_theme_font_size_override("font_size", UIFont.SIZE)
	for role: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		again.add_theme_color_override(role, INK)
	var shades := {"normal": Color.WHITE, "hover": Color(1.07, 1.07, 1.07),
			"pressed": Color(0.9, 0.9, 0.9)}
	for state: String in shades:
		var style := UISkin.sliced(BUTTON_TEXTURE, 6, 4, 4)
		style.modulate_color = shades[state]
		again.add_theme_stylebox_override(state, style)
	again.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	again.pressed.connect(_on_new_game)
	box.add_child(again)


func _label(text: String, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.add_theme_font_override("font", UIFont.body())
	label.add_theme_font_size_override("font_size", UIFont.SIZE)
	label.add_theme_color_override("font_color", color)
	return label


func _recenter() -> void:
	if _root == null:
		return
	var screen := get_viewport().get_visible_rect().size
	_root.position = Vector2.ZERO
	_root.size = screen
	_backdrop.position = Vector2.ZERO
	_backdrop.size = screen
	var zoom := 2
	var room := screen * MAX_FILL
	while zoom > 1 and (BASE_SIZE.x * zoom > room.x or BASE_SIZE.y * zoom > room.y):
		zoom -= 1
	_window.scale = Vector2.ONE * zoom
	_window.size = BASE_SIZE
	_window.position = ((screen - BASE_SIZE * zoom) * 0.5).round()
