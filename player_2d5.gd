class_name Player2D5
extends CharacterBody2D

## Player2D5
## 2.5D Arcade Basketball Player Controller (Godot 4)
## Supports separate P1 (WASD) / P2 (Arrow keys) controls, auto animations,
## jumping elevation, ball possession, shooting, poster dunks, and dash-steals.

signal ball_picked_up(player: Player2D5, ball: Node2D)
signal ball_lost(player: Player2D5, ball: Node2D)
signal shot_released(player: Player2D5, charge_power: float)
signal dunk_started(player: Player2D5, target_hoop: Node2D)
signal dunk_slammed(player: Player2D5, target_hoop: Node2D)
signal steal_performed(stealer: Player2D5, victim: Player2D5)
signal tackled(player: Player2D5)

@export_group("Player Configuration")
## Set to 1 for Player 1 (WASD), or 2 for Player 2 (Arrow Keys)
@export var player_id: int = 1
@export var move_speed: float = 380.0
@export var jump_force: float = -450.0
@export var target_hoop: Node2D
@export var is_bot: bool=false

@export_group("2.5D Hierarchy Setup")
@export var sprite_root: Node2D
@export var animated_sprite: AnimatedSprite2D
@export var shadow_node: Node2D
@export var ball_hold_point: Node2D

@export_group("Offense (Shooting & Dunking)")
@export var shot_charge_speed: float = 1.4
@export var min_shot_charge: float = 0.25
@export var max_shot_distance: float = 850.0
@export var dunk_range: float = 210.0
@export var dunk_height_threshold: float = 35.0
@export var dunk_flight_speed: float = 700.0
## How high (px) the player rises while slamming, so hands reach the rim
@export var dunk_rim_lift: float = 60.0

@export_group("Defense (Dash-Steal)")
@export var dash_speed: float = 760.0
@export var dash_duration: float = 0.22
@export var dash_cooldown: float = 0.70
@export var steal_tackle_radius: float = 58.0

@export_group("Physics & Tuning")
@export var elevation_gravity: float = 1150.0
@export var pickup_radius: float = 55.0
@export var pickup_cooldown_time: float = 0.55
@export var stun_duration: float = 0.65

# 2.5D Elevation tracking
var elevation: float = 0.0
var elevation_velocity: float = 0.0
var is_airborne: bool = false
var bot_shot_cooldown: float = 0.0

# Ball state
var held_ball: Node2D = null
var pickup_cooldown_timer: float = 0.0

# Offensive state
var is_charging_shot: bool = false
var shot_charge: float = 0.0
var is_dunking: bool = false
var dunk_target_pos: Vector2 = Vector2.ZERO

# Defensive state
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector2 = Vector2.RIGHT

# Control & stun states
var is_stunned: bool = false
var stun_timer: float = 0.0
var facing_direction: Vector2 = Vector2.RIGHT

# Input Action Cache
var action_up: String = ""
var action_down: String = ""
var action_left: String = ""
var action_right: String = ""
var action_jump: String = ""
var action_action: String = ""


func _ready() -> void:
	_init_input_actions()
	_validate_hierarchy()
	add_to_group("players")
	if player_id == 1:
		add_to_group("player_1")
	else:
		add_to_group("player_2")


func _init_input_actions() -> void:
	action_up = "p%d_up" % player_id
	action_down = "p%d_down" % player_id
	action_left = "p%d_left" % player_id
	action_right = "p%d_right" % player_id
	action_jump = "p%d_jump" % player_id
	action_action = "p%d_action" % player_id


func _validate_hierarchy() -> void:
	if not sprite_root:
		if has_node("VisualRoot"):
			sprite_root = get_node("VisualRoot")
		elif has_node("Sprite2D"):
			sprite_root = get_node("Sprite2D")
		elif has_node("AnimatedSprite2D"):
			sprite_root = get_node("AnimatedSprite2D")

	if not animated_sprite:
		if sprite_root and sprite_root.has_node("AnimatedSprite2D"):
			animated_sprite = sprite_root.get_node("AnimatedSprite2D")
		elif sprite_root and sprite_root.has_node("PlayerSprite"):
			animated_sprite = sprite_root.get_node("PlayerSprite") as AnimatedSprite2D
		elif has_node("VisualRoot/PlayerSprite"):
			animated_sprite = get_node("VisualRoot/PlayerSprite") as AnimatedSprite2D
		elif has_node("VisualRoot/AnimatedSprite2D"):
			animated_sprite = get_node("VisualRoot/AnimatedSprite2D") as AnimatedSprite2D
		elif has_node("AnimatedSprite2D"):
			animated_sprite = get_node("AnimatedSprite2D")
		elif sprite_root is AnimatedSprite2D:
			animated_sprite = sprite_root as AnimatedSprite2D

	if not shadow_node and has_node("Shadow"):
		shadow_node = get_node("Shadow")

	if not ball_hold_point:
		if has_node("BallHoldPoint"):
			ball_hold_point = get_node("BallHoldPoint")
		elif sprite_root and sprite_root.has_node("BallHoldPoint"):
			ball_hold_point = sprite_root.get_node("BallHoldPoint")


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_handle_elevation_physics(delta)
	_handle_movement_and_input(delta)
	_handle_ball_pickup_check()
	_update_visual_elevation()
	_update_animations()


