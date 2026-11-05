class_name UIFont
extends RefCounted

## The pack's pixel fonts, set up so they stay hard-edged. Body and title are
## drawn on a 7px grid and look right at SIZE; the small face is drawn on a 5px
## grid and looks right at SMALL_SIZE. Use those sizes rather than scaling.

const SIZE := 10
## Where the 5px face lands every stroke on a whole pixel. Measured, not
## derived: at 10 it already starts doubling some strokes and not others.
const SMALL_SIZE := 8

const _BODY := preload("res://Assets/Fonts/pixelFont-3-7x5-sproutLands.ttf")
const _TITLE := preload("res://Assets/Fonts/pixelFont-4-7x7-sproutLands.ttf")
const _SMALL := preload("res://Assets/Fonts/pixelFont-2-5x5-sproutLands.ttf")

static var _prepared := false

## Small, light capitals for descriptions.
static func body() -> FontFile:
	_prepare()
	return _BODY


## Heavier capitals for names, headings and stack counts.
static func title() -> FontFile:
	_prepare()
	return _TITLE


## Tiny, light capitals for tight spots, like the clock's date plate.
static func small() -> FontFile:
	_prepare()
	return _SMALL


static func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	for font in [_BODY, _TITLE, _SMALL]:
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
