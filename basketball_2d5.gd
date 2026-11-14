class_name Basketball2D5
extends CharacterBody2D

## Basketball2D5
## 2.5D Arcade Basketball Physics Controller (Godot 4)
## Handles 2.5D ground movement (X=horizontal, Y=court depth) and simulated Z-elevation
## for arc trajectories, gravity bounces, possession locking, and obstacle bank shot detection.

signal ball_scored(points: int, scorer_id: int, is_bank_shot: bool, is_dunk: bool)
signal bounced_court()
signal hit_obstacle_event(obstacle: Node2D)
signal possession_changed(new_holder: Node2D)

@export_group("2.5D Hierarchy Setup")
## Visual container node (contains the ball Sprite2D). Displaced upward by -elevation.
@export var sprite_root: Node2D
## Optional shadow node on the ground plane.
@export var shadow_node: Node2D
## Visual spin rate for the ball sprite when flying through the air
@export var spin_rate: float = 8.0

@export_group("Physics Tuning")
@export var elevation_gravity: float = 1200.0
@export var ground_bounce_damping: float = 0.65
@export var obstacle_bounce_damping: float = 0.85
@export var ground_friction: float = 0.95
@export var min_bounce_cutoff: float = 75.0
## Height of the rim above the hoop's ground point (matches the court art)
@export var rim_elevation: float = 139.0

@export_group("Hold Settings")
@export var default_hold_offset: Vector2 = Vector2(0, -28)

# Possession & Scoring State
var holder: Node2D = null
var last_touched_by: int = 0
var hit_obstacle: bool = false

# 2.5D Simulated Height
var elevation: float = 0.0
var elevation_velocity: float = 0.0
var is_in_flight: bool = false

# Guided Shot Trajectory Variables
var is_targeted_shot: bool = false
var shot_timer: float = 0.0
var shot_duration: float = 0.0
var shot_start_pos: Vector2 = Vector2.ZERO
var shot_target_pos: Vector2 = Vector2.ZERO
var shot_arc_peak: float = 0.0
var shot_start_elevation: float = 0.0
var shot_target_elevation: float = 139.0
var shot_is_miss: bool = false


## Charge level (0..1) that gives a perfect shot from this distance to the hoop
static func ideal_charge_for(dist: float) -> float:
	return clamp(dist / 700.0, 0.3, 0.95)


## Half-width of the "perfect" charge window
const PERFECT_CHARGE_WINDOW: float = 0.12


func _ready() -> void:
	add_to_group("basketball")
	_validate_hierarchy()


func _validate_hierarchy() -> void:
	if not sprite_root:
		if has_node("VisualRoot"):
			sprite_root = get_node("VisualRoot")
		elif has_node("Sprite2D"):
			sprite_root = get_node("Sprite2D")
		elif has_node("AnimatedSprite2D"):
			sprite_root = get_node("AnimatedSprite2D")

	if not shadow_node and has_node("Shadow"):
		shadow_node = get_node("Shadow")


func _physics_process(delta: float) -> void:
	if holder != null:
		_process_held_state(delta)
	elif is_targeted_shot:
		_process_targeted_shot(delta)
	else:
		_process_ballistic_physics(delta)

	_update_visuals(delta)


func _process_held_state(_delta: float) -> void:

	# Locked in player's hands: match player position and hands offset
	if is_instance_valid(holder):
		if holder.has_method("get_hold_position"):
			global_position = holder.get_hold_position()
		else:
			global_position = holder.global_position + default_hold_offset

		if "elevation" in holder:
			elevation = holder.elevation + 30.0
		else:
			elevation = 30.0

		velocity = Vector2.ZERO
		elevation_velocity = 0.0
	else:
		holder = null


func _process_targeted_shot(delta: float) -> void:
	shot_timer += delta
	var t: float = clamp(shot_timer / shot_duration, 0.0, 1.0)

	# Ground position travels linearly to hoop
	var next_ground_pos: Vector2 = shot_start_pos.lerp(shot_target_pos, t)
	var move_delta: Vector2 = next_ground_pos - global_position

	# Check for obstacle collisions in flight path
	var collision: KinematicCollision2D = move_and_collide(move_delta)
	if collision:
		var collider_node: Node2D = collision.get_collider() as Node2D
		if _is_obstacle(collider_node):
			# Bank Shot opportunity!
			hit_obstacle = true
			hit_obstacle_event.emit(collider_node)
			# Ricochet off obstacle into free ballistic physics
			is_targeted_shot = false
			velocity = move_delta.bounce(collision.get_normal()).normalized() * 380.0
			elevation_velocity = 200.0
			return

	# Parabolic arc in elevation (Z-axis)
	var arc_sin: float = sin(t * PI)
	elevation = (arc_sin * shot_arc_peak) + lerp(shot_start_elevation, shot_target_elevation, t)

	# Completed shot trajectory to rim
	if t >= 1.0:
		is_targeted_shot = false
		is_in_flight = false
		# Give a slight downward bounce from rim if it wasn't captured by net area
		elevation = shot_target_elevation
		elevation_velocity = -120.0
		if shot_is_miss:
			hit_obstacle_event.emit(null)  # rim clank -> camera shake
		velocity = Vector2(randf_range(-60.0, 60.0), randf_range(-40.0, 40.0))


