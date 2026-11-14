class_name ObstacleManager2D5
extends Node2D

## ObstacleManager2D5
## Dynamic Court Obstacle & Hazard Controller (Godot 4)
## Coordinates sliding bumpers, rotating barriers, low-gravity zones, and oscillating hoops
## in the middle of the court, activating different configurations randomly between rounds.

signal hazard_activated(hazard_name: String)
signal hazard_cleared()

enum HazardMode {
	NONE = 0,
	SLIDING_BUMPERS = 1,
	ROTATING_BARRIERS = 2,
	LOW_GRAVITY_ZONE = 3,
	CHAOS_ALL = 4
}

@export_group("Obstacle Node Bindings")
## Assign your custom bumper nodes (CharacterBody2D, AnimatableBody2D, or Node2D)
@export var sliding_bumpers: Array[Node2D] = []
## Assign your rotating barrier nodes (AnimatableBody2D or Node2D)
@export var rotating_barriers: Array[Node2D] = []
## Assign your low-gravity Area2D zone nodes
@export var low_gravity_zones: Array[Area2D] = []
## Optional hoop nodes to oscillate during chaos rounds
@export var oscillating_hoops: Array[Node2D] = []

@export_group("Bumper Settings")
@export var bumper_amplitude: float = 150.0
@export var bumper_speed: float = 2.2
@export var bumper_knockback_impulse: float = 460.0

@export_group("Rotating Barrier Settings")
@export var barrier_rotation_speed: float = 1.8

@export_group("Low Gravity Settings")
## Gravity multiplier applied to players and ball inside the zone (e.g. 0.45 for floaty moon jumps)
@export var low_gravity_factor: float = 0.45

@export_group("Oscillating Hoop Settings")
@export var hoop_amplitude: float = 30.0
@export var hoop_speed: float = 1.9

@export_group("Automation")
@export var auto_cycle_on_round_reset: bool = true

var current_hazard_mode: HazardMode = HazardMode.NONE
var elapsed_hazard_time: float = 0.0

# Initial transforms cache
var _bumper_initial_positions: Dictionary = {}
var _hoop_initial_positions: Dictionary = {}


# Bodies currently inside a low-gravity zone (so gravity is always restored)
var _low_gravity_bodies: Array[Node] = []


func _ready() -> void:
	_auto_discover_nodes()
	_init_obstacle_metadata()
	_cache_initial_transforms()
	clear_all_hazards()


## Fills the arrays from scene groups when they were not assigned in the Inspector:
## "bumpers", "barriers", "low_gravity_zones"
func _auto_discover_nodes() -> void:
	if sliding_bumpers.is_empty():
		for n in get_tree().get_nodes_in_group("bumpers"):
			if n is Node2D:
				sliding_bumpers.append(n as Node2D)
	if rotating_barriers.is_empty():
		for n in get_tree().get_nodes_in_group("barriers"):
			if n is Node2D:
				rotating_barriers.append(n as Node2D)
	if low_gravity_zones.is_empty():
		for n in get_tree().get_nodes_in_group("low_gravity_zones"):
			if n is Area2D:
				low_gravity_zones.append(n as Area2D)


func _init_obstacle_metadata() -> void:
	# Tag all child and assigned obstacles with group and metadata for ball ricochet detection
	for bumper in sliding_bumpers:
		if is_instance_valid(bumper):
			bumper.add_to_group("obstacles")
			bumper.set_meta("is_obstacle", true)

	for barrier in rotating_barriers:
		if is_instance_valid(barrier):
			barrier.add_to_group("obstacles")
			barrier.set_meta("is_obstacle", true)

	for zone in low_gravity_zones:
		if is_instance_valid(zone):
			if not zone.body_entered.is_connected(_on_low_gravity_body_entered):
				zone.body_entered.connect(_on_low_gravity_body_entered)
			if not zone.body_exited.is_connected(_on_low_gravity_body_exited):
				zone.body_exited.connect(_on_low_gravity_body_exited)


func _cache_initial_transforms() -> void:
	for bumper in sliding_bumpers:
		if is_instance_valid(bumper):
			_bumper_initial_positions[bumper] = bumper.position

	for hoop in oscillating_hoops:
		if is_instance_valid(hoop):
			_hoop_initial_positions[hoop] = hoop.position


func _physics_process(delta: float) -> void:
	if current_hazard_mode == HazardMode.NONE:
		return

	elapsed_hazard_time += delta

	# Process Sliding Bumpers
	if current_hazard_mode in [HazardMode.SLIDING_BUMPERS, HazardMode.CHAOS_ALL]:
		_update_sliding_bumpers()

	# Process Rotating Barriers
	if current_hazard_mode in [HazardMode.ROTATING_BARRIERS, HazardMode.CHAOS_ALL]:
		_update_rotating_barriers(delta)

	# Process Oscillating Hoops
	if current_hazard_mode == HazardMode.CHAOS_ALL:
		_update_oscillating_hoops()


