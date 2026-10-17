class_name UISkin
extends RefCounted

## The shared look of the game's windows: the palette, the sliced plates, and
## the scrollbar.
##
## This started inside ProfilePanel, which was the only window for a while. The
## storage window needs the same scrollbar and the same ink, and two copies of a
## scrollbar is how two scrollbars end up looking subtly different. ProfilePanel
## still calls everything by its old names; the definitions just live here now.
##
## Everything is static -- there is no skin to instance, only numbers that every
## panel has to agree on.

const SCROLL_TEXTURE := preload("res://Assets/UI/Scrollbar.png")

const TEXT_COLOR := Color("5a3d3d")
const MUTED_COLOR := Color("90625d")
const SHORT_COLOR := Color("b5513f")
const RULE_COLOR := Color("c9a376")

## Width of the scrollbar, from its art. The sliced boxes carry no minimum of
## their own, so whoever builds a scroll area has to say this.
const SCROLLBAR_WIDTH := 11


## A plate that stretches: the corners stay put while the edges and middle grow.
## `edge` is how much of the texture is border; `pad` is the space inside it.
static func sliced(texture: Texture2D, edge: int, pad_x: int, pad_y: int) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = edge
	box.texture_margin_right = edge
	box.texture_margin_top = edge
	box.texture_margin_bottom = edge
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


## The scrollbar. A vertical bar only ever stretches along its length, so the
## margins that matter are the top and bottom ones, and they are not the same
## number: both the track and the grabber are drawn with a deeper shadow under
## them than highlight above.
##
## Measured off the art rather than guessed (rows that repeat = the stretchable
## middle):
##   grabber 11x21  middle rows 4..14  -> cap 4 above, 6 below
##   track    7x40  middle rows 4..37  -> cap 4 above, 2 below
## The track's 7px art sits centred in an 11px cell, which is why its side
## margin is 5 and not 3 -- it covers the empty columns as well.
static func scroll_theme() -> Theme:
	var theme := Theme.new()
	var track := func() -> StyleBoxTexture:
		return scroll_part(Rect2(33, 0, 11, 40), 5, 4, 2)
	var grabber := func(x: int) -> StyleBoxTexture:
		return scroll_part(Rect2(x, 0, 11, 21), 4, 4, 6)
	theme.set_stylebox("scroll", "VScrollBar", track.call())
	theme.set_stylebox("scroll_focus", "VScrollBar", track.call())
	theme.set_stylebox("grabber", "VScrollBar", grabber.call(11))
	theme.set_stylebox("grabber_highlight", "VScrollBar", grabber.call(22))
	theme.set_stylebox("grabber_pressed", "VScrollBar", grabber.call(0))
	return theme


static func scroll_part(region: Rect2, side: int, top: int, bottom: int) -> StyleBoxTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = SCROLL_TEXTURE
	atlas.region = region
	var box := StyleBoxTexture.new()
	box.texture = atlas
	box.texture_margin_left = side
	box.texture_margin_right = side
	box.texture_margin_top = top
	box.texture_margin_bottom = bottom
	box.content_margin_left = 0
	box.content_margin_right = 0
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	return box
