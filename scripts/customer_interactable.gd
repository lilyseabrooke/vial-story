class_name CustomerInteractable
extends InteractableBase
## Purely presentational visualization of one Shop.active_visits entry. See
## docs/design/systems.md, system 5, and CustomerDirector, which owns
## spawning/despawning these.
##
## This node never decides anything -- the purchase decision already
## happened (or will happen) inside Shop, entirely independent of whether
## this sprite exists at all. It just walks a customer in, wanders between
## whichever browse points CustomerDirector handed it (any number, hand-placed
## and moveable in the editor -- see Shop.tscn's CustomerBrowsePoints
## container) until CustomerDirector tells it the bound visit resolved
## (Shop.customer_visit_resolved), then walks back out. Movement is the same
## goal-directed "walk to a target, arrive, stop" shape as NPCInteractable.

enum State { ENTERING, BROWSING, LEAVING }

const MOVE_SPEED := 70.0
const ARRIVE_DISTANCE := 8.0
## How long a customer lingers at one browse point before wandering to
## another -- mirrors NPCInteractable's meander wait window in spirit,
## just shorter since a visit's whole browse window is only ~15-30 minutes.
const BROWSE_DWELL_MIN_SECONDS := 2.0
const BROWSE_DWELL_MAX_SECONDS := 5.0

## Fired once this customer has walked back out to the entry point and is
## ready to be freed -- CustomerDirector clears its tracking entry on this
## rather than on tree_exiting, so it can do bookkeeping before queue_free().
signal despawn_requested(customer_interactable: CustomerInteractable)

var visit: Dictionary = {}

var _state: State = State.ENTERING
var _entry_position: Vector2 = Vector2.ZERO
var _browse_points: Array[Vector2] = []

## Only meaningful while _state == BROWSING: true while walking to
## _browse_target, false while dwelling at it (see _browsing_idle_timer).
var _walking_to_browse_point: bool = false
var _browse_target: Vector2 = Vector2.ZERO
var _browsing_idle_timer: float = 0.0

@onready var _collision_body: Node2D = $CollisionBody


func _ready() -> void:
	super._ready()
	use_sprite(load("res://assets/sprites/CustomerBase.tres"))
	set_sprite_tint(Color.from_hsv(Rng.range_f(0.0, 1.0), 0.35, 1.0))


## Called once by CustomerDirector right after instancing. browse_points is
## every CustomerBrowsePoints marker in the room (any count >= 1 -- see
## CustomerDirector._browse_points_for_room()); a customer wanders between a
## random subset of them for the rest of the visit. already_browsing is true
## when the player walks into the Shop mid-visit -- skips straight to
## wandering instead of re-walking an entrance nobody saw.
func bind_visit(new_visit: Dictionary, entry_pos: Vector2, browse_points: Array[Vector2], already_browsing: bool) -> void:
	visit = new_visit
	_entry_position = entry_pos
	_browse_points = browse_points
	var customer: Dictionary = visit.customer
	display_name = "%s %s" % [customer.first_name, customer.last_name]
	prompt_text = "talk to %s" % display_name

	if already_browsing:
		position = _pick_browse_point()
		_state = State.BROWSING
		_start_browsing_dwell()
	else:
		position = entry_pos
		_browse_target = _pick_browse_point()
		_walking_to_browse_point = true
		_state = State.ENTERING

	_sync_collision_body()


## Called by CustomerDirector when Shop.customer_visit_resolved fires for
## this instance's visit -- transitions to LEAVING from wherever they
## currently are (mid-walk-between-points, dwelling, or even still mid-walk
## from ENTERING). Unconditional and idempotent on purpose: this used to only
## fire from BROWSING, on the assumption ENTERING always finishes well before
## a visit's resolve_timestamp -- true at 1x speed on a short walk, false at
## higher Clock speed levels or a long walk to a distant CustomerBrowsePoints
## entry, where ENTERING could still be in progress when the visit resolves.
## Shop.customer_visit_resolved only ever fires once per visit, so dropping it
## while _state == ENTERING left a customer stranded in BROWSING forever the
## moment they *did* arrive -- no further signal was ever coming, they were
## stuck (and, since Shop had already forgotten the visit, uninteractable:
## Shop.attempt_persuasion() found no matching active_visits entry), silently
## eating one of CustomerDirector.MAX_VISIBLE_CUSTOMERS' slots for good.
## _step_toward(_entry_position, ...) works correctly from any position, so
## there's no reason to gate this by current state at all.
func on_visit_resolved() -> void:
	_state = State.LEAVING


