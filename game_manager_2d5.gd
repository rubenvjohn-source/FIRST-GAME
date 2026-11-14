class_name GameManager2D5
extends Node2D

## GameManager2D5
## Master Coordinator for "Chaos Dunk" 2.5D Local 2-Player Basketball (Godot 4)
## Automatically detects scene nodes, manages match clock (90s), P1/P2 score tracking,
## net scoring sensors, bank shot bonuses (+3 pts), round hazard cycling, and rematch resets.

signal score_updated(p1_score: int, p2_score: int, scoring_player: int, points_awarded: int, banner_text: String)
signal match_timer_updated(seconds_remaining: float)
signal match_started()
signal match_over(winner_player_id: int)
signal round_reset()
signal announcement_banner(text: String, duration: float)

@export_group("Players & Ball")
@export var player_1: Player2D5
@export var player_2: Player2D5
@export var basketball: Basketball2D5

@export_group("Court & Y-Sort Setup")
@export var court_entity_root: Node2D

@export_group("Hoops & Scoring")
## P1 attacks this hoop (right side)
@export var hoop_p1_target: Node2D
## P2 attacks this hoop (left side)
@export var hoop_p2_target: Node2D
## Horizontal distance (px) from the hoop's ground point at which the ball counts as "in the rim"
@export var rim_catch_radius: float = 24.0
## Ball must be within this many px of rim height to score
@export var rim_height_window: float = 45.0

@export_group("Camera & Obstacle Integration")
@export var camera_shake: CameraShake2D
@export var obstacle_manager: ObstacleManager2D5

@export_group("Spawn Points (Floor Position)")
## Default spawn points on the wooden court floor (global coordinates)
@export var p1_spawn_pos: Vector2 = Vector2(330.0, 420.0)
@export var p2_spawn_pos: Vector2 = Vector2(950.0, 420.0)
@export var ball_spawn_pos: Vector2 = Vector2(640.0, 415.0)

@export_group("Court Bounds (global coords, matches the court art)")
## Wood floor is a trapezoid: narrow far edge (top), wide near edge (bottom)
@export var court_top_y: float = 314.0
@export var court_bottom_y: float = 516.0
@export var court_top_left_x: float = 148.0
@export var court_top_right_x: float = 1136.0
@export var court_bottom_left_x: float = 20.0
@export var court_bottom_right_x: float = 1259.0
## Keep players this far inside the lines
@export var player_margin: Vector2 = Vector2(12.0, 8.0)
## Keep the ball this far inside the lines
@export var ball_margin: Vector2 = Vector2(8.0, 2.0)

@export_group("Match Rules & Timing")
@export var match_duration: float = 90.0
@export var three_point_threshold_dist: float = 235.0
@export var score_reset_delay: float = 1.9

# Match State
var p1_score: int = 0
var p2_score: int = 0
var match_time_remaining: float = 90.0
var is_match_running: bool = false
var is_resetting_round: bool = false
var reset_timer: float = 0.0


func _ready() -> void:
	_setup_default_input_mappings()
	_verify_y_sorting()
	_auto_locate_dependencies()
	_setup_ball_player_exceptions()
	_connect_ball_events()
	_connect_player_events()
	start_match()


## Programmatically guarantees default inputs if not configured in Project Settings
func _setup_default_input_mappings() -> void:
	var default_actions: Dictionary = {
		# Player 1: WASD, Space (Jump), E / Left Shift (Action)
		"p1_up": [KEY_W],
		"p1_down": [KEY_S],
		"p1_left": [KEY_A],
		"p1_right": [KEY_D],
		"p1_jump": [KEY_SPACE],
		"p1_action": [KEY_E, KEY_SHIFT],

		# Player 2: Arrow Keys, Enter (Jump), Right Ctrl / Slash (Action)
		"p2_up": [KEY_UP],
		"p2_down": [KEY_DOWN],
		"p2_left": [KEY_LEFT],
		"p2_right": [KEY_RIGHT],
		"p2_jump": [KEY_ENTER],
		"p2_action": [KEY_CTRL, KEY_SLASH]
	}

	for action_name in default_actions:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
			for key_code in default_actions[action_name]:
				var ev: InputEventKey = InputEventKey.new()
				ev.physical_keycode = key_code
				InputMap.action_add_event(action_name, ev)


## Enforces 2.5D Y-sorting on the court container so depth sorting is flawless
func _verify_y_sorting() -> void:
	y_sort_enabled = true
	if court_entity_root:
		court_entity_root.y_sort_enabled = true
	elif get_parent() is CanvasItem:
		(get_parent() as CanvasItem).y_sort_enabled = true


