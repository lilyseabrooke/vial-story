class_name LeyLineMinigamePanel
extends Control
## The Ley Line resonance minigame. One instance owned by hud.gd, hosted in a
## dedicated LeyLineArenaOverlay (not MenuScene) while a LeyLines session is
## active, and reused per-open via show_for(), the same "build once, populate
## per-open" shape as AttemptPuzzlePanel.show_for(). Unlike every other
## minigame/menu, this one is deliberately chromeless -- no frame, no title,
## no round/difficulty text, no bonus-mote tracker, no close button, and Esc
## is blocked outright while it's open (see main.gd's _unhandled_input, gated
## on LeyLines.is_active()) -- see LeyLineArenaOverlay for why. This class is
## now just a thin wrapper: it owns the LeyArena, forwards the inspector-
## exported tunables into it, and relays LeyArena.finished to
## LeyLines.resolve_minigame(). Nothing in LeyLines / LeyLineNodeInteractable
## knows this file grew a real minigame -- the swap is entirely below this
## line.
##
## Gameplay: a big circle is the ley line node; the player steers a small icon
## (WASD or arrow keys) around it. Everything is dangerous except a few small
## safe zones. Each round a resonance ring collapses to the center; when it
## snaps, the game measures how much of the icon overlaps a safe zone. Danger
## overlap costs Resolve *now* (proportional to the caught fraction, like
## Brewing charging Resolve on a botch), and the average safe fraction across
## all rounds is the performance handed to LeyLines at the end.
##
## Movement is velocity-based with acceleration/friction so it has weight but
## stays responsive; Arcane History (Skills.level) shrinks the icon and makes
## it faster and snappier -- so a skilled arcanist both fits safe zones more
## easily and commits to them more precisely. Difficulty (already softened by
## leyline_ease upstream) shrinks the safe zones, shortens the timer, and
## makes the zones drift and shrink as the ring collapses -- the high-skill
## element is tracking that moving, shrinking target and arriving centered.
## Safe-zone radius has a hard floor (`zone_radius_min`) that difficulty can
## never shrink past -- past that point difficulty instead spawns solid
## obstacles (`obstacle_count`, some stationary, some drifting like the safe
## zones) that block the icon outright rather than merely costing Resolve, so
## higher difficulty keeps adding real navigation pressure instead of asking
## for pixel-perfect zone-fitting against an ever-shrinking target.
##
## LeyLineArenaOverlay only flips Clock.is_paused (a flag the player polls);
## it never pauses the SceneTree, so the arena's _process/_draw run normally
## while it's open. WASD/arrows are polled here and don't collide with
## main.gd's _unhandled_input hotkeys (Space/E/R/1/2/3 -- Esc is blocked
## entirely, see above).
##
## A triggering Surge's size/speed (LeyLineSurgeDef, see LeyLines) additionally
## shape a run: size divides icon/zone/mote radii (the arena's fixed-pixel
## canvas doesn't grow, so a bigger Size just makes everything in it smaller
## relative to that canvas, i.e. more distance to cover), and speed divides
## each round's collapse timer (round_time) so the ring closes faster. Both
## floor to 1.0 -- size can't shrink the arena below its current baseline, and
## a non-positive speed is treated as no change -- see LeyArena.start_run().
##
## The arena is natively 880x880 (LeyArena.ARENA_SIZE) -- doubled from an
## earlier 440x440 pass deliberately *not* left as a Control.scale rendering
## transform. A transform scale is fine for vector draw calls (which the
## arena is entirely made of today) but would degrade any future illustrated
## sprite art, since a texture gets sampled at its native resolution and then
## stretched by the transform same as any other bitmap upscale. Every
## spatial tunable here (radii, drift/movement speeds, padding constants) is
## authored directly at the arena's real 880x880 scale instead, so a sprite
## dropped in later at its intended on-screen size renders natively with no
## resampling. Purely temporal values (round_time, lead_in, flash_time,
## results_time) and dimensionless ratios (zone_shrink, turn_response,
## wall_bounce, *_variance, *_chance) don't scale with space and are
## unchanged.

# --- Tunables, editable in the inspector on LeyLineMinigamePanel.tscn ---
# These live on the outer (scene-root) class rather than on the inner LeyArena
# because Godot doesn't surface an inner class's @exports in the inspector.
# build() forwards them into _arena via _configure_arena() before any run.
# Difficulty-curve values are Vector2(easy, hard); Arcane-History-curve values
# are Vector2(novice, skilled); the .x/.y ends are lerped per run.

