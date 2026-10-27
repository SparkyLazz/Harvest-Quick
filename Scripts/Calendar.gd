class_name Calendar
extends RefCounted

## How a day number and a clock reading are said out loud. The calendar is
## Stardew's: four seasons of 28 days, seven-day weeks, and day 1 is Monday the
## 1st of Spring, year 1.
##
## The clock counts minutes since midnight of the day the player woke on, so it
## runs past 24:00 into the small hours rather than wrapping: 25:30 is half past
## one that same night. The day starts at DAY_START, and at PASS_OUT the player
## drops wherever they stand.

const DAYS_PER_SEASON := 28
const DAYS_PER_WEEK := 7
const SEASONS: Array[String] = ["Spring", "Summer", "Fall", "Winter"]
const WEEKDAYS: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

## 6:00 in the morning.
const DAY_START := 6 * 60
## 2:00 the next morning.
const PASS_OUT := 26 * 60
## The clock moves in steps this size, so it reads 6:00, 6:10, 6:20...
const STEP := 10
## Real seconds per game minute. 0.7 gives Stardew's 7 seconds per 10 minutes,
## so a whole day from 6:00 to 2:00 is about 14 real minutes.
const SECONDS_PER_MINUTE := 0.7


## 0 for Spring through 3 for Winter.
static func season_index(day: int) -> int:
	return ((day - 1) / DAYS_PER_SEASON) % SEASONS.size()


static func season(day: int) -> String:
	return SEASONS[season_index(day)]


## 1 to 28.
static func day_of_season(day: int) -> int:
	return (day - 1) % DAYS_PER_SEASON + 1


static func year(day: int) -> int:
	return (day - 1) / (DAYS_PER_SEASON * SEASONS.size()) + 1


static func weekday(day: int) -> String:
	return WEEKDAYS[(day - 1) % DAYS_PER_WEEK]


## Counted from 1, across seasons and years. The debt collector's weeks.
static func week(day: int) -> int:
	return (day - 1) / DAYS_PER_WEEK + 1


## "Mon 1", for the clock plate. The season is shown beside it.
static func date_text(day: int) -> String:
	return "%s %d" % [weekday(day), day_of_season(day)]


## "6:00 am", "12:30 pm", "1:50 am". Shown in STEP-minute steps.
static func time_text(minutes: int) -> String:
	var shown := minutes - minutes % STEP
	var hour := (shown / 60) % 24
	var half := "am" if hour < 12 else "pm"
	var face := hour % 12
	if face == 0:
		face = 12
	return "%d:%02d %s" % [face, shown % 60, half]
