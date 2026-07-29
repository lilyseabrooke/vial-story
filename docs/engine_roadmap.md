# Engine-Building Roadmap

This document tracks the metamorphosis from prototype to engine described in `CLAUDE.md`'s
development philosophy. Where `docs/design/systems.md` is the spec for *what the game does*, this
is the spec for *what building blocks the game is made of* — the shared primitives a new system
should be assembled from rather than reimplemented from scratch, plus the editor tooling that makes
those primitives easy to use without reading five other systems first.

Each phase lists: the problem (with concrete evidence), the primitive being extracted, and what it
unblocks. Phases are ordered by dependency, not just priority — do not skip ahead without checking
what a later phase assumes exists.

## Already unified (the model to imitate)

Three things already work the way everything below should:

- **`SaveManager`** — every autoload implements `get_save_data()`/`load_save_data()`; `SaveManager`
  drives all of them generically via `_SAVE_ORDER`. No per-system save code lives outside this contract.
- **Currency** — all gold flows through `Inventory.materials` + `add_materials`/`spend_materials` +
  one `materials_changed` signal. Nothing pokes a raw field.
- **Condition gating** — `QuestDef.complete_condition` and `SceneTriggerDef.condition` both reuse the
  VN expression parser/evaluator as one shared boolean-gate language.

## Phase 0 — Quick wins (no dependencies)

**0a. Class icons for `Resource` subclasses.**
`RecipeDef`, `QuestDef`, `IngredientDef`, `SeedDef`, `SkillDef`, `UpgradeDef`, `CurseDef`, etc. all
render as the generic Resource icon in the FileSystem dock and Inspector. Add an `icon` argument to
each `class_name` declaration. Five minutes each, immediate visual clarity as `data/` content volume
grows.

## Phase 1 — `TimedJobBase`

**Problem:** 11 autoloads — `Brewing`, `Herbalism`, `Academy`, `ArtStudio`, `Demonology`,
`Draconology`, `LeyLines`, `NpcScheduler`, `Shop`, `Summoning`, `Transmutation` — each independently
reimplement the same shape: idempotent `register_*`, a `start_timestamp`/`ready_timestamp` computed
from `Clock.get_timestamp()` + a speed modifier, a `_on_minute_tick` loop flipping status to ready,
and a collect step guarded on ready-status. `brewing.gd` and `herbalism.gd` are near line-for-line
identical in this skeleton; only the botch-roll (Brewing) and yield-tier (Herbalism) steps are
genuinely domain-specific.

**Build:** `TimedJobBase` — fields `start_timestamp`, `ready_timestamp`, `status`; methods
`start(duration_minutes, speed_modifier)`, `tick(timestamp) -> bool` (fires on the ready transition),
`collect() -> bool`. Owning autoloads keep their roll/yield/consume logic as hooks around it. Migrate
one system at a time, starting with the two most identical (`Brewing`, `Herbalism`) to prove the
extraction, then the remaining nine.

**Why first:** mechanical, low-risk (refactoring code that already works, not new behavior), and
immediately shrinks the largest duplicated surface in the codebase. Phase 6's debug dock assumes
this exists.

## Phase 2 — Scaffolding commands (tooling)

**Problem:** the `InteractableBase` subclass convention and `scenes/ui/components/*` convention both
rely on "copy an existing sibling `.tscn` exactly" (per `CLAUDE.md`) — tribal knowledge, not
tool-enforced.

**Build:** an `EditorPlugin` adding `Project > Tools > New Interactable...` and
`New UI Component...` entries (or a small dock), generating the paired `.gd` + `.tscn` from a
template.

**Why here:** built early so it can be *used* to scaffold every component the later phases add
(ChoiceListMenu rows, Notification rows, panel controllers in Phase 6) instead of those still being
hand-copied.

## Phase 3 — Unify the effect-string interpreters

**Problem:** three independent hand-written `match`/dispatch blocks all do "name a game-state
mutation, look it up, apply it": `Economy._apply_effect()` (upgrades), `Curse._apply_penalty()`
(curses), and `VNExpressionEvaluator._call_function()` (VN/quests) — the last one is already the most
general. Additionally, the puzzle-constraint-type `match` is separately duplicated between
`alchemy.gd` and `potion_def.gd`.

**Build:** fold `Economy._apply_effect` and `Curse._apply_penalty` into the VN evaluator's function
table (or a thin shared `EffectRegistry` wrapping it), so `effect_target` strings for upgrades,
skills, and curse penalties all resolve through one registry with one list of valid keys. Unify the
puzzle-constraint-type match into a single source of truth both `alchemy.gd` and `potion_def.gd` read
from.

**Why here:** this registry is what Phase 4's inspector tool needs to enumerate valid keys from — it
must exist before the dropdown can be built.

## Phase 4 — `effect_target` dropdown inspector (tooling)

