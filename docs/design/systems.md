# Vial Story — Systems Spec (Prototype Scope)

This document specs the gameplay systems for the sim/management half of Vial Story.
It covers what's in scope for the first prototype in full, and stubs the systems that
come later (VN/relationship layer, exploration, curse-as-mechanic) so the hooks exist
without building them out yet.

Status key: **[BUILD]** = target for prototype, **[STUB]** = design placeholder only.

---

## 1. Clock & Day-Cycle System **[BUILD]**

The central system everything else hooks into. Time is a continuous ticking clock
(Stardew Valley-style), not discrete player-triggered phases — the player should
feel the tension of having *enough* time in a day but never quite enough for
everything they want to do, and should be able to make active tradeoffs (e.g.
skipping class to handle a time-sensitive brew).

```
Clock
  - day_number: int
  - day_type: Weekday | Weekend
  - minutes_since_midnight: int      # continuous, e.g. 360 = 6:00 AM
  - tick_rate: game-minutes per real-second (tunable)
  - is_paused: bool                  # true during menus/dialogue/minigames
```

- Day runs roughly 6:00 AM to a soft cap around 2:00 AM; nothing else is phase-gated,
  the player just moves around and acts freely in real time.
- **Ending a day** has three independent triggers, all routed through one
  `AdvanceToNextDay(reason)` resolution so there's a single source of truth for
  "day is over":
  1. **Voluntary sleep** (bed interaction) — no penalty, possibly a small bonus for
     turning in at a reasonable hour.
  2. **Late-night collapse** — clock hits the ~2 AM cap while still awake → forced
     sleep, minor penalty (small Materials loss and/or a later start next morning).
  3. **Resolve collapse** — Resolve hits zero (see system 8) → forced end of day,
     framed narratively as giving up for today rather than a hard fail.
- **Scheduled Windows** are the generic structure other systems hook into instead of
  discrete phases:
  ```
  ScheduledWindow
    - day_type filter
    - start_time, end_time
    - trigger_type: Location (player must walk to a spot) | Ambient (runs passively)
  ```
  - **Class** = Location-triggered window. Walking to the classroom entrance during
    its window fires a `TimeSkip` straight to the window's end, plus class rewards
    (skill XP, item drops) and attendance credit toward `GradeRecord`. Not going
    means the window simply elapses while the player free-roams elsewhere — counted
    as an absence for grading purposes, but no time is lost, which is what makes
    skipping class for a time-sensitive brew a real, legible tradeoff.
  - **Shop open hours** = Ambient window. While current time falls inside it, the
    shop-stock sale-roll (system 5) just runs continuously in the background.
  - Love-interest schedules will reuse this same struct later (see system 13, stub).
- **TimeSkip** is the one utility both class-attendance and sleep/collapse call:
  given `(from_time, to_time, day_delta)`, it resolves everything that would have
  happened across that span — brew jobs and grow plots flip to Ready if their
  absolute timestamp falls within the skipped range, shop sales accrue for any
  open-hours portion of the skip — before the trigger-specific reward/penalty is
  applied on top.
- Because of `TimeSkip`, brew/grow completion only needs one absolute timestamp
  (`day_number * 1440 + minutes_since_midnight`) checked against the clock — it
  doesn't matter whether the player is standing at the station when it finishes or
  skipped straight over it via class or sleep.

---

## 2. Ingredient System **[BUILD]**

```
Ingredient
  - id
  - display_name
  - category: Natural | Artificial | Spectral | Demonic | Draconic | Extraplanar
  - tier: int                     # gates which recipes/stations can use it
  - source_methods: [Buy, Grow, Craft, Summon, Forage]  # unlocked per-save
  - quantity                      # tracked in player inventory
```

- `category` is mostly flavor plus which upgrade ladder unlocks its sourcing method.
- `tier` is the actual difficulty/recipe-gating knob, independent of category.
- Prototype only needs `Buy` and `Grow` implemented; `Craft`/`Summon`/`Forage` are
  stubbed as source methods that recipes/upgrades can reference but that have no
  unlock path yet.

