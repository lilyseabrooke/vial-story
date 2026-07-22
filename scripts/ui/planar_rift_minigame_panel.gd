class_name PlanarRiftMinigamePanel
extends VBoxContainer
## The Planar Rift summoning minigame, hosted by MenuScene while a Summoning
## session is active. One instance owned by hud.gd, opened in response to
## Summoning.rift_minigame_requested and reused per-open via show_for(), the
## same "build once, populate per-open" shape as LeyLineMinigamePanel.
##
## Gameplay: the portal is open and slowly closing (a countdown). Four symbol
## options sit on the portal rim; the player picks one with a movement key
## (W/A/S/D or arrows -> up/left/down/right), which appends it to the sequence
## queue and deals four fresh options. Building a queue that exactly matches a
## RiftBundleDef.sequence summons that bundle (starts its background job via
## Summoning.complete_rift_minigame). Pressing E wipes the queue, but the wipe
## takes time while the portal keeps closing. If the portal shuts before a
## valid sequence lands, the run fails (Summoning.fail_rift_minigame -> a
## Resolve hit). Known sequences are listed on the right as a reference and
## light up as the queue tracks them.
##
## The four options only *sometimes* include a symbol that continues a bundle's
## sequence from the current queue (continuation_chance); otherwise they're
## random. So knowing a sequence isn't enough -- the needed symbol also has to
## come up, or you wipe and re-deal against the timer. That gamble is the point:
## it forces guesswork, makes wiping a real decision, and rewards trying unknown
## symbols to discover new combinations.
##
## MenuScene only flips Clock.is_paused; it never pauses the SceneTree, so the
## arena's _process/_draw/_input run normally while the menu is open. The
## arena consumes W/A/S/D/arrows/E via set_input_as_handled() so E doesn't also
## fire main.gd's interact hotkey; Esc is left alone so it still closes the menu.

const OPTION_COUNT := 4

# --- Tunables, editable in the inspector on PlanarRiftMinigamePanel.tscn ---

@export_group("Portal Timer")
## Base seconds the portal stays open before it shuts.
@export var portal_time_base: float = 22.0
## Extra seconds added per point of Skills.get_bonus("summon_control") -- the
## Summoning skill's one live effect on the minigame (range/learn_speed remain
## stubs). A steadier summoner holds the portal open longer.
@export var seconds_per_control: float = 4.0
## Seconds a queue wipe (E) takes to clear -- the portal keeps closing through it.
@export var wipe_time: float = 0.75

@export_group("Options")
## Per-deal probability that the four options include a symbol that actually
## continues a bundle's sequence from the current queue. Below 1.0 the needed
## symbol is *not* guaranteed to appear -- knowing a sequence isn't enough, you
## also need it to come up (or wipe and try again), which is what makes the
## rift a gamble and rewards experimentation. Filler is random, so a
## continuation can still turn up by chance even on a deal that didn't seed one.
@export_range(0.0, 1.0) var continuation_chance: float = 0.7

@export_group("Flourish Timing")
@export var success_time: float = 1.7                ## success bloom held before reporting out
@export var failure_time: float = 1.5                ## portal-slam held before reporting out

var _arena: RiftArena
var _reference: RiftReference
var _status_label: Label
var _hint_label: Label
var _rift_id: String = ""


func build() -> void:
	custom_minimum_size = Vector2(700, 0)
	alignment = BoxContainer.ALIGNMENT_CENTER

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 15)
	add_child(_status_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)

	_arena = RiftArena.new()
	_arena.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_arena)
	_arena.queue_changed.connect(_on_queue_changed)
	_arena.hint_changed.connect(_on_hint_changed)
	_arena.run_finished.connect(_on_run_finished)

	_reference = RiftReference.new()
	_reference.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_reference)

	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_hint_label.custom_minimum_size = Vector2(680, 0)
	_hint_label.modulate = Color(0.68, 0.66, 0.74)
	add_child(_hint_label)


func show_for(rift_id: String) -> void:
	_rift_id = rift_id
	_status_label.text = "The rift is open — build a summoning sequence before it closes."
	_hint_label.text = "W/A/S/D or arrows to choose a symbol · E to wipe the sequence"

	var control_bonus := Skills.get_bonus("summon_control")
	var portal_time := portal_time_base + control_bonus * seconds_per_control

	_reference.refresh()
	_reference.set_queue([])
	_arena.start_run(ContentRegistry.rift_bundles, portal_time, wipe_time, success_time, failure_time, continuation_chance)


