extends CharacterBody2D
## Top-down player movement. See docs/design/systems.md, system 12.

const SPEED := 220.0


func _physics_process(_delta: float) -> void:
	if Clock.is_paused:
		velocity = Vector2.ZERO
		return

	var input_vector := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input_vector.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_vector.x += 1
	if Input.is_key_pressed(KEY_W):
		input_vector.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_vector.y += 1

	velocity = input_vector.normalized() * SPEED if input_vector != Vector2.ZERO else Vector2.ZERO
	move_and_slide()