**Problem:** `effect_target: String` on `UpgradeDef`/`SkillDef` is stringly-typed — a typo like
`"station_potenc"` fails silently at runtime with no warning.

**Build:** an `EditorInspectorPlugin` that detects `effect_target`-style fields and renders an
`OptionButton` populated from Phase 3's registry instead of a raw text field.

**Depends on:** Phase 3 (needs one registry to enumerate keys from — building this against three
scattered `match` blocks would just re-encode the duplication into the tool).

## Phase 5 — Generic content-authoring framework

**Problem:** most flat content (a plain ingredient, a straightforward recipe) needs no custom tool at
all — Godot's native "New Resource → fill Inspector → save" workflow already works as a form-based
creation tool the moment a `Resource` subclass has good `@export` hints (`@export_enum`, typed
`Array[IngredientDef]` reference lists, `@export_range`). Content is currently hand-authored as raw
`.tres` text specifically because that annotation work hasn't been done, not because the format
requires it. Two field shapes are the real risk, though: `QuestDef.complete_condition`/`reward` are
`Array[String]` of hand-typed action-call syntax (`give_item(...)`, `add_affection(...)`) reusing the
VN expression grammar — the same class of footgun as `effect_target`, just for function calls instead
of keys — and any content shaped as an **ordered sequence of steps** (e.g. a `SummoningSequenceDef` or
`LeySurgeDef` holding stages/phases) is exactly where Godot's stock `Array[Resource]` inspector gets
clunky for reordering/inserting/previewing.

**Build:** two things, not five bespoke "New X" dialogs:
1. Audit existing content `Resource` scripts (`IngredientDef`, `RecipeDef`, `QuestDef`,
   `SummoningSequenceDef`, `LeySurgeDef`, etc.) and tighten `@export` hints so the stock Inspector
   already does most of the work.
2. One generic content-authoring dock: a registry of content types (Ingredient, Potion/Recipe, Quest,
   Summoning Sequence, Ley Surge, ...) that instances the right `Resource` and opens it for editing,
   plus an extension point for "smart field" widgets that specific field names/types opt into — a
   function-picker-plus-typed-arg-form widget for the action-call string arrays, and a reorderable
   step-list widget for sequence/stage content. Plain fields fall through to the stock Inspector.
   Dialogue/VN content is explicitly out of scope here — it gets its own dedicated tool later given
   its importance.

**Depends on:** shares `EditorInspectorPlugin` infrastructure with Phase 4 — sequence directly after
it rather than in parallel.

## Phase 6 — Cost / Grant primitives

**Problem:** the check-then-spend idiom
(`if not Inventory.spend_materials(x.cost): return "Not enough Materials."`) is copy-pasted near
verbatim across `economy.gd`, `brewing.gd`, `herbalism.gd`. Reward granting (items, XP, affinity) is
called ad hoc and independently at every system's own call sites — except `QuestDef.reward`, which
already routes dynamic rewards through the VN evaluator's action-call strings (`give_item`,
`add_affection`, etc.). That's the right model; it just isn't used anywhere but quests yet.