func _on_queue_changed(queue: Array) -> void:
	_reference.set_queue(queue)


func _on_hint_changed(text: String) -> void:
	_hint_label.text = text


func _on_run_finished(success: bool, bundle_id: String, time_fraction: float) -> void:
	# The arena has already played its success/failure flourish. Report out;
	# Summoning clears the session inside these before emitting the signals
	# hud.gd closes the menu on, so the MenuScene.closed abort-guard is a no-op.
	# time_fraction (portal time left at the match) feeds the summon's quality.
	if success:
		Summoning.complete_rift_minigame(_rift_id, bundle_id, time_fraction)
	else:
		Summoning.fail_rift_minigame(_rift_id)


# ===========================================================================
# Glyph drawing -- one distinct rune per SUMMONING_SYMBOLS index (0..11),
# drawn centered at `center` within radius `r` in `color`. Static so both the
# arena and the reference panel render symbols identically.
# ===========================================================================

static func draw_glyph(ci: CanvasItem, index: int, center: Vector2, r: float, color: Color) -> void:
	var w := maxf(2.0, r * 0.17)
	match index:
		0:  # sun -- ringed disc with rays
			ci.draw_arc(center, r * 0.55, 0.0, TAU, 24, color, w, true)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector2.from_angle(a)
				ci.draw_line(center + d * r * 0.72, center + d * r, color, w, true)
		1:  # moon -- crescent (thick partial arc)
			ci.draw_arc(center, r * 0.72, PI * 0.35, PI * 1.65, 24, color, w * 1.6, true)
		2:  # star -- five-point outline
			var pts := _star_points(center, r, r * 0.42, 5, -PI / 2.0)
			ci.draw_polyline(pts, color, w, true)
		3:  # eye -- lens (two arcs) with a pupil
			ci.draw_arc(center + Vector2(0, r * 0.42), r * 0.95, PI * 1.15, PI * 1.85, 20, color, w, true)
			ci.draw_arc(center - Vector2(0, r * 0.42), r * 0.95, PI * 0.15, PI * 0.85, 20, color, w, true)
			ci.draw_circle(center, r * 0.24, color)
		4:  # wave -- single sine curve
			ci.draw_polyline(_wave_points(center, r, r * 0.45, 0.0), color, w, true)
		5:  # flame -- pointed teardrop
			ci.draw_colored_polygon(_flame_points(center, r), color)
		6:  # root -- stem with two forks
			ci.draw_line(center + Vector2(0, -r), center + Vector2(0, r * 0.2), color, w, true)
			ci.draw_line(center + Vector2(0, r * 0.2), center + Vector2(-r * 0.7, r), color, w, true)
			ci.draw_line(center + Vector2(0, r * 0.2), center + Vector2(r * 0.7, r), color, w, true)
			ci.draw_line(center + Vector2(0, -r * 0.3), center + Vector2(r * 0.55, -r * 0.05), color, w, true)
		7:  # thorn -- vertical shaft with two barbs
			ci.draw_line(center + Vector2(0, r), center + Vector2(0, -r), color, w, true)
			ci.draw_line(center + Vector2(0, -r * 0.1), center + Vector2(r * 0.7, -r * 0.5), color, w, true)
			ci.draw_line(center + Vector2(0, r * 0.3), center + Vector2(-r * 0.7, -r * 0.1), color, w, true)
		8:  # key -- ringed bow, stem, and teeth
			ci.draw_arc(center + Vector2(0, -r * 0.5), r * 0.42, 0.0, TAU, 18, color, w, true)
			ci.draw_line(center + Vector2(0, -r * 0.1), center + Vector2(0, r), color, w, true)
			ci.draw_line(center + Vector2(0, r * 0.55), center + Vector2(r * 0.5, r * 0.55), color, w, true)
			ci.draw_line(center + Vector2(0, r * 0.9), center + Vector2(r * 0.4, r * 0.9), color, w, true)
		9:  # gate -- archway
			ci.draw_arc(center + Vector2(0, -r * 0.05), r * 0.7, PI, TAU, 20, color, w, true)
			ci.draw_line(center + Vector2(-r * 0.7, -r * 0.05), center + Vector2(-r * 0.7, r), color, w, true)
			ci.draw_line(center + Vector2(r * 0.7, -r * 0.05), center + Vector2(r * 0.7, r), color, w, true)
		10:  # coil -- inward spiral
			ci.draw_polyline(_spiral_points(center, r), color, w, true)
		11:  # tide -- two stacked waves
			ci.draw_polyline(_wave_points(center - Vector2(0, r * 0.32), r, r * 0.34, 0.0), color, w, true)
			ci.draw_polyline(_wave_points(center + Vector2(0, r * 0.32), r, r * 0.34, PI), color, w, true)
		_:
			ci.draw_arc(center, r * 0.7, 0.0, TAU, 20, color, w, true)


