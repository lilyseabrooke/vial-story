class_name LeyLineMinigamePanel
extends VBoxContainer
## The Ley Line resonance minigame, hosted by MenuScene while a LeyLines
## session is active. One instance owned by hud.gd, opened in response to
## LeyLines.minigame_started and reused per-open via show_for(), the same
## "build once, populate per-open" shape as AttemptPuzzlePanel.show_for().
##
## Contract with the rest of the system (unchanged from the placeholder it
## replaces): report a single 0.0-1.0 performance number to
## LeyLines.resolve_minigame() when finished, or LeyLines.abort_minigame() to
## bail (which MenuScene.closed handles for us on any Esc/close). Nothing in
## LeyLines / LeyLineNodeInteractable / hud.gd's wiring knows this file grew a
## real minigame -- the swap is entirely below this line.
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
##
## MenuScene only flips Clock.is_paused (a flag the player polls); it never
## pauses the SceneTree, so the arena's _process/_draw run normally while the
## menu is open. WASD/arrows are polled here and don't collide with main.gd's
## _unhandled_input hotkeys (Space/Esc/E/R/1/2/3).

# --- Tunables, editable in the inspector on LeyLineMinigamePanel.tscn ---
# These live on the outer (scene-root) class rather than on the inner LeyArena
# because Godot doesn't surface an inner class's @exports in the inspector.
# build() forwards them into _arena via _configure_arena() before any run.
# Difficulty-curve values are Vector2(easy, hard); Arcane-History-curve values
# are Vector2(novice, skilled); the .x/.y ends are lerped per run.

@export_group("Difficulty Curve (easy → hard)")
## difficulty value that maps to the hardest end of every curve (norm 1.0)
@export var difficulty_span: float = 3.0
@export var round_time := Vector2(4.5, 2.0)          ## seconds of ring collapse
@export var lead_in: float = 0.6                     ## fixed read time before the ring collapses
@export var zone_radius := Vector2(62.0, 22.0)       ## safe-zone radius
@export var zone_shrink := Vector2(1.0, 0.55)        ## end/start radius ratio over the round
@export var zone_drift := Vector2(0.0, 60.0)         ## px/s the zones wander
@export var zone_count := Vector2(3, 1)              ## number of safe zones (rounded)
@export var max_resolve_per_round: float = 12.0      ## fully-in-danger cost, before difficulty weight

@export_group("Arcane History Curve (novice → skilled)")
## Arcane History level that reaches the skilled end of every curve.
@export var level_cap: float = 6.0
@export var icon_radius := Vector2(20.0, 10.0)       ## player icon radius
@export var max_speed := Vector2(240.0, 430.0)       ## px/s
@export var accel := Vector2(750.0, 3600.0)          ## px/s^2 to speed up
@export var friction := Vector2(600.0, 3400.0)       ## px/s^2 decel when idle
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
@export var bonus_radius: float = 12.0               ## mote radius (its catch size)
## Fraction of speed kept when bouncing off the arena wall (1.0 = no loss).
@export var wall_bounce: float = 0.85

var _arena: LeyArena
var _status_label: Label
var _hint_label: Label


func build() -> void:
	custom_minimum_size = Vector2(460, 0)
	alignment = BoxContainer.ALIGNMENT_CENTER

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 15)
	add_child(_status_label)

	_arena = LeyArena.new()
	_arena.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_configure_arena()
	add_child(_arena)
	_arena.round_started.connect(_on_round_started)
	_arena.resolve_charged.connect(_on_resolve_charged)
	_arena.bonus_collected.connect(_on_bonus_collected)
	_arena.finished.connect(_on_finished)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.modulate = Color(0.65, 0.65, 0.7)
	_hint_label.text = "WASD / arrows to steer. Sit fully inside a glowing zone before the ring snaps shut."
	add_child(_hint_label)


