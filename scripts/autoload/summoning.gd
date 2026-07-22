extends Node
## Planar Rift: drawing extraplanar ingredients (and other outcomes) through
## a rift. Autoloaded as "Summoning". See docs/design/systems.md, the
## Summoning / Planar Rift System section.
##
## A rift's job is a Clock.get_timestamp() deadline, same fire-and-forget
## shape as BrewJob/GrowPlotInstance, not a tethered accumulator like
## WritJob/DragonStashJob -- a summon can run anywhere from minutes to
## multiple days, so it has to keep advancing while the player is off doing
## something else entirely, not just while they stand at the rift.
##
## Choosing *which* bundle a rift resolves into is the symbol-sequence
## minigame (PlanarRiftMinigamePanel): the player builds a sequence of symbols
## against a closing-portal timer, and matching a bundle's `sequence` summons
## that bundle. This autoload owns the minigame *session* (open/complete/fail/
## abort, mirroring LeyLines) plus the persistent set of sequences the player
## has learned; the panel owns the play itself and calls back in. Which bundle
## gets built fully determines the outcome, so -- unlike Demonology/Draconology
## -- there's no further roll at collection time.

signal rift_started(rift_id: String, bundle_id: String)
signal rift_ready(rift_id: String, bundle_id: String)
signal rift_collected(rift_id: String, bundle_id: String, ingredients: Dictionary, material_delta: int, resolve_delta: int, quality: float)
## The player interacted with an idle rift: hud.gd opens the minigame panel in
## response, the same "autoload signal -> HUD opens a panel" shape LeyLines uses.
signal rift_minigame_requested(rift_id: String)
## The sequence completed: the summon's quality has just been rolled (time
## remaining + a Summoning roll). Carries the roll so hud.gd can render the
## dice, the same way Draconology/Transmutation surface their rolls. Fired
## before rift_started, so the roll reads before the "summon begins" line.
signal rift_quality_rolled(rift_id: String, bundle_id: String, quality: float, roll: Dictionary)
## The portal closed before a valid sequence was built -- a mishap event, so it
## carries the Resolve already spent for hud.gd/room_builder to react to.
signal rift_failed(rift_id: String, resolve_cost: int)

const XP_PER_RIFT := 25
## The portal slamming shut on a run-out is a failure event, same shape as a
## botched brew charging Resolve.
const FAIL_RESOLVE_COST := 8
## Sequences run 4 (the minimum, most bundles) to 8 (advanced bundles) symbols.
const MIN_SEQUENCE_LENGTH := 4
const MAX_SEQUENCE_LENGTH := 8

## Quality (0..1) is a blend of how much portal time was left at completion and
## a Summoning roll, each contributing half. A natural crit nudges it a little
## further, same "crit only shifts quality" rule Draconology/Demonology use.
const QUALITY_TIME_WEIGHT := 0.5
const QUALITY_ROLL_WEIGHT := 0.5
const QUALITY_ROLL_DC := 11.0
const QUALITY_CRIT_SWING := 0.1

## The twelve symbols a rift can present. Order is the canonical glyph index
## used by PlanarRiftMinigamePanel's _draw (index 0..11 -> a distinct rune);
## `id` is what RiftBundleDef.sequence entries reference, `color` tints both
## the option cell and the reference glyphs. Purely a fixed set -- not data-
## driven, since these are shared UI/vocabulary constants, not authored content.
const SUMMONING_SYMBOLS := [
	{"id": "sun", "name": "Sun", "color": Color(1.00, 0.80, 0.25)},
	{"id": "moon", "name": "Moon", "color": Color(0.70, 0.80, 1.00)},
	{"id": "star", "name": "Star", "color": Color(1.00, 0.95, 0.60)},
	{"id": "eye", "name": "Eye", "color": Color(0.55, 0.95, 0.90)},
	{"id": "wave", "name": "Wave", "color": Color(0.35, 0.75, 1.00)},
	{"id": "flame", "name": "Flame", "color": Color(1.00, 0.45, 0.30)},
	{"id": "root", "name": "Root", "color": Color(0.55, 0.85, 0.45)},
	{"id": "thorn", "name": "Thorn", "color": Color(0.82, 0.55, 0.95)},
	{"id": "key", "name": "Key", "color": Color(0.95, 0.85, 0.55)},
	{"id": "gate", "name": "Gate", "color": Color(0.68, 0.72, 0.88)},
	{"id": "coil", "name": "Coil", "color": Color(0.95, 0.60, 0.80)},
	{"id": "tide", "name": "Tide", "color": Color(0.40, 0.88, 0.80)},
]

var _jobs: Dictionary = {}          # rift_id -> PlanarRiftJob
## Bundle ids whose sequences the player knows, shown in the minigame's
## reference panel. Used as a set (id -> true). Persisted. Building a bundle's
## sequence blind teaches it, so the "known" set grows through play.
var _known_bundles: Dictionary = {}
## rift_id of the rift whose minigame is currently open, "" when none. Transient
## (like LeyLines' session) -- never saved; a minigame can't outlive the pause.
var _active_minigame_rift: String = ""