func _update_timers(delta: float) -> void:
	if pickup_cooldown_timer > 0.0:
		pickup_cooldown_timer = max(0.0, pickup_cooldown_timer - delta)

	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = max(0.0, dash_cooldown_timer - delta)

	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false

	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false


func _handle_elevation_physics(delta: float) -> void:
	if is_airborne or elevation > 0.0:
		elevation_velocity -= elevation_gravity * delta
		elevation += elevation_velocity * delta

		if elevation <= 0.0:
			elevation = 0.0
			elevation_velocity = 0.0
			is_airborne = false
			if is_dunking:
				_cancel_dunk()


func _handle_movement_and_input(delta: float) -> void:
	if is_stunned:
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
		move_and_slide()
		return

	if is_dunking:
		_process_dunk_flight(delta)
		return

	if is_dashing:
		velocity = dash_direction * dash_speed
		move_and_slide()
		_check_dash_steal_collision()
		return

	# Separate Input vector per player_id
	var input_vec: Vector2 = Vector2.ZERO
	if is_bot:
		input_vec = _get_bot_input_vector()
	else:
		input_vec = Input.get_vector(action_left, action_right, action_up, action_down)
	if input_vec.length_squared() > 0.001:
		velocity = input_vec * move_speed
		facing_direction = input_vec.normalized()
		_update_sprite_flip(facing_direction.x)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, move_speed * 7.0 * delta)

	move_and_slide()

	if Input.is_action_just_pressed(action_jump) and not is_airborne:
		_trigger_jump()

	_handle_action_input(delta)


## Turn the player to face left (-1) or right (+1)
func face(dir_x: float) -> void:
	facing_direction = Vector2(sign(dir_x), 0.0)
	_update_sprite_flip(dir_x)


func _update_sprite_flip(dir_x: float) -> void:
	if sprite_root and abs(dir_x) > 0.1:
		sprite_root.scale.x = abs(sprite_root.scale.x) if dir_x > 0 else -abs(sprite_root.scale.x)


func _trigger_jump() -> void:
	is_airborne = true
	elevation_velocity = abs(jump_force)


func _handle_action_input(delta: float) -> void:
	var has_possession: bool = (held_ball != null)

	if has_possession:
		if Input.is_action_just_pressed(action_action):
			if is_airborne and elevation >= dunk_height_threshold and _is_in_dunk_range():
				_trigger_poster_dunk()
				return
			else:
				is_charging_shot = true
				shot_charge = min_shot_charge

		if Input.is_action_pressed(action_action) and is_charging_shot:
			shot_charge = min(1.0, shot_charge + (shot_charge_speed * delta))

		if Input.is_action_just_released(action_action) and is_charging_shot:
			_release_shot()
	else:
		if Input.is_action_just_pressed(action_action) and not is_dashing and dash_cooldown_timer <= 0.0:
			_trigger_dash_steal()


func _is_in_dunk_range() -> bool:
	if not target_hoop:
		return false
	var dist: float = global_position.distance_to(target_hoop.global_position)
	return dist <= dunk_range


func _trigger_poster_dunk() -> void:
	is_dunking = true
	is_charging_shot = false
	dunk_target_pos = target_hoop.global_position
	elevation = max(elevation, 70.0)
	elevation_velocity = 80.0
	dunk_started.emit(self, target_hoop)


func _process_dunk_flight(delta: float) -> void:
	var to_hoop: Vector2 = dunk_target_pos - global_position
	var dist: float = to_hoop.length()

	if dist < 28.0:
		_slam_dunk()
	else:
		# Rise toward the rim instead of falling under gravity while flying
		elevation = move_toward(elevation, dunk_rim_lift, 500.0 * delta)
		elevation_velocity = 0.0
		velocity = to_hoop.normalized() * dunk_flight_speed
		move_and_slide()