func show_for(_node_id: String, difficulty: float, rounds: int) -> void:
	var difficulty_norm := clampf(difficulty / difficulty_span, 0.0, 1.0)
	var arcane_level := Skills.level("arcane_history")
	_status_label.text = "%s  —  Round 1 / %d" % [_difficulty_word(difficulty_norm), rounds]
	_arena.start_run(difficulty_norm, rounds, arcane_level)


## Push the inspector-exported curve values into the arena. Called once from
## build(); the arena holds them as plain vars and lerps their .x/.y ends per
## run, so re-tuning in the inspector takes effect on the next minigame open.
func _configure_arena() -> void:
	_arena.round_time = round_time
	_arena.lead_in = lead_in
	_arena.zone_radius = zone_radius
	_arena.zone_shrink = zone_shrink
	_arena.zone_drift = zone_drift
	_arena.zone_count = zone_count
	_arena.max_resolve_per_round = max_resolve_per_round
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


func _on_round_started(round_index: int, total: int, difficulty_norm: float) -> void:
	_status_label.text = "%s  —  Round %d / %d" % [_difficulty_word(difficulty_norm), round_index + 1, total]


func _on_resolve_charged(_amount: int, total: int) -> void:
	if total > 0:
		_hint_label.text = "Resolve lost so far: %d" % total


func _on_bonus_collected(total: int) -> void:
	_hint_label.text = "Bonus mote collected! (%d banked)" % total


func _on_finished(performance: float, bonus: int) -> void:
	# LeyLines cleared its active session inside resolve_minigame() before
	# emitting minigame_resolved, so hud.gd's close_menu() won't trip the
	# "still active -> abort" guard. Nothing else to do here.
	LeyLines.resolve_minigame(performance, bonus)


func _difficulty_word(norm: float) -> String:
	if norm < 0.2:
		return "Placid ley line"
	if norm < 0.45:
		return "Stirring ley line"
	if norm < 0.7:
		return "Turbulent ley line"
	return "Violent ley line"


# ===========================================================================
# LeyArena -- the custom-drawn playfield. Kept as an inner class so the whole
# minigame is one swappable file (per the system's design note); it's a real
# Control instance once added to the tree, so its _process/_draw fire normally.
# ===========================================================================

