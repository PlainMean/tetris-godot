extends Node2D
# ============================================================
#  Tetris (Godot 4) - classic, single-file implementation
#  Board: 10 columns x 20 rows. Rendering done in _draw(),
#  fixed timestep gravity, standard 7-bag, ghost piece,
#  hold piece, next queue, score/level/lines.
# ============================================================

const COLS := 10
const ROWS := 20
const CELL := 30
const BOARD_X := 30
const BOARD_Y := 55

# Standard tetromino definitions (cell offsets). Rotation handled via
# 90-degree matrix rotation of the offsets around the shape's pivot.
const SHAPES := {
	"I":  { "cells": [Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(3,1)], "color": Color(0.2, 0.85, 0.9) },   # cyan
	"O":  { "cells": [Vector2i(1,0), Vector2i(2,0), Vector2i(1,1), Vector2i(2,1)], "color": Color(0.95, 0.9, 0.2) },  # yellow
	"T":  { "cells": [Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)], "color": Color(0.75, 0.35, 0.9) }, # purple
	"S":  { "cells": [Vector2i(1,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1)], "color": Color(0.3, 0.9, 0.4) },    # green
	"Z":  { "cells": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(2,1)], "color": Color(0.95, 0.3, 0.3) },  # red
	"J":  { "cells": [Vector2i(0,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)], "color": Color(0.35, 0.5, 0.95) }, # blue
	"L":  { "cells": [Vector2i(2,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)], "color": Color(0.95, 0.6, 0.2) },  # orange
}
const SHAPE_NAMES := ["I", "O", "T", "S", "Z", "J", "L"]

# --- game state ---
var board: Array = []          # 2D array [row][col] of Color or null
var bag: Array = []            # shuffled piece queue
var current: Dictionary = {}   # {type, cells, color, pos}
var hold_type: String = ""
var can_hold := true
var next_queue: Array = []     # upcoming types
var score := 0
var lines := 0
var level := 1
var gravity_acc := 0.0
var game_over := false
var started := false
var paused := false

var font: Font = null

# gravity in seconds per row at level 1
const BASE_GRAVITY := 0.8

func _ready() -> void:
	font = _default_font()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_input()
	_clear_board()
	_new_bag()
	_spawn_piece()


func _default_font() -> Font:
	var c := Control.new()
	var f: Font = c.get_theme_default_font()
	c.free()
	return f


func _register_input() -> void:
	_add_action("move_left", [KEY_LEFT, KEY_A])
	_add_action("move_right", [KEY_RIGHT, KEY_D])
	_add_action("soft_drop", [KEY_DOWN, KEY_S])
	_add_action("hard_drop", [KEY_SPACE])
	_add_action("rotate_cw", [KEY_UP, KEY_W, KEY_X])
	_add_action("rotate_ccw", [KEY_Z])
	_add_action("hold", [KEY_C, KEY_SHIFT])
	_add_action("pause", [KEY_P])
	_add_action("restart", [KEY_R, KEY_ENTER])


func _add_action(name: String, keycodes: Array) -> void:
	if InputMap.has_action(name):
		return
	var evs := []
	for k in keycodes:
		var e := InputEventKey.new()
		e.physical_keycode = k
		evs.append(e)
	InputMap.add_action(name, 0.5)
	for e in evs:
		InputMap.action_add_event(name, e)


# ---------------- board helpers ----------------
func _clear_board() -> void:
	board = []
	for r in ROWS:
		var row := []
		for c in COLS:
			row.append(null)
		board.append(row)


func _new_bag() -> void:
	var b: Array = SHAPE_NAMES.duplicate()
	b.shuffle()
	bag.append_array(b)


func _peek_next() -> String:
	if bag.size() < 5:
		_new_bag()
	return bag[0]


func _take_next() -> String:
	while bag.is_empty():
		_new_bag()
	return bag.pop_front()


func _spawn_piece() -> void:
	var type := _take_next()
	# refill next queue to keep at least 3 shown
	while next_queue.size() < 3:
		next_queue.append(_peek_next())
		bag.pop_front()
	var info: Dictionary = SHAPES[type]
	current = {
		"type": type,
		"cells": info["cells"],
		"color": info["color"],
		"pos": Vector2i(3, 0),  # spawn column
	}
	if _collides(current["cells"], current["pos"]):
		game_over = true


func _rotated(cells: Array, dir: int) -> Array:
	# rotate 90deg around the piece's own pivot (cells as-is)
	var out: Array = []
	for v in cells:
		if dir > 0:
			var r := Vector2i(-v.y, v.x)
			out.append(r)
		else:
			var r := Vector2i(v.y, -v.x)
			out.append(r)
	return out


func _collides(cells: Array, pos: Vector2i) -> bool:
	for v in cells:
		var x: int = pos.x + v.x
		var y: int = pos.y + v.y
		if x < 0 or x >= COLS or y >= ROWS:
			return true
		if y >= 0 and board[y][x] != null:
			return true
	return false