## Auto-discovers any scene nodes that weren't manually wired in Inspector
func _auto_locate_dependencies() -> void:
	var root: Node = get_tree().current_scene if get_tree().current_scene else get_parent()

	# Find Player 1
	if not player_1:
		if root.has_node("Player"):
			player_1 = root.get_node("Player") as Player2D5
		elif root.has_node("Player1"):
			player_1 = root.get_node("Player1") as Player2D5
		else:
			var p1_nodes: Array[Node] = get_tree().get_nodes_in_group("player_1")
			if p1_nodes.size() > 0:
				player_1 = p1_nodes[0] as Player2D5

	# Find Player 2
	if not player_2:
		if root.has_node("Player2"):
			player_2 = root.get_node("Player2") as Player2D5
		else:
			var p2_nodes: Array[Node] = get_tree().get_nodes_in_group("player_2")
			if p2_nodes.size() > 0:
				player_2 = p2_nodes[0] as Player2D5

	# Guarantee IDs are separated!
	if player_1:
		player_1.player_id = 1
	if player_2:
		player_2.player_id = 2

	# Find Basketball
	if not basketball:
		if root.has_node("Basketball"):
			basketball = root.get_node("Basketball") as Basketball2D5
		else:
			var balls: Array[Node] = get_tree().get_nodes_in_group("basketball")
			if balls.size() > 0:
				basketball = balls[0] as Basketball2D5

	# Find Hoops
	if not hoop_p1_target:
		if root.has_node("Right Hoop"):
			hoop_p1_target = root.get_node("Right Hoop") as Node2D
		elif root.has_node("RightHoop"):
			hoop_p1_target = root.get_node("RightHoop") as Node2D

	if not hoop_p2_target:
		if root.has_node("Left Hoop"):
			hoop_p2_target = root.get_node("Left Hoop") as Node2D
		elif root.has_node("LeftHoop"):
			hoop_p2_target = root.get_node("LeftHoop") as Node2D

	# Assign targets to players
	if player_1 and hoop_p1_target:
		player_1.target_hoop = hoop_p1_target
	if player_2 and hoop_p2_target:
		player_2.target_hoop = hoop_p2_target

	# Find Obstacle Manager
	if not obstacle_manager:
		obstacle_manager = root.get_node_or_null("ObstacleManager") as ObstacleManager2D5

	# Find Camera
	if not camera_shake:
		var cam: Camera2D = get_viewport().get_camera_2d()
		if cam is CameraShake2D:
			camera_shake = cam as CameraShake2D
		elif root.has_node("Camera2D"):
			camera_shake = root.get_node("Camera2D") as CameraShake2D


func _connect_ball_events() -> void:
	if basketball:
		if not basketball.ball_scored.is_connected(_on_ball_scored_direct):
			basketball.ball_scored.connect(_on_ball_scored_direct)
		if not basketball.hit_obstacle_event.is_connected(_on_ball_obstacle_hit):
			basketball.hit_obstacle_event.connect(_on_ball_obstacle_hit)


## The ball is picked up by distance, so it should never physically block players
## (and players should never block shots).
func _setup_ball_player_exceptions() -> void:
	if not basketball:
		return
	for p in [player_1, player_2]:
		if p != null:
			basketball.add_collision_exception_with(p)
			p.add_collision_exception_with(basketball)


func _connect_player_events() -> void:
	for p in [player_1, player_2]:
		if p == null:
			continue
		if not p.steal_performed.is_connected(_on_steal):
			p.steal_performed.connect(_on_steal)


func _on_steal(_stealer: Player2D5, _victim: Player2D5) -> void:
	if camera_shake:
		camera_shake.shake_steal()


func _physics_process(_delta: float) -> void:
	if basketball and is_match_running and not is_resetting_round:
		_check_hoop_scoring()
	_confine_to_court()


## Ball scores when it is loose, near a hoop's ground point, at rim height and falling
## (or at the end of a guided shot). Holding the ball under the hoop never scores.
func _check_hoop_scoring() -> void:
	if basketball.holder != null:
		return

	var hoops: Array = [[1, hoop_p1_target], [2, hoop_p2_target]]
	for entry in hoops:
		var hoop: Node2D = entry[1]
		if hoop == null:
			continue
		if basketball.global_position.distance_to(hoop.global_position) > rim_catch_radius:
			continue
		if abs(basketball.elevation - basketball.rim_elevation) > rim_height_window:
			continue
		if not (basketball.is_targeted_shot or basketball.elevation_velocity <= 0.0):
			continue
		_register_hoop_score(entry[0], hoop)
		return


## Court floor is a trapezoid: x limits depend on depth (y)
func clamp_to_court(pos: Vector2, margin: Vector2) -> Vector2:
	var y: float = clamp(pos.y, court_top_y + margin.y, court_bottom_y - margin.y)
	var t: float = inverse_lerp(court_top_y, court_bottom_y, y)
	var left: float = lerp(court_top_left_x, court_bottom_left_x, t) + margin.x
	var right: float = lerp(court_top_right_x, court_bottom_right_x, t) - margin.x
	return Vector2(clamp(pos.x, left, right), y)