class LeyArena extends Control:

	signal round_started(round_index: int, total: int, difficulty_norm: float)
	signal resolve_charged(amount: int, total: int)
	signal bonus_collected(total: int)
	signal finished(performance: float, bonus: int)

	const ARENA_SIZE := 440.0
	const ARENA_RADIUS := 205.0
	const EDGE_PAD := 6.0

	# Tuning curves, set by LeyLineMinigamePanel._configure_arena() from its
	# inspector @exports before start_run(). The defaults here are just a
	# fallback if the arena is ever used standalone -- the panel overwrites
	# all of them. Difficulty curve is Vector2(easy, hard); Arcane History
	# curve is Vector2(novice, skilled); .x/.y are lerped per run.
	var round_time := Vector2(4.5, 2.0)
	var lead_in := 0.6
	var zone_radius := Vector2(62.0, 22.0)
	var zone_shrink := Vector2(1.0, 0.55)
	var zone_drift := Vector2(0.0, 60.0)
	var zone_count := Vector2(3, 1)
	var max_resolve_per_round := 12.0
	var level_cap := 6.0
	var icon_radius := Vector2(20.0, 10.0)
	var max_speed := Vector2(240.0, 430.0)
	var accel := Vector2(750.0, 3600.0)
	var friction := Vector2(600.0, 3400.0)
	var turn_response := Vector2(0.42, 1.0)
	var flash_time := 0.45
	var results_time := 1.8
	var bonus_chance := 0.45
	var bonus_radius := 12.0
	var wall_bounce := 0.85

	enum State { IDLE, LEAD_IN, COUNT, FLASH, RESULTS }

	# tuned per run from difficulty / Arcane History
	var _difficulty_norm := 0.0
	var _rounds := 3
	var _icon_r := 15.0
	var _max_speed := 300.0
	var _accel := 2000.0
	var _friction := 2000.0
	var _turn_response := 1.0
	var _zone_base_r := 40.0
	var _zone_shrink := 1.0
	var _drift_speed := 0.0
	var _zone_count := 2
	var _round_time := 3.5

	var _state: int = State.IDLE
	var _round_index := 0
	var _timer := 0.0
	var _time_left := 0.0

	var _player_pos := Vector2.ZERO   # relative to arena center
	var _vel := Vector2.ZERO
	var _zones: Array = []            # each: {pos: Vector2, drift: Vector2, r: float}
	var _zone_r_now := 40.0          # current (shrunk) zone radius this frame

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


	func start_run(difficulty_norm: float, rounds: int, arcane_level: int) -> void:
		_difficulty_norm = difficulty_norm
		_rounds = maxi(rounds, 1)

		var lvl := clampf(float(arcane_level) / level_cap, 0.0, 1.0)
		_icon_r = lerpf(icon_radius.x, icon_radius.y, lvl)
		_max_speed = lerpf(max_speed.x, max_speed.y, lvl)
		_accel = lerpf(accel.x, accel.y, lvl)
		_friction = lerpf(friction.x, friction.y, lvl)
		_turn_response = lerpf(turn_response.x, turn_response.y, lvl)

		_zone_base_r = lerpf(zone_radius.x, zone_radius.y, difficulty_norm)
		_zone_shrink = lerpf(zone_shrink.x, zone_shrink.y, difficulty_norm)
		_drift_speed = lerpf(zone_drift.x, zone_drift.y, difficulty_norm)
		_zone_count = int(roundf(lerpf(zone_count.x, zone_count.y, difficulty_norm)))
		_round_time = lerpf(round_time.x, round_time.y, difficulty_norm)

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
		_maybe_spawn_mote()
		_zone_r_now = _zone_base_r
		_timer = lead_in
		_time_left = _round_time
		_state = State.LEAD_IN
		round_started.emit(_round_index, _rounds, _difficulty_norm)


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
				if pos.distance_to(z.pos) < z.r + bonus_radius + 20.0:
					near_zone = true
					break
			if near_zone:
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


	func _process(delta: float) -> void:
		_anim_t += delta
		if _mote_pop_t > 0.0:
			_mote_pop_t = maxf(_mote_pop_t - delta, 0.0)
		match _state:
			State.LEAD_IN:
				_update_movement(delta)
				_timer -= delta
				if _timer <= 0.0:
					_state = State.COUNT
			State.COUNT:
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

		_check_mote_pickup()


	## Collect the mote if the icon overlaps it. Cheap circle-vs-circle test run
	## every movement frame (LEAD_IN and COUNT), so a fast pass-through counts.
	func _check_mote_pickup() -> void:
		if not _mote_active:
			return
		if _player_pos.distance_to(_mote_pos) <= _icon_r + bonus_radius:
			_mote_active = false
			_bonus_collected += 1
			_mote_pop_t = 0.35
			_mote_pop_pos = _mote_pos
			bonus_collected.emit(_bonus_collected)


	func _update_zones(delta: float) -> void:
		var t := 1.0 - clampf(_time_left / _round_time, 0.0, 1.0)  # 0 at start, 1 at snap
		_zone_r_now = _zone_base_r * lerpf(1.0, _zone_shrink, t)
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
			resolve_charged.emit(cost, _resolve_lost)

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

	func _draw() -> void:
		var c := Vector2(ARENA_SIZE, ARENA_SIZE) * 0.5

		# Danger field: the whole node is hostile. Flare it on the snap flash.
		var flaring := _state == State.FLASH
		var danger := Color(0.30, 0.06, 0.12) if not flaring else Color(0.62, 0.10, 0.16)
		draw_circle(c, ARENA_RADIUS, danger)
		draw_arc(c, ARENA_RADIUS, 0.0, TAU, 64, Color(0.75, 0.2, 0.28, 0.8), 3.0, true)

		# Safe zones: soft green glow with a bright rim.
		for z in _zones:
			var zp: Vector2 = c + z.pos
			var zr: float = z.r
			draw_circle(zp, zr, Color(0.20, 0.70, 0.45, 0.30))
			draw_circle(zp, zr * 0.6, Color(0.35, 0.90, 0.55, 0.35))
			draw_arc(zp, zr, 0.0, TAU, 40, Color(0.55, 1.0, 0.70, 0.95), 2.5, true)

		# Resonance ring: collapses from the wall to the center as time runs
		# out; during LEAD_IN it holds at the wall so the round can be read.
		var ring_t := 1.0
		if _state == State.COUNT:
			ring_t = clampf(_time_left / _round_time, 0.0, 1.0)
		if _state == State.COUNT or _state == State.LEAD_IN:
			var ring_r := lerpf(_icon_r + 4.0, ARENA_RADIUS, ring_t)
			var urgency := 1.0 - ring_t
			var ring_col := Color(0.9, 0.85, 0.5).lerp(Color(1.0, 0.35, 0.35), urgency)
			draw_arc(c, ring_r, 0.0, TAU, 56, ring_col, 3.0, true)

		# Bonus mote: a pulsing gold spark. Placed away from safe zones, so
		# it's the risk/reward beat -- grab it or hold your safe position.
		if _mote_active:
			var mp: Vector2 = c + _mote_pos
			var pulse := 0.5 + 0.5 * sin(_anim_t * 6.0)
			draw_circle(mp, bonus_radius + 6.0 + 3.0 * pulse, Color(1.0, 0.85, 0.3, 0.18))
			draw_circle(mp, bonus_radius, Color(1.0, 0.82, 0.25, 0.55))
			draw_circle(mp, bonus_radius * 0.55, Color(1.0, 0.95, 0.7, 0.95))
			draw_arc(mp, bonus_radius, 0.0, TAU, 24, Color(1.0, 0.9, 0.5, 0.9), 2.0, true)

		# Collection flash: an expanding, fading gold ring where a mote was grabbed.
		if _mote_pop_t > 0.0:
			var pt := _mote_pop_t / 0.35            # 1 -> 0
			var pop_r := lerpf(bonus_radius + 4.0, bonus_radius + 34.0, 1.0 - pt)
			draw_arc(c + _mote_pop_pos, pop_r, 0.0, TAU, 28, Color(1.0, 0.9, 0.5, pt), 3.0, true)

		# Player icon: tinted toward green when safe, red when exposed.
		var pp: Vector2 = c + _player_pos
		var safe_now := _best_safe_fraction()
		var icon_col := Color(0.85, 0.35, 0.3).lerp(Color(0.4, 1.0, 0.6), safe_now)
		if safe_now >= 0.999:
			draw_circle(pp, _icon_r + 4.0, Color(0.5, 1.0, 0.7, 0.35))
		draw_circle(pp, _icon_r, icon_col)
		draw_arc(pp, _icon_r, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 2.0, true)

		if _state == State.RESULTS:
			_draw_results(c)


	func _draw_results(c: Vector2) -> void:
		var font := get_theme_default_font()
		var font_size := 26
		var pct := int(roundf(_performance * 100.0))
		var grade := "Great!" if _performance >= 0.85 else \
			("Good" if _performance >= 0.6 else \
			("Rough" if _performance >= 0.25 else "Lost it"))
		var text := "%s  %d%% safe" % [grade, pct]
		if _bonus_collected > 0:
			text += "   +%d bonus" % _bonus_collected
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var bg := Color(0.05, 0.05, 0.08, 0.72)
		draw_rect(Rect2(c.x - tw * 0.5 - 16, c.y - 26, tw + 32, 52), bg)
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + 8), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.95, 0.95, 1.0))
