# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Vial Story is a Godot 4.7 (GDScript) prototype for a sim RPG about running a cursed alchemy shop as a
magic-academy student, with a dating-sim/VN layer planned on top later. The current build is the
sim-loop prototype only — no VN/relationship content yet. **`docs/design/systems.md` is the
authoritative design spec**: every gameplay system, its concrete data shape, prototype scope vs.
stubbed-for-later, and open tunable values. Read the relevant section there before adding or changing
a system, and update it when a system's behavior changes.

## Running and verifying changes

- There's no CLI build step — this is a Godot project. Open `project.godot` in Godot 4.7+ and press
  F5 (main scene) or F6 (current scene). If the Godot MCP tools (`run_project` / `get_debug_output` /
  `stop_project` / `launch_editor`) are configured, they can drive the same thing headlessly.
- **No automated test suite exists.** Verify behavior by temporarily adding a script-driven scenario
  to the end of `_ready()` in `scripts/main.gd` — call the real autoload methods directly (e.g.
  `Brewing.start_brew(...)`, `await Brewing.brew_ready`, `Herbalism.harvest(...)`), print the results,
  run it, read the console output, then remove the scaffold once confirmed. Most systems are
  timestamp/signal-driven, so driving them through their actual signals (rather than asserting on
  internal state) is what actually exercises the logic.