func _slam_dunk() -> void:
	is_dunking = false
	dunk_slammed.emit(self, target_hoop)

	if held_ball:
		var ball_ref: Node2D = held_ball
		drop_ball(Vector2.DOWN * 200.0)
		if ball_ref.has_method("score_dunk"):
			ball_ref.score_dunk(player_id, target_hoop)

	pickup_cooldown_timer = pickup_cooldown_time


func _cancel_dunk() -> void:
	is_dunking = false


func _release_shot() -> void:
	is_charging_shot = false
	if not held_ball:
		return

	var ball_to_shoot: Node2D = held_ball
	var hoop_pos: Vector2 = target_hoop.global_position if target_hoop else (global_position + facing_direction * 400.0)
	
	drop_ball(Vector2.ZERO)
	pickup_cooldown_timer = pickup_cooldown_time

	shot_released.emit(self, shot_charge)

	if ball_to_shoot.has_method("launch_shot"):
		ball_to_shoot.launch_shot(global_position, hoop_pos, elevation, shot_charge, player_id)


func _trigger_dash_steal() -> void:
	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown

	var input_vec: Vector2 = Input.get_vector(action_left, action_right, action_up, action_down)
	dash_direction = input_vec.normalized() if input_vec.length_squared() > 0.001 else facing_direction
	_check_dash_steal_collision()


func _check_dash_steal_collision() -> void:
	var opponent_group: String = "player_2" if player_id == 1 else "player_1"
	var opponents: Array[Node] = get_tree().get_nodes_in_group(opponent_group)

	for opp in opponents:
		if opp is Player2D5:
			var opp_player: Player2D5 = opp as Player2D5
			var dist: float = global_position.distance_to(opp_player.global_position)
			if dist <= steal_tackle_radius:
				if abs(elevation - opp_player.elevation) < 45.0:
					_execute_steal_on(opp_player)
					break


func _execute_steal_on(victim: Player2D5) -> void:
	if victim.held_ball:
		var loose_ball: Node2D = victim.held_ball
		var scatter_dir: Vector2 = (victim.global_position - global_position).normalized()
		victim.drop_ball(scatter_dir * 320.0)
		victim.apply_stun(stun_duration)
		steal_performed.emit(self, victim)


func apply_stun(duration: float) -> void:
	is_stunned = true
	stun_timer = duration
	is_dashing = false
	is_charging_shot = false
	is_dunking = false
	tackled.emit(self)


func _handle_ball_pickup_check() -> void:
	if held_ball != null or pickup_cooldown_timer > 0.0 or is_stunned:
		return

	var balls: Array[Node] = get_tree().get_nodes_in_group("basketball")
	for b in balls:
		if b is Node2D:
			var ball_node: Node2D = b as Node2D
			if "holder" in ball_node and ball_node.holder != null:
				continue

			var dist: float = global_position.distance_to(ball_node.global_position)
			if dist <= pickup_radius:
				var ball_elev: float = ball_node.elevation if "elevation" in ball_node else 0.0
				if abs(elevation - ball_elev) < 45.0:
					pickup_ball(ball_node)
					break


func pickup_ball(ball: Node2D) -> void:
	held_ball = ball
	if ball.has_method("catch_by"):
		ball.catch_by(self)
	ball_picked_up.emit(self, ball)


func drop_ball(impulse: Vector2 = Vector2.ZERO) -> void:
	if not held_ball:
		return

	var ball_to_drop: Node2D = held_ball
	held_ball = null
	pickup_cooldown_timer = pickup_cooldown_time

	if ball_to_drop.has_method("drop_loose"):
		ball_to_drop.drop_loose(impulse, elevation)

	ball_lost.emit(self, ball_to_drop)


## Returns the ball's GROUND position. The ball lifts itself visually by elevation.
func get_hold_position() -> Vector2:
	if ball_hold_point:
		return ball_hold_point.global_position
	return global_position + Vector2(facing_direction.x * 18.0, 1.0)


func _update_visual_elevation() -> void:
	if sprite_root:
		sprite_root.position.y = -elevation

	queue_redraw()

	if shadow_node:
		var shadow_factor: float = clamp(1.0 - (elevation / 350.0), 0.35, 1.0)
		shadow_node.scale = Vector2(shadow_factor, shadow_factor)
		if shadow_node is CanvasItem:
			shadow_node.modulate.a = shadow_factor * 0.8


