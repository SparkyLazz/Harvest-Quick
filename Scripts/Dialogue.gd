extends Node

## Who is talking and what is left to say.
##
## An autoload, so anything anywhere can start a conversation without knowing
## where the box is drawn: `Dialogue.say("THE NEIGHBOUR", ["...", "..."])`. The
## box (`DialogueBox`, owned by the HUD) listens and draws it; this script
## holds no pixels and no node paths.
##
## A conversation is a list of lines said one after another. `advance()` moves
## on, and the box calls it when the player presses on. Starting a new one
## while another is up replaces it -- the last speaker wins -- rather than
## queueing, because the only things that interrupt here are the player's own
## actions.
##
## Nothing branches yet. There are no choices, no portraits that change mood
## and no conditions inside a conversation: what an NPC says is picked *before*
## the conversation starts, by whoever calls `say` (`Townsfolk.gd` does it from
## the state of the debt, the day and the weather). That covers every
## conversation step 5 needs, and leaves the shape of a branching tree to be
## decided when something actually needs one.

## A conversation has started. `speaker` is the name shown over the box.
signal started(speaker: String, portrait: Texture2D, tint: Color)
## A new line is on screen.
signal line_shown(line: String, index: int, total: int)
## The last line has been dismissed.
signal finished

## Who is speaking, "" when nobody is.
var speaker := ""
## The face to show in the frame beside the box, null for an empty frame, and
## the colour to draw it in. Everyone is the same cat at the moment, so the
## tint is what tells one speaker's portrait from another's -- the same
## stand-in their sprites in the world use.
var portrait: Texture2D = null
var portrait_tint := Color.WHITE
## The lines of the conversation running now.
var lines: Array[String] = []
## Which line is on screen, -1 when none is.
var index := -1


## True while there is a conversation on screen.
func is_talking() -> bool:
	return index >= 0


## Starts a conversation. An empty `what` says nothing at all, which is what a
## caller with nothing to say should pass rather than a blank line.
func say(who: String, what: Array, face: Texture2D = null,
		face_tint: Color = Color.WHITE) -> void:
	var said: Array[String] = []
	for line in what:
		var text := str(line).strip_edges()
		if not text.is_empty():
			said.append(text)
	if said.is_empty():
		stop()
		return
	speaker = who
	portrait = face
	portrait_tint = face_tint
	lines = said
	index = 0
	started.emit(speaker, portrait, portrait_tint)
	line_shown.emit(lines[0], 0, lines.size())


## Moves to the next line, or ends the conversation after the last one.
## Returns true while there is still something on screen.
func advance() -> bool:
	if not is_talking():
		return false
	index += 1
	if index >= lines.size():
		stop()
		return false
	line_shown.emit(lines[index], index, lines.size())
	return true


## Ends whatever is being said now.
func stop() -> void:
	if not is_talking():
		return
	speaker = ""
	portrait = null
	portrait_tint = Color.WHITE
	lines = []
	index = -1
	finished.emit()


## The line on screen, "" when nothing is.
func current_line() -> String:
	return lines[index] if is_talking() else ""