func _process_ballistic_physics(delta: float) -> void:
	# Ground movement & boundary/obstacle collisions
	if velocity.length_squared() > 1.0:
		var collision: KinematicCollision2D = move_and_collide(velocity * delta)
		if collision:
			var normal: Vector2 = collision.get_normal()
			var collider_node: Node2D = collision.get_collider() as Node2D

			if _is_obstacle(collider_node):
				hit_obstacle = true
				hit_obstacle_event.emit(collider_node)
				velocity = velocity.bounce(normal) * obstacle_bounce_damping
			else:
				velocity = velocity.bounce(normal) * 0.7

		# Ground friction when touching the floor
		if elevation <= 0.0:
			velocity = velocity * pow(ground_friction, delta * 60.0)
			if velocity.length() < 10.0:
				velocity = Vector2.ZERO

	# Simulated Z-gravity
	elevation_velocity -= elevation_gravity * delta
	elevation += elevation_velocity * delta

	# Floor collision bounce
	if elevation <= 0.0:
		elevation = 0.0
		if abs(elevation_velocity) > min_bounce_cutoff:
			elevation_velocity = -elevation_velocity * ground_bounce_damping
			bounced_court.emit()
		else:
			elevation_velocity = 0.0
			is_in_flight = false


func _is_obstacle(node: Node2D) -> bool:
	if not node:
		return false
	return node.is_in_group("obstacles") or node.has_meta("is_obstacle")


func _update_visuals(delta: float) -> void:
	visible = (holder == null)
	# Displace visual sprite vertically on screen by -elevation
	if sprite_root:
		sprite_root.position.y = -elevation
		# Ball spin during flight
		if (is_targeted_shot or is_in_flight) and abs(velocity.x) > 10.0:
			sprite_root.rotation += sign(velocity.x) * spin_rate * delta

	# Scale shadow based on height
	if shadow_node:
		var shadow_scale: float = clamp(1.0 - (elevation / 400.0), 0.3, 1.0)
		shadow_node.scale = Vector2(shadow_scale, shadow_scale)
		if shadow_node is CanvasItem:
			shadow_node.modulate.a = shadow_scale * 0.75


## Called by player when picking up or receiving the ball
func catch_by(new_holder: Node2D) -> void:
	holder = new_holder
	is_targeted_shot = false
	is_in_flight = false
	hit_obstacle = false

	if "player_id" in new_holder:
		last_touched_by = new_holder.player_id

	possession_changed.emit(new_holder)


## Called when the ball is knocked loose, passed, or dropped
func drop_loose(scatter_impulse: Vector2, initial_elevation: float = 0.0) -> void:
	holder = null
	shot_start_pos = global_position
	elevation = initial_elevation
	elevation_velocity = 180.0
	velocity = scatter_impulse
	is_targeted_shot = false
	is_in_flight = true
	possession_changed.emit(null)


## Launches an arcade arc shot toward target hoop
func launch_shot(from_ground: Vector2, to_ground: Vector2, start_elev: float, charge_power: float, shooter_id: int) -> void:
	holder = null
	last_touched_by = shooter_id
	hit_obstacle = false
	is_in_flight = true
	is_targeted_shot = true

	global_position = from_ground
	shot_start_pos = from_ground
	shot_target_pos = to_ground
	shot_start_elevation = start_elev
	shot_target_elevation = rim_elevation

	# Distance and arc calculations
	var dist: float = from_ground.distance_to(to_ground)
	# Flight time scales with distance, bounded for snappy arcade feel (0.55s - 0.95s)
	shot_duration = clamp(dist / 650.0, 0.55, 0.95)
	shot_timer = 0.0

	# Accuracy: charge close to the ideal level always goes in, otherwise the shot
	# can miss and lands a short way from the rim
	var error: float = abs(charge_power - ideal_charge_for(dist))
	var make_chance: float = clamp(1.0 - max(0.0, error - PERFECT_CHARGE_WINDOW) * 2.5, 0.2, 1.0)
	shot_is_miss = randf() > make_chance
	if shot_is_miss:
		shot_target_pos = to_ground + Vector2.from_angle(randf() * TAU) * randf_range(45.0, 80.0)

	# Peak height of arc based on charge power and distance
	shot_arc_peak = lerp(120.0, 240.0, clamp(charge_power, 0.0, 1.0))

	# Initial ground velocity for direction tracking
	velocity = (to_ground - from_ground).normalized() * (dist / shot_duration)
	possession_changed.emit(null)


## Special instant slam execution for Poster Dunks
func score_dunk(dunker_id: int, hoop: Node2D) -> void:
	last_touched_by = dunker_id
	holder = null
	global_position = hoop.global_position
	elevation = rim_elevation
	elevation_velocity = -350.0
	velocity = Vector2(0, 120.0)
	is_targeted_shot = false
	is_in_flight = false

	# Award dunk score (2 points, is_dunk = true)
	ball_scored.emit(2, dunker_id, false, true)


## Triggered by Area2D hoop net sensor
func score_in_hoop(hoop_id: int, is_three_pointer: bool) -> void:
	# Calculate score points:
	# 3 points for beyond arc, 2 points for inside arc.
	# +3 BONUS for "BANK SHOT!" if it hit an obstacle before scoring!
	var base_points: int = 3 if is_three_pointer else 2
	var total_points: int = base_points + (3 if hit_obstacle else 0)

	ball_scored.emit(total_points, last_touched_by, hit_obstacle, false)

	# Net swish drop
	elevation_velocity = -220.0
	velocity = Vector2(0, 80.0)
	hit_obstacle = false


## Resets ball to center court for tip-off
func reset_to_court(court_center: Vector2) -> void:
	holder = null
	last_touched_by = 0
	hit_obstacle = false
	is_targeted_shot = false
	is_in_flight = false
	global_position = court_center
	shot_start_pos = court_center
	elevation = 160.0
	elevation_velocity = 0.0
	velocity = Vector2.ZERO
	possession_changed.emit(null)