func _physics_process(delta: float) -> void:
	if Clock.is_paused:
		return

	match _state:
		State.ENTERING:
			if _step_toward(_browse_target, delta):
				_state = State.BROWSING
				_start_browsing_dwell()
		State.BROWSING:
			_process_browsing(delta)
		State.LEAVING:
			if _step_toward(_entry_position, delta):
				despawn_requested.emit(self)

	_sync_collision_body()


func _process_browsing(delta: float) -> void:
	if _walking_to_browse_point:
		if _step_toward(_browse_target, delta):
			_walking_to_browse_point = false
			_start_browsing_dwell()
		return

	play_directional_animation(false, Vector2.ZERO)
	_browsing_idle_timer -= delta
	if _browsing_idle_timer <= 0.0:
		_browse_target = _pick_browse_point()
		_walking_to_browse_point = true


func _start_browsing_dwell() -> void:
	play_directional_animation(false, Vector2.ZERO)
	_browsing_idle_timer = Rng.range_f(BROWSE_DWELL_MIN_SECONDS, BROWSE_DWELL_MAX_SECONDS)


## Picks a random browse point, preferring one that isn't wherever we
## currently are so a customer with 2+ points to choose from actually moves
## instead of re-"picking" the spot it's already standing on. Falls back to
## _entry_position (never crashes) if CustomerDirector ever hands over an
## empty list -- shouldn't happen with a correctly set-up room, but a
## misconfigured one degrades to "customer stands still" rather than erroring.
func _pick_browse_point() -> Vector2:
	if _browse_points.is_empty():
		return _entry_position
	if _browse_points.size() == 1:
		return _browse_points[0]
	var candidates := _browse_points.filter(func(p: Vector2) -> bool: return p != position)
	if candidates.is_empty():
		candidates = _browse_points
	return candidates[Rng.range_i(0, candidates.size() - 1)]


## Steps position toward target, returns true once arrived (and stops
## moving) -- caller decides what "arrived" means for its current state.
func _step_toward(target: Vector2, delta: float) -> bool:
	var to_target := target - position
	if to_target.length() <= ARRIVE_DISTANCE:
		return true
	var direction := to_target.normalized()
	position += direction * MOVE_SPEED * delta
	play_directional_animation(true, direction)
	return false


func _sync_collision_body() -> void:
	_collision_body.global_position = global_position


## Tries an Insight persuasion roll against this customer (Shop.
## attempt_persuasion(), see docs/design/systems.md system 5) -- one attempt
## per visit; every subsequent interact() just re-shows the flavor line. The
## roll itself (RollDisplay callout) is shown by GameHud, which listens to
## Shop.persuasion_attempted directly rather than being driven from here, so
## it fires the same way whether the player or Garnet triggered it.
func interact(main: MainScene) -> void:
	var customer: Dictionary = visit.get("customer", {})
	if customer.is_empty():
		return
	var result := Shop.attempt_persuasion(visit.get("visit_id", -1))
	if result.is_empty():
		main.hud.log_message("%s %s (%s) is browsing, looking for something %s." % [
			customer.first_name,
			customer.last_name,
			customer.occupation,
			customer.wanted_tag,
		])
		return
	if result.passed:
		main.hud.log_message("Your pitch lands with %s %s." % [customer.first_name, customer.last_name])
	else:
		main.hud.log_message("%s %s doesn't seem convinced." % [customer.first_name, customer.last_name])