func _update_sliding_bumpers() -> void:
	for i in range(sliding_bumpers.size()):
		var bumper: Node2D = sliding_bumpers[i]
		if not is_instance_valid(bumper):
			continue

		var base_pos: Vector2 = _bumper_initial_positions.get(bumper, bumper.position)
		# Alternate vertical vs horizontal motion based on index
		var offset: float = sin(elapsed_hazard_time * bumper_speed + (i * PI * 0.5)) * bumper_amplitude
		if i % 2 == 0:
			bumper.position.y = base_pos.y + offset
		else:
			bumper.position.x = base_pos.x + offset


func _update_rotating_barriers(delta: float) -> void:
	for barrier in rotating_barriers:
		if is_instance_valid(barrier):
			barrier.rotation += barrier_rotation_speed * delta


func _update_oscillating_hoops() -> void:
	for hoop in oscillating_hoops:
		if is_instance_valid(hoop):
			var base_pos: Vector2 = _hoop_initial_positions.get(hoop, hoop.position)
			hoop.position.y = base_pos.y + sin(elapsed_hazard_time * hoop_speed) * hoop_amplitude


func activate_random_hazard() -> void:
	var available_modes: Array[HazardMode] = [
		HazardMode.NONE,
		HazardMode.SLIDING_BUMPERS,
		HazardMode.ROTATING_BARRIERS,
		HazardMode.LOW_GRAVITY_ZONE,
		HazardMode.CHAOS_ALL
	]

	# Pick a mode different from current if possible
	var new_mode: HazardMode = available_modes.pick_random()
	set_hazard_mode(new_mode)


func set_hazard_mode(mode: HazardMode) -> void:
	clear_all_hazards()
	current_hazard_mode = mode
	elapsed_hazard_time = 0.0

	var hazard_title: String = "Normal Court"

	match mode:
		HazardMode.NONE:
			hazard_title = "Standard Court"
		HazardMode.SLIDING_BUMPERS:
			_set_nodes_active(sliding_bumpers, true)
			hazard_title = "SLIDING BUMPERS ACTIVE!"
		HazardMode.ROTATING_BARRIERS:
			_set_nodes_active(rotating_barriers, true)
			hazard_title = "ROTATING BARRIERS ENGAGED!"
		HazardMode.LOW_GRAVITY_ZONE:
			_set_areas_active(low_gravity_zones, true)
			hazard_title = "LOW-GRAV ZONE DEPLOYED!"
		HazardMode.CHAOS_ALL:
			_set_nodes_active(sliding_bumpers, true)
			_set_nodes_active(rotating_barriers, true)
			_set_areas_active(low_gravity_zones, true)
			_set_nodes_active(oscillating_hoops, true)
			hazard_title = "CHAOS COURT OVERDRIVE!"

	hazard_activated.emit(hazard_title)


func clear_all_hazards() -> void:
	current_hazard_mode = HazardMode.NONE
	_set_nodes_active(sliding_bumpers, false)
	_set_nodes_active(rotating_barriers, false)
	_set_areas_active(low_gravity_zones, false)
	_set_nodes_active(oscillating_hoops, false)

	# Reset transforms to original positions
	for bumper in _bumper_initial_positions:
		if is_instance_valid(bumper):
			bumper.position = _bumper_initial_positions[bumper]

	for hoop in _hoop_initial_positions:
		if is_instance_valid(hoop):
			hoop.position = _hoop_initial_positions[hoop]

	hazard_cleared.emit()


func _set_nodes_active(nodes: Array[Node2D], active: bool) -> void:
	for node in nodes:
		if is_instance_valid(node):
			node.visible = active
			node.set_process(active)
			node.set_physics_process(active)
			_toggle_collision_children(node, active)


func _set_areas_active(areas: Array[Area2D], active: bool) -> void:
	for area in areas:
		if is_instance_valid(area):
			area.visible = active
			area.set_deferred("monitoring", active)
			area.set_deferred("monitorable", active)
	if not active:
		_restore_low_gravity()


func _toggle_collision_children(parent: Node, active: bool) -> void:
	for child in parent.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", not active)
		_toggle_collision_children(child, active)


func _on_low_gravity_body_entered(body: Node2D) -> void:
	if "elevation_gravity" in body and not _low_gravity_bodies.has(body):
		_low_gravity_bodies.append(body)
		body.elevation_gravity *= low_gravity_factor


func _on_low_gravity_body_exited(body: Node2D) -> void:
	if _low_gravity_bodies.has(body):
		_low_gravity_bodies.erase(body)
		body.elevation_gravity /= low_gravity_factor


func _restore_low_gravity() -> void:
	for body in _low_gravity_bodies:
		if is_instance_valid(body):
			body.elevation_gravity /= low_gravity_factor
	_low_gravity_bodies.clear()


func get_active_hazard_name() -> String:
	match current_hazard_mode:
		HazardMode.NONE: return "Standard Court"
		HazardMode.SLIDING_BUMPERS: return "Sliding Bumpers"
		HazardMode.ROTATING_BARRIERS: return "Rotating Barriers"
		HazardMode.LOW_GRAVITY_ZONE: return "Low-Gravity Zone"
		HazardMode.CHAOS_ALL: return "Chaos All"
	return "Standard Court"