---

## 3. Recipe System **[BUILD]**

```
Recipe
  - id
  - display_name
  - known: bool                   # separate from "available to learn"
  - station_required: StationType
  - brew_time: int                # in minutes of game-clock time
  - ingredients: [(ingredient_id, quantity)]
  - base_potency_range: (min, max)
  - base_ease_range: (min, max)
  - output_potion_id
  - unlock_minigame_id            # puzzle used to learn it
```

- Two-stage unlock: a recipe can be *available for purchase* before it's *known*.
  Learning it consumes the puzzle minigame identified by `unlock_minigame_id`.
- Recipes should live in a data table/resource, not hardcoded — content will grow fast.
- Prototype: minigame can be stubbed as an instant "learn" button; the puzzle itself
  is a separate build task.
- Quality is two independent numeric axes, not a single grade (see system 4):
  **potency** (how powerful the effect is) and **ease** (how easy the potion is to
  take/use). Different buyer archetypes and love interests will eventually weight
  these differently — a casual customer might prefer ease, Dragon House might care
  about potency and ignore ease — but for the prototype both are just raw numbers
  with no bucketing/tiers.

---

## 4. Brewing / Alchemy Station System **[BUILD]**

```
Station
  - id
  - station_type
  - tier
  - potency_modifier               # from tier/upgrades
  - ease_modifier                  # from tier/upgrades
  - speed_modifier

BrewJob
  - recipe_id
  - station_id
  - start_timestamp                # day_number*1440 + minutes_since_midnight
  - ready_timestamp                # start_timestamp + brew_time, modified by speed_modifier/skill
  - rolled_potency                 # from base_potency_range, Brewing skill, station potency_modifier
  - rolled_ease                    # from base_ease_range, Brewing skill, station ease_modifier
  - botched                        # rolled at brew start; see below
  - status: Brewing | Ready | Collected
```

- Jobs are resolved by absolute timestamp comparison against the clock, and must be
  resolvable in batch via `TimeSkip` — most brewing completes while the player is in
  class or asleep, so no system should assume the brew scene is actively open when a
  job finishes.
- `rolled_potency`/`rolled_ease` are raw numeric values shown directly to the player,
  not bucketed into tiers — they feed shop pricing/sale-chance and, later, buyer- and
  love-interest-specific preferences.
- A brew has a flat chance (prototype: 10%) of being botched, rolled at brew start.
  A botched brew still consumes the full brew time and ingredients, but yields no
  potion and costs Resolve instead — see system 8.

---

## 5. Shop Stock System **[BUILD]**

Stardew-box model: dump potions from inventory into a stock pool; they sell off
gradually during open hours rather than instantly overnight.

```
ShopStock
  - capacity: int                 # upgradeable
  - slots: [StockedPotion]        # (potion_id, potency, ease, price)
```

- Stocking interaction is low-friction: one action dumps all sellable potions from
  inventory into stock, up to capacity.
- While the current clock time falls within the shop's Ambient open-hours window
  (system 1), stocked potions roll sell-chance on a fixed simulated interval (e.g.
  every N in-game minutes), weighted by price, potency/ease (per system 3/4), and
  shop reputation (reputation stat: stub for now, default flat weight).
- On sale: remove one unit, add Materials, log the sale for a "while you were away"
  summary shown to the player at the next check-in.
- Capacity is the primary upgrade lever (no manual shelf placement in prototype).

---

## 6. Skills System **[BUILD]**

```
Skill
  - id                             # Brewing, Herbalism, Summoning, ...
  - xp
  - level
  - level_up_curve
  - effects: [(level_threshold, effect)]
```

- Skills system is a passive listener: other systems fire XP events (brew completed,
  harvest completed, class attended, exam passed) and the skill system applies xp/levels.
- Effect examples:
  - Brewing: + `potency_modifier`/`ease_modifier`, + brew speed
  - Herbalism: + grow yield, + grow speed, unlocks higher-tier natural ingredients
  - Summoning: unlocks demonic/extraplanar sourcing tiers **[STUB — no sourcing path yet]**
