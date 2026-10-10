class_name UIFont
extends RefCounted

## The pack's pixel fonts, set up so they stay hard-edged. Both are drawn on a
## 7px grid and look right at SIZE; use that size rather than scaling the font.

const SIZE := 10

const _BODY := preload("res://Assets/Fonts/pixelFont-3-7x5-sproutLands.ttf")
const _TITLE := preload("res://Assets/Fonts/pixelFont-4-7x7-sproutLands.ttf")

static var _prepared := false

## Small, light capitals for descriptions.
static func body() -> FontFile:
	_prepare()
	return _BODY


## Heavier capitals for names, headings and stack counts.
static func title() -> FontFile:
	_prepare()
	return _TITLE


static func _prepare() -> void:
	if _prepared:
		return
	_prepared = true
	for font in [_BODY, _TITLE]:
		font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