func _try_move(dx: int, dy: int) -> bool:
	var np := Vector2i(current["pos"].x + dx, current["pos"].y + dy)
	if not _collides(current["cells"], np):
		current["pos"] = np
		return true
	return false


func _try_rotate(dir: int) -> void:
	var new_cells := _rotated(current["cells"], dir)
	# wall kicks: try offsets 0, -1, +1, -2, +2
	for kick in [0, -1, 1, -2, 2]:
		var p := Vector2i(current["pos"].x + kick, current["pos"].y)
		if not _collides(new_cells, p):
			current["cells"] = new_cells
			current["pos"] = p
			return


func _ghost_y() -> int:
	var y: int = current["pos"].y
	while not _collides(current["cells"], Vector2i(current["pos"].x, y + 1)):
		y += 1
	return y


func _lock_piece() -> void:
	for v in current["cells"]:
		var x: int = current["pos"].x + v.x
		var y: int = current["pos"].y + v.y
		if y < 0:
			game_over = true
			return
		board[y][x] = current["color"]
	_clear_lines()
	can_hold = true
	if not game_over:
		_spawn_piece()


func _clear_lines() -> void:
	var removed := 0
	var r := ROWS - 1
	while r >= 0:
		var full := true
		for c in COLS:
			if board[r][c] == null:
				full = false
				break
		if full:
			board.remove_at(r)
			board.push_front([])
			var empty: Array = []
			for c in COLS:
				empty.append(null)
			board[0] = empty
			removed += 1
		else:
			r -= 1
	if removed > 0:
		var pts := 0
		match removed:
			1: pts = 100
			2: pts = 300
			3: pts = 500
			4: pts = 800
		score += pts * level
		lines += removed
		level = lines / 10 + 1
		gravity_acc = 0.0


func _gravity_delta() -> float:
	return BASE_GRAVITY * pow(0.8, level - 1)


func _hard_drop() -> void:
	var gy: int = _ghost_y()
	var drop: int = gy - current["pos"].y
	current["pos"].y = gy
	score += drop * 2
	_lock_piece()


# ---------------- input ----------------
func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		if event.is_action_pressed("restart"):
			_restart()
		return
	if event.is_action_pressed("pause"):
		paused = not paused
		return
	if paused:
		return
	started = true
	if event.is_action_pressed("move_left"):
		_try_move(-1, 0)
	elif event.is_action_pressed("move_right"):
		_try_move(1, 0)
	elif event.is_action_pressed("soft_drop"):
		if _try_move(0, 1):
			score += 1
	elif event.is_action_pressed("hard_drop"):
		_hard_drop()
	elif event.is_action_pressed("rotate_cw"):
		_try_rotate(1)
	elif event.is_action_pressed("rotate_ccw"):
		_try_rotate(-1)
	elif event.is_action_pressed("hold"):
		_do_hold()
	queue_redraw()


func _do_hold() -> void:
	if not can_hold:
		return
	var cur_type: String = current["type"]
	var prev_hold := hold_type
	hold_type = cur_type
	can_hold = false
	if prev_hold == "":
		_spawn_piece()
	else:
		var info: Dictionary = SHAPES[prev_hold]
		current = {
			"type": prev_hold,
			"cells": info["cells"],
			"color": info["color"],
			"pos": Vector2i(3, 0),
		}
		if _collides(current["cells"], current["pos"]):
			game_over = true


func _restart() -> void:
	score = 0
	lines = 0
	level = 1
	gravity_acc = 0.0
	hold_type = ""
	can_hold = true
	next_queue.clear()
	bag.clear()
	game_over = false
	paused = false
	_clear_board()
	_new_bag()
	_spawn_piece()
	queue_redraw()


# ---------------- main loop ----------------
func _process(delta: float) -> void:
	if game_over or paused or not started:
		return
	gravity_acc += delta
	var thresh := _gravity_delta()
	while gravity_acc >= thresh:
		gravity_acc -= thresh
		if not _try_move(0, 1):
			_lock_piece()
			break
	queue_redraw()


# ---------------- rendering ----------------
func _draw() -> void:
	_draw_board()
	if started and not game_over:
		_draw_piece(current["cells"], current["pos"], current["color"], true)
		_draw_piece(current["cells"], Vector2i(current["pos"].x, _ghost_y()), Color(1, 1, 1, 0.25), false)
	_draw_ui()


func _draw_board() -> void:
	# board background + grid
	draw_rect(Rect2(BOARD_X, BOARD_Y, COLS * CELL, ROWS * CELL), Color(0.10, 0.11, 0.14))
	for r in ROWS:
		for c in COLS:
			var col = board[r][c]
			if col != null:
				_draw_cell(c, r, col)
			else:
				draw_rect(Rect2(BOARD_X + c * CELL, BOARD_Y + r * CELL, CELL, CELL), Color(0.14, 0.15, 0.19), false, 1.0)
	# border
	draw_rect(Rect2(BOARD_X - 3, BOARD_Y - 3, COLS * CELL + 6, ROWS * CELL + 6), Color(0.35, 0.4, 0.5), false, 3.0)