@export_group("Difficulty Curve (easy → hard)")
## difficulty value that maps to the hardest end of every curve (norm 1.0).
## Surge difficulty is authored on the game's usual ~0-10 scale (and can run
## higher still) -- difficulty_norm clamps at 1.0, so anything at or past this
## span just plays at the hardest tier rather than escalating further.
@export var difficulty_span: float = 10.0
@export var round_time := Vector2(4.5, 2.0)          ## seconds of ring collapse
@export var lead_in: float = 0.6                     ## fixed read time before the ring collapses
@export var zone_radius := Vector2(124.0, 44.0)      ## safe-zone radius
## Hard floor on safe-zone radius (after difficulty shrink, in-round shrink,
## and Surge size scaling) -- difficulty can never push a zone smaller than
## this, no matter how high it climbs. Extra difficulty past that point goes
## into obstacles instead (see the Obstacles group below).
@export var zone_radius_min: float = 40.0
@export var zone_shrink := Vector2(1.0, 0.55)        ## end/start radius ratio over the round
@export var zone_drift := Vector2(0.0, 120.0)        ## px/s the zones wander
@export var zone_count := Vector2(3, 1)              ## number of safe zones (rounded)
@export var max_resolve_per_round: float = 12.0      ## fully-in-danger cost, before difficulty weight

@export_group("Obstacles (easy → hard)")
## Number of solid obstacles blocking the icon, rounded; 0 at the easy end so
## low-difficulty runs stay obstacle-free.
@export var obstacle_count := Vector2(0, 4)
@export var obstacle_radius: float = 48.0            ## obstacle base radius (scales with Surge size like everything else)
## Per-obstacle random multiplier on obstacle_radius (x = smallest, y =
## largest), rolled independently for every obstacle so a single run has a
## mix of sizes rather than identical hazards.
@export var obstacle_radius_variance := Vector2(0.6, 1.5)
## Per-obstacle chance of drifting like a safe zone instead of sitting still.
@export var obstacle_moving_chance := Vector2(0.0, 0.5)
@export var obstacle_speed := Vector2(80.0, 220.0)   ## px/s for moving obstacles

@export_group("Arcane History Curve (novice → skilled)")
## Arcane History level that reaches the skilled end of every curve.
@export var level_cap: float = 6.0
@export var icon_radius := Vector2(40.0, 20.0)       ## player icon radius
@export var max_speed := Vector2(480.0, 860.0)       ## px/s
@export var accel := Vector2(1500.0, 7200.0)         ## px/s^2 to speed up
@export var friction := Vector2(1200.0, 6800.0)      ## px/s^2 decel when idle
## How readily acceleration can fight existing momentum (how sharply the icon
## turns). Below 1.0, the accel component opposing current velocity is damped,
## so a novice's momentum must bleed off before a reversal takes.
@export var turn_response := Vector2(0.42, 1.0)

@export_group("Timing")
@export var flash_time: float = 0.45                 ## snap flash before the next round
@export var results_time: float = 1.8                ## final grade held on screen before reporting out

@export_group("Bonus Mote & Wall")
## Per-round chance a gold bonus mote spawns. Touching it banks one extra
## spectral ingredient, granted at the end regardless of safe-zone tier -- but
## it's placed away from safe zones, so grabbing it pulls you out of position.
@export var bonus_chance: float = 0.45
@export var bonus_radius: float = 24.0               ## mote radius (its catch size)
## Fraction of speed kept when bouncing off the arena wall (1.0 = no loss).
@export var wall_bounce: float = 0.85

var _arena: LeyArena


func build() -> void:
	_arena = LeyArena.new()
	_configure_arena()
	add_child(_arena)
	_arena.finished.connect(_on_finished)
	custom_minimum_size = get_effective_size()


## The arena's on-screen footprint -- kept as its own accessor (rather than
## having LeyLineArenaOverlay read _arena.custom_minimum_size directly) so a
## future resize doesn't need to touch the overlay's centering math too.
func get_effective_size() -> Vector2:
	return _arena.custom_minimum_size


