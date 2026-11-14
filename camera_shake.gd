class_name CameraShake2D
extends Camera2D

## CameraShake2D
## Punchy Trauma-Based Screen Shake System (Godot 4)
## Employs trauma math (trauma^2 or trauma^3) with smooth noise offset and angular roll"res://basketball_2d5.gd"
## to deliver arcade-style impact for poster dunks, bank shots, steals, and buzzer beaters.

@export_group("Shake Tuning")
## Decay rate: how fast shake trauma falls to zero per second
@export var trauma_decay: float = 1.6
## Maximum pixel displacement at trauma = 1.0
@export var max_offset: Vector2 = Vector2(28.0, 22.0)
## Maximum rotational roll in radians at trauma = 1.0
@export var max_roll_radians: float = 0.04
## Trauma exponent: 2.0 = quadratic, 3.0 = cubic (feels punchier and more responsive)
@export var trauma_exponent: float = 2.2
## Frequency of trauma shake oscillation
@export var shake_frequency: float = 32.0

var trauma: float = 0.0
var shake_time: float = 0.0
var base_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	base_offset = offset


func _process(delta: float) -> void:
	if trauma > 0.0:
		trauma = max(0.0, trauma - (trauma_decay * delta))
		shake_time += delta * shake_frequency

		var shake_intensity: float = pow(trauma, trauma_exponent)
		
		# Multi-harmonic pseudo-random shake offsets
		var sin_x: float = sin(shake_time) + sin(shake_time * 1.7) * 0.5
		var cos_y: float = cos(shake_time * 1.3) + sin(shake_time * 2.1) * 0.5
		var roll_sin: float = sin(shake_time * 0.9)

		offset = base_offset + Vector2(
			max_offset.x * shake_intensity * sin_x,
			max_offset.y * shake_intensity * cos_y
		)
		rotation = max_roll_radians * shake_intensity * roll_sin
	else:
		offset = base_offset
		rotation = 0.0


## Adds trauma directly (clamped 0.0 to 1.0)
func add_trauma(amount: float) -> void:
	trauma = clamp(trauma + amount, 0.0, 1.0)


## Preset: Cataclysmic Poster Dunk slam
func shake_poster_dunk() -> void:
	trauma = 1.0


## Preset: Bank Shot off obstacle (+3 points)
func shake_bank_shot() -> void:
	add_trauma(0.75)


## Preset: Standard shot made through net
func shake_score() -> void:
	add_trauma(0.45)


## Preset: Dash-Steal collision / tackle
func shake_steal() -> void:
	add_trauma(0.35)


## Preset: Loose ball hitting rim or backboard
func shake_rim_clank() -> void:
	add_trauma(0.25)