var _symbol_index_by_id: Dictionary = {}   # symbol id -> index into SUMMONING_SYMBOLS


func _ready() -> void:
	for i in SUMMONING_SYMBOLS.size():
		_symbol_index_by_id[SUMMONING_SYMBOLS[i].id] = i
	Clock.minute_tick.connect(_on_minute_tick)


func get_job(rift_id: String) -> PlanarRiftJob:
	return _jobs.get(rift_id)


func is_active(rift_id: String) -> bool:
	return _jobs.has(rift_id)


# --- Symbol helpers -------------------------------------------------------

func symbol_index(symbol_id: String) -> int:
	return _symbol_index_by_id.get(symbol_id, -1)


func symbol_color(symbol_id: String) -> Color:
	var idx := symbol_index(symbol_id)
	return SUMMONING_SYMBOLS[idx].color if idx >= 0 else Color.WHITE


# --- Learned-sequence knowledge ------------------------------------------

func knows_bundle(bundle_id: String) -> bool:
	return _known_bundles.has(bundle_id)


func learn_bundle(bundle_id: String) -> void:
	_known_bundles[bundle_id] = true


## Bundle ids the player knows, ordered by RiftBundleDef.sequence length then
## id so the reference panel reads shortest-first (easiest to execute on top).
func known_bundle_ids() -> Array[String]:
	var ids: Array[String] = []
	for bundle in ContentRegistry.rift_bundles:
		if _known_bundles.has(bundle.id):
			ids.append(bundle.id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ba := ContentRegistry.get_rift_bundle(a)
		var bb := ContentRegistry.get_rift_bundle(b)
		if ba.sequence.size() != bb.sequence.size():
			return ba.sequence.size() < bb.sequence.size()
		return a < b
	)
	return ids


# --- Minigame session -----------------------------------------------------

func is_minigame_active() -> bool:
	return _active_minigame_rift != ""


## The player interacted with an idle rift -- open the minigame. No-op if a
## job is already running here or a session is already open (interact() guards
## the former, MenuScene freezing the player guards the latter, but belt and
## braces).
func open_rift_minigame(rift_id: String) -> void:
	if _jobs.has(rift_id) or is_minigame_active():
		return
	_active_minigame_rift = rift_id
	rift_minigame_requested.emit(rift_id)


## The minigame built a bundle's full sequence: roll the summon's quality from
## the portal time still remaining (`time_fraction`, 0..1) and a Summoning roll,
## learn the bundle (so blind discovery sticks), and start the background job
## carrying that quality. Clears the session before emitting so hud.gd's
## close-on-close guard sees no active session -- same ordering
## LeyLines.resolve_minigame() uses.
func complete_rift_minigame(rift_id: String, bundle_id: String, time_fraction: float) -> void:
	if _active_minigame_rift != rift_id:
		return
	_active_minigame_rift = ""

	var modifier := float(Skills.level("summoning"))
	var roll := Rng.roll_2d10(modifier, QUALITY_ROLL_DC)
	# 2d10 spans 2..20; normalise (modifier pushes a skilled summoner reliably
	# toward the top, clamped to 1.0).
	var roll_norm := clampf((roll.total - 2.0) / 18.0, 0.0, 1.0)
	var quality := QUALITY_TIME_WEIGHT * clampf(time_fraction, 0.0, 1.0) + QUALITY_ROLL_WEIGHT * roll_norm
	if roll.critical_success:
		quality += QUALITY_CRIT_SWING
	elif roll.critical_failure:
		quality -= QUALITY_CRIT_SWING
	quality = clampf(quality, 0.0, 1.0)

	learn_bundle(bundle_id)
	rift_quality_rolled.emit(rift_id, bundle_id, quality, roll)
	start_rift(rift_id, bundle_id, quality)


## Human-readable band for a 0..1 quality, for log/UI text.
func quality_word(quality: float) -> String:
	if quality >= 0.85:
		return "Pristine"
	if quality >= 0.6:
		return "Strong"
	if quality >= 0.35:
		return "Fair"
	return "Faint"


## The portal closed before any valid sequence was built -- charge Resolve (a
## mishap event) and report it. Clears the session first, same ordering as
## complete_rift_minigame().
func fail_rift_minigame(rift_id: String) -> void:
	if _active_minigame_rift != rift_id:
		return
	_active_minigame_rift = ""
	Resolve.spend(FAIL_RESOLVE_COST, "a planar rift slamming shut")
	rift_failed.emit(rift_id, FAIL_RESOLVE_COST)


## The player left the minigame without finishing (Esc / closing the menu) --
## no job, no Resolve cost, session just thrown away. Same "walking away from a
## synchronous session" shape as LeyLines.abort_minigame().
func abort_rift_minigame() -> void:
	if not is_minigame_active():
		return
	_active_minigame_rift = ""


