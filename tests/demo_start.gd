extends Node
# Throwaway demo scene: starts the real Tetris scene and places a few
# pieces so we can capture/screenshot the board mid-game. NOT shipped.

func _ready() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	# let the scene initialize
	await get_tree().process_frame
	main.started = true
	# place a handful of pieces at varied columns for a good screenshot
	for i in 8:
		main._try_rotate(1)
		main._try_move((i % 7) - 3, 0)
		main._hard_drop()
	print("demo: placed pieces, score=%d lines=%d" % [main.score, main.lines])
	print("demo: leaving game running for screenshot capture")