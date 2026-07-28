class_name NPCInteractable
extends InteractableBase
## A love interest the player can talk to. See docs/design/systems.md,
## system 13 ("NPC interaction").
##
## Spawned and moved between rooms by NPCDirector, which drives npc_id and
## calls set_meander_bounds() at spawn and on every room change; npc_id must
## match a registered CharacterDef.id and the npc_id used by the NPC's
## NPCLineSetDef entries. Meanders on its own within meander_bounds while
## its current room is active -- as a plain Area2D with no physics body, it
## just walks through walls/the player harmlessly, which is fine for an
## ambient wander with no pathfinding.

const MEANDER_SPEED := 85.0
const MEANDER_WAIT_MIN := 6.0
const MEANDER_WAIT_MAX := 14.0
const MEANDER_ARRIVE_DISTANCE := 8.0

@export var npc_id: String = ""

var meander_bounds: Rect2 = Rect2()

var _target: Vector2
var _wait_timer: float = 0.0


func _ready() -> void:
	super._ready()
	var character_def := Characters.get_character(npc_id)
	if character_def != null and character_def.sprite_frames != null:
		use_sprite(character_def.sprite_frames)
	_pick_new_target()


## Called by NPCDirector at spawn and on every room change -- also re-rolls
## the wander target so the NPC doesn't try to walk toward a point that
## belonged to the previous room's coordinate space.
func set_meander_bounds(bounds: Rect2) -> void:
	meander_bounds = bounds
	_pick_new_target()


func _physics_process(delta: float) -> void:
	if Clock.is_paused:
		return

	var to_target := _target - position
	if to_target.length() <= MEANDER_ARRIVE_DISTANCE:
		play_directional_animation(false, Vector2.ZERO)
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_pick_new_target()
	else:
		var direction := to_target.normalized()
		position += direction * MEANDER_SPEED * delta
		play_directional_animation(true, direction)


func _pick_new_target() -> void:
	if meander_bounds.size == Vector2.ZERO:
		return
	_target = Vector2(
		Rng.range_f(meander_bounds.position.x, meander_bounds.end.x),
		Rng.range_f(meander_bounds.position.y, meander_bounds.end.y)
	)
	_wait_timer = Rng.range_f(MEANDER_WAIT_MIN, MEANDER_WAIT_MAX)


func interact(_main: MainScene) -> void:
	NPCDialogue.talk_to(npc_id)