- **Godot's global class cache goes stale.** After adding or renaming a `class_name` script, a
  headless `run_project` will fail to resolve the new class ("Could not find type X in the current
  scope") until the editor has scanned it at least once. Launch the editor, wait several seconds, and
  confirm the class shows up in `.godot/global_script_class_cache.cfg` before running headless again.
- Git workflow (branching, committing `.tscn`/`.tres`, PR process) is documented in
  `docs/GIT_WORKFLOW.md`.

## Architecture

**Autoload singletons are the system boundary.** Every gameplay system is a global autoload in
`scripts/autoload/`, registered in `project.godot`'s `[autoload]` section in roughly dependency order:
`Clock` → `Inventory` → `Resolve` → `Skills` → `Brewing` → `Shop` → `Herbalism` → `Economy` →
`Academy`. Systems call each other directly and listen to each other's signals — there is no central
event bus or game-state object.

- **`Clock`** is what everything else hooks into. Time is a continuous tick
  (`minutes_into_day`, tunable via `tick_rate_minutes_per_second`), not discrete phases or a real-time
  clock. `Clock.get_timestamp()` returns an absolute, monotonically increasing minute count that
  `BrewJob` and `GrowPlotInstance` use for their deadlines, so completion is just a comparison against
  `Clock.minute_tick` — it doesn't matter whether the player is watching or time got skipped.
  `Clock.skip_to()` is the `TimeSkip` primitive: used for sleep/collapse and by
  `Academy.attend_class()` to fast-forward to the end of the class window.
- **`Skills`** is a passive XP/level ledger that knows nothing about brewing or growing — other
  systems call `Skills.add_xp(skill_id, amount)` and read back `Skills.get_bonus(effect_target)` (a
  string key like `"station_potency"` or `"grow_yield"`) to apply their own effects.
  `Resolve.is_strained()` is checked *inside* `get_bonus()`, so the "strained halves every skill bonus"
  debuff lives in one place instead of being duplicated per system.
- **`Resolve`** only drains from explicit failure events (e.g. `Brewing`'s botched-brew roll calls
  `Resolve.spend(...)`) — never from routine actions or time passing. Hitting zero calls
  `Clock.resolve_collapse()`, funneling through the same day-end path as sleep and the late-night cap.
- **Data-driven content** lives under `data/` as `.tres` resources (`ingredients/`, `recipes/`,
  `seeds/`, `skills/`, `upgrades/`), each backed by a `Resource` subclass in `scripts/data/` (e.g.
  `RecipeDef`, `SkillDef`, `UpgradeDef`). These are hand-authored text resources — when adding one,
  copy an existing sibling file's format exactly; typed array exports need the
  `Array[Type]([...])` syntax in the `.tres`, not a bare `[...]` literal, or Godot's parser rejects it.
  `UpgradeDef` and `SkillDef` both use a generic `effect_target: String` + `effect_amount: float` pair
  rather than a typed effect enum, resolved via a `match` in `Economy._apply_effect()` (upgrades) or
  applied additively per level threshold in `Skills` (skills).
- **`scripts/main.gd`** is now a thin orchestrator: it grants starting ingredients, builds a
  `RoomBuilder` and a `GameHud` (both plain, non-autoload `Node`s it owns as children, not scenes), and
  wires the handful of signals that need to touch both — e.g. `Herbalism.harvested` updates a HUD label
  *and* a grow-plot `Interactable`'s status text. `_on_interact_pressed()`'s type match is the other
  thing that stays here, since dispatching an interaction is inherently "which system do I call, which
  panel do I open." `scripts/room_builder.gd` (`RoomBuilder`) owns exploration-layer geometry — rooms,
  the shared player/camera, `Interactable` placement/switching — and connects directly to any autoload
  signal whose effect is purely spatial (`Herbalism.plot_added`/`planted`). `scripts/hud.gd` (`GameHud`)
  owns the debug HUD, the Escape menu shell, and the brew/supply panels, and connects directly to any
  autoload signal whose effect is purely a label/log update (most of them). Split out once `main.gd`
  grew past ~700 lines of two unrelated concerns (world geometry vs. presentation) glued together by
  signal wiring; keep new systems' UI-only reactions in `hud.gd` and world-only reactions in
  `room_builder.gd`, and only add to `main.gd` when a reaction genuinely needs both.
- **Exploration layer**: `Interactable` (`scripts/interactable.gd`) is one reusable `Area2D` scene
  configured per-instance (`interactable_type` enum, `target_id`, prompt text, color) rather than a
  subclass per interaction kind — the actual behavior for each type lives in `main.gd`'s
  `_on_interact_pressed()`, not on the Interactable itself. Player movement uses raw
  `Input.is_key_pressed(KEY_*)` checks (`scripts/player.gd`) rather than an InputMap, consistent with
  how the debug hotkeys (`Space`, `R`, `Up`/`Down`) are handled in `main.gd`'s `_unhandled_input`.
- **`MenuScene`** (`scripts/menu_scene.gd`) is the generalized modal menu shell used for any
  interactable that opens a menu rather than firing instantly (brew station → recipe list, supply
  shelf → buy ingredients/seeds/upgrades). It owns only the shared chrome — title, close button, and
  pausing — and is handed a bespoke content `Control` per menu type. `open()` reparents that
  content into its body and sets `Clock.is_paused = true`; `close()` reverses both. `player.gd`
  freezes movement off that same `Clock.is_paused` flag rather than tracking menu state itself, so
  `MenuScene` doesn't need to know the player exists. Menus are single-purpose per interactable (no
  tabs) and close on `Esc`, on re-pressing `E` at the same interactable, or on entering/exiting a
  different interactable; `STOCK_BOX`, `BED`, and `CLASS_DOOR` stay instant one-shot actions and never
  go through `MenuScene`. `_panel` (the root `PanelContainer` everything above gets reparented into) has
  `theme/ui_theme.tres` assigned to it, so panel/button/font styling for every menu is centralized there —
  swapping in illustrated art later is a theme/asset change, not a script change. `GameMenu`'s tab
  container shell and its signal-wiring pattern (autoload signal → `update_x()`) are still built ad hoc
  in code, same as `hud.gd`, but each tab's *repeated* rows/cells (item slots, skill rows, relationship
  rows, recipe entries, quest entries) are `scenes/ui/components/*.tscn` scenes paired with a
  `scripts/ui/components/*.gd` script (`class_name`, matching the `Interactable.tscn`/`interactable.gd`
  pairing convention) exposing a `populate(...)` method — `update_x()` instances and populates them
  instead of building nodes inline. Every component degrades gracefully to a tinted placeholder
  (colored dot, border swatch) when the underlying data `Resource`'s `icon`/`portrait` field is `null`,
  so illustrated art can land incrementally without ever breaking the UI. `IngredientDef`/`SeedDef` have
  an `icon: Texture2D` field and `CharacterDef` a `portrait: Texture2D` field for this; `RecipeDef` has
  no icon field of its own — the Recipes tab borrows the first required ingredient's icon as a stand-in
  until a `PotionDef` resource exists to hang a real one on.
- **Centering an ad hoc `Control` needs both calls.** `some_control.set_anchors_preset(Control.PRESET_CENTER)`
  only sets the anchor ratios — it leaves offsets untouched, so a freshly created, unsized `Control`
  ends up with its *top-left corner* pinned to the anchor point (screen center) rather than actually
  centered, and since Godot's default `grow_horizontal`/`grow_vertical` is `GROW_DIRECTION_END`, it
  then only grows right/down from there as content is added — the more content, the further it drifts
  off-center and, for tall panels (e.g. a Settings screen), off the bottom of the screen. Every
  code-built, centered panel must also set `grow_horizontal = Control.GROW_DIRECTION_BOTH` and
  `grow_vertical = Control.GROW_DIRECTION_BOTH` right after the `set_anchors_preset` call, so the panel
  grows symmetrically around the center point as its content/minimum size changes. `character_creator.gd`
  and `menu_scene.gd` do this correctly; `main_menu.gd` originally omitted it and needed the same fix.
