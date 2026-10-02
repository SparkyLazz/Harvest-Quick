class_name Season
extends RefCounted

## Which quarter of the year a day falls in.
##
## The year was already divided into four — [WeatherWidget] has been printing
## SPR.04 on its date plate since before any of this — but it was divided inside
## the widget, as a string for a label. A season nothing could ask about is a
## season that cannot stop a seed going in the ground, and now that it has to,
## the division belongs somewhere both the plate and the shop can reach.
##
## All static. There is nothing to remember: a season is a fact about a day
## number, the same way the day of the week is, and an object holding "it is
## currently autumn" would only be a second place for that to be wrong.

enum Of {
	SPRING,
	SUMMER,
	AUTUMN,
	WINTER,
}

## Days in one season. Four of these make the year.
const LENGTH: int = 28

## Short names, in [enum Of] order, for the date plate.
const SHORT: Array[String] = ["SPR", "SUM", "AUT", "WIN"]

## Full names, for anywhere with room to spell it.
const FULL: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]

## Which season [param day] falls in. Day 1 is the first day of spring.
static func of_day(day: int) -> Of:
	return ((maxi(day, 1) - 1) / LENGTH) % SHORT.size() as Of

## Which day of its own season [param day] is, counting from 1.
static func day_of(day: int) -> int:
	return (maxi(day, 1) - 1) % LENGTH + 1

## How many days are left in [param day]'s season, including today. What a shop
## wants, because a seed that takes ten days is no use with four of them left.
static func days_left(day: int) -> int:
	return LENGTH - day_of(day) + 1

## The date plate's reading of [param day], e.g. "SUM.14".
static func label(day: int) -> String:
	return "%s.%02d" % [SHORT[of_day(day)], day_of(day)]

## What a season is called.
static func name_of(season: Of) -> String:
	return FULL[season]

## The season after [param season]. Winter rolls round to spring.
static func after(season: Of) -> Of:
	return (season + 1) % FULL.size() as Of

## Turns a set of season flags — the bitmask [member CropData.seasons] keeps —
## into something readable, e.g. "Spring, Autumn" or "All year".
static func names_in_mask(mask: int) -> String:
	if mask == 0:
		return "Never"
	var all := (1 << FULL.size()) - 1
	if mask & all == all:
		return "All year"
	var out: Array[String] = []
	for i in FULL.size():
		if mask & (1 << i) != 0:
			out.append(FULL[i])
	return ", ".join(out)

## Whether [param season] is in the flags [param mask].
static func in_mask(mask: int, season: Of) -> bool:
	return mask & (1 << int(season)) != 0
