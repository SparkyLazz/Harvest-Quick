class_name StatusSign
extends Control

## The hanging sign in the top-right corner: hearts on a wide plate, and the
## purse on a smaller plate hung under it on two posts. It is the pack's own
## design for health and money (UI Sprites/ALL UI ASSETS on one sheet.png),
## cut into parts by Tools/cut_status.py so it can be built for any number of
## hearts and any amount -- the plates are nine-sliced, the rest is placed by
## the measurements below, taken off the pack's own sign.
##
## It mirrors the clock in the opposite corner: the same margin, the HUD's
## zoom, and the game's one face for the amount. The coin hops whenever the
## amount changes -- the morning the bin pays out, a packet bought at the stall.
##
## Everything is drawn in one _draw, through this one node's transform, and
## that is what keeps the posts joined to the plates at a window size that
## scales the UI by a fraction: a shared edge goes through the same arithmetic
## and lands on the same screen pixel. Separate nodes each round their own
## position, which is how the clock's layers came apart (the thermometer seam,
## TECH_NOTES) -- keep this sign one node. Tools/test_clock_seams.gd checks it,
## and was seen to fail on a deliberate one-pixel gap.

const ATLAS := preload("res://Assets/UI/Status.png")
const TOP_PLATE := Rect2(0, 0, 71, 31)
const LOW_PLATE := Rect2(0, 32, 41, 20)
const POST := Rect2(44, 32, 3, 3)
const HEART_FULL := Rect2(0, 53, 19, 17)
const HEART_HALF := Rect2(20, 53, 19, 17)
const HEART_EMPTY := Rect2(40, 53, 19, 17)

## Measured off the pack's sign, in its own pixels.
## The first heart's corner in the top plate, and from one heart to the next
## (19 of heart, 2 of gap); the plate keeps the same 5 either side.
const HEART_AT := Vector2(5, 6)
const HEART_STEP := 21
const TOP_HEIGHT := 31
## The posts hang between the plates, y 31 to 33: one 6 in from the lower
## plate's left edge, one 10 in from its right (so 31 on the pack's 41-wide one).
const POST_TOP := 31
const POST_LEFT := 6
const POST_RIGHT := 10
const LOW_TOP := 34
const LOW_HEIGHT := 20
const LOW_MIN_WIDTH := 41
## In the lower plate: the coin, and the amount after it, standing level with
## the coin's middle; the plate grows to the right for long amounts.
const COIN_AT := Vector2(5, 4)
const TEXT_X := 15
const TEXT_BASELINE := 11
const TEXT_PAD := 5
## Gap from the screen's top and right edges, in screen pixels, as the clock has.
const MARGIN := 10

## Whole-number zoom, set by the HUD to match its own.
var ui_scale := 2: set = set_ui_scale
## How many hearts the plate holds, and how many are full (halves allowed).
var hearts := 4: set = set_hearts
var health := 4.0: set = set_health

var _coins := 0
## The coin's hop: how much bigger than itself it is drawn right now.
var _hop := 0.0
var _top_box: StyleBoxTexture
var _low_box: StyleBoxTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_box = _plate(TOP_PLATE)
	_low_box = _plate(LOW_PLATE)
	_coins = PlayerState.coins
	PlayerState.coins_changed.connect(_on_coins_changed)
	get_viewport().size_changed.connect(_place)
	_layout()


## What the purse reads (for tests).
func amount_text() -> String:
	return str(_coins)


func set_ui_scale(value: int) -> void:
	ui_scale = clampi(value, 1, 8)
	_layout()


func set_hearts(value: int) -> void:
	hearts = maxi(value, 1)
	_layout()


func set_health(value: float) -> void:
	health = value
	queue_redraw()


## Which heart to draw in place `index` (from 0) for `health` hearts: full when
## health covers it entirely, half when it covers its first half, else empty.
## The profile screen's rail draws its hearts with this too, so the two agree.
static func heart_for(index: int, health_now: float) -> Rect2:
	if health_now >= index + 1:
		return HEART_FULL
	if health_now >= index + 0.5:
		return HEART_HALF
	return HEART_EMPTY


func _on_coins_changed(coins: int) -> void:
	_coins = coins
	_layout()
	create_tween().tween_method(_set_hop, 0.35, 0.0, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_hop(value: float) -> void:
	_hop = value
	queue_redraw()


func _top_width() -> int:
	return int(HEART_AT.x) * 2 + hearts * HEART_STEP - (HEART_STEP - int(HEART_FULL.size.x))


func _low_width() -> int:
	var text := UIFont.body().get_string_size(str(_coins), HORIZONTAL_ALIGNMENT_LEFT, -1, UIFont.SIZE).x
	return maxi(LOW_MIN_WIDTH, TEXT_X + int(text) + TEXT_PAD)


## Sizes the sign to what it holds and stands it in its corner.
func _layout() -> void:
	if not is_inside_tree():
		return
	size = Vector2(maxi(_top_width(), _low_width()), LOW_TOP + LOW_HEIGHT)
	_place()
	queue_redraw()


## Top-right, MARGIN in from both edges at any window size. It grows from its
## own top-left, so its position is worked out from its scaled width.
func _place() -> void:
	scale = Vector2.ONE * ui_scale
	position = Vector2(get_viewport_rect().size.x - MARGIN - size.x * ui_scale, MARGIN).round()


func _draw() -> void:
	var low_w := _low_width()
	for x in [POST_LEFT, low_w - POST_RIGHT]:
		draw_texture_rect_region(ATLAS, Rect2(Vector2(x, POST_TOP), POST.size), POST)
	draw_style_box(_top_box, Rect2(0, 0, _top_width(), TOP_HEIGHT))
	draw_style_box(_low_box, Rect2(0, LOW_TOP, low_w, LOW_HEIGHT))
	for i in hearts:
		draw_texture_rect_region(ATLAS,
				Rect2(HEART_AT + Vector2(i * HEART_STEP, 0), HEART_FULL.size), heart_for(i, health))
	# The coin hops from its own middle.
	var coin := UISkin.COIN
	var centre := Vector2(0, LOW_TOP) + COIN_AT + coin.size * 0.5
	var drawn := coin.size * (1.0 + _hop)
	draw_texture_rect_region(UISkin.COINS, Rect2(centre - drawn * 0.5, drawn), coin)
	draw_string(UIFont.body(), Vector2(TEXT_X, LOW_TOP + TEXT_BASELINE), str(_coins),
			HORIZONTAL_ALIGNMENT_LEFT, -1, UIFont.SIZE, UISkin.TEXT_COLOR)


## A plate as a nine-slice box: the border is 3 round the top and sides and 5
## along the bottom (rim, shadow lip, outline); the flat face stretches.
func _plate(region: Rect2) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = ATLAS
	box.region_rect = region
	box.texture_margin_left = 3
	box.texture_margin_top = 3
	box.texture_margin_right = 3
	box.texture_margin_bottom = 5
	return box
