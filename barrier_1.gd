extends AnimatableBody2D

func _on_hazard_hitbox_body_entered(body: Node2D) -> void:
	print("HIT: ", body.name)
	
	# If a player hits the barrier:
	if body.has_method("drop_ball"):
		var scatter_dir: Vector2 = (body.global_position - global_position).normalized()
		body.drop_ball(scatter_dir * 400.0)
		
		if body.has_method("apply_stun"):
			body.apply_stun(0.8)
			
		body.velocity = scatter_dir * 500.0

	# If the loose basketball hits the barrier:
	elif body.is_in_group("basketball"):
		var push_dir: Vector2 = (body.global_position - global_position).normalized()
		body.velocity = push_dir * 500.0
		body.hit_obstacle = true