func _confine_to_court() -> void:
	for p in [player_1, player_2]:
		if p != null:
			p.global_position = clamp_to_court(p.global_position, player_margin)

	# Ball: only while loose on the floor/in the air (held ball follows its holder,
	# guided shots fly to the hoop on their own)
	if basketball and basketball.holder == null and not basketball.is_targeted_shot:
		var before: Vector2 = basketball.global_position
		var after: Vector2 = clamp_to_court(before, ball_margin)
		if after != before:
			basketball.global_position = after
			if not is_equal_approx(after.x, before.x):
				basketball.velocity.x = -basketball.velocity.x * 0.6
			if not is_equal_approx(after.y, before.y):
				basketball.velocity.y = -basketball.velocity.y * 0.6


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_R) and (not is_match_running or Input.is_key_pressed(KEY_CTRL)):
		rematch()
		return

	if not is_match_running:
		return

	match_time_remaining -= delta
	match_timer_updated.emit(max(0.0, match_time_remaining))

	if match_time_remaining <= 0.0:
		_end_match()
		return

	if is_resetting_round:
		reset_timer -= delta
		if reset_timer <= 0.0:
			_complete_round_reset()


func start_match() -> void:
	p1_score = 0
	p2_score = 0
	match_time_remaining = match_duration
	is_match_running = true
	is_resetting_round = false
	for p in [player_1, player_2]:
		if p != null:
			p.set_physics_process(true)

	score_updated.emit(p1_score, p2_score, 0, 0, "MATCH START!")
	match_started.emit()

	_reset_positions()

	if obstacle_manager:
		obstacle_manager.activate_random_hazard()


func _register_hoop_score(scoring_hoop_id: int, hoop_target: Node2D) -> void:
	if not basketball or is_resetting_round:
		return

	var is_bank: bool = basketball.hit_obstacle
	# scoring_hoop_id is the attacking player's id (P1 -> right hoop, P2 -> left hoop)
	var shooter_id: int = scoring_hoop_id

	var is_three_ptr: bool = false
	if hoop_target:
		var dist: float = basketball.shot_start_pos.distance_to(hoop_target.global_position)
		is_three_ptr = dist >= three_point_threshold_dist

	var points: int = 3 if is_three_ptr else 2
	var banner: String = "3-POINTER!" if is_three_ptr else "2-POINT BUCKET!"

	if is_bank:
		points += 3
		banner = "BANK SHOT! +3 BONUS!"
		if camera_shake:
			camera_shake.shake_bank_shot()
	else:
		if camera_shake:
			camera_shake.shake_score()

	_apply_score(shooter_id, points, banner)


func _on_ball_scored_direct(points: int, scorer_id: int, is_bank_shot: bool, is_dunk: bool) -> void:
	if is_resetting_round:
		return

	var banner: String = "SCORE!"
	if is_dunk:
		banner = "POSTER DUNK SLAM!!"
		if camera_shake:
			camera_shake.shake_poster_dunk()
	elif is_bank_shot:
		banner = "BANK SHOT! +3 BONUS!"
		if camera_shake:
			camera_shake.shake_bank_shot()
	else:
		if camera_shake:
			camera_shake.shake_score()

	_apply_score(scorer_id, points, banner)


func _on_ball_obstacle_hit(_obstacle: Node2D) -> void:
	if camera_shake:
		camera_shake.shake_rim_clank()


func _apply_score(scorer_id: int, points: int, banner: String) -> void:
	if scorer_id == 1:
		p1_score += points
	else:
		p2_score += points

	score_updated.emit(p1_score, p2_score, scorer_id, points, banner)
	announcement_banner.emit(banner, 1.8)

	is_resetting_round = true
	reset_timer = score_reset_delay


func _complete_round_reset() -> void:
	is_resetting_round = false
	_reset_positions()

	if obstacle_manager and obstacle_manager.auto_cycle_on_round_reset:
		obstacle_manager.activate_random_hazard()

	round_reset.emit()


func _reset_positions() -> void:
	if player_1:
		player_1.velocity = Vector2.ZERO
		player_1.global_position = p1_spawn_pos
		player_1.elevation = 0.0
		player_1.elevation_velocity = 0.0
		player_1.is_airborne = false
		player_1.is_dunking = false
		player_1.is_charging_shot = false
		player_1.is_dashing = false
		player_1.is_stunned = false
		player_1.face(1.0)
		if player_1.held_ball:
			player_1.drop_ball(Vector2.ZERO)

	if player_2:
		player_2.velocity = Vector2.ZERO
		player_2.global_position = p2_spawn_pos
		player_2.elevation = 0.0
		player_2.elevation_velocity = 0.0
		player_2.is_airborne = false
		player_2.is_dunking = false
		player_2.is_charging_shot = false
		player_2.is_dashing = false
		player_2.is_stunned = false
		player_2.face(-1.0)
		if player_2.held_ball:
			player_2.drop_ball(Vector2.ZERO)

	if basketball:
		basketball.reset_to_court(ball_spawn_pos)


func _end_match() -> void:
	is_match_running = false
	for p in [player_1, player_2]:
		if p != null:
			p.velocity = Vector2.ZERO
			p.set_physics_process(false)
	var winner: int = 0
	var outcome_banner: String = "MATCH DRAW!"

	if p1_score > p2_score:
		winner = 1
		outcome_banner = "PLAYER 1 WINS!"
	elif p2_score > p1_score:
		winner = 2
		outcome_banner = "PLAYER 2 WINS!"

	announcement_banner.emit(outcome_banner + " (Press 'R' for Rematch)", 5.0)
	match_over.emit(winner)


func rematch() -> void:
	start_match()
