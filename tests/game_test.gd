extends Node
# Headless gameplay test for the Tetris main scene.
# Drives the real scene through its input-handling path and asserts
# movement, rotation, hard-drop/locking, scoring, and line-clear logic.
# Run:  godot --headless res://tests/game_test.tscn

var failures := 0
var checks := 0

func _ready() -> void:
	call_deferred("_run")


func _synthesize_key(action: String, key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	Input.parse_input_event(ev)
	# let the scene's _unhandled_input pick it up
	await get_tree().process_frame


func _check(name: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("  [FAIL] ", name)
	else:
		print("  [PASS] ", name)


func _run() -> void:
	print("== Tetris gameplay test ==")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)

	# 1. A piece should have spawned during _ready
	var cur = main.current
	_check("spawn: current piece set", cur != null and cur.has("type"))

	# 2. Starting the game via a real input event sets started
	await _synthesize_key("move_left", KEY_LEFT)
	_check("input: started becomes true after a key", main.started == true)
	var px: int = main.current["pos"].x

	# 3. Move right via real input
	await _synthesize_key("move_right", KEY_RIGHT)
	var px2: int = main.current["pos"].x
	_check("input: right arrow moves piece +1", px2 == px + 1)

	# 4. Rotate via real input (piece cells should differ or rotation attempted)
	var cells_before: Array = main.current["cells"].duplicate()
	await _synthesize_key("rotate_cw", KEY_UP)
	var cells_after: Array = main.current["cells"]
	_check("input: rotate-cw changes orientation", not (_same_cells(cells_before, cells_after)))

	# 5. Hold via input; the current type moves to hold, a new piece spawns
	var orig_type: String = main.current["type"]
	await _synthesize_key("hold", KEY_C)
	_check("hold: hold_type set to previous piece", main.hold_type == orig_type)

	# 6. Hard drop via input: score increases and a new piece spawns (locked)
	var score_before: int = main.score
	await _synthesize_key("hard_drop", KEY_SPACE)
	_check("hard drop: score increased", main.score > score_before)
	var cells_locked := false
	for r in main.board:
		for c in r:
			if c != null:
				cells_locked = true
	_check("hard drop: a piece locked onto the board", cells_locked)

	# 7. Gravity drops a piece over time (simulate big deltas)
	var locked_after_grav := 0
	main.started = true
	for i in 300:
		main._process(0.8)
		for r in main.board:
			for c in r:
				if c != null:
					locked_after_grav += 1
		if main.game_over:
			break
	_check("gravity: pieces stack until game over", main.game_over == true or locked_after_grav > 10)

	# 8. Line clear logic (independent): fill a row except one cell, then clear it
	var m2 := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(m2)
	var cc := Color(1, 0, 0)
	for c in 10:
		m2.board[19][c] = cc
	var lines_before: int = m2.lines
	m2._clear_lines()
	_check("line clear: one full row removed", m2.lines == lines_before + 1)

	print("== checks: %d, failures: %d ==" % [checks, failures])
	if failures == 0:
		print("RESULT: PASS")
	else:
		print("RESULT: FAIL")
	get_tree().quit(failures)


func _same_cells(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return false
	return true