- Prototype needs Brewing + Herbalism fully wired; other skills can exist as data
  with no unlocked effects yet.

---

## 7. Herbalism / Growing System **[BUILD]**

```
GrowPlot
  - id
  - planted_ingredient_id | null
  - planted_timestamp
  - ready_timestamp                # planted_timestamp + growth_time, modified by Herbalism level
  - status: Empty | Growing | ReadyToHarvest
```

- Growth resolves by absolute timestamp comparison, same as brew jobs — checked on
  any relevant tick and swept during `TimeSkip` (overnight, or across a skipped
  class window).
- Number of plots is an upgrade lever (e.g. terrace stations).

---

## 8. Resolve Meter System **[BUILD]**

A combined health/energy stat. Unlike a Stardew-style stamina bar, it does not
drain from normal time passing or routine actions — only from things going wrong.

```
Resolve
  - current: int
  - max: int
  - strained_threshold: int        # below this, a global debuff applies
```

- Normal actions (brewing, harvesting, walking, attending class) do **not** cost
  Resolve on their own.
- Failure/mishap events cost Resolve: a botched brew, a summoning accident (once
  Summoning exists), a failed exam, etc. Each failure event defines its own Resolve
  cost.
- Below `strained_threshold`: a global debuff to all skills — every skill-driven
  bonus returned by `Skills.get_bonus()` (system 6) is halved while strained, rather
  than each system implementing its own separate debuff check.
- At 0: forced end of day via `AdvanceToNextDay(resolve_collapse)` (system 1) —
  narratively framed as the character giving up for today rather than a hard fail
  state. This is the mechanical hook for moments like "that summoning attempt went
  badly, guess today's ingredient run is off — might as well go see the Eagle House
  girl instead" emerging from the meter itself rather than scripted logic.
- Regenerates on sleep (full or partial — needs tuning), and potentially via rest
  actions or items later.
- Prototype scope: only Brewing failure events need to cost Resolve; other failure
  sources (Summoning, exams) plug in once those systems exist.

---

## 9. Class / Exam / Grade System **[BUILD]**

The fail state. Deliberately low-stress and recoverable — no single-strike loss.

```
GradeRecord
  - running_score: float           # per-class or overall; simple average is enough for prototype
  - strikes: int                   # accumulates on failing grade
  - strike_decay: on any passing grade, decrement strikes
```

- Attending class (via the Location-triggered `ScheduledWindow` + `TimeSkip`, system
  1) contributes a small continuous bonus to `running_score` plus skill XP / item
  drops. Not attending contributes nothing and counts toward absence tracking, but
  costs the player no time relative to staying out and doing something else.
- Exams are scripted periodic events that roll a grade from `running_score` (+ any
  prep actions taken, if/when those exist).
- Passing a grade decays `strikes`; failing increments it.
- Reaching `strikes >= N` triggers the game-over state: Academy revokes selling
  privileges, ending the Vial Story run.
- Player can always see current standing (report card UI) — grades and strikes are
  never hidden information.
- **[STUB]** Term structure and the overarching time-limit framing are out of scope
  for the prototype; `GradeRecord` should not assume a fixed term length yet.

Prototype implementation values (tunable):
- Class window: 8:00 AM – 12:00 PM, weekdays only. Since Exploration (system 12)
  isn't built, "attend class" is a time-gated debug-HUD action rather than a
  walk-to-trigger — attending fires `Clock.skip_to()` to the window's end, the
  first real use of the `TimeSkip` concept for something other than sleep/collapse.
- Attendance: +15 to `running_score` (capped 100), +10 Herbalism XP.
- Exams: every 7 in-game days; `running_score` resets to 0 after each exam so
  attendance matters every cycle rather than accumulating indefinitely.
- Passing threshold: `running_score >= 50`.
- Strike limit: 3. Reaching it sets `Clock.is_paused = true` — a full stop, not a
  soft lock — matching the original framing that this ends the run.

---

## 10. Economy / Upgrades System **[BUILD]**