## surge_size/surge_speed come straight from the triggering Surge
## (LeyLineSurgeDef.size/.speed) -- named to avoid shadowing Control's own
## `size` property. surge_size < 1.0 and surge_speed <= 0.0 are both floored
## to 1.0 (no change) inside LeyArena.start_run(), same "the panel doesn't
## validate, the arena does" split as every other run-shaping value here.
func show_for(_node_id: String, difficulty: float, rounds: int, surge_size: float, surge_speed: float) -> void:
	var difficulty_norm := clampf(difficulty / difficulty_span, 0.0, 1.0)
	var arcane_level := Skills.level("arcane_history")
	_arena.start_run(difficulty_norm, rounds, arcane_level, surge_size, surge_speed)


## Push the inspector-exported curve values into the arena. Called once from
## build(); the arena holds them as plain vars and lerps their .x/.y ends per
## run, so re-tuning in the inspector takes effect on the next minigame open.
func _configure_arena() -> void:
	_arena.round_time = round_time
	_arena.lead_in = lead_in
	_arena.zone_radius = zone_radius
	_arena.zone_radius_min = zone_radius_min
	_arena.zone_shrink = zone_shrink
	_arena.zone_drift = zone_drift
	_arena.zone_count = zone_count
	_arena.max_resolve_per_round = max_resolve_per_round
	_arena.obstacle_count = obstacle_count
	_arena.obstacle_radius = obstacle_radius
	_arena.obstacle_radius_variance = obstacle_radius_variance
	_arena.obstacle_moving_chance = obstacle_moving_chance
	_arena.obstacle_speed = obstacle_speed
	_arena.level_cap = level_cap
	_arena.icon_radius = icon_radius
	_arena.max_speed = max_speed
	_arena.accel = accel
	_arena.friction = friction
	_arena.turn_response = turn_response
	_arena.flash_time = flash_time
	_arena.results_time = results_time
	_arena.bonus_chance = bonus_chance
	_arena.bonus_radius = bonus_radius
	_arena.wall_bounce = wall_bounce


func _on_finished(performance: float, bonus: int) -> void:
	LeyLines.resolve_minigame(performance, bonus)


# ===========================================================================
# LeyArena -- the custom-drawn playfield. Kept as an inner class so the whole
# minigame is one swappable file (per the system's design note); it's a real
# Control instance once added to the tree, so its _process/_draw fire normally.
# ===========================================================================

