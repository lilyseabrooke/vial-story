class_name Dragon
extends CharacterBody2D
## A roaming threat on the Dragons' Ground. See docs/design/systems.md, the
## Dragons / Roaming Threats section.
##
## Not an enemy to be defeated -- the player has no attack -- just one to be
## avoided. Wanders its spawn point at idle, provokes into a chase once the
## player closes within its (skill-reduced) provoke_range, and loses interest
## again once the player gets far enough away. A landed hit knocks the player
## back, grants them a brief invincibility window, and pauses the dragon in
## place for def.attack_pause_seconds -- the window that actually lets the
## player get away rather than just eating repeated hits.

enum State { ROAMING, CHASING, ATTACK_PAUSE }

## A dragon loses the chase once the player gets this multiple of the
## dragon's base (not skill-reduced) provoke_range away -- "an expanded range
## about 50% bigger than the dragon's original detection range."
const LOSE_SIGHT_MULTIPLIER := 1.5
## Each Draconology level shrinks how close a dragon can sense the player
## from before provoking, floored at MIN_PROVOKE_RANGE_FRACTION of the base.
const PROVOKE_RANGE_PER_DRACONOLOGY_LEVEL := 6.0
const MIN_PROVOKE_RANGE_FRACTION := 0.25
const ROAM_WAIT_MIN := 1.0
const ROAM_WAIT_MAX := 3.0
const ROAM_ARRIVE_DISTANCE := 8.0

var def: DragonDef
var home_position: Vector2

var _state: State = State.ROAMING
var _roam_target: Vector2
var _roam_wait_timer: float = 0.0
var _attack_pause_timer: float = 0.0

@onready var _visual: ColorRect = $Visual
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


## Configures this node from its def and drops it at spawn_position, which
## also anchors its roam radius -- called once by RoomBuilder right after
## instancing, same shape as GrowPlotInteractable's runtime setup.
func setup(dragon_def: DragonDef, spawn_position: Vector2) -> void:
	def = dragon_def
	home_position = spawn_position
	global_position = spawn_position

	_visual.color = def.visual_color
	_visual.size = Vector2(def.visual_radius, def.visual_radius) * 2.0
	_visual.position = -_visual.size / 2.0

	var shape := CircleShape2D.new()
	shape.radius = def.visual_radius
	_collision_shape.shape = shape

	_pick_new_roam_target()


func _physics_process(delta: float) -> void:
	if Clock.is_paused:
		velocity = Vector2.ZERO
		return

	var player := get_tree().get_first_node_in_group("player") as Player

	match _state:
		State.ATTACK_PAUSE:
			velocity = Vector2.ZERO
			_attack_pause_timer -= delta
			if _attack_pause_timer <= 0.0:
				_state = State.CHASING if _within_lose_sight_range(player) else State.ROAMING
				if _state == State.ROAMING:
					_pick_new_roam_target()
		State.CHASING:
			_process_chasing(player)
		State.ROAMING:
			_process_roaming(player)

	move_and_slide()


func _process_roaming(player: Player) -> void:
	if player != null and _can_provoke() and global_position.distance_to(player.global_position) <= _effective_provoke_range():
		_state = State.CHASING
		return

	var to_target := _roam_target - global_position
	if to_target.length() <= ROAM_ARRIVE_DISTANCE:
		velocity = Vector2.ZERO
		_roam_wait_timer -= get_physics_process_delta_time()
		if _roam_wait_timer <= 0.0:
			_pick_new_roam_target()
	else:
		velocity = to_target.normalized() * def.roam_speed


func _process_chasing(player: Player) -> void:
	if player == null or not _within_lose_sight_range(player):
		_state = State.ROAMING
		_pick_new_roam_target()
		velocity = Vector2.ZERO
		return

	var distance := global_position.distance_to(player.global_position)
	if distance <= def.attack_range:
		_attack(player)
		return

	velocity = (player.global_position - global_position).normalized() * def.chase_speed


func _attack(player: Player) -> void:
	# The player is already flashing from a very recent hit -- don't chain
	# another one, but don't just idle either, since standing still while
	# still in range would look broken; the pause state naturally resumes
	# the chase once it expires.
	if player.is_invincible():
		velocity = Vector2.ZERO
		return
	player.apply_knockback(global_position, def.knockback_force)
	Resolve.spend(def.resolve_damage, "%s attack" % def.display_name)
	_state = State.ATTACK_PAUSE
	_attack_pause_timer = def.attack_pause_seconds
	velocity = Vector2.ZERO


func _within_lose_sight_range(player: Player) -> bool:
	if player == null:
		return false
	return global_position.distance_to(player.global_position) <= def.provoke_range * LOSE_SIGHT_MULTIPLIER


func _can_provoke() -> bool:
	if def.never_provoke_draconology_level <= 0:
		return true
	return Skills.level("draconology") < def.never_provoke_draconology_level


func _effective_provoke_range() -> float:
	var reduction := Skills.level("draconology") * PROVOKE_RANGE_PER_DRACONOLOGY_LEVEL
	return maxf(def.provoke_range - reduction, def.provoke_range * MIN_PROVOKE_RANGE_FRACTION)


func _pick_new_roam_target() -> void:
	var angle := Rng.range_f(0.0, TAU)
	var dist := Rng.range_f(0.0, def.roam_radius)
	_roam_target = home_position + Vector2(cos(angle), sin(angle)) * dist
	_roam_wait_timer = Rng.range_f(ROAM_WAIT_MIN, ROAM_WAIT_MAX)