- Materials is the single currency, earned via shop sales, spent on:
  shop/lab upgrades, recipe access, ingredient purchases, and (later) relationship
  gifts / story gates.
- Upgrades are data-driven (id, cost, effect target — e.g. `ShopStock.capacity += 1`,
  `Station.potency_modifier += x`, `GrowPlot count += 1`).
- Costs are the main pacing lever for the whole loop; needs a tuning pass once the
  core loop is playable, not before.

---

## 11. Curse System **[STUB — flavor only for now]**

```
CurseState
  - active_curse_flags: [flag_id]  # each may carry a small negative modifier
```

- For the prototype, the curse is narrative flavor draped over the fact that the
  player starts with minimal stations/recipes/capacity — no dedicated mechanical
  curse layer is required to justify the slow start.
- Leave the `CurseState` hook in place so small mechanical interventions (a debuff
  that's story-removable) can be layered on top later, without redesigning the
  brewing/shop systems to accommodate it.
- Not Materials-purchasable in the prototype — no sink should be built for it yet.

---

## 12. Exploration / Map System **[STUB]**

- Top-down movement within the shop interior and a small surrounding neighborhood.
- Scope is deliberately limited: a handful of interactable nodes (shop counter,
  stock box, brew stations, grow plots, a couple of NPC/scene triggers outside),
  not an open world.
- Anything outside this small area (classes, most love-interest content) resolves
  as a VN scene rather than being walked to — see system #13.
- No pathfinding/AI needs beyond simple player movement + interaction prompts for
  the prototype.
- **Rooms**: the interior is split into separate room containers (currently
  `Shop` and `Bedroom`) built up front in `main.gd`'s `_build_rooms()`, each
  holding its own floor + interactables. Only one room is active at a time —
  `_switch_room()` toggles `visible`/`process_mode` on the room containers
  (inactive rooms are `PROCESS_MODE_DISABLED`, which also stops their
  `Interactable` areas from firing enter/exit signals while hidden) and
  repositions the single shared player + camera. The player and camera are
  scene-level nodes, not per-room, so they persist across a switch.
- **Room transitions** are just another `Interactable.Type` (`STAIRS`), configured
  with a `target_room` id and a `spawn_position` in the destination room, the
  same per-instance-config pattern as every other interactable type. The Bed
  lives in the Bedroom; the Shop's brew station/stock box/supply shelf/class
  door/grow plots stay in the Shop, connected by a stairs interactable in each
  room pointing at the other.

---

## 13. VN / Relationship System **[BUILD — in progress]**

A custom-built dialogue engine, not a third-party addon — the explicit intent is to
frontload real engine investment now so that later work is writing/art, not more
engineering. Scope for the first pass: one love interest, a handful of scenes,
proving trigger → full-screen scene → consequence end-to-end.

### Expression language **[BUILT]**

A single small boolean-expression grammar backs both dialogue `if` statements and
scene-trigger conditions — one evaluator, two use sites, rather than parallel
condition systems.

```
primary    := NUMBER | STRING | "true" | "false" | IDENT "(" args ")" | "(" expr ")"
comparison := primary ( ("==" | "!=" | ">=" | "<=" | ">" | "<") primary )?
not_expr   := "not" not_expr | comparison
and_expr   := not_expr ( "and" not_expr )*
or_expr    := and_expr ( "or" and_expr )*
```

- `scripts/vn/vn_expression_parser.gd` (`VNExpressionParser`) — hand-rolled
  tokenizer + recursive-descent parser. AST nodes are plain `Dictionary`s
  (`{"type": "call", "name": ..., "args": [...]}` etc.) rather than a class per
  node kind, since they're transient and structurally varied enough that a class
  hierarchy would be overhead. A malformed expression `push_error`s and `parse()`
  returns `null` rather than crashing.
- `scripts/vn/vn_expression_evaluator.gd` (`VNExpressionEvaluator`) — walks the
  AST. One dispatch table (`match` on function name, same pattern as
  `Economy._apply_effect()`) serves both value-returning condition functions
  (`has_flag`, `affection`, `has_item`, `materials`, `skill_level`) and
  side-effecting action functions (`set_flag`, `clear_flag`, `add_affection`,
  `give_item`) — the parser doesn't structurally distinguish a condition from an
  action (both are just `call` nodes), so neither does the evaluator.
- `Story` autoload — flat flag store (`has_flag`/`set_flag`/`flag_changed` signal).
- `LoveInterests` autoload — affection per love-interest id
  (`get_affection`/`add_affection`/`affection_changed` signal). Static love-interest
  data (display name, house, etc.) will live in a `LoveInterestDef` resource once
  scenes need it; affection itself only needs a string id.

### Dialogue script format **[BUILT]**

A line-oriented script format (Ink/Yarn-style), parsed and then *compiled* to a
flat, linear instruction list with resolved label/jump targets — not a tree the
runtime walks recursively — so the runtime itself stays a simple instruction
pointer rather than needing to recurse into `if`/`else` bodies. `if`/`else` blocks
use explicit `endif` terminators rather than indentation sensitivity, trading a
little visual elegance for a much more robust hand-rolled parser.

`scripts/vn/vn_script_compiler.gd` (`VNScriptCompiler`) implements this as a
single static `compile(source: String) -> Dictionary`, returning
`{"scene_id": ..., "instructions": [...]}` on success or `{}` on failure (errors
`push_error`d, same no-exceptions contract as `VNExpressionParser`). Instructions
are plain `Dictionary`s tagged with an `"op"` string (`SHOW_LINE`, `SHOW_CHOICE`,
`JUMP`, `JUMP_IF_FALSE`, `STAGE_ENTER`, `STAGE_EXIT`, `STAGE_MOVE`,
`STAGE_EXPRESSION`, `CALL`, `END`) — same node-as-Dictionary convention as the
expression AST. `JUMP`/`JUMP_IF_FALSE`/choice-option targets are resolved
integer instruction indices (never label-name strings), and `JUMP_IF_FALSE.condition`
/ `CALL.call` embed the exact AST `VNExpressionParser` produces — no re-encoding,
so the eventual `DialogueRunner` can call `VNExpressionEvaluator.evaluate()`
directly on those fields.

Compilation is a single pass over the script's lines that emits instructions
while building a `label -> index` table and a list of not-yet-resolved jump
targets (`goto`/choice options), followed by one small backpatch pass over just
that list. `if`/`else`/`endif` resolve their own jump targets inline as they're
encountered (no backpatch needed there, since by the time `else`/`endif` is
reached the relevant instruction index is already known) via a stack of
in-progress `if` frames — implemented as a real stack so nested `if` will fall
out for free later even though v1 only exercises one level. `choice` blocks are
detected structurally: after a `choice` line, subsequent lines are consumed as
`"text" -> label` options for as long as they match that shape, ending at the
first line that doesn't (no explicit `endchoice`, no indentation tracking).

Verified against the sample script below via a throwaway test scene (compiled
instruction list checked structurally — jump/choice targets land on the right
*content*, not hardcoded indices — including the negative case of an
unresolvable `goto` correctly failing compilation).

Planned v1 grammar: speaker lines (`Kaelith: "text"`), `choice` blocks with
`"text" -> label` options, `label`/`goto`, one level of `if <expr> / else / endif`,
action-call statements (reusing the expression language's `call` syntax), and
stage directions for full VN-style staging — this is **full-screen VN
presentation** (background + character sprites positioned in the scene itself,
not a small portrait-in-a-box), so stage directions need arbitrary 2D positions,
not fixed left/center/right slots:

```
scene kaelith_greeting
enter Kaelith at 200,400
Kaelith: "You're still up? Typical."
choice
  "Ask about her day" -> ask_day
  "Offer her a potion" -> offer_potion

label ask_day
Kaelith: "It's been long. Exams, you know."
goto end

label offer_potion
if has_item("clarity_tonic")
  Kaelith: "For me? How thoughtful."
  add_affection("kaelith", 5)
  give_item("clarity_tonic", -1)
else
  Kaelith: "You don't actually have one, do you?"
endif
goto end

label end
end_scene
```

Stage directions also need `exit <char>`, `move <char> to <x>,<y>`, and an
expression/sprite-variant switch (e.g. `expression Kaelith smug`) for changing a
present character's art without moving or removing them. Multi-character and
NPC-to-NPC scenes fall out of this for free — the runtime doesn't care whether
the speaker changes every line or stays the same, and a scene the player only
observes is just lines where neither active speaker is the player.

Placeholder art: plain colored rectangles + labels, same as the room's
placeholder art — since VN sprites fill most of the screen rather than being a
small player-sized block, this is expected to read clearly as "VN scene" without
needing portrait-shaped placeholders.

### Runtime and presentation **[NOT BUILT YET]**

- `DialogueRunner` — steps through a compiled scene's instructions, emitting
  signals (`line_shown(speaker, text)`, `choice_requested(options)`,
  `stage_changed(...)`) and waiting for the UI to call back in (`advance()`,
  `choose(index)`).
- `DialogueBox` — full-screen scene: background, positioned character sprites
  (added/removed/moved per stage direction, active speaker highlighted / others
  dimmed), name plate + text at the bottom, choice buttons.

### Scene triggering **[NOT BUILT YET]**

No fixed taxonomy of trigger *types* — a scene can be triggered by anything at
any time, so a `SceneTriggerDef` just carries a condition expression (the same
expression language as `if` statements) rather than an enum of trigger kinds.

```
SceneTriggerDef
  - id
  - script_path
  - condition: String        # expression source, parsed once at registration
  - priority: Priority        # LOW | NORMAL | HIGH | MAX — buckets, not raw numbers
  - repeatable: bool
  - show_from_menu: bool      # can this cut in through an open menu?
```

- `SceneDirector` autoload registers all `SceneTriggerDef`s and re-evaluates them
  via `recheck()` — on every `Clock.minute_tick` as a cheap baseline (so
  time/flag-only conditions never lag more than a minute), and immediately from
  specific call sites (a menu closing, a sale landing, a room change, etc.) for
  anything that should feel instant. A satisfied trigger fires the highest
  `priority` bucket first, then earliest-registered within that bucket.
- **No explicit queue.** A trigger that's satisfied but blocked (player mid-menu,
  and `show_from_menu` is false) simply doesn't fire yet; the very next
  `recheck()` — which happens constantly regardless — re-runs the same
  priority/registration-order selection fresh. This also means a trigger whose
  condition stops holding true while "queued" is naturally dropped rather than
  firing stale.
- An already-*playing* scene always blocks new scenes outright, regardless of
  `show_from_menu` — that flag only lets a scene cut through a menu (e.g. calling
  a love interest from a phone menu item), not through another scene in progress.
  No nested scenes.
- Non-repeatable scenes mark themselves played via the same `Story` flag store
  (`has_flag("scene_played_" + scene_id)`) rather than separate "seen" bookkeeping.

---

## Suggested Prototype Build Order

1. Clock & day-cycle system (system 1)
2. Ingredient inventory + a couple hardcoded recipes + brewing stations, no minigame yet (systems 2–4)
3. Shop stocking + probabilistic sales during ambient open hours (system 5)
4. Materials economy + a small number of purchasable upgrades (system 10)
5. Skills with XP/leveling hooked to Brewing + Herbalism (system 6)
6. Resolve meter, wired to brewing failure events (system 8)
7. Class scheduled-window resolution + grade/strike tracking (system 9)
8. Herbalism growing plots (system 7)
9. Recipe-learning minigame; remaining ingredient sourcing methods; exploration polish
10. VN/relationship layer (systems 12–13) and curse mechanical interventions (system 11)

## Open Design Questions (not yet decided)

- Shop reputation: does it exist as a stat in the prototype, or is sale-chance flat
  until later?
- Exact grade formula (attendance weight vs. exam performance vs. prep actions).
- Resolve regen curve on sleep (full reset vs. partial) and whether any daytime rest
  action should exist in the prototype.
- Target real-world length of a full in-game day (drives `tick_rate` tuning).