class LeyArena extends Control:

	signal finished(performance: float, bonus: int)

	const ARENA_SIZE := 880.0
	const ARENA_RADIUS := 410.0
	const EDGE_PAD := 12.0

	# Tuning curves, set by LeyLineMinigamePanel._configure_arena() from its
	# inspector @exports before start_run(). The defaults here are just a
	# fallback if the arena is ever used standalone -- the panel overwrites
	# all of them. Difficulty curve is Vector2(easy, hard); Arcane History
	# curve is Vector2(novice, skilled); .x/.y are lerped per run.
	var round_time := Vector2(4.5, 2.0)
	var lead_in := 0.6
	var zone_radius := Vector2(124.0, 44.0)
	var zone_radius_min := 40.0
	var zone_shrink := Vector2(1.0, 0.55)
	var zone_drift := Vector2(0.0, 120.0)
	var zone_count := Vector2(3, 1)
	var max_resolve_per_round := 12.0
	var obstacle_count := Vector2(0, 4)
	var obstacle_radius := 48.0
	var obstacle_radius_variance := Vector2(0.6, 1.5)
	var obstacle_moving_chance := Vector2(0.0, 0.5)
	var obstacle_speed := Vector2(80.0, 220.0)
	var level_cap := 6.0
	var icon_radius := Vector2(40.0, 20.0)
	var max_speed := Vector2(480.0, 860.0)
	var accel := Vector2(1500.0, 7200.0)
	var friction := Vector2(1200.0, 6800.0)
	var turn_response := Vector2(0.42, 1.0)
	var flash_time := 0.45
	var results_time := 1.8
	var bonus_chance := 0.45
	var bonus_radius := 24.0
	var wall_bounce := 0.85

	enum State { IDLE, LEAD_IN, COUNT, FLASH, RESULTS }

	# tuned per run from difficulty / Arcane History
	var _difficulty_norm := 0.0
	var _rounds := 3
	var _icon_r := 30.0
	var _max_speed := 600.0
	var _accel := 4000.0
	var _friction := 4000.0
	var _turn_response := 1.0
	var _zone_base_r := 80.0
	var _zone_shrink := 1.0
	var _drift_speed := 0.0
	var _zone_count := 2
	var _round_time := 3.5
	## Surge Size, floored to 1.0 (the arena's own minimum) -- divides icon/zone/
	## mote radii so a bigger Size makes everything in the fixed-pixel arena
	## relatively smaller, i.e. a bigger space to cover without the canvas
	## itself changing size.
	var _size := 1.0
	var _bonus_r := 24.0   ## bonus_radius, scaled down by _size for this run
	var _obstacle_count := 0
	var _obstacle_r := 48.0
	var _obstacle_moving_chance := 0.0
	var _obstacle_speed_val := 0.0

	var _state: int = State.IDLE
	var _round_index := 0
	var _timer := 0.0
	var _time_left := 0.0

	var _player_pos := Vector2.ZERO   # relative to arena center
	var _vel := Vector2.ZERO
	var _zones: Array = []            # each: {pos: Vector2, drift: Vector2, r: float}
	var _zone_r_now := 80.0          # current (shrunk) zone radius this frame
	var _obstacles: Array = []       # each: {pos: Vector2, drift: Vector2, r: float} -- drift ZERO = stationary

	var _scores: Array = []          # per-round safe fraction 0..1
	var _resolve_lost := 0
	var _last_safe := 0.0            # for FLASH/RESULTS readout
	var _performance := 0.0

	var _mote_active := false        # a gold bonus mote is present this round
	var _mote_pos := Vector2.ZERO
	var _bonus_collected := 0        # motes banked across the whole run
	var _mote_pop_t := 0.0           # collection-flash countdown
	var _mote_pop_pos := Vector2.ZERO
	var _anim_t := 0.0               # free-running clock for pulse visuals


	func _init() -> void:
		custom_minimum_size = Vector2(ARENA_SIZE, ARENA_SIZE)
		set_process(false)


	## surge_size/surge_speed come from the triggering Surge
	## (LeyLineSurgeDef.size/.speed), already forwarded through
	## LeyLines.minigame_started and LeyLineMinigamePanel.show_for() unclamped
	## -- this is where the actual "below 1.0 clamps to 1.0" floor for both
	## gets applied, same place every other run-shaping value here gets
	## resolved from its raw input. Named surge_* (not size/speed) because this
	## class extends Control, which already has its own `size` property.
	func start_run(difficulty_norm: float, rounds: int, arcane_level: int, surge_size: float, surge_speed: float) -> void:
		_difficulty_norm = difficulty_norm
		_rounds = maxi(rounds, 1)
		_size = maxf(surge_size, 1.0)
		var speed_mult := surge_speed if surge_speed > 0.0 else 1.0

		var lvl := clampf(float(arcane_level) / level_cap, 0.0, 1.0)
		_icon_r = lerpf(icon_radius.x, icon_radius.y, lvl) / _size
		_max_speed = lerpf(max_speed.x, max_speed.y, lvl)
		_accel = lerpf(accel.x, accel.y, lvl)
		_friction = lerpf(friction.x, friction.y, lvl)
		_turn_response = lerpf(turn_response.x, turn_response.y, lvl)

		_zone_base_r = maxf(lerpf(zone_radius.x, zone_radius.y, difficulty_norm) / _size, zone_radius_min)
		_zone_shrink = lerpf(zone_shrink.x, zone_shrink.y, difficulty_norm)
		_drift_speed = lerpf(zone_drift.x, zone_drift.y, difficulty_norm)
		_zone_count = int(roundf(lerpf(zone_count.x, zone_count.y, difficulty_norm)))
		_round_time = lerpf(round_time.x, round_time.y, difficulty_norm) / speed_mult
		_bonus_r = bonus_radius / _size

		_obstacle_count = int(roundf(lerpf(obstacle_count.x, obstacle_count.y, difficulty_norm)))
		_obstacle_r = obstacle_radius / _size
		_obstacle_moving_chance = lerpf(obstacle_moving_chance.x, obstacle_moving_chance.y, difficulty_norm)
		_obstacle_speed_val = lerpf(obstacle_speed.x, obstacle_speed.y, difficulty_norm)

		_round_index = 0
		_scores.clear()
		_resolve_lost = 0
		_performance = 0.0
		_bonus_collected = 0
		_mote_active = false
		_mote_pop_t = 0.0
		_player_pos = Vector2.ZERO
		_vel = Vector2.ZERO

		_begin_round()
		set_process(true)


	func _begin_round() -> void:
		_generate_zones()
		_generate_obstacles()
		_maybe_spawn_mote()
		_zone_r_now = _zone_base_r
		_timer = lead_in
		_time_left = _round_time
		_state = State.LEAD_IN


	## Occasionally drop a gold bonus mote, placed clear of the safe zones and
	## the player's current spot so going for it genuinely trades away safe
	## position. Leaves _mote_active false if no clear spot turns up.
	func _maybe_spawn_mote() -> void:
		_mote_active = false
		if not Rng.chance(bonus_chance):
			return
		for _attempt in 16:
			var ang := Rng.range_f(0.0, TAU)
			var dist := ARENA_RADIUS * Rng.range_f(0.35, 0.85)
			var pos := Vector2.from_angle(ang) * dist
			if pos.distance_to(_player_pos) < ARENA_RADIUS * 0.3:
				continue
			var near_zone := false
			for z in _zones:
				if pos.distance_to(z.pos) < z.r + _bonus_r + 40.0:
					near_zone = true
					break
			if near_zone:
				continue
			var near_obstacle := false
			for o in _obstacles:
				if pos.distance_to(o.pos) < o.r + _bonus_r + 24.0:
					near_obstacle = true
					break
			if near_obstacle:
				continue
			_mote_pos = pos
			_mote_active = true
			return


	func _generate_zones() -> void:
		_zones.clear()
		for i in _zone_count:
			var pos := Vector2.ZERO
			# A few tries to place each zone away from the player and from the
			# zones already placed, so there's always somewhere to travel.
			for _attempt in 8:
				var ang := TAU * (float(i) + Rng.range_f(-0.35, 0.35)) / float(_zone_count)
				var dist := ARENA_RADIUS * Rng.range_f(0.38, 0.82)
				pos = Vector2.from_angle(ang) * dist
				if pos.distance_to(_player_pos) < ARENA_RADIUS * 0.45:
					continue
				var clash := false
				for z in _zones:
					if pos.distance_to(z.pos) < _zone_base_r * 2.6:
						clash = true
						break
				if not clash:
					break
			var drift := Vector2.from_angle(Rng.range_f(0.0, TAU)) * _drift_speed
			_zones.append({"pos": pos, "drift": drift, "r": _zone_base_r})


	## Solid obstacles the icon can't pass through -- difficulty's overflow once
	## zone_radius_min stops it from shrinking safe zones any further. Placed
	## clear of the player and safe zones (a few tries each, same "give up and
	## accept the last-tried spot" shape as _generate_zones()), then given a
	## chance to drift like a safe zone instead of sitting still. Each
	## obstacle's radius is independently rolled off obstacle_radius_variance
	## so a run has a mix of sizes rather than identical hazards.
	func _generate_obstacles() -> void:
		_obstacles.clear()
		for _i in _obstacle_count:
			var r := _obstacle_r * Rng.range_f(obstacle_radius_variance.x, obstacle_radius_variance.y)
			var pos := Vector2.ZERO
			for _attempt in 10:
				var ang := Rng.range_f(0.0, TAU)
				var dist := ARENA_RADIUS * Rng.range_f(0.25, 0.85)
				pos = Vector2.from_angle(ang) * dist
				if pos.distance_to(_player_pos) < ARENA_RADIUS * 0.35:
					continue
				var clash := false
				for z in _zones:
					if pos.distance_to(z.pos) < z.r + r + 48.0:
						clash = true
						break
				if not clash:
					for o in _obstacles:
						if pos.distance_to(o.pos) < (r + o.r) * 1.2:
							clash = true
							break
				if not clash:
					break
			var drift := Vector2.ZERO
			if Rng.chance(_obstacle_moving_chance):
				drift = Vector2.from_angle(Rng.range_f(0.0, TAU)) * _obstacle_speed_val
			# rot/cross only drive the shard's drawn shape (two crossed bars, see
			# _draw()) -- collision stays a plain circle against r for now, a
			# simple bounding-shape stand-in for the eventual sprite + fitted
			# collision shape.
			var rot := Rng.range_f(0.0, TAU)
			var cross := Rng.range_f(deg_to_rad(55.0), deg_to_rad(125.0))
			_obstacles.append({"pos": pos, "drift": drift, "r": r, "rot": rot, "cross": cross})


	func _process(delta: float) -> void:
		_anim_t += delta
		if _mote_pop_t > 0.0:
			_mote_pop_t = maxf(_mote_pop_t - delta, 0.0)
		match _state:
			State.LEAD_IN:
				_update_obstacles(delta)
				_update_movement(delta)
				_timer -= delta
				if _timer <= 0.0:
					_state = State.COUNT
			State.COUNT:
				_update_obstacles(delta)
				_update_movement(delta)
				_update_zones(delta)
				_time_left -= delta
				if _time_left <= 0.0:
					_resonate()
			State.FLASH:
				_timer -= delta
				if _timer <= 0.0:
					_advance_round()
			State.RESULTS:
				_timer -= delta
				if _timer <= 0.0:
					_finish()
		queue_redraw()


	func _update_movement(delta: float) -> void:
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			dir.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			dir.x += 1.0
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			dir.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			dir.y += 1.0

		if dir != Vector2.ZERO:
			var accel_vec := dir.normalized() * _accel
			# Damp the part of the acceleration that fights current momentum,
			# scaled by Arcane History -- a novice turns sluggishly because
			# their steering can't overrule their drift as hard.
			if _turn_response < 1.0 and _vel.length() > 1.0:
				var vdir := _vel.normalized()
				var opposing := accel_vec.dot(vdir)
				if opposing < 0.0:
					accel_vec -= vdir * opposing * (1.0 - _turn_response)
			_vel += accel_vec * delta
			if _vel.length() > _max_speed:
				_vel = _vel.normalized() * _max_speed
		else:
			var drop := _friction * delta
			if _vel.length() <= drop:
				_vel = Vector2.ZERO
			else:
				_vel -= _vel.normalized() * drop

		_player_pos += _vel * delta

		# Keep the icon inside the arena and bounce it off the wall: reflect
		# the outward velocity component (damped by wall_bounce) so hitting the
		# edge sends you back in rather than pinning you to it.
		var limit := ARENA_RADIUS - _icon_r - EDGE_PAD
		if _player_pos.length() > limit:
			var n := _player_pos.normalized()
			_player_pos = n * limit
			var outward := _vel.dot(n)
			if outward > 0.0:
				_vel = (_vel - 2.0 * outward * n) * wall_bounce

		_resolve_obstacle_collisions()
		_check_mote_pickup()


	## Obstacles are solid: push the icon back out to the obstacle's edge and
	## reflect the velocity component driving it inward (same wall_bounce feel
	## as the arena's own edge), rather than letting it pass through or just
	## stopping dead against it.
	func _resolve_obstacle_collisions() -> void:
		for o in _obstacles:
			var offset: Vector2 = _player_pos - o.pos
			var min_dist: float = _icon_r + o.r
			var dist := offset.length()
			if dist >= min_dist:
				continue
			var n := offset / dist if dist > 0.0001 else Vector2.RIGHT
			_player_pos = o.pos + n * min_dist
			var inward := _vel.dot(n)
			if inward < 0.0:
				_vel = (_vel - 2.0 * inward * n) * wall_bounce


	## Drift + wall-bounce, identical shape to the safe zones' own drift in
	## _update_zones() -- stationary obstacles (drift == ZERO) are a no-op.
	func _update_obstacles(delta: float) -> void:
		for o in _obstacles:
			if o.drift == Vector2.ZERO:
				continue
			o.pos += o.drift * delta
			var limit: float = ARENA_RADIUS - o.r - EDGE_PAD
			if o.pos.length() > limit and o.pos.length() > 0.0:
				var n: Vector2 = o.pos.normalized()
				o.pos = n * limit
				o.drift = o.drift.bounce(n)


	## Collect the mote if the icon overlaps it. Cheap circle-vs-circle test run
	## every movement frame (LEAD_IN and COUNT), so a fast pass-through counts.
	func _check_mote_pickup() -> void:
		if not _mote_active:
			return
		if _player_pos.distance_to(_mote_pos) <= _icon_r + _bonus_r:
			_mote_active = false
			_bonus_collected += 1
			_mote_pop_t = 0.35
			_mote_pop_pos = _mote_pos


	func _update_zones(delta: float) -> void:
		var t := 1.0 - clampf(_time_left / _round_time, 0.0, 1.0)  # 0 at start, 1 at snap
		_zone_r_now = maxf(_zone_base_r * lerpf(1.0, _zone_shrink, t), zone_radius_min)
		for z in _zones:
			z.r = _zone_r_now
			z.pos += z.drift * delta
			# bounce the zone off the arena wall
			var limit: float = ARENA_RADIUS - z.r - EDGE_PAD
			if z.pos.length() > limit and z.pos.length() > 0.0:
				var n: Vector2 = z.pos.normalized()
				z.pos = n * limit
				z.drift = z.drift.bounce(n)


	func _resonate() -> void:
		var safe := _best_safe_fraction()
		_last_safe = safe
		_scores.append(safe)

		var danger := 1.0 - safe
		var weight := 0.6 + 0.6 * _difficulty_norm
		var cost := int(roundf(danger * max_resolve_per_round * weight))
		if cost > 0:
			_resolve_lost += cost
			Resolve.spend(cost, "ley line resonance")

		_timer = flash_time
		_state = State.FLASH


	func _advance_round() -> void:
		_round_index += 1
		if _round_index >= _rounds:
			var total := 0.0
			for s in _scores:
				total += s
			_performance = total / float(_scores.size()) if not _scores.is_empty() else 0.0
			_timer = results_time
			_state = State.RESULTS
		else:
			_begin_round()


	func _finish() -> void:
		set_process(false)
		_state = State.IDLE
		finished.emit(_performance, _bonus_collected)


	## Best coverage of the icon by any single safe zone, 0..1. Zones are
	## spaced apart on spawn so straddling two is neither expected nor
	## rewarded -- max-of-one is a faithful, predictable read for the player.
	func _best_safe_fraction() -> float:
		var icon_area := PI * _icon_r * _icon_r
		var best := 0.0
		for z in _zones:
			var d: float = _player_pos.distance_to(z.pos)
			var frac := _lens_area(d, _icon_r, z.r) / icon_area
			best = maxf(best, clampf(frac, 0.0, 1.0))
		return best


	## Area of intersection of two circles (radii r1, r2, centers d apart).
	func _lens_area(d: float, r1: float, r2: float) -> float:
		if d >= r1 + r2:
			return 0.0
		if d <= absf(r1 - r2):
			var rm := minf(r1, r2)
			return PI * rm * rm
		var r1s := r1 * r1
		var r2s := r2 * r2
		var d1 := (d * d - r2s + r1s) / (2.0 * d)
		var d2 := d - d1
		var a1 := r1s * acos(clampf(d1 / r1, -1.0, 1.0)) - d1 * sqrt(maxf(r1s - d1 * d1, 0.0))
		var a2 := r2s * acos(clampf(d2 / r2, -1.0, 1.0)) - d2 * sqrt(maxf(r2s - d2 * d2, 0.0))
		return a1 + a2


	# -----------------------------------------------------------------------
	# Drawing
	# -----------------------------------------------------------------------

	## One rectangular "bar" of an obstacle's crossed-shard shape: a narrow
	## rect (long along `angle`), centered on `center`, sized off `r` -- two of
	## these at different angles (see _draw()'s obstacle loop) is the whole
	## shape. Kept a simple oversized rect rather than trying to look like a
	## realistic crystal; this is explicitly a placeholder for a future sprite.
	func _shard_bar_points(center: Vector2, r: float, angle: float) -> PackedVector2Array:
		var half_len := r * 1.05
		var half_w := r * 0.36
		var local := [
			Vector2(-half_len, -half_w), Vector2(half_len, -half_w),
			Vector2(half_len, half_w), Vector2(-half_len, half_w),
		]
		var pts := PackedVector2Array()
		for p in local:
			pts.append(center + p.rotated(angle))
		return pts


	func _draw() -> void:
		var c := Vector2(ARENA_SIZE, ARENA_SIZE) * 0.5

		# Danger field: the whole node is hostile. Flare it on the snap flash.
		var flaring := _state == State.FLASH
		var danger := Color(0.30, 0.06, 0.12) if not flaring else Color(0.62, 0.10, 0.16)
		draw_circle(c, ARENA_RADIUS, danger)
		draw_arc(c, ARENA_RADIUS, 0.0, TAU, 64, Color(0.75, 0.2, 0.28, 0.8), 6.0, true)

		# Safe zones: soft green glow with a bright rim.
		for z in _zones:
			var zp: Vector2 = c + z.pos
			var zr: float = z.r
			draw_circle(zp, zr, Color(0.20, 0.70, 0.45, 0.30))
			draw_circle(zp, zr * 0.6, Color(0.35, 0.90, 0.55, 0.35))
			draw_arc(zp, zr, 0.0, TAU, 40, Color(0.55, 1.0, 0.70, 0.95), 5.0, true)

		# Obstacles: a jagged crystal-shard cluster (two crossed bars) rather
		# than a circle, so it reads clearly as a distinct hazard type at a
		# glance instead of blending in with zones/mote -- a stand-in for a
		# future sprite with its own fitted collision. Gray if stationary,
		# amber if drifting.
		for o in _obstacles:
			var op: Vector2 = c + o.pos
			var stationary: bool = o.drift == Vector2.ZERO
			var ocol := Color(0.4, 0.4, 0.46) if stationary else Color(0.6, 0.42, 0.18)
			var oline := Color(0.12, 0.12, 0.15, 0.9)
			for bar_angle in [o.rot, o.rot + o.cross]:
				var pts := _shard_bar_points(op, o.r, bar_angle)
				draw_colored_polygon(pts, ocol)
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), oline, 4.0, true)

		# Resonance ring: collapses from the wall to the center as time runs
		# out; during LEAD_IN it holds at the wall so the round can be read.
		var ring_t := 1.0
		if _state == State.COUNT:
			ring_t = clampf(_time_left / _round_time, 0.0, 1.0)
		if _state == State.COUNT or _state == State.LEAD_IN:
			var ring_r := lerpf(_icon_r + 8.0, ARENA_RADIUS, ring_t)
			var urgency := 1.0 - ring_t
			var ring_col := Color(0.9, 0.85, 0.5).lerp(Color(1.0, 0.35, 0.35), urgency)
			draw_arc(c, ring_r, 0.0, TAU, 56, ring_col, 6.0, true)

		# Bonus mote: a pulsing gold spark. Placed away from safe zones, so
		# it's the risk/reward beat -- grab it or hold your safe position.
		if _mote_active:
			var mp: Vector2 = c + _mote_pos
			var pulse := 0.5 + 0.5 * sin(_anim_t * 6.0)
			draw_circle(mp, _bonus_r + 12.0 + 6.0 * pulse, Color(1.0, 0.85, 0.3, 0.18))
			draw_circle(mp, _bonus_r, Color(1.0, 0.82, 0.25, 0.55))
			draw_circle(mp, _bonus_r * 0.55, Color(1.0, 0.95, 0.7, 0.95))
			draw_arc(mp, _bonus_r, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, 0.9), 4.0, true)

		# Collection flash: an expanding, fading gold ring where a mote was grabbed.
		if _mote_pop_t > 0.0:
			var pt := _mote_pop_t / 0.35            # 1 -> 0
			var pop_r := lerpf(_bonus_r + 8.0, _bonus_r + 68.0, 1.0 - pt)
			draw_arc(c + _mote_pop_pos, pop_r, 0.0, TAU, 28, Color(1.0, 0.9, 0.5, pt), 6.0, true)

		# Player icon: tinted toward green when safe, red when exposed.
		var pp: Vector2 = c + _player_pos
		var safe_now := _best_safe_fraction()
		var icon_col := Color(0.85, 0.35, 0.3).lerp(Color(0.4, 1.0, 0.6), safe_now)
		if safe_now >= 0.999:
			draw_circle(pp, _icon_r + 8.0, Color(0.5, 1.0, 0.7, 0.35))
		draw_circle(pp, _icon_r, icon_col)
		draw_arc(pp, _icon_r, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 4.0, true)

		if _state == State.RESULTS:
			_draw_results(c)


	func _draw_results(c: Vector2) -> void:
		var font := get_theme_default_font()
		var font_size := 52
		var pct := int(roundf(_performance * 100.0))
		var grade := "Great!" if _performance >= 0.85 else \
			("Good" if _performance >= 0.6 else \
			("Rough" if _performance >= 0.25 else "Lost it"))
		var text := "%s  %d%% safe" % [grade, pct]
		if _bonus_collected > 0:
			text += "   +%d bonus" % _bonus_collected
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var bg := Color(0.05, 0.05, 0.08, 0.72)
		draw_rect(Rect2(c.x - tw * 0.5 - 32, c.y - 52, tw + 64, 104), bg)
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + 16), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.95, 1.0))