## Plays the appropriate animation (idle, run, dribble, run_dribble, jumpshot, defense)
func _update_animations() -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return

	var anim: String = "idle"

	if is_dunking or is_airborne or is_charging_shot:
		anim = "jumpshot"
	elif is_dashing:
		anim = "defense"
	elif held_ball != null:
		if velocity.length() > 20.0:
			anim = "run_dribble" if animated_sprite.sprite_frames.has_animation("run_dribble") else "dribble"
		else:
			anim = "dribble" if animated_sprite.sprite_frames.has_animation("dribble") else "idle"
	else:
		if velocity.length() > 20.0:
			anim = "run"
		else:
			anim = "idle"

	if animated_sprite.sprite_frames.has_animation(anim):
		if animated_sprite.animation != anim or not animated_sprite.is_playing():
			animated_sprite.play(anim)


## Soft blob shadow on the floor (shrinks as the player rises)
func _draw() -> void:
	var f: float = clamp(1.0 - (elevation / 250.0), 0.4, 1.0)
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(f, f * 0.4))
	draw_circle(Vector2.ZERO, 24.0, Color(0, 0, 0, 0.35 * f))

	# Shot power meter: green zone = perfect release
	if is_charging_shot and target_hoop:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var ideal: float = Basketball2D5.ideal_charge_for(global_position.distance_to(target_hoop.global_position))
		var w: float = 46.0
		var top: float = -108.0 - elevation
		draw_rect(Rect2(-w / 2.0 - 1.0, top - 1.0, w + 2.0, 8.0), Color(0, 0, 0, 0.8))
		var zone_l: float = clamp(ideal - Basketball2D5.PERFECT_CHARGE_WINDOW, 0.0, 1.0)
		var zone_r: float = clamp(ideal + Basketball2D5.PERFECT_CHARGE_WINDOW, 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0 + zone_l * w, top, (zone_r - zone_l) * w, 6.0), Color(0.2, 0.6, 0.25))
		var in_zone: bool = abs(shot_charge - ideal) <= Basketball2D5.PERFECT_CHARGE_WINDOW
		draw_rect(Rect2(-w / 2.0, top + 2.0, shot_charge * w, 2.0), Color(0.5, 1.0, 0.5) if in_zone else Color(1.0, 0.85, 0.2))
	# ---------------------------------------
		## AI Bot Brain (Attacks hoop, shoots, dunks, chases ball, and steals!)
## AI Bot Brain (Nerfed to feel human and fun to play against!)
## AI Bot Brain (No glitching under the hoop, waits after shooting!)
func _get_bot_input_vector() -> Vector2:
	# 1. BOT JUST SHOT -> Freeze/watch the shot, don't rush the rim!

	if bot_shot_cooldown > 0.0:
		return Vector2.ZERO

	# 2. IF BOT HAS THE BALL -> Drive to basket
	if held_ball != null:
		if target_hoop:
			var to_hoop: Vector2 = target_hoop.global_position - global_position
			var dist: float = to_hoop.length()

			# Close to basket -> Dunk!
			if dist < 200.0 and not is_airborne:
				_trigger_jump()
				_trigger_poster_dunk()
			# Mid-range -> Shoot!
			elif dist < 380.0 and not is_charging_shot:
				is_charging_shot = true
				shot_charge = randf_range(0.48, 0.72)
				_release_shot()

			return to_hoop.normalized() * 0.85
		return Vector2.ZERO

	# 3. FIND THE BASKETBALL
	var balls: Array[Node] = get_tree().get_nodes_in_group("basketball")
	if balls.size() == 0:
		return Vector2.ZERO
	var ball: Node2D = balls[0] as Node2D

	# If opponent has ball -> Defend
	if "holder" in ball and ball.holder != null and ball.holder != self:
		var to_opponent: Vector2 = ball.holder.global_position - global_position
		var dist_to_you: float = to_opponent.length()
		
		if dist_to_you < 80.0 and dash_cooldown_timer <= 0.0 and randf() < 0.4:
			_trigger_dash_steal()

		if dist_to_you < 55.0:
			return Vector2.ZERO
		
		return to_opponent.normalized() * 0.75

	# 4. LOOSE BALL -> ONLY chase if ball is near the floor (not high in the air!)
	var ball_height: float = ball.elevation if "elevation" in ball else 0.0
	if ball_height > 60.0:
		# Ball is flying high in an arc / through the hoop -> Wait on the court!
		return Vector2.ZERO

	var to_ball: Vector2 = ball.global_position - global_position
	return to_ball.normalized() * 0.8
func _unhandled_input(event: InputEvent) -> void:
	if player_id == 2 and event is InputEventKey:
		if event.pressed and event.keycode == KEY_B and not event.echo:
			is_bot = not is_bot
			print("PLAYER 2 BOT MODE: ", is_bot)