func _draw_cell(cx: int, cy: int, col: Color) -> void:
	var rect := Rect2(BOARD_X + cx * CELL, BOARD_Y + cy * CELL, CELL, CELL)
	draw_rect(rect, col)
	# bevel/highlight for a chunky block look
	draw_rect(Rect2(rect.position, Vector2(CELL, 6)), col.lightened(0.35))
	draw_rect(Rect2(rect.position, Vector2(6, CELL)), col.lightened(0.35))
	draw_rect(Rect2(rect.position + Vector2(0, CELL - 6), Vector2(CELL, 6)), col.darkened(0.35))
	draw_rect(Rect2(rect.position + Vector2(CELL - 6, 0), Vector2(6, CELL)), col.darkened(0.35))


func _draw_piece(cells: Array, pos: Vector2i, col: Color, solid: bool) -> void:
	for v in cells:
		var x: int = pos.x + v.x
		var y: int = pos.y + v.y
		if y < 0:
			continue
		var rect := Rect2(BOARD_X + x * CELL, BOARD_Y + y * CELL, CELL, CELL)
		if solid:
			draw_rect(rect, col)
			draw_rect(Rect2(rect.position, Vector2(CELL, 6)), col.lightened(0.35))
			draw_rect(Rect2(rect.position, Vector2(6, CELL)), col.lightened(0.35))
			draw_rect(Rect2(rect.position + Vector2(0, CELL - 6), Vector2(CELL, 6)), col.darkened(0.35))
			draw_rect(Rect2(rect.position + Vector2(CELL - 6, 0), Vector2(6, CELL)), col.darkened(0.35))
		else:
			draw_rect(rect, Color(col.r, col.g, col.b, 0.25), false, 2.0)


func _draw_ui() -> void:
	var panel_x := BOARD_X + COLS * CELL + 20
	var y := BOARD_Y
	var title_col := Color(0.9, 0.92, 1.0)

	draw_string(font, Vector2(BOARD_X, BOARD_Y - 18), "TETRIS", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.2, 0.8, 0.9))

	# Score
	draw_string(font, Vector2(panel_x, y), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.65, 0.75))
	draw_string(font, Vector2(panel_x, y + 24), str(score), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, title_col)
	y += 56

	# Level
	draw_string(font, Vector2(panel_x, y), "LEVEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.65, 0.75))
	draw_string(font, Vector2(panel_x, y + 24), str(level), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, title_col)
	y += 56

	# Lines
	draw_string(font, Vector2(panel_x, y), "LINES", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.65, 0.75))
	draw_string(font, Vector2(panel_x, y + 24), str(lines), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, title_col)
	y += 80

	# Hold
	draw_string(font, Vector2(panel_x, y), "HOLD", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.65, 0.75))
	_draw_mini_piece(panel_x, y + 34, hold_type)
	y += 120

	# Next
	draw_string(font, Vector2(panel_x, y), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.65, 0.75))
	var ny := y + 34
	for i in next_queue.size():
		_draw_mini_piece(panel_x, ny, next_queue[i])
		ny += 84

	# Controls hint
	var hint_y := BOARD_Y + ROWS * CELL + 28
	var hint := "Arrows/WASD move   Space drop   C hold   P pause"
	draw_string(font, Vector2(BOARD_X, hint_y), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.55, 0.6, 0.65))

	if not started:
		_draw_overlay("TETRIS", "Press any arrow or Enter to start")
	elif paused and not game_over:
		_draw_overlay("PAUSED", "Press P to resume")
	elif game_over:
		_draw_overlay("GAME OVER", "Press R to restart")


func _draw_mini_piece(x: int, y: int, type: String) -> void:
	if type == "" or not SHAPES.has(type):
		return
	var info: Dictionary = SHAPES[type]
	var col: Color = info["color"]
	var cells: Array = info["cells"]
	# center the mini piece in a 4x4 box
	var box := 4 * 16  # 64px
	for v in cells:
		var rx: int = x + 16 + v.x * 16
		var ry: int = y + 16 + v.y * 16
		draw_rect(Rect2(rx, ry, 14, 14), col)


func _draw_overlay(title: String, sub: String) -> void:
	var center_x := BOARD_X + (COLS * CELL) / 2.0
	draw_rect(Rect2(BOARD_X - 10, BOARD_Y + ROWS * CELL / 2.0 - 50, COLS * CELL + 20, 100), Color(0, 0, 0, 0.72))
	draw_string(font, Vector2(center_x, BOARD_Y + ROWS * CELL / 2.0 - 10), title, HORIZONTAL_ALIGNMENT_CENTER, -1, 28, Color(0.95, 0.4, 0.4))
	draw_string(font, Vector2(center_x, BOARD_Y + ROWS * CELL / 2.0 + 20), sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color(0.9, 0.9, 0.95))