static func _star_points(center: Vector2, outer: float, inner: float, points: int, start: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2 + 1:
		var a := start + PI * float(i) / float(points)
		var rad := outer if i % 2 == 0 else inner
		pts.append(center + Vector2.from_angle(a) * rad)
	return pts


static func _wave_points(center: Vector2, half_w: float, amp: float, phase: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 20
	for i in steps + 1:
		var t := float(i) / float(steps)
		var x := lerpf(-half_w, half_w, t)
		var y := sin(t * TAU + phase) * amp
		pts.append(center + Vector2(x, y))
	return pts


static func _flame_points(center: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r * 0.62, r * 0.1),
		center + Vector2(r * 0.36, r * 0.85),
		center + Vector2(0, r * 0.55),
		center + Vector2(-r * 0.36, r * 0.85),
		center + Vector2(-r * 0.62, r * 0.1),
	])


static func _spiral_points(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var turns := 2.4
	var steps := 40
	for i in steps + 1:
		var t := float(i) / float(steps)
		var a := t * TAU * turns
		var rad := lerpf(r, r * 0.08, t)
		pts.append(center + Vector2.from_angle(a) * rad)
	return pts


# ===========================================================================
# RiftArena -- the custom-drawn playfield (portal, options, queue, timer).
# Kept as an inner class so the whole minigame is one swappable file, same as
# LeyArena; a real Control once in the tree, so _process/_draw/_input fire.
# ===========================================================================

class RiftArena extends Control:

	signal queue_changed(queue: Array)
	signal hint_changed(text: String)
	signal run_finished(success: bool, bundle_id: String, time_fraction: float)

	const ARENA_W := 460.0
	const ARENA_H := 500.0
	const PORTAL_CENTER := Vector2(230.0, 292.0)
	const PORTAL_RADIUS := 128.0
	const OPTION_DIST := 128.0
	const OPTION_RADIUS := 42.0
	const QUEUE_Y := 42.0
	const QUEUE_SLOT_DIST := 40.0
	const QUEUE_R := 16.0

	# The four option positions, in pick order: up, right, down, left.
	const DIRS := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
	const DIR_KEYS := ["W", "D", "S", "A"]
	const CONTROL_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_E]

	const COL_CALM := Color(0.36, 0.22, 0.58)
	const COL_URGENT := Color(0.66, 0.13, 0.19)
	const COL_GOLD := Color(1.0, 0.85, 0.42)

	enum State { PLAYING, WIPING, SUCCESS, FAILURE, DONE }

	var _bundles: Array = []
	var _portal_time := 22.0
	var _wipe_time := 0.75
	var _success_time := 1.7
	var _failure_time := 1.5
	var _continuation_chance := 0.7

	var _state: int = State.PLAYING
	var _time_left := 0.0
	var _wipe_t := 0.0
	var _flourish_t := 0.0
	var _anim_t := 0.0

	var _queue: Array = []            # symbol ids picked so far
	var _options: Array = []          # 4 symbol ids currently offered
	var _full := false                # queue at MAX with no match -> must wipe
	var _success_bundle: RiftBundleDef = null
	var _success_time_frac := 0.0     # portal time left at the match, feeds quality

	var _pick_flash_dir := -1
	var _pick_flash_t := 0.0
	var _pop_slot := -1               # newest queue slot, for a pop-in scale
	var _pop_t := 0.0


	func _init() -> void:
		custom_minimum_size = Vector2(ARENA_W, ARENA_H)
		set_process(false)


	func start_run(bundles: Array, portal_time: float, wipe_time: float, success_time: float, failure_time: float, continuation_chance: float) -> void:
		_bundles = bundles
		_portal_time = maxf(portal_time, 4.0)
		_wipe_time = wipe_time
		_success_time = success_time
		_failure_time = failure_time
		_continuation_chance = continuation_chance

		_state = State.PLAYING
		_time_left = _portal_time
		_wipe_t = 0.0
		_flourish_t = 0.0
		_queue.clear()
		_full = false
		_success_bundle = null
		_success_time_frac = 0.0
		_pick_flash_dir = -1
		_pick_flash_t = 0.0
		_pop_slot = -1
		_pop_t = 0.0

		_generate_options()
		queue_changed.emit(_queue.duplicate())
		set_process(true)
		set_process_input(true)


	# --- Input -------------------------------------------------------------

	func _input(event: InputEvent) -> void:
		if not (event is InputEventKey) or not event.pressed or event.echo:
			return
		var code: int = event.keycode
		if not CONTROL_KEYS.has(code):
			return
		# Consume every control key regardless of state so E can't leak to
		# main.gd's interact hotkey (movement is frozen while paused anyway).
		get_viewport().set_input_as_handled()
		if _state != State.PLAYING:
			return
		match code:
			KEY_W, KEY_UP:
				_pick(0)
			KEY_D, KEY_RIGHT:
				_pick(1)
			KEY_S, KEY_DOWN:
				_pick(2)
			KEY_A, KEY_LEFT:
				_pick(3)
			KEY_E:
				_begin_wipe()


	func _pick(dir_index: int) -> void:
		if _full or dir_index >= _options.size():
			return
		var sym: String = _options[dir_index]
		_queue.append(sym)
		_pick_flash_dir = dir_index
		_pick_flash_t = 0.28
		_pop_slot = _queue.size() - 1
		_pop_t = 0.3
		queue_changed.emit(_queue.duplicate())

		var matched := _matched_bundle()
		if matched != null:
			_begin_success(matched)
			return
		if _queue.size() >= Summoning.MAX_SEQUENCE_LENGTH:
			_full = true
			hint_changed.emit("The sequence is full and matches nothing — press E to wipe and start over.")
			return
		_generate_options()
		hint_changed.emit("%d symbols placed. Keep going, or press E to wipe." % _queue.size())


	func _begin_wipe() -> void:
		if _queue.is_empty():
			return
		_state = State.WIPING
		_wipe_t = _wipe_time
		_full = false
		hint_changed.emit("Wiping the sequence — the portal keeps closing...")


	func _finish_wipe() -> void:
		_queue.clear()
		_generate_options()
		queue_changed.emit(_queue.duplicate())
		_state = State.PLAYING
		hint_changed.emit("Sequence cleared. Choose your first symbol.")


	func _begin_success(bundle: RiftBundleDef) -> void:
		_success_bundle = bundle
		_success_time_frac = _time_frac()   # captured before the flourish drains the clock
		_state = State.SUCCESS
		_flourish_t = _success_time
		hint_changed.emit("The rift yields: %s!" % bundle.display_name)


	func _begin_failure() -> void:
		if _state == State.SUCCESS:
			return
		_state = State.FAILURE
		_flourish_t = _failure_time
		hint_changed.emit("The portal slams shut!")


	# --- Sequence logic ----------------------------------------------------

	## Symbols that continue at least one bundle's sequence from the current
	## queue -- guaranteed to appear among the options, so any known sequence
	## is always executable.
	func _valid_next_symbols() -> Array:
		var result: Array = []
		var n := _queue.size()
		for bundle in _bundles:
			var seq: Array = bundle.sequence
			if seq.size() <= n:
				continue
			var is_prefix := true
			for i in n:
				if seq[i] != _queue[i]:
					is_prefix = false
					break
			if is_prefix and not result.has(seq[n]):
				result.append(seq[n])
		return result


	func _matched_bundle() -> RiftBundleDef:
		for bundle in _bundles:
			if _sequence_equals(bundle.sequence, _queue):
				return bundle
		return null


	func _sequence_equals(seq: Array, q: Array) -> bool:
		if seq.size() != q.size():
			return false
		for i in seq.size():
			if seq[i] != q[i]:
				return false
		return true


	## Only *sometimes* seed a valid continuation (continuation_chance) -- the
	## rest is random filler, so the needed symbol isn't guaranteed to appear.
	## Knowing a sequence isn't enough; you also need the symbols to come up, or
	## wipe and re-deal. That gamble is the point, and it's what makes trying
	## unknown symbols (experimentation) worthwhile. Filler can still surface a
	## continuation by chance, so effective odds run a bit above the raw chance.
	func _generate_options() -> void:
		var opts: Array = []
		var valid := _valid_next_symbols()
		if not valid.is_empty() and Rng.chance(_continuation_chance):
			opts.append(valid[Rng.range_i(0, valid.size() - 1)])
		var filler: Array = []
		for sym in Summoning.SUMMONING_SYMBOLS:
			if not opts.has(sym.id):
				filler.append(sym.id)
		for s in _shuffled(filler):
			if opts.size() >= OPTION_COUNT:
				break
			opts.append(s)
		_options = _shuffled(opts)


	func _shuffled(arr: Array) -> Array:
		var out := arr.duplicate()
		for i in range(out.size() - 1, 0, -1):
			var j := Rng.range_i(0, i)
			var tmp = out[i]
			out[i] = out[j]
			out[j] = tmp
		return out


	# --- Process -----------------------------------------------------------

	func _process(delta: float) -> void:
		_anim_t += delta
		if _pick_flash_t > 0.0:
			_pick_flash_t = maxf(_pick_flash_t - delta, 0.0)
		if _pop_t > 0.0:
			_pop_t = maxf(_pop_t - delta, 0.0)

		match _state:
			State.PLAYING:
				_tick_timer(delta)
			State.WIPING:
				_tick_timer(delta)
				if _state == State.WIPING:
					_wipe_t -= delta
					if _wipe_t <= 0.0:
						_finish_wipe()
			State.SUCCESS:
				_flourish_t -= delta
				if _flourish_t <= 0.0:
					_emit_finish(true)
			State.FAILURE:
				_flourish_t -= delta
				if _flourish_t <= 0.0:
					_emit_finish(false)
		queue_redraw()


	func _tick_timer(delta: float) -> void:
		_time_left -= delta
		if _time_left <= 0.0:
			_time_left = 0.0
			_begin_failure()


	func _emit_finish(success: bool) -> void:
		set_process(false)
		set_process_input(false)
		_state = State.DONE
		run_finished.emit(success, _success_bundle.id if _success_bundle != null else "", _success_time_frac)


	# --- Drawing -----------------------------------------------------------

	func _time_frac() -> float:
		return clampf(_time_left / _portal_time, 0.0, 1.0)


	func _draw() -> void:
		_draw_portal()
		_draw_queue()
		_draw_options()
		if _state == State.SUCCESS:
			_draw_success()
		elif _state == State.FAILURE:
			_draw_failure()


	func _draw_portal() -> void:
		var frac := _time_frac()
		var urgency := 1.0 - frac
		# Base disc: violet when calm, shifting red as the portal closes.
		var base := COL_CALM.lerp(COL_URGENT, urgency * urgency)
		draw_circle(PORTAL_CENTER, PORTAL_RADIUS, Color(base.r, base.g, base.b, 0.9))

		# Swirling energy: a few rotating arcs, faster and redder under urgency.
		var spin := _anim_t * (0.6 + urgency * 1.6)
		for i in 3:
			var rr := PORTAL_RADIUS * (0.4 + 0.2 * float(i))
			var a0 := spin * (1.0 if i % 2 == 0 else -1.0) + float(i) * 1.3
			var swirl := COL_GOLD.lerp(Color(1.0, 0.5, 0.4), urgency)
			draw_arc(PORTAL_CENTER, rr, a0, a0 + PI * 1.2, 32, Color(swirl.r, swirl.g, swirl.b, 0.28), 3.0, true)

		# Closing iris: a dark disc swelling from the center to swallow the
		# portal as time runs out, with a bright event-horizon rim.
		var iris_r := PORTAL_RADIUS * urgency
		if _state == State.FAILURE:
			iris_r = lerpf(PORTAL_RADIUS * urgency, PORTAL_RADIUS + OPTION_RADIUS, 1.0 - clampf(_flourish_t / _failure_time, 0.0, 1.0))
		if iris_r > 1.0:
			draw_circle(PORTAL_CENTER, iris_r, Color(0.04, 0.03, 0.06, 0.92))
			draw_arc(PORTAL_CENTER, iris_r, 0.0, TAU, 40, Color(1.0, 0.55, 0.4, 0.7), 2.5, true)

		# Rim + depleting timer arc (sweeps from the top, clockwise).
		draw_arc(PORTAL_CENTER, PORTAL_RADIUS, 0.0, TAU, 48, Color(0.6, 0.5, 0.8, 0.5), 3.0, true)
		var ring_col := Color(0.75, 0.95, 1.0).lerp(Color(1.0, 0.3, 0.3), urgency)
		draw_arc(PORTAL_CENTER, PORTAL_RADIUS + 12.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 56, ring_col, 5.0, true)


	func _draw_queue() -> void:
		var start_x := PORTAL_CENTER.x - float(Summoning.MAX_SEQUENCE_LENGTH - 1) * QUEUE_SLOT_DIST * 0.5
		var wipe_p := 0.0
		if _state == State.WIPING:
			wipe_p = 1.0 - clampf(_wipe_t / _wipe_time, 0.0, 1.0)
		for i in Summoning.MAX_SEQUENCE_LENGTH:
			var pos := Vector2(start_x + float(i) * QUEUE_SLOT_DIST, QUEUE_Y)
			if i < _queue.size():
				var alpha := 1.0
				var offset := Vector2.ZERO
				if _state == State.WIPING:
					alpha = 1.0 - wipe_p
					offset = Vector2(0, -wipe_p * 18.0)
				var col := Summoning.symbol_color(_queue[i])
				var slot_r := QUEUE_R
				if i == _pop_slot and _pop_t > 0.0:
					slot_r *= 1.0 + 0.4 * (_pop_t / 0.3)
				draw_circle(pos + offset, slot_r + 3.0, Color(col.r, col.g, col.b, 0.14 * alpha))
				draw_arc(pos + offset, slot_r + 3.0, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.8 * alpha), 2.0, true)
				PlanarRiftMinigamePanel.draw_glyph(self, Summoning.symbol_index(_queue[i]), pos + offset, slot_r * 0.72, Color(col.r, col.g, col.b, alpha))
			else:
				draw_arc(pos, QUEUE_R, 0.0, TAU, 18, Color(0.5, 0.5, 0.6, 0.3), 1.5, true)
			# A hair-thin connector between slots reads them as one sequence.
			if i > 0:
				var prev := Vector2(start_x + float(i - 1) * QUEUE_SLOT_DIST, QUEUE_Y)
				draw_line(prev + Vector2(QUEUE_R + 2, 0), pos - Vector2(QUEUE_R + 2, 0), Color(0.5, 0.5, 0.6, 0.25), 1.0, true)


	func _draw_options() -> void:
		var dim := _state != State.PLAYING or _full
		for i in _options.size():
			var dir: Vector2 = DIRS[i]
			var pos := PORTAL_CENTER + dir * OPTION_DIST
			var sym_id: String = _options[i]
			var col := Summoning.symbol_color(sym_id)
			var base_alpha := 0.4 if dim else 1.0

			# Cell backing.
			var flash := 0.0
			if i == _pick_flash_dir and _pick_flash_t > 0.0:
				flash = _pick_flash_t / 0.28
			var bg := Color(0.09, 0.08, 0.13, 0.92 * base_alpha).lerp(Color(col.r, col.g, col.b, 0.9), flash * 0.5)
			draw_circle(pos, OPTION_RADIUS, bg)
			draw_arc(pos, OPTION_RADIUS, 0.0, TAU, 32, Color(col.r, col.g, col.b, base_alpha), 2.5 + flash * 2.0, true)

			# Glyph.
			PlanarRiftMinigamePanel.draw_glyph(self, Summoning.symbol_index(sym_id), pos, OPTION_RADIUS * 0.5, Color(col.r, col.g, col.b, base_alpha))

			# Direction key hint, just outside the cell along its direction.
			if not dim:
				var font := get_theme_default_font()
				var key: String = DIR_KEYS[i]
				var label_pos := pos + dir * (OPTION_RADIUS + 15.0)
				var tw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
				draw_string(font, label_pos - Vector2(tw * 0.5, -5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.7, 0.7, 0.8, 0.9))


	func _draw_success() -> void:
		var t := 1.0 - clampf(_flourish_t / _success_time, 0.0, 1.0)   # 0 -> 1
		# Golden bloom expanding out of the portal.
		draw_circle(PORTAL_CENTER, PORTAL_RADIUS * (0.4 + 0.8 * t), Color(1.0, 0.9, 0.55, 0.35 * (1.0 - t)))
		draw_arc(PORTAL_CENTER, PORTAL_RADIUS * (0.5 + 1.1 * t), 0.0, TAU, 48, Color(1.0, 0.9, 0.5, 0.8 * (1.0 - t)), 4.0, true)
		_draw_banner(_success_bundle.display_name if _success_bundle != null else "", COL_GOLD)


	func _draw_failure() -> void:
		var t := 1.0 - clampf(_flourish_t / _failure_time, 0.0, 1.0)
		if t < 0.25:
			var fl := 1.0 - t / 0.25
			draw_circle(PORTAL_CENTER, PORTAL_RADIUS + OPTION_RADIUS, Color(0.8, 0.15, 0.15, 0.5 * fl))
		_draw_banner("The rift slams shut", Color(1.0, 0.5, 0.45))


	func _draw_banner(text: String, color: Color) -> void:
		if text == "":
			return
		var font := get_theme_default_font()
		var font_size := 22
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var c := PORTAL_CENTER
		draw_rect(Rect2(c.x - tw * 0.5 - 16, c.y - 22, tw + 32, 44), Color(0.05, 0.04, 0.08, 0.8))
		draw_string(font, Vector2(c.x - tw * 0.5, c.y + 7), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# ===========================================================================
# RiftReference -- the right-hand "Known Sequences" panel. Draws each learned
# bundle's sequence as mini-glyphs and lights up the row the queue is tracking.
# ===========================================================================

class RiftReference extends Control:

	const PANEL_W := 226.0
	const PANEL_H := 500.0
	const ROW_TOP := 46.0
	const ROW_H := 64.0
	const GLYPH_R := 12.0
	const GLYPH_DIST := 27.0

	var _known: Array = []            # RiftBundleDef, shortest-first
	var _queue: Array = []


	func _init() -> void:
		custom_minimum_size = Vector2(PANEL_W, PANEL_H)


	func refresh() -> void:
		_known.clear()
		for id in Summoning.known_bundle_ids():
			var bundle := ContentRegistry.get_rift_bundle(id)
			if bundle != null:
				_known.append(bundle)
		queue_redraw()


	func set_queue(queue: Array) -> void:
		_queue = queue
		queue_redraw()


	## True if `seq` begins with the current queue (queue non-empty).
	func _tracks(seq: Array) -> int:
		if _queue.is_empty() or _queue.size() > seq.size():
			return 0
		for i in _queue.size():
			if seq[i] != _queue[i]:
				return 0
		return _queue.size()


	func _draw() -> void:
		# Backing.
		draw_rect(Rect2(0, 0, PANEL_W, PANEL_H), Color(0.07, 0.07, 0.10, 0.85))
		draw_rect(Rect2(0, 0, PANEL_W, PANEL_H), Color(0.4, 0.4, 0.5, 0.4), false, 1.5)

		var font := get_theme_default_font()
		draw_string(font, Vector2(14, 26), "Known Sequences", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.85, 0.85, 0.95))

		if _known.is_empty():
			draw_multiline_string(font, Vector2(14, ROW_TOP + 6), "No sequences known yet.\nBuild one blind to learn it.",
				HORIZONTAL_ALIGNMENT_LEFT, PANEL_W - 28, 13, -1, Color(0.6, 0.6, 0.7))
			return

		for row in _known.size():
			var bundle: RiftBundleDef = _known[row]
			var y := ROW_TOP + float(row) * ROW_H
			var seq: Array = bundle.sequence
			var matched := _tracks(seq)
			var full_match := matched == seq.size() and matched > 0

			# Row highlight when the queue is tracking this sequence.
			if matched > 0:
				var hl := COL_HL_FULL if full_match else COL_HL_PARTIAL
				draw_rect(Rect2(6, y - 4, PANEL_W - 12, ROW_H - 8), hl)

			draw_string(font, Vector2(14, y + 14), bundle.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.88, 0.88, 0.96))

			for i in seq.size():
				var gp := Vector2(20.0 + float(i) * GLYPH_DIST, y + 42.0)
				var col: Color = Summoning.symbol_color(seq[i])
				var lit := i < matched
				var a := 1.0 if lit else 0.55
				if lit:
					draw_circle(gp, GLYPH_R + 2.0, Color(col.r, col.g, col.b, 0.25))
				PlanarRiftMinigamePanel.draw_glyph(self, Summoning.symbol_index(seq[i]), gp, GLYPH_R, Color(col.r, col.g, col.b, a))

	const COL_HL_PARTIAL := Color(0.3, 0.4, 0.6, 0.22)
	const COL_HL_FULL := Color(0.9, 0.75, 0.3, 0.3)
