class_name Player
extends CharacterBody2D
## Top-down player movement. See docs/design/systems.md, system 12.
##
## Also owns knockback/invincibility from a dragon attack (see Dragon._attack
## and the Dragons / Roaming Threats section) -- a hit overrides normal WASD
## movement with a decaying knockback impulse and starts a flashing
## invincibility window, both tracked here rather than on Dragon since
## they're player state that needs to persist independent of which (if any)
## dragon caused them.

const SPEED := 170.0
const KNOCKBACK_DECAY := 900.0
const INVINCIBILITY_SECONDS := 1.2
const FLASH_INTERVAL := 0.1

@onready var _visual: AnimatedSprite2D = $Visual

var _knockback_velocity: Vector2 = Vector2.ZERO
var _invincible_timer: float = 0.0
var _flash_timer: float = 0.0
var _facing: String = "Down"


func _physics_process(delta: float) -> void:
	if Clock.is_paused:
		velocity = Vector2.ZERO
		return

	_update_invincibility(delta)

	if _knockback_velocity.length() > 1.0:
		velocity = _knockback_velocity
		_knockback_velocity = _knockback_velocity.move_toward(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	else:
		var input_vector := Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down")
		)
		var speed := SPEED * Clock.SPEED_MULTIPLIERS[Clock.speed_level]
		velocity = input_vector.normalized() * speed if input_vector != Vector2.ZERO else Vector2.ZERO
		_update_animation(input_vector)

	move_and_slide()


## Picks the walking/idle row to match input direction, favoring whichever
## axis has the larger magnitude so diagonal input still reads as a single
## cardinal direction (the spritesheet only has four facings).
func _update_animation(input_vector: Vector2) -> void:
	if input_vector == Vector2.ZERO:
		_visual.play("Idle" + _facing)
		return

	if absf(input_vector.x) > absf(input_vector.y):
		_facing = "Right" if input_vector.x > 0.0 else "Left"
	else:
		_facing = "Down" if input_vector.y > 0.0 else "Up"
	_visual.play("Walking" + _facing)


func is_invincible() -> bool:
	return _invincible_timer > 0.0


## Shoves the player away from from_position and starts the invincibility/
## flash window. No-op while already invincible so a dragon can't re-trigger
## knockback mid-flinch -- Dragon._attack() also checks is_invincible() itself
## before calling this, but the guard lives here too since this is the state
## it's actually protecting.
func apply_knockback(from_position: Vector2, force: float) -> void:
	if is_invincible():
		return
	var direction := (global_position - from_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	_knockback_velocity = direction * force
	_invincible_timer = INVINCIBILITY_SECONDS
	_flash_timer = FLASH_INTERVAL


func _update_invincibility(delta: float) -> void:
	if _invincible_timer <= 0.0:
		_visual.visible = true
		return
	_invincible_timer -= delta
	_flash_timer -= delta
	if _flash_timer <= 0.0:
		_flash_timer = FLASH_INTERVAL
		_visual.visible = not _visual.visible
	if _invincible_timer <= 0.0:
		_visual.visible = true