**Build:** `Inventory.try_spend(costs: Array)` as one check-and-commit primitive (pantry-awareness as
a parameter, not a parallel method, replacing Brewing's separate pantry-aware reimplementation). Let
any system build reward action-call strings at runtime and hand them to `VNExpressionEvaluator`
instead of calling `Inventory`/`Skills` sinks directly.

**Depends on:** Phase 3's registry work establishes the pattern of "one interpreter, many callers"
this phase extends from effects to costs/rewards. Also feeds `TimedJobBase.collect()` (Phase 1) a
natural place to call Grant on completion — revisit Brewing/Herbalism's collect hooks once this
lands.

## Phase 7 — Choice & confirmation UI primitives

**Problem:** "array of options → buttons → selected index" has been independently built four times:
`BrewMenu`'s recipe list, the class-effort picker, `ArtStudioPicker`, and VN dialogue choices. None
share more than `MenuKeyNav`'s static nav toolkit. Separately, no general `ConfirmationDialog` exists
— `art_studio_discard_confirm.gd` says so in its own comments and built a one-off instead.

**Build:**
- `ChoiceOption` (Resource: `id`, `label`, `description`, `icon`, `enabled`, `metadata`) +
  `ChoiceListMenu` (`populate(options: Array[ChoiceOption])`, one `selected(id)` signal), internally
  wiring the `ButtonGroup` + `MenuKeyNav` pattern `BrewMenu` already uses. Migrate the class-effort
  picker, `ArtStudioPicker`, and VN dialogue choices onto it directly (all three are already this
  shape underneath). `BrewMenu`'s ingredient/detail card and `QuestEntry`'s independent action rows
  layer on top as richer content rather than being rewritten.
- `ConfirmationDialog` (message + confirm/cancel signals) as a sibling component sharing the same nav
  wiring.

**Depends on:** Phase 2's scaffolding tool should generate the new component's `.gd`/`.tscn` pair.
This is also the primitive the future Contract Book "menu with choices" expansion will consume
directly instead of being built from scratch.

## Phase 8 — Notifications

**Problem:** `ItemToastFeed` only reacts to `Inventory.ingredient_gained`; `hud.gd` documents in its
own comments that materials/level-ups/quest-completions/resolve-collapse are "console-only until a
dedicated toast system... replaces this stub."

**Build:** `Notifications.push({icon, text, tint})` queue; `ItemToastFeed`-style rows become one
subscriber among several. Wire `Skills.leveled_up`, `quest_completed`, `Resolve` collapse/strain, etc.
into it.

**Depends on:** Phase 7's component patterns (row scenes, animation-in/out chrome) are the natural
template for notification rows.

**Status: reverted.** Built and wired (`Notifications` autoload + `NotificationFeed`/`NotificationToast`
components, `hud.gd`'s `log_message()` pushing every message through it), but playtesting showed every
message it surfaced was unwanted noise — level-ups, quest completion, writ/dragon/ley line/summoning
progress, etc. all read as clutter once actually on screen next to rolls and item toasts. Removed
entirely rather than left disabled: `log_message()` is back to console-only on purpose. If a future
system genuinely needs to reach the player beyond a roll (`RollDisplay`) or an item gain
(`ItemToastFeed`), route it through the VN dialogue box with no speaker instead of reintroducing a
toast queue.

## Phase 9 — `hud.gd` decomposition

**Problem:** `hud.gd` is 1013 lines with 75 manual signal connections and no backing `.tscn` — every
panel (`GameMenu`, `AlchemyLabMenu`, `GardenMenu`, `CursePanel`, the help popover, etc.) is built via
`.new()`/`add_child` chains in code. This is the same shape that already forced one split of
`main.gd`, and it's the direct cause of the ad hoc-Control centering bug documented in `CLAUDE.md`.

**Build:** each panel gets its own `.tscn` + controller script (mirroring the `InteractableBase`
subclass convention), owning its own autoload connections; `hud.gd` shrinks to a thin shell that
instances them.

**Depends on:** deliberately last — panels should be built as consumers of `ChoiceListMenu` (Phase 7)
and `Notifications` (Phase 8) rather than migrated once and then immediately reworked again once
those primitives land. Use Phase 2's scaffolding tool to generate the new panel scenes.

**Status:** `CursePanel` converted first (smallest, most self-contained panel) to prove the pattern —
its static chrome (title, description label, requirements/tray two-column layout, Dispel button) now
lives in `scenes/ui/CursePanel.tscn`, with `curse_panel.gd` reduced to a `setup()` node-ref resolution
plus its existing dynamic logic. Note `setup()` rather than `@onready`: these MenuScene-hosted panels
are only reparented into the live tree on first `MenuScene.open()`, and some open call sites (e.g.
`CurseInteractable`) call `open_for()` *before* `open_menu()`, so node refs must resolve eagerly right
after `instantiate()`, not lazily in `_ready()` — the same pitfall bit `ConfirmPanel` in Phase 7 and was
fixed the same way. The remaining panels (`GameMenu`, `AlchemyLabMenu`, `GardenMenu`,
`PantryStorageMenu`, `brew_panel`, `discover_panel`, `supply_panel`, the help popover) are left as
incremental follow-up migrations using this proven pattern + Phase 2's scaffolding tool, rather than
converted in one large sweep — each conversion needs in-game verification of its actual open/interact
flow (not just a clean headless boot) to catch the `setup()`-vs-`@onready` class of bug above, which a
full-sweep pass in one sitting can't safely get for every panel.

## Deferred / not currently scoped

Flagged during discussion but not part of this roadmap unless priorities change:

- **Data validator dock** — a `Project > Tools` panel cross-checking `.tres` references
  (ingredient IDs, reward action-call strings, effect_target keys) for validity.
- **`.vnscript` syntax highlighting** — a custom `EditorSyntaxHighlighter` for the dialogue DSL.
- **"Jobs" debug dock** — a panel listing every active `TimedJobBase` instance across every autoload
  with a manual "force ready" button, once Phase 1 lands.
- **One-click cache-rescan tool** — an `EditorPlugin` menu entry automating the global script class
  cache rescan `CLAUDE.md` documents as a recurring headless-run friction.
- **Roll-broadcast signal** — a single `Rng.roll_resolved` signal so `hud.gd` subscribes once instead
  of once per roll-based system (12+ near-identical `connect()` stanzas today). Low priority: the
  roll pipeline (`Rng.roll_2d10` → `RollDisplay` + persistent log) already works well; this only
  trims boilerplate.