## Starts the background summon job for an explicitly chosen bundle (the
## minigame's outcome), carrying the quality the minigame rolled. No-op if this
## rift already has a job running.
func start_rift(rift_id: String, bundle_id: String, quality: float = 0.0) -> void:
	if _jobs.has(rift_id):
		return
	var bundle := ContentRegistry.get_rift_bundle(bundle_id)
	if bundle == null:
		return

	var job := PlanarRiftJob.new()
	job.rift_id = rift_id
	job.bundle_id = bundle.id
	job.quality = clampf(quality, 0.0, 1.0)
	job.start_timestamp = Clock.get_timestamp()
	job.ready_timestamp = job.start_timestamp + bundle.duration_minutes
	_jobs[rift_id] = job
	rift_started.emit(rift_id, bundle.id)


## Grants the resolved bundle's ingredients/material/resolve outcomes and
## closes the job out. Returns false if there's nothing ready to collect.
func collect_rift(rift_id: String) -> bool:
	var job: PlanarRiftJob = _jobs.get(rift_id)
	if job == null or job.status != PlanarRiftJob.Status.READY:
		return false
	var bundle := ContentRegistry.get_rift_bundle(job.bundle_id)
	if bundle == null:
		return false

	var quality := job.quality
	var granted: Dictionary = {}

	# Base ingredients -- always granted, quality-independent floor.
	for i in bundle.ingredient_ids.size():
		_grant_into(granted, bundle.ingredient_ids[i], bundle.ingredient_quantities[i])

	# Quality-scaled ingredients -- authored amount is the quality-1.0 figure;
	# round(qty * quality) is what actually lands.
	for i in bundle.scaled_ingredient_ids.size():
		var scaled_qty := int(round(float(bundle.scaled_ingredient_quantities[i]) * quality))
		_grant_into(granted, bundle.scaled_ingredient_ids[i], scaled_qty)

	# Quality-gated ingredients -- full amount, but only past their threshold.
	for i in bundle.gated_ingredient_ids.size():
		if quality >= bundle.gated_ingredient_min_quality[i]:
			_grant_into(granted, bundle.gated_ingredient_ids[i], bundle.gated_ingredient_quantities[i])

	# Materials: base delta (+/-) plus a quality-scaled bonus. Not a purchase --
	# the exchange already happened out on the plane, so unlike
	# Inventory.spend_materials() this is never blocked by insufficient funds,
	# same "the outcome already occurred" reasoning as Demonology's drawbacks.
	var material_total := bundle.material_delta + int(round(float(bundle.scaled_material_bonus) * quality))
	if material_total != 0:
		Inventory.add_materials(material_total)
	if bundle.resolve_delta > 0:
		Resolve.restore(bundle.resolve_delta)
	elif bundle.resolve_delta < 0:
		Resolve.spend(-bundle.resolve_delta, "a planar rift's toll")

	_jobs.erase(rift_id)
	Skills.add_xp("summoning", XP_PER_RIFT)
	rift_collected.emit(rift_id, bundle.id, granted, material_total, bundle.resolve_delta, quality)
	return true


## Adds `quantity` of `id` to the inventory and tallies it into `granted` (the
## dict handed to rift_collected). No-op for a non-positive quantity, so a
## scaled reward that rounds to 0 simply doesn't appear.
func _grant_into(granted: Dictionary, id: String, quantity: int) -> void:
	if quantity <= 0:
		return
	Inventory.add_ingredient(id, quantity)
	granted[id] = granted.get(id, 0) + quantity


func _on_minute_tick(timestamp: int) -> void:
	for rift_id in _jobs.keys():
		var job: PlanarRiftJob = _jobs[rift_id]
		if job.status == PlanarRiftJob.Status.SUMMONING and timestamp >= job.ready_timestamp:
			job.status = PlanarRiftJob.Status.READY
			rift_ready.emit(rift_id, job.bundle_id)


func get_save_data() -> Dictionary:
	var jobs_data: Dictionary = {}
	for rift_id in _jobs:
		var job: PlanarRiftJob = _jobs[rift_id]
		jobs_data[rift_id] = {
			"bundle_id": job.bundle_id,
			"start_timestamp": job.start_timestamp,
			"ready_timestamp": job.ready_timestamp,
			"status": int(job.status),
			"quality": job.quality,
		}
	return {"jobs": jobs_data, "known_bundles": _known_bundles.keys()}


func load_save_data(data: Dictionary) -> void:
	_jobs.clear()
	var jobs_data: Dictionary = data.get("jobs", {})
	for rift_id in jobs_data:
		var d: Dictionary = jobs_data[rift_id]
		var job := PlanarRiftJob.new()
		job.rift_id = rift_id
		job.bundle_id = d.get("bundle_id", "")
		job.start_timestamp = d.get("start_timestamp", 0)
		job.ready_timestamp = d.get("ready_timestamp", 0)
		job.status = d.get("status", PlanarRiftJob.Status.SUMMONING) as PlanarRiftJob.Status
		job.quality = d.get("quality", 0.0)
		_jobs[rift_id] = job

	_known_bundles.clear()
	for bundle_id in data.get("known_bundles", []):
		_known_bundles[bundle_id] = true
