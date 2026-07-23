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
- **Speed controls** (Sims-style): 1x/1.5x/2x buttons in the HUD (and 1/2/3 hotkeys)
  call `Clock.set_speed_level()`, which multiplies the base tick rate. Those digit
  hotkeys are reused as quick-brew slots while the brew menu is open (system 4) —
  no conflict, since the world is paused during menus. The actual
  `tick_rate_minutes_per_second` eases toward the new target every frame
  (`move_toward` in `_process`) instead of snapping, so speed changes read as a
  smooth ramp rather than a jump cut.
- **Menu keyboard navigation** (`MenuKeyNav`, `scripts/ui/menu_key_nav.gd`): every
  menu drives on the same keys the brew menu established (system 4) — **W/S** (or
  arrows) move a cursor rendered as the theme's forced-*hover* look, **E** activates
  the control under it, **A/D** nudge sliders and cycle OptionButtons, and **Esc**
  backs out one level, falling through unconsumed to whoever owns closing (main.gd
  for `MenuScene` menus) when there's nothing left to undo. Simple button-list menus
  get it by adding a `MenuKeyNav` child node to the content Control — it re-collects
  the host's buttons/sliders in tree order on every move, so rebuilt panels never
  strand the cursor — currently the supply shelf, class-effort, and Potion Book
  discover panels, plus the main menu's root/load/settings screens (the latter two
  with `handle_escape`, so Esc is their Back button; `require_pause` off there since
  the title screen never pauses). `BrewMenu` and `GameMenu` keep their own two-mode
  `_input()` but build on MenuKeyNav's shared statics
  (`set_highlight`/`activate`/`adjust`/`collect_nav_controls`/`ensure_visible`).
  The Escape menu's two levels mirror the brew menu's browse/focus split: W/S at the
  rail switch sections directly, E steps into the shown section's controls (a
  no-op for sections with nothing actionable), Esc steps back to the rail, and a
  second Esc closes the menu; a caption pinned under the rail shows the active
  level's key map.
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
  - role: Base | Binder | Catalyst
  - weight: float
  - characteristics: [(characteristic_id, value)]   # e.g. ("astral", 3), ("dream", -1)
```

- `category` is mostly flavor plus which upgrade ladder unlocks its sourcing method.
- `tier` is the actual difficulty/recipe-gating knob, independent of category.
- Prototype only needs `Buy` and `Grow` implemented; `Craft`/`Summon`/`Forage` are
  stubbed as source methods that recipes/upgrades can reference but that have no
  unlock path yet.
- `role`/`weight`/`characteristics` don't do anything on their own — they only feed a
  potion's discovery puzzle (system 3). `characteristics` is a set of free-form,
  signed integer axes (astral, abyssal, necromantic, dream, ...) with no fixed enum;
  an axis absent from an ingredient's list is implicitly 0. `IngredientDef` stores
  both as parallel arrays (`characteristic_ids`/`characteristic_values`), same
  convention as `RecipeDef`'s `ingredient_ids`/`ingredient_quantities`.

---

## 3. Recipe System **[BUILD]**

```
Potion                              # PotionDef, scripts/data/potion_def.gd
  - id
  - display_name
  - icon
  - station_required: StationType
  - brew_time: int                 # in minutes of game-clock time
  - potency_range: (min, max)
  - ease_range: (min, max)
  - puzzle_constraints: [(type, target, min, max)]   # the recipe-discovery puzzle

Recipe                              # RecipeDef, scripts/data/recipe_def.gd
  - id
  - display_name                   # a *method* label, e.g. "Ember Dust + Rift Glass" — not the potion's name
  - known: bool                    # seeds Alchemy's learned set at new-game start only
  - output_potion_id               # which Potion this is a way of making
  - ingredients: [(ingredient_id, quantity)]
```

- **A potion's stats and discovery criteria live on `PotionDef`; a `RecipeDef` is just
  one learned *way* to make it** — an ingredient combination, nothing more. This split
  exists because recipes can't be hand-authored one-per-permutation at scale: with
  hundreds of ingredients across many potions there's no way to anticipate every viable
  combination up front. Instead, the player finds them — any ingredient selection that
  satisfies a `PotionDef`'s puzzle criteria becomes its own independently-learned
  `RecipeDef`, synthesized at runtime, so the same potion can end up with several
  unrelated learned recipes (moonpetal + iron filings *and*, separately, ember dust +
  rift glass) without either being pre-written as content.
- Two-stage unlock: a potion's discovery puzzle is *always available* at the Potion Book
  (not gated on whether the player already knows a recipe for it) before any resulting
  recipe becomes *learned* (brewable at the Alembic). Recipe *learned* state lives at
  runtime in the `Alchemy` autoload (`is_learned`/`get_learned_recipe`/
  `get_learned_recipes`/`unlearn_recipe`,
  `recipe_learned`/`recipe_unlearned`/`puzzle_attempted` signals, its own
  `get_save_data()`/`load_save_data()`) — `known` on a starter `RecipeDef` `.tres` only
  seeds which recipes `Alchemy` starts a new game already knowing (see
  `data/recipes/minor_healing_draught.tres`/`clarity_tonic.tres`). A potion the player
  starts with no knowledge of at all (`grave_ward_tonic`) has **no** `RecipeDef` on disk
  — only its `PotionDef`; every recipe for it comes from discovery.
  `unlearn_recipe()` has no UI trigger yet in the prototype; it's a hook for a later
  curse/memory-loss mechanical intervention (system 11).
- Both potions and recipes live in data tables/resources, not hardcoded — content will
  grow fast, and potions/recipes now scale independently of each other.
- Discovering and brewing are split across two interactables: the **Potion Book**
  (`PotionBookInteractable`, `scripts/potion_book_interactable.gd`) opens
  `hud.discover_panel`, listing a "Discover: X" button per `PotionDef` that has a
  puzzle — shown unconditionally, since discovery always looks for a *new* recipe and
  is never blocked by an existing one; the **Alembic** (`BrewStationInteractable`)
  opens `hud.brew_panel` — a `BrewMenu` (`scripts/ui/brew_menu.gd`), described in
  system 4, listing only learned recipes. `BrewMenu.refresh()` reacts to
  `Alchemy.recipe_learned`/`recipe_unlearned` so a freshly discovered recipe appears at
  the Alembic the same frame it's found.
- **Recipe-discovery puzzle [BUILT]**: the Potion Book's "Discover: X" button opens a
  drag-and-drop puzzle (`scripts/ui/attempt_puzzle_panel.gd`, `AttemptPuzzlePanel`),
  laid out in three columns: a pinned note (top-left, tilted `PanelContainer`) showing
  the potion's objectives with a live ✓ against each one already satisfied by the
  current field; the potion field (middle) — one `PotionRoleSlot` per
  Base/Binder/Catalyst (`scenes/ui/components/PotionRoleSlot.tscn`), Base visually
  marked required via a gold accent border; and the player's ingredients (right) — one
  draggable `IngredientDragChip` (`scenes/ui/components/IngredientDragChip.tscn`) per
  owned ingredient, grouped into Base/Binder/Catalyst sections, showing weight and
  non-zero characteristics. Both components are standard Godot Control drag-and-drop
  (`_get_drag_data`/`_can_drop_data`/`_drop_data`); a slot only accepts a chip whose
  ingredient's `role` matches. Since each of the 3 slots holds at most one
  ingredient, "2 or 3 ingredients, always including a Base" falls out of the layout
  itself — `AttemptPuzzlePanel._selection_is_valid()` requires the Base slot filled
  plus at least one of Binder/Catalyst, and disables Submit otherwise (a deliberate
  narrowing: any *base-containing* 2-3 ingredient combination can be found this way,
  not literally any arbitrary set of ingredients). Submitting consumes exactly the
  filled slots' ingredients (win or lose — same "ingredients are spent on the attempt"
  feel as a real brew) and calls `Alchemy.attempt_discovery(potion, ingredient_ids)`,
  which checks the selection against `PotionDef.puzzle_constraint_types` (parallel
  arrays: `_types`/`_targets`/`_min`/`_max`, same convention as a recipe's
  `ingredient_ids`/`ingredient_quantities`) — `characteristic_range` (a summed
  characteristic must land in `[min, max]`), `total_weight_range`,
  `ingredient_count_range`, and `role_lightest`/`role_heaviest` (every ingredient of
  the target role must be strictly lighter/heavier than every ingredient of every
  other role present — requires the role, and at least one other role, to actually be
  used, not vacuously true). `Alchemy.check_constraints()` returns a per-constraint
  pass/fail array, reused both by `attempt_discovery()` (all must pass) and by the
  note's live ✓ markers, so the UI's feedback and the actual judging logic can't drift
  apart. `data/potions/grave_ward_tonic.tres` is the sample proving the pipeline:
  Necromantic 4–6, Dream ≤ 0, catalyst must be the lightest component — solved by
  Grave Dust as Base (weight 2.0, necromantic +3) + Ghostcap Mushroom as Catalyst
  (weight 0.5, necromantic +2, dream -1). `data/potions/minor_healing_draught.tres`
  and `clarity_tonic.tres` carry deliberately loose criteria (just a weight/count
  range, or a light characteristic nudge) so many different base+catalyst/binder
  combinations satisfy them — demonstrating that a potion's *known* starter recipe
  doesn't stop the player from finding a second, different one later.
- On a successful attempt, `attempt_discovery()` builds a deterministic id from the
  potion and the exact ingredient multiset used (sorted `ingredient_id`×`count`
  pairs, e.g. `minor_healing_draught__ember_dustx1_rift_glassx1`) — this doubles as
  the dedup key, so re-finding the exact same combination resolves to the
  already-learned `RecipeDef` (`already_known: true` in the returned result) instead
  of creating a duplicate. A genuinely new combination gets a freshly synthesized
  `RecipeDef` (`display_name` auto-built from the ingredients' names, e.g. "Ember Dust
  + Rift Glass"), registered into `Alchemy`'s learned set and emitted via
  `recipe_learned`. A failed attempt only logs a message via `puzzle_attempted` — no
  separate "wasted" penalty beyond the consumed ingredients, and nothing is learned.
  Because discovered `RecipeDef`s exist only inside `Alchemy` (never as `.tres`
  content), `Alchemy.get_save_data()` serializes each learned recipe's full fields
  rather than just an id, and `SaveManager._SAVE_ORDER` restores `Alchemy` before
  `Brewing` so an in-progress brew job (which resolves its `RecipeDef` via
  `Alchemy.get_learned_recipe()`) has something to resolve against.
- The Grimoire (`GameMenu`'s recipe tab, system 13/journal) mirrors this: it lists one
  group per `ContentRegistry.potions` entry (not per recipe), showing every learned
  recipe for that potion as its own row beneath the potion's name, or a single "???
  (unknown)" placeholder row if none have been discovered yet.
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
  - potion_count                   # 1, or 2 on a critical success
  - status: Brewing | Ready | Collected
```

- Jobs are resolved by absolute timestamp comparison against the clock, and must be
  resolvable in batch via `TimeSkip` — most brewing completes while the player is in
  class or asleep, so no system should assume the brew scene is actively open when a
  job finishes.
- `rolled_potency`/`rolled_ease` are raw numeric values shown directly to the player,
  not bucketed into tiers — they feed shop pricing/sale-chance and, later, buyer- and
  love-interest-specific preferences.
- Starting a brew rolls **one** visible 2d10 check (`Rng.roll_2d10`, system 16) — a
  BG3-style dice check surfaced in the message wall (system 16), `DICE_DC := 11.0`, modifier = the averaged
  `potency_modifier`/`ease_modifier` (station + `Skills.get_bonus()`). The roll's
  total sets a shared quality scalar `t`, lerped onto the potion's
  `potency_range`/`ease_range` (`PotionDef`, system 3 — not per-recipe data), and each stat then
  gets its own small independent quiet `+/- STAT_VARIANCE` wobble (`Rng.range_f`) so
  potency and ease aren't identical despite sharing one quality roll.
- The roll's *natural* die faces (not the modified total) decide the outcome, not the
  pass/fail-vs-DC result: a natural 1 on either die is a critical failure and botches
  the brew — it fails immediately rather than occupying the station for the brew
  time (ingredients are still consumed, since they're spent before the roll), yields
  no potion, and costs Resolve instead (system 8) — replacing the old flat 10% botch
  chance. No `BrewJob` is ever created for a botched roll, so the station is free
  again the instant `start_brew()` returns. A natural 10 on either die is a critical
  success and sets `potion_count = 2` (no stacking if both dice show 10). A natural
  1+10 pair is an "inflection point" — shown distinctly in the message wall, but has
  no mechanics attached yet.
- Each `BrewStationInteractable` shows a bottom-to-top progress bar above it while
  `Brewing`, swapping to a "Ready!" popup once the job's status flips to `Ready`
  (`RoomBuilder._sync_station_indicator()`, driven off `Brewing`'s signals plus
  `Clock.minute_tick` so it also restores correctly on a loaded save). A station with
  a job running — `Brewing` or `Ready` — can't be interacted with to open the brew
  menu; interacting with a `Ready` station auto-collects it instead
  (`BrewStationInteractable.interact()`), failing quietly (job stays put) if
  `Inventory.has_room_for_potions()` says there's no room. `Inventory.MAX_POTIONS`
  (20) is the first potion-capacity limit in the prototype; the brew menu has no
  standalone "Collect" button since the menu only opens when a station has no job
  at all.
- **The brew menu** (`BrewMenu`, `scripts/ui/brew_menu.gd`) is the `MenuScene`
  content the Alembic opens. Master-detail: a scrollable list of *learned*
  recipes on the left, a detail/confirm card on the right. The player's **pantry**
  (owned ingredients as icon×N chips) is *not* nested inside this window — it's a
  separate `PantryWindow` (`scripts/ui/pantry_window.gd`) that GameHud parks just
  to the left of the brew window (`MenuScene.get_window_rect()` locates it),
  shows/refreshes on open, and fades out on any menu close — keeping the brew
  window from stacking yet another frame. Recipes that share an
  `output_potion_id` are **grouped** under one potion heading (`_potion_name()`,
  reading `ContentRegistry.get_potion(id).display_name`/`.icon`), each shown as
  a "method" variant (`_variant_label()` — simply the recipe's `display_name`,
  since that field is the method label, e.g. "Ember Dust + Rift Glass", not the
  potion's name — see system 3). A "Ready to brew only" toggle filters the list
  to recipes the player has ingredients for (`Inventory.has_ingredients_for`).
  The detail card shows the required ingredients as icon×N chips tinted
  green/red by whether the player has enough, plus the potion's potency/ease
  ranges and brew time (`ContentRegistry.get_potion(recipe.output_potion_id)`),
  and a Brew button (disabled when short).
  `IngredientChip`/`BrewRecipeRow` (`scripts/ui/components/`) are the repeated
  cells, following the same populate()-driven, icon-with-fallback-dot component
  convention as `ItemSlot`. BrewMenu only *reads* game state and emits
  `brew_confirmed(recipe)`; `hud.gd._on_brew_confirmed()` runs `Brewing.start_brew`
  and closes the menu on an accepted attempt.
- **Keyboard navigation** (`BrewMenu._input()`) works in two modes, so the whole
  menu is playable without the mouse:
  - *Browsing* (default): **W/S** move the highlighted selection through the flat
    list of visible recipes (`_visible_recipes`, scrolled into view), **E** focuses
    the selection, and a bare **1/2/3** brews whatever recipe is pinned to that
    quick slot. **Esc** is deliberately *not* consumed here — it falls through to
    main.gd, which closes the menu.
  - *Focused* (after E): a cursor sits on the detail card's action buttons —
    **W/S** (or arrows / A/D) move it across **Brew** and the three quick-slot
    buttons (`_action_index`/`_action_buttons`, skipping a disabled Brew when the
    recipe isn't brewable), and **E** activates the button under it. **1/2/3** still
    directly pin the focused recipe to that slot regardless of cursor, and **Esc**
    steps back to browsing (consumed, so the menu stays open; a second Esc, now
    browsing, closes it). The cursor marks its button by forcing the theme's
    *hover* look (`_highlight_action_button()`, routed through
    `MenuKeyNav.set_highlight()` — see system 1 — which overrides the
    normal/pressed styleboxes + font, since the focus outline read as too
    subtle); a magic-tinted ring
    around the detail card (`_detail_focus_ring`) plus a mode line and footer tip
    signal the focused state.
  The mouse still works alongside all of this (click a row to select, the Brew
  button to brew, the slot buttons to pin). Every key except browsing-Esc is marked
  handled so it never falls through to main.gd's Clock-speed hotkeys (system 1) —
  safe because the world is paused whenever a menu is open.
- **Quick slots** (1/2/3) are session-only (held on the `BrewMenu` instance, not
  saved) and self-clear if their recipe becomes unlearned (`_validate_quick_slots`).

---

## 5. Shop Stock System **[BUILD]**

Stardew-box model: dump potions from inventory into a stock pool; they sell off
gradually during open hours rather than instantly overnight.

```
ShopStock
  - capacity: int                 # upgradeable, starts at 8 (one 8-wide row)
  - slots: [StockedPotion]        # (potion_id, potency, ease, price)
  - reputation: int               # stub — initialized, not yet read by any logic
  - coffers: int                  # accumulated sale proceeds, uncollected
```

- Stocking interaction is low-friction: one action dumps all sellable potions from
  inventory into stock, up to capacity.
- While the current clock time falls within the shop's Ambient open-hours window
  (system 1), stocked potions roll sell-chance on a fixed simulated interval (e.g.
  every N in-game minutes), weighted by price, potency/ease (per system 3/4), and
  shop reputation (reputation stat: stub for now, default flat weight). This roll
  goes through `Rng.chance()` (system 16) — quiet/background, no message-wall row,
  same behavior/values as before.
- On sale: remove one unit, add the price to `coffers` (not directly to
  Inventory.materials) and log the sale for a "while you were away" summary shown
  to the player at the next check-in.
- Materials sit in `coffers` until the player physically visits the shopfront
  (the STOCK_BOX interactable) and collects them into Inventory.materials —
  stocking and collecting are one combined action at that interactable.
- Capacity is the primary upgrade lever (no manual shelf placement in prototype).
  Starts at 8 (an 8x1 grid in the Shop tab); `expanded_stock_shelf` adds 8 more,
  bringing it to 16 (8x2).

---

## 6. Skills System **[BUILD]**

```
Skill
  - id                             # alchemy, herbalism, summoning, ...
  - xp
  - level                          # xp / xp_per_level, no cap
  - xp_per_level                   # 100 for every skill today
  - effects: [(level_threshold, effect_target, effect_amount)]
```

- Skills system is a passive listener: other systems fire XP events (brew completed,
  harvest completed, class attended, exam passed) and the skill system applies xp/levels.
- The full 11-skill roster (`data/skills/*.tres`, registered via `Skills.SKILL_PATHS`):
  1. **Alchemy** — better-quality potions, faster. `station_potency`, `station_ease`, `station_speed`.
  2. **Herbalism** — better-quality plants, easier harvest/care, learns natural ingredients faster.
     `grow_yield`, `grow_speed`, `learn_speed_natural`.
  3. **Summoning** — wider range/control of extraplanar phenomena, learns extraplanar ingredients
     faster. The rift/collection loop itself is built (system 22), but `summon_range`,
     `summon_control`, and `learn_speed_extraplanar` all tune the choosing-a-bundle minigame, which is
     still a random stand-in — **[STUB — no minigame to tune yet]**.
  4. **Arcane History** — easier ley-line interactions returning more spectral ingredients, learns
     spectral ingredients faster. `leyline_ease`, `leyline_yield`, `learn_speed_spectral` **[STUB]**.
  5. **Draconology** — safer in draconic areas, more ingredients from draconic nodes, learns draconic
     ingredients faster. `draconic_safety` (Dragon's Stash roll modifier) and `draconic_yield`
     (ingredients granted per stash) are both read by the Draconology / Dragon's Stash System
     (system 19); `learn_speed_draconic` **[STUB]**.
  6. **Demonology** — better demon barter with less drawback, learns demonic ingredients faster.
     `demon_yield` (ingredients granted per writ) is read by the Demonology / Contract System
     (system 17) the same as every other skill effect, via `Skills.get_bonus()`. Writ speed and the
     submission roll modifier are also Demonology-driven but *not* through the `Skills` bonus ledger —
     `Demonology._demon_barter()` computes them directly and continuously from
     `Skills.level("demonology")` instead of unlocking at fixed level thresholds like every other
     skill effect (see system 17). `learn_speed_demonic` **[STUB]**.
  7. **Transmutation** — better dismantling of objects for materials, learns artificial ingredients
     faster. `transmute_ease`, `transmute_yield`, `learn_speed_artificial` **[STUB]**.
  8. **Charm** — better social-check success, unlocks new dialog options. `social_check_bonus`
     **[STUB — no social-check/dialog system yet]**.
  9. **Focus** — better class performance. `class_performance` — the one non-Alchemy/Herbalism skill
     that's actually wired: `Academy.attend_class()` reads `Skills.get_bonus("class_performance")` as
     the roll modifier and awards Focus XP on attendance.
  10. **Creativity** — better art-creation success (second material source or shop-status boost).
      `art_success` **[STUB — no art system yet]**.
  11. **Insight** — better shop sales and customer retention. `shop_sales`, `customer_retention`
      **[STUB — Shop doesn't read these yet]**.
- Skills whose category-linked ingredient-learning effect isn't consumed anywhere yet (Summoning,
  Arcane History, Draconology, Transmutation, and Demonology's own `learn_speed_demonic`) still exist
  fully as data — only the mechanic that would read `learn_speed_*` is unbuilt, same scope choice as
  the old Summoning stub.
- Ingredient category ↔ skill mapping (`Skills.CATEGORY_SKILL_IDS`, `IngredientDef.Category`):
  NATURAL→Herbalism, ARTIFICIAL→Transmutation, SPECTRAL→Arcane History, DEMONIC→Demonology,
  DRACONIC→Draconology, EXTRAPLANAR→Summoning.
- **Starting skill points**, allocated on `CharacterCreator`'s skills step and applied by
  `SaveManager.create_new_game()` via `Skills.grant_starting_points()`:
  - `Skills.STARTING_ALLOCATION_POINTS` (5) points spread freely across
    `Skills.STARTING_ALLOCATABLE_SKILL_IDS` (Alchemy, Charm, Focus, Creativity, Insight), capped at
    `Skills.STARTING_ALLOCATION_MAX_PER_SKILL` (3) per skill.
  - `Skills.STARTING_ORIGIN_SKILL_POINTS` (2) points, fixed and non-editable, in whichever ingredient
    skill the player's shop-origin choice favors via `Skills.skill_id_for_category()` — e.g. Raven
    Canopy (`ingredient_category = DEMONIC`) grants +2 Demonology.
  - A "point" is a full starting level: `grant_starting_points()` calls `add_xp(skill_id, points *
    xp_per_level)`, so it replays through the normal leveling/effect path rather than setting level
    directly.
- Prototype needs Alchemy + Herbalism + Focus fully wired; the other 8 skills exist as complete data
  (levelable, grants starting points, `get_bonus()` returns their totals) with no consuming mechanic
  yet.

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
- Plots live in the Garden map, not the Shop (see system 12) — there is no
  Materials-purchasable way to add more in the prototype; the plot count is
  fixed at `STARTING_PLOT_COUNT`.

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
- **HUD vial grows with `max_resolve`.** `ResolveVial` (top-left HUD card) scales its
  vial art continuously as `max_resolve` rises above `Resolve.BASE_MAX_RESOLVE` (100),
  via a sqrt curve clamped at 2x size — deliberately curve-driven off `max_resolve`
  itself rather than off any specific upgrade/skill, since prototype scope doesn't yet
  define what raises the cap and multiple sources may stack.

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
- **Effort level.** `ClassDoorInteractable` opens a `MenuScene` panel (`hud.class_panel`)
  offering three `Academy.Effort` choices — Coast (`LOW`), Regular Effort (`NORMAL`),
  Burn It / 110% (`HIGH`) — before `Academy.attend_class(effort)` fires. Every level
  costs Resolve (`Academy.EFFORT_RESOLVE_COST`, spent via `Resolve.spend()` same as a
  Brewing botch): very little at Coast, a real bite at Burn It. Effort does not change
  the base attendance/class-performance flow above — it only scales the reward roll
  below, via `Academy.EFFORT_REWARD_MULTIPLIER` (magnitude) and
  `Academy.EFFORT_REWARD_ROLLS` (Burn It gets a second independent roll rather than a
  guaranteed double reward, so it stays a gamble rather than strictly-better-and-
  predictable).
- **Class rewards.** Each reward roll (`Academy._roll_class_reward()`) is a visible
  2d10 Focus check (`Rng.roll_2d10`, modifier `Skills.level("focus")`, flat
  `REWARD_ROLL_DC := 11.0`) that scales the reward's magnitude on top of effort — a
  critical success multiplies it further (`REWARD_CRIT_MULTIPLIER`), a failed roll
  shrinks it (`REWARD_FAIL_MULTIPLIER`) — then a reward type is chosen uniformly from
  `Academy.REWARD_TYPES`: a new ingredient, a Materials grant, a new potion recipe
  (`Alchemy.learn_recipe`), a new Planar Rift summoning sequence
  (`Summoning.learn_bundle`), a relationship bump with a random `Characters` entry
  (`LoveInterests.add_affection`), XP in a random skill (`Skills.add_xp`), or shop
  reputation (`Shop.add_reputation`, new — reputation was previously write-only, seeded
  to 0 and never incremented). A type whose pool is momentarily empty (e.g. every
  recipe already learned) falls back to a Materials grant rather than a dead roll. No
  `AcademyRewardDef` resource introduced — kept as flat consts on `Academy`, matching
  the existing `ATTENDANCE_BONUS`/`PASSING_SCORE` style.
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
- A visible 2d10 check also runs on every class attendance (`Rng.roll_2d10`, system
  16; modifier `Skills.get_bonus("class_performance")`, flat `CLASS_PERFORMANCE_DC :=
  11.0`), on top of — not gating — the base attendance bonus: passing grants an
  additional `CLASS_PERFORMANCE_BONUS := 10.0` to `running_score`. Shown via the dice
  popup. No `AcademyClassDef` resource introduced for this — kept as flat consts on
  `Academy`, matching the existing `ATTENDANCE_BONUS`/`PASSING_SCORE` style. Only
  `roll.passed` is consulted; the roll's crit fields (system 16) aren't used here yet.
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
  stock box, brew stations, grow plots in the Garden, a couple of NPC/scene
  triggers outside), not an open world.
- Anything outside this small area (classes, most love-interest content) resolves
  as a VN scene rather than being walked to — see system #13.
- No pathfinding/AI needs beyond simple player movement + interaction prompts for
  the prototype.
- **Rooms**: the interior is split into separate hand-authored room scenes
  (currently `scenes/rooms/Shop.tscn`, `Bedroom.tscn`, `DragonsGround.tscn`,
  `ScrapYard.tscn`, `Garden.tscn`, `CommonGarden.tscn`, `Altar.tscn`,
  `LeyLineOutcropping.tscn`, `Orrery.tscn`, `RavenCanopy.tscn`,
  `LeyLineFissure.tscn`, `ConfluenceZone.tscn`, `FormerReliquary.tscn`, and
  `Underbelly.tscn`), each
  a `Room`-scripted
  (`scripts/room.gd`) `Node2D` with `Floor`/`Walls` `TileMapLayer`s, a
  `SpawnPoint` `Marker2D`, and an `Interactables` container of pre-placed
  interactable instances configured entirely via the Inspector.
  `RoomBuilder.build_rooms()` (`scripts/room_builder.gd`) loads all fourteen
  scenes up front, reads each room's markers, and wires every pre-placed
  interactable's signals; grow-plot interactables, Dragons' Ground stashes,
  and Scrap Yard heaps are the exceptions and stay code-instanced (each
  parented under its own spawner node, or — for grow plots — the Garden's
  `Plots` container, rather than a room's `Interactables` container) since
  they come from runtime `Herbalism`/`Draconology`/`Transmutation` data
  rather than being hand-placed — see system 19 for how the Dragons' Ground
  spawns and places its stashes, and system 18's Scrap Heap subsection for
  the Scrap Yard's identically-shaped `ScrapHeapSpawnerNode`. Only one room
  is active at a time — `switch_room()` toggles `visible`/`process_mode` on
  the room scenes (inactive rooms are `PROCESS_MODE_DISABLED`, which also
  stops their interactable areas from firing enter/exit signals while
  hidden) and repositions the single shared player + camera. The player and
  camera are scene-level nodes, not per-room, so they persist across a
  switch. Wall tiles carry real collision (physics layer 2, named "Walls" in
  `project.godot`'s `[layer_names]`; `Player`'s `collision_mask` includes
  it) — floor tiles don't; `Bedroom`/`DragonsGround`/`ScrapYard`/`Garden`/
  `Altar`/`LeyLineOutcropping`/`Orrery` currently leave `Floor`/`Walls` empty
  placeholders with no tileset assigned yet, same as `Shop.tscn` did before
  its interior was painted.
- **Interactables**: one base scene/script per behavior rather than a single
  generic node configured by a type enum — `InteractableBase`
  (`scripts/interactable_base.gd`/`scenes/interactables/InteractableBase.tscn`)
  owns the shared Area2D proximity signals and visual/label chrome, and each
  concrete type (`BrewStationInteractable`, `StockBoxInteractable`,
  `GrowPlotInteractable`, `SupplyShelfInteractable`, `BedInteractable`,
  `ClassDoorInteractable`, `StairsInteractable`) is its own scene inheriting
  that base scene, pairing a `class_name` script that overrides
  `interact(main: MainScene)` with the actual action for that type (calling
  Brewing/Shop/Herbalism/Economy/Clock/Academy directly, or reaching into
  `main.hud`/`main.room_builder` for the systems that need HUD or room-level
  state). `MainScene._on_interact_pressed()` just calls
  `_current_interactable.interact(self)` — dispatch is polymorphism, not a
  type match. `BrewStationInteractable` alone adds the brew progress
  bar/ready-popup child nodes and their `set_brew_progress()`/
  `show_brew_ready()`/`clear_brew_indicator()` methods, since no other type
  needs an in-world progress indicator.
- **Room transitions** are just another interactable type
  (`StairsInteractable`), configured with a `target_room` id and a
  `spawn_position` in the destination room, the same per-instance-config
  pattern as every other interactable. The Bed lives in the Bedroom; the
  Shop's brew station/stock box/supply shelf/class door stay in the Shop;
  the grow plots live in the Garden (its only other content is the stairs
  back); the Dragons' Ground has nothing but its stashes and a stairs back;
  the Scrap Yard is the same shape as the Dragons' Ground but with a
  `ScrapHeapSpawner` in place of the `DragonSpawner`/`DragonStashSpawner`
  pair; the Contract Book lives in the Altar, the Ley Line Node in the Ley
  Line Outcropping, and the Planar Rift in the Orrery — each of these three
  is the same "single hand-placed fixture plus a stairs back" shape as the
  Garden — each pair of rooms is connected by a stairs interactable in each
  room pointing at the other. One quirk of `_load_room()`'s spawn-position
  resolution: it only auto-fills a stairs' `spawn_position` from the target
  room's `SpawnPoint` if the target room was *already* loaded when the
  stairs gets wired, so a stairs pointing at a room that loads later
  (`Shop`'s stairs to `Bedroom`/`DragonsGround`/`ScrapYard`/`Altar`/
  `LeyLineOutcropping`/`Orrery`, all of which load after `Shop`) needs its
  `spawn_position` hand-set in the `.tscn` to match that room's `SpawnPoint`
  instead of relying on auto-resolution.
- **Shop Back.** One extra door in the Shop (`StairsToShopBack`) whose
  `target_room` is resolved at runtime from `PlayerProfile.shop_origin`
  instead of being fixed in the `.tscn` like every other stairs —
  `RoomBuilder._wire_shop_back_door()` runs once, after all rooms are loaded,
  and looks the origin id up in `SHOP_BACK_ROOM_BY_ORIGIN` to set that one
  node's `target_room`/`spawn_position` (falling back to the Garden if
  `shop_origin` is empty/unrecognized, e.g. a scaffolded test run that
  skipped character creation). This is on top of, not instead of, the
  always-present stairs above — every ingredient-category room stays
  reachable from the Shop regardless of origin; Shop Back just gives the
  chosen category's room a second, closer door. Five of the six
  `ShopLocationDef` entries get their own dedicated room, distinct from the
  always-reachable one covering the same system so the two don't collide on
  a shared interactable/spawner id: `raven_canopy` → `RavenCanopy.tscn`
  (a second `ContractBookInteractable`, `target_id = "contract_book_2"`),
  `ley_line_fissure` → `LeyLineFissure.tscn` (`ley_line_node_2`),
  `confluence_zone` → `ConfluenceZone.tscn` (`planar_rift_2`),
  `former_reliquary` → `FormerReliquary.tscn` (a `ScrapHeapSpawner`,
  `spawner_id = "former_reliquary_heaps"`, same shape as the Scrap Yard's),
  and `underbelly` → `Underbelly.tscn` (a `DragonStashSpawner`,
  `spawner_id = "underbelly_stashes"`, plus a `DragonSpawner` capped to a
  `wyrmling`/`drake`-only roster and `count_min`/`count_max` of 1–2 — "a few
  low-level dragons" rather than the Dragons' Ground's full roster/count).
  The sixth, `magic_garden`, is the same "own dedicated room" shape as the
  other five, just without a duplicated interactable — grow plots are one
  global `Herbalism`-driven pool, so `Garden.tscn` (`GARDEN_ROOM_ID`) is
  magic_garden's exclusive Shop Back room and a second scene,
  `CommonGarden.tscn` (`COMMON_GARDEN_ROOM_ID`), is the always-reachable
  counterpart every other origin uses instead of `Garden.tscn` — Shop's
  `StairsToCommonGarden` (the always-present door, alongside `StairsUp`/
  `StairsToDragonsGround`/`StairsToScrapYard`/`StairsToAltar`/etc.) points at
  `CommonGarden`, not `Garden`. `RoomBuilder._active_garden_room_id()` picks
  which of the two rooms' `Plots` container the code-instanced grow-plot
  Interactables actually land in, based on the same `shop_origin ==
  "magic_garden"` check `_wire_shop_back_door()` uses — so a magic_garden
  playthrough finds its plots behind the Shop and every other playthrough
  finds them in the always-reachable `CommonGarden` instead. Only one of the
  two rooms ever holds live plots in a given playthrough; the other's
  `Plots` container just stays empty.

---

## 13. VN / Relationship System **[Engine BUILT — content authoring next]**

A custom-built dialogue engine, not a third-party addon — the explicit intent is to
frontload real engine investment now so that later work is writing/art, not more
engineering. The full pipeline (expression language → script compiler →
runtime → full-screen presentation → condition-based triggering) is built and
verified end-to-end against one placeholder scene/trigger pair
(`kaelith_greeting`). What's left for the first pass — one love interest, a
handful of scenes — is content: actual writing, and whatever new
stage-direction/grammar needs fall out of authoring real scenes rather than
the engine itself.

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
  (`get_affection`/`add_affection`/`affection_changed` signal). Deliberately has
  no static character data of its own and no concept of *which* ids are
  "love interests" — it's a bare affection ledger keyed by whatever string id a
  script passes to `add_affection`, fully decoupled from `CharacterDef` below.
- `CharacterDef` (`scripts/data/character_def.gd`, a `Resource`) — static
  *display* data (`id`, `display_name`, `placeholder_color`) for anyone who can
  appear in a VN scene, romanceable or not (a shopkeeper and a love interest are
  the same kind of thing to the dialogue engine). No romance-specific fields —
  whether a character accumulates affection is entirely up to whether a script
  happens to call `add_affection()` for their id, not something declared here.
  Registered by id via the `Characters` autoload (`scripts/autoload/characters.gd`,
  same explicit-path-list-at-`_ready()` pattern as `SceneDirector`'s triggers);
  `DialogueBox` looks up `Characters.get_character(name)` when spawning a
  character sprite and uses its `placeholder_color` if registered, falling back
  to a cycled placeholder palette for anyone not yet authored — so an unnamed
  one-off extra doesn't need a `CharacterDef` to appear in a scene, but a
  recurring character (love interest or otherwise) gets a *consistent* color
  across every scene rather than one dependent on entry order within a single
  scene. The five love interests are registered (`data/characters/callie.tres`,
  `larissa.tres`, `haerin.tres`, `daniela.tres`, `lyra.tres`; ids match those
  used by `add_affection()`) — see `docs/design/characters.md` for who they are.
  The old `kaelith_greeting` sample scene (`data/vn_scenes/kaelith_greeting.vnscript`)
  still uses an unregistered "Kaelith" placeholder speaker and is unaffected,
  since unregistered speakers just fall back to the cycled placeholder palette.

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
`JUMP`, `JUMP_IF_FALSE`, `STAGE_BACKGROUND`, `STAGE_ENTER`, `STAGE_EXIT`,
`STAGE_MOVE`, `STAGE_EXPRESSION`, `CALL`, `END`) — same node-as-Dictionary convention as the
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
not fixed left/center/right slots. `background <name>` was added once
`DialogueBox` needed something to render behind characters — it compiles to a
`STAGE_BACKGROUND` instruction carrying just a name string; `DialogueBox` maps
that name to a placeholder color (deterministic hash-to-hue), the same
"no real assets yet" spirit as the character rectangles:

```
scene kaelith_greeting
background bedroom
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

### Runtime and presentation **[BUILT]**

- `DialogueRunner` (`scripts/vn/dialogue_runner.gd`) — **built.** Loads a
  `VNScriptCompiler.compile()` result and steps through it as a plain
  instruction pointer, emitting `line_shown(speaker, text)`,
  `choice_requested(options)`, `stage_changed(instruction)`, and
  `scene_ended()`, and waiting for the presentation layer to call back in
  (`start()`, `advance()`, `choose(index)`). Stage directions and action calls
  (`CALL`, `JUMP`, `JUMP_IF_FALSE`) execute immediately and fall through to the
  next instruction within the same call — only `SHOW_LINE`/`SHOW_CHOICE`/`END`
  actually pause execution — so a scene with several back-to-back stage
  directions or `if`-guarded actions plays out in one `advance()`/`choose()`
  call, exactly like the compiler's flat-instruction-list design intended.
  Verified against the `kaelith_greeting` sample end-to-end via a throwaway
  test scene: both choice branches, the `if has_item(...)` true/false paths,
  and the resulting `LoveInterests`/`Inventory` side effects (affection +5,
  `clarity_tonic` consumed) all confirmed correct.
- `DialogueBox` (`scripts/vn/dialogue_box.gd`) — **built.** A code-built
  `CanvasLayer` (not `MenuScene`-based — VN scenes are full-screen, not a
  chrome-and-content panel), owning its own `DialogueRunner` internally
  (`open(compiled_scene)` constructs one, connects all four signals, calls
  `start()`). Background and character sprites are placeholder colored
  rectangles (deterministic hash-to-hue for backgrounds by name, a small
  fixed palette cycled per character), with a name+expression label instead
  of real art; the currently-speaking character is full-opacity, everyone
  else present is dimmed. Dialogue text reveals with a typewriter effect
  (`Timer`-driven, seconds-per-character scaled by `Settings.text_speed_multiplier`
  — the Settings screens' Text Speed dropdown, `scripts/autoload/settings.gd`;
  "Instant" skips the timer and reveals the whole line immediately); clicking
  anywhere on the background while a line is still revealing completes it instantly
  instead of advancing, and only a second click calls `DialogueRunner.advance()`
  — the click handler lives on the full-screen background `ColorRect`, with
  the character layer and each character rectangle set to
  `MOUSE_FILTER_IGNORE` so clicks fall through to it, while choice buttons
  (default `STOP` filter) still take priority when clicked directly. Choice
  options render as dynamically-built `Button`s; pressing one calls
  `DialogueRunner.choose(index)`. `scene_ended()` closes the box and
  un-pauses `Clock`, mirroring how `MenuScene` pauses/unpauses on open/close.
  Verified via a throwaway test scene simulating real clicks and button
  presses through the `kaelith_greeting` sample, including the `background`
  stage direction, both choice branches, and the resulting affection/inventory
  side effects.

### Scene triggering **[BUILT]**

No fixed taxonomy of trigger *types* — a scene can be triggered by anything at
any time, so `SceneTriggerDef` (`scripts/data/scene_trigger_def.gd`, a `Resource`
like `RecipeDef`/`SkillDef`) just carries a condition expression (the same
expression language as `if` statements) rather than an enum of trigger kinds:

```
SceneTriggerDef
  - id
  - script_path
  - condition: String        # expression source, parsed once at registration
  - priority: Priority        # LOW | NORMAL | HIGH | MAX — buckets, not raw numbers
  - repeatable: bool
  - show_from_menu: bool      # can this cut in through an open menu?
```

- `SceneDirector` (`scripts/autoload/scene_director.gd`) registers every
  `SceneTriggerDef` listed in its `TRIGGER_PATHS` const (same "explicit path
  list, not directory scanning" convention `main.gd` uses for recipes/ingredients).
  Registration parses the condition *and* compiles the script up front
  (`VNScriptCompiler.compile()` on the file's contents, read via
  `FileAccess.get_file_as_string()`), so `recheck()` never touches the
  filesystem or a parser mid-game — it only walks the small pre-built
  `{trigger, condition_ast, compiled}` list. `SceneDirector` owns a single
  `DialogueBox` child (created once in `_ready()`) that every fired scene
  plays through.
- `recheck()` runs on every `Clock.minute_tick` (connected in `_ready()`), plus
  two explicit call sites for anything that should feel instant rather than
  waiting up to a minute: `MenuScene.close()` (so a scene can cut in the moment
  a menu closes) and `main.gd`'s `_switch_room()` (so room-entry conditions
  fire immediately on walking through a door/stairs). Deliberately just these
  two for now — a sale landing or other finer-grained events can get their own
  call site later if content ends up needing it, but menu-close and room-change
  cover what's needed today. A satisfied
  trigger fires the highest `priority` bucket first, then earliest-registered
  within that bucket (a strict-greater-than comparison while iterating in
  registration order naturally keeps the earliest of any tie).
- **No explicit queue.** A trigger that's satisfied but blocked (player mid-menu,
  and `show_from_menu` is false) simply doesn't fire yet; the very next
  `recheck()` — which happens constantly regardless — re-runs the same
  priority/registration-order selection fresh. This also means a trigger whose
  condition stops holding true while "queued" is naturally dropped rather than
  firing stale.
- An already-*playing* scene always blocks new scenes outright, regardless of
  `show_from_menu` — that flag only lets a scene cut through a menu (e.g. calling
  a love interest from a phone menu item), not through another scene in progress.
  `SceneDirector` tracks this itself (`_is_scene_playing`) rather than asking
  `DialogueBox`, since `Clock.is_paused` alone can't distinguish "a menu is open"
  from "a scene is playing" (both set it) — `recheck()` checks its own playing
  flag first (blocks everything, no exceptions) and only then falls back to
  `Clock.is_paused` for the `show_from_menu` gate.
- One-shot tracking reuses the `Story` flag store exactly as spec'd:
  `has_flag("scene_played_" + scene_id)`, keyed by the *compiled* scene id
  (not the trigger id), set right before firing a non-repeatable trigger.
- Verified end-to-end via a throwaway test scene against a sample pair
  (`data/scene_triggers/kaelith_greeting_trigger.tres` →
  `data/vn_scenes/kaelith_greeting.vnscript`, condition `"true"`,
  non-repeatable): confirmed it auto-fires on the very first `Clock.minute_tick`
  with no code driving it, plays through to `scene_ended()`, sets the played
  flag, does *not* refire afterward, stays blocked while `Clock.is_paused` is
  true (simulating an open menu), and fires immediately once unblocked. That
  sample's condition being unconditionally `"true"` was only ever meant to
  prove the pipeline in isolation — it is **not** in `TRIGGER_PATHS` (which is
  empty), since registering it live meant it actually fired in a real
  playthrough, ahead of the character creator. Real triggers need an actual
  gating condition before they belong in `TRIGGER_PATHS`.
  No nested scenes.
- Non-repeatable scenes mark themselves played via the same `Story` flag store
  (`has_flag("scene_played_" + scene_id)`) rather than separate "seen" bookkeeping.

---

## 14. Save/Load System [BUILD]

Persists a full playthrough to disk as JSON, with forward-compatible versioning, checksum-validated
corruption detection, and automatic backups. Not an anti-cheat measure — save files are plain,
human-readable JSON, since editing them isn't a concern the prototype worries about.

- **Games vs. slots.** A *game* is one playthrough, identified by the game-start choices — character
  name, pronouns, House, and shop origin (e.g. "magic_garden" vs. "ley_line_fissure") — via the
  `PlayerProfile` autoload (`character_name: String`, `pronouns: String`, `house_id: String`,
  `shop_origin: String`, `player_color_hex: String`). A game can hold any number of numbered *save
  slots*, each a full snapshot at a point in time. This mirrors a Stardew-Valley-style per-farm save
  list, but supports true multi-save-per-playthrough rather than one save per farm. `shop_origin` and
  `house_id` are now real `ShopLocationDef`/`HouseDef` ids (loaded via `ContentRegistry.get_shop_location()`
  / `get_house()`) — `ShopLocationDef`'s favored `IngredientDef.Category` per location is now consumed:
  it drives the +2 shop-origin skill bonus (system 6), and it drives which room the Shop Back door
  leads to (system 12's Shop Back subsection). `scripts/character_creator.gd` is the
  character-creation UI, a 3-step wizard (Back/Next/Confirm nav, `Next` disabled until the current
  step is valid): (1) name, pronouns, House (a row of placeholder tiles, one per
  `ContentRegistry.houses` entry, tinted via each House's own hand-authored `HouseDef.placeholder_color`
  — Dragon plum, Eagle crimson, Boar forest green, Scorpion gold, Dolphin teal — since House has no
  category to derive a tint from like shop locations do), and an HSV color for the player's placeholder
  rectangle — deliberately sparse today, a stand-in for a future character-appearance step; (2) the
  5-point skill allocation; (3) shop location, picked from a 3x2 `GridContainer` of toggle buttons (one
  per `ContentRegistry.shop_locations` entry) instead of a dropdown, each with a placeholder
  color-swatch icon tinted via `IngredientDef.CATEGORY_COLORS` by the location's `ingredient_category`
  (Natural forest green, Artificial gold, Spectral tea green, Demonic plum, Draconic crimson,
  Extraplanar teal — no real per-location art yet) and a live preview of the origin skill bonus it
  grants. Plum/gold/forest are hand-tuned rather than Godot's named Color constants — stock PLUM read
  as pink and GOLD as canary yellow at tile size, and forest is nudged blue-green to read distinctly
  from teal. Confirming calls
  `SaveManager.create_new_game(character_name,
  pronouns, house_id, shop_origin, player_color, skill_allocations)` — which also resets `Skills` (in
  case a prior playthrough left XP behind) and grants the allocated starting points.
- **Title screen.** `res://scenes/MainMenu.tscn` (`scripts/main_menu.gd`, `MainMenu`) is now
  `run/main_scene` and is where CharacterCreator fires from — behind a "New Game" button rather than
  unconditionally at boot. "Load Game" lists `SaveManager.list_games()` and calls
  `quick_load_latest(game_id)` on the chosen one; "Settings" is a panel of generic, intentionally
  unwired placeholder controls (volume sliders, fullscreen/V-Sync checkboxes, text speed/difficulty
  dropdowns) with no persistence or gameplay effect yet. Both New Game and Load Game hand off to the
  new transient `GameFlow` autoload (`game_id: String`, `is_new_game: bool` — not part of any save
  payload) before `change_scene_to_file`-ing to `res://scenes/Main.tscn`; `main.gd._ready()` reads
  `GameFlow.is_new_game` to decide whether to grant starting ingredients (new game) or trust the
  state `SaveManager` already restored (loaded game), and reads `PlayerProfile.player_color_hex`
  directly instead of taking a signal argument, since CharacterCreator no longer lives in this scene.
  The Escape menu (`scripts/hud.gd`) now also has a "Save Game" button that calls
  `SaveManager.save_game(GameFlow.game_id)` — the only place gameplay saves are triggered from today
  (no autosave yet).
- **Per-autoload save contract.** Every gameplay autoload (`Clock`, `Inventory`, `Resolve`, `Skills`,
  `Alchemy`, `Brewing`, `Shop`, `Herbalism`, `Economy`, `Academy`, `Story`, `LoveInterests`, `PlayerProfile`)
  owns a `get_save_data() -> Dictionary` / `load_save_data(data: Dictionary) -> void` pair, consistent
  with every other system owning its own state. Only plain Dictionaries/Arrays/primitives cross this
  boundary — `SeedDef` references (in `GrowPlotInstance`) are saved as their string `id` and
  re-resolved on load via the `ContentRegistry` autoload (a small id→Resource lookup that replaced
  `main.gd`'s previously-duplicated content path lists). `RecipeDef` references (in `BrewJob`) are the
  exception: since most recipes are discovered at runtime rather than loaded from `.tres` content
  (system 3), `Alchemy` itself saves/restores each learned recipe's full fields, and `BrewJob.recipe`
  is re-resolved via `Alchemy.get_learned_recipe()`, not `ContentRegistry` — which is also why
  `Alchemy` must restore before `Brewing` in `SaveManager._SAVE_ORDER`.
- **Economy double-apply hazard.** Upgrade effects (station modifiers, shop capacity, plot count) are
  applied once at purchase time directly onto `Brewing`/`Shop`/`Herbalism`'s own numbers. Those
  *resulting* numbers are what gets saved and restored directly by each system's own
  `load_save_data()`. `Economy.load_save_data()` restores `purchased_upgrade_ids` only for
  `is_purchased()` UI gating and deliberately does **not** replay it through `_apply_effect()` — doing
  so would double-apply every modifier/capacity/plot on top of the already-restored values. This is the
  one cross-system invariant in the save system worth remembering, same category as `Resolve.
  is_strained()` living inside `Skills.get_bonus()`.
- **Timestamps need no rebasing.** `Clock.get_timestamp()` is an absolute, never-reset minute counter,
  so `BrewJob`/`GrowPlotInstance` timestamps saved as raw integers compare correctly the instant `Clock`
  is restored — `SaveManager.load_game()` restores `Clock` before anything else, so any job/plot whose
  deadline already passed while the save was closed resolves automatically on the very next
  `minute_tick`, with zero special catch-up code (the same mechanism `TimeSkip` already relies on).
- **Disk layout**: `user://saves/<game_id>/meta.json` (game identity + a cheap per-slot summary, so
  listing every game for a picker UI never opens a full slot file) plus `slot_<n>.json` per save. Every
  write is preceded by copying the existing file to a `.bak` (one generation, last-known-good only —
  the multiple slots themselves already give the player manual rollback) and is itself written via a
  `.tmp` file + rename so an interrupted write can't leave a truncated file at the real path.
- **Checksum.** SHA256 (via `HashingContext`) over the canonical JSON of a slot's payload (or, for
  `meta.json`, the dict minus its own checksum field), stored alongside the data. On load: try the
  primary file, fall back to `.bak` if the primary fails validation (self-healing the primary from the
  backup afterward), and if *both* fail validation, fail loudly — return an explicit error rather than
  silently starting a new game over a corrupted save. The caller (UI) is responsible for surfacing that
  to the player.
- **Versioning.** Every slot wrapper carries a `version` int; `SaveManager._MIGRATIONS` is a
  version→`Callable` map applied in a loop until the payload reaches `CURRENT_SAVE_VERSION`. Empty
  today (only v1 exists) but the seam is in place so a future format change doesn't require rewriting
  the loader.
- `SaveManager`'s public surface: `create_new_game`, `save_game`, `load_game`, `quick_load_latest`
  (loads a game's `meta.json.latest_slot` — the "one big continue button" case), `list_games`,
  `list_slots`, `delete_slot`, `delete_game`.

---

## 15. Quest / Journal System **[BUILD]**

Populates the Escape menu's Journal tab. No taxonomy of quest *types* (shop
order vs. class assignment vs. love-interest favor vs. tutorial milestone) —
a quest is just a completion condition plus a reward, expressed in the same
expression language the VN layer already has (system 13), so all four kinds
fall out of one data shape rather than needing per-category code:

```
QuestDef
  - id
  - display_name
  - description
  - complete_condition: String   # same expression grammar as VN `if`/SceneTriggerDef.condition
  - reward: [String]             # action-call expressions, e.g. give_item(...), add_affection(...)
  - auto_complete: bool          # true: reward grants the instant complete_condition is true
                                  # false: waits for QuestManager.turn_in(id)
```

- **No `start_condition`.** Unlike `SceneTriggerDef`, a quest never starts
  itself — `QuestManager.start_quest(id)` is the only way a quest becomes
  Active, called explicitly from wherever makes sense (a debug-HUD hook, an
  NPC interaction once Exploration exists, or a VN scene action-call — the
  expression language gained a matching `start_quest("id")` function in
  `VNExpressionEvaluator` for the latter, same dispatch table as
  `give_item`/`add_affection`). This was a deliberate choice over condition-
  gated auto-start: quests are handed out by content, not discovered by
  polling world state.
- **Progress *is* polled**, same pattern as `SceneDirector.recheck()`:
  `QuestManager` re-evaluates every Active quest's `complete_condition` on
  every `Clock.minute_tick`. This is a prototype-scope simplification — an
  event-driven counter per objective type (increment on the specific signal
  a quest cares about, e.g. `Brewing.brew_completed`) is the planned
  replacement once there's enough real quest content to know what objective
  shapes actually recur, but it's a drop-in swap behind the same
  `QuestManager` public API, not a `QuestDef` shape change.
- **Two completion flows**, chosen per-quest via `auto_complete`:
  - `true`: the moment `complete_condition` evaluates true, `QuestManager`
    evaluates every `reward` expression and marks the quest Completed in the
    same tick — no player action needed.
  - `false`: `complete_condition` true instead flips the quest to
    `ReadyToTurnIn`; rewards only grant when something calls
    `QuestManager.turn_in(id)` explicitly (the Journal tab renders a "Turn
    In" button for any quest in this state as the prototype's one turn-in
    surface; a station/NPC-specific turn-in interaction can replace or
    supplement that later).
- **Rewards reuse `VNExpressionEvaluator`**, not a separate quest-effect
  table — a quest reward and a scene's action-call statements are the same
  kind of thing (`give_item`, `add_affection`, `set_flag`, ...), so quest
  authoring and scene authoring share one syntax and one place new action
  functions get added.
- Both `complete_condition` and every `reward` expression are parsed once at
  `QuestManager._ready()` (same "never touch the parser mid-game" discipline
  `SceneDirector` uses for its triggers) — a malformed expression is a
  `push_error` at startup, not a silent no-op mid-playthrough.
- `QuestManager` follows the same per-autoload save contract as system 14:
  `get_save_data()`/`load_save_data()` round-trip a flat `{quest_id: status}`
  dict; registered in `SaveManager._SAVE_ORDER` after `LoveInterests`.
- Content lives under `data/quests/*.tres`, loaded via `ContentRegistry`
  (`QUEST_PATHS` const list, same explicit-path pattern as every other
  content type) — `first_brew.tres` and `stock_the_shelf.tres` are the two
  sample quests proving the pipeline end-to-end (one `auto_complete: true`
  skill-level milestone, one `auto_complete: false` materials-threshold quest
  with a manual turn-in), granted to every new game by `main.gd`.

---

## 16. Shared Randomness System **[BUILD]**

A single seeded `RandomNumberGenerator` stream, shared by every random outcome in the
game — from silent background rolls (shop sale chance) to visible 2d10-and-modifier
dice checks (brewing, Academy class performance, and later VN/social checks). One
shared stream means one consumption order and one thing to persist (`.state`), rather
than juggling determinism across several independent RNG instances.

```
Rng (autoload)
  - _rng: RandomNumberGenerator   # private, single instance
```

- **Quiet API** — direct replacement for bare `randf()`/`randf_range()`:
  `Rng.chance(probability) -> bool`, `Rng.range_f(from, to) -> float`,
  `Rng.range_i(from, to) -> int`.
- **Visible dice API** — `Rng.roll_2d10(modifier, dc) -> Dictionary`, returning
  `{die_a, die_b, modifier, total, dc, passed, critical_failure, critical_success,
  inflection_point}`. Additive, BG3/5e-style: roll 2d10, add a flat modifier sourced
  from `Skills.get_bonus()` (already strain-aware per system 8), compare against a
  difficulty class. No advantage/disadvantage mechanic in scope.
- **Crit semantics** are computed generically from the roll's *natural* (unmodified)
  die faces, so any caller can opt into them without `Rng` knowing what a "botch" or
  a "crit" means to that system: a natural `1` on either die is a `critical_failure`,
  a natural `10` on either die is a `critical_success`, and a natural `1`+`10` pair
  overrides both into an `inflection_point` — currently flavor-only, no mechanics
  attached to it anywhere yet. It's on each caller to decide what (if anything) these
  mean; Brewing (system 4) is the only current consumer of the crit fields.
- Visible rolls render through the message wall (`scripts/ui/components/message_wall.gd`
  + `message_entry.gd`), a bottom-right translucent scrollback that replaced the old
  modal `DiceRollPopup`/`MenuScene` pairing — dice results and info notices (e.g. a
  potion selling in the shop) both land there as rows that fade in, linger a few
  seconds, then dim rather than pausing the game (`GameHud.log_message()` and
  `MessageWall.add_dice_result()` are the two entry points; `hud.gd` calls the latter
  directly off each roll signal instead of opening a menu). A row never actually
  disappears once posted, only dims — the wall scrolls (wheel, or click-drag) back
  through history, and hovering a row brightens it to full opacity and expands its
  detail line. The wall collapses to a small icon in the corner once nothing is
  recent and the mouse isn't over it. Neither component ever rolls dice itself — they
  only render an already-produced result `Dictionary`, so headless code can call
  `Rng.roll_2d10()` with no UI involvement.
- **Seeding**: `Rng.seed_new_game()` is called exactly once, from `main.gd`'s
  `GameFlow.is_new_game` branch, at the same point starting ingredients/quests are
  granted. Loading a save never reseeds — only `.state` (the stream's draw position)
  is restored via the per-autoload save contract (system 14), so a player cannot
  reroll a bad outcome by reloading.
- Registered in `SaveManager._SAVE_ORDER` immediately after `Clock`, and in
  `project.godot`'s autoload list immediately after `Clock` — it has no dependencies
  of its own but must exist before every system that rolls (`Resolve`, `Skills`,
  `Brewing`, `Shop`, `Herbalism`, `Academy`, ...).
- **Which checks are quiet vs. visible** (a deliberate per-call-site choice, not a
  blanket rule): shop passive sale-chance ticks (system 5) stay quiet/background —
  frequent and ambient, even an unobtrusive message-wall row would be noise. Brewing's
  combined roll and Academy class performance are visible 2d10 checks — infrequent,
  player-meaningful moments worth surfacing in the message wall.

---

## 17. Demonology / Contract System **[BUILD]**

Bartering with a demonic entity for demonic ingredients, via a Contract Book interactable.
Unlike Brewing/Herbalism, a writ's timer only advances while the player is physically
standing at the book — walking away or opening the Escape menu pauses it — so the
loop is deliberately about staying put and watching a meter climb, not a
fire-and-forget deadline.

```
WritJob (scripts/data/writ_job.gd, RefCounted)
  - book_id: String
  - status: Status(WRITING, REVISING)
  - is_working: bool
  - minutes_elapsed: int
  - minutes_required: int
  - quality: float
  - revisions_completed: int

Demonology (autoload)
  - _writs: Dictionary            # book_id -> WritJob
  - _pending_consequences: Array[Dictionary]  # {type, severity, trigger_timestamp}
```

- **Writing, then automatic revision.** `start_writ(book_id)` opens a writ in the
  `WRITING` phase (`BASE_WRITING_MINUTES` = 60, reduced by `Demonology._demon_barter()`).
  Finishing WRITING rolls an initial `quality` from `Skills.level("demonology")` plus
  `±QUALITY_BASE_VARIANCE` random swing, flips the writ to `REVISING`, and immediately
  starts the first revision — the player never has to re-trigger revising, only
  submission. Every revision costs the same fixed `BASE_REVISION_MINUTES` (30, i.e.
  exactly half of the writing time, also `_demon_barter()`-reduced) regardless of how
  many have already happened; only the *quality bonus per revision* shrinks,
  geometrically (`FIRST_REVISION_BONUS * REVISION_DECAY^(n-1)`), matching "smaller bonus
  each time" without making later revisions faster or slower than earlier ones.
  `_demon_barter()` is `Skills.level("demonology") * DEMON_BARTER_PER_LEVEL`, halved
  under `Resolve.is_strained()` same as `Skills.get_bonus()` — deliberately continuous
  per level rather than the flat-bonus-at-a-threshold shape every other skill effect
  uses (`SkillDef.effect_levels`), so writ speed (and the submission roll below) keeps
  improving every level instead of plateauing after one threshold.
- **Engagement, not a deadline.** `WritJob.minutes_elapsed`/`minutes_required` is an
  accumulator `Demonology._on_minute_tick()` increments only for writs whose
  `is_working` is true — never a `Clock.get_timestamp()` deadline comparison like
  `BrewJob`/`GrowPlotInstance`. `ContractBookInteractable` is the only interactable
  whose `player_exited` signal is wired (in `RoomBuilder._wire_interactable()`) to
  mutate autoload state directly (`Demonology.pause_writ()`) rather than just clearing
  the HUD prompt — walking away is the pause button. Opening the Escape menu doesn't
  need special-casing at all: `Clock.is_paused` already halts every Clock-driven system,
  writs included.
- **`interact()` is a three-way toggle**, not a menu open like `BrewStationInteractable`:
  no writ → `start_writ()`; an existing writ currently `is_working` → `submit_writ()` if
  it's past its first draft (`REVISING`), or just `pause_writ()` if it's still on its
  initial `WRITING` pass (nothing to submit yet); a paused writ → `resume_writ()`. No
  `MenuScene` panel is involved in the core loop at all — pausing the Clock (which
  `MenuScene.open()` does) would also freeze the player, making "walk away to pause"
  impossible, so the entire mechanic lives in world-space HUD (the meter + diamonds
  above the book), the same shape as `BrewStationInteractable`'s progress bar.
- **Submission**: `submit_writ()` rolls `Rng.roll_2d10(Demonology._demon_barter(),
  SUBMIT_DC)`; a critical success/failure only shifts `quality` by `±CRIT_QUALITY_SWING`
  (per the design note that crits just nudge quality, nothing more exotic). Final
  quality drives two independent outputs:
  - **Ingredient count** — `BASE_INGREDIENT_COUNT + floor(quality / QUALITY_INGREDIENT_DIVISOR)
    + Skills.get_bonus("demon_yield")`, granted from `DEMONIC_INGREDIENT_IDS` (currently
    `imp_ash`, `brimstone_shard` — the first two `IngredientDef.Category.DEMONIC`
    resources; `source_methods = [SourceMethod.SUMMON]`, `buy_price = 0` since they're
    only obtainable through a writ, never bought).
  - **Drawback count** — `_drawback_count_for_quality()`: 0 at/above `quality
    100`, climbing to `MAX_DRAWBACKS` (4) well below `70`. Each rolled drawback is one
    of `ConsequenceType` (`RESOLVE_LOSS`, `REPUTATION_LOSS`, `CLASS_PERFORMANCE_LOSS`,
    `RELATIONSHIP_LOSS`, `SHOP_STOCK_LOSS`, `INVENTORY_LOSS`), each independently a
    coin-flip between firing immediately (`_apply_consequence_now()`) or queued
    `FUTURE_CONSEQUENCE_MIN/MAX_DAYS` out into `_pending_consequences`, resolved by
    `_resolve_pending_consequences()` comparing against `Clock.get_timestamp()` on every
    `minute_tick` — the one deadline-style timestamp comparison in this system, since
    delayed consequences (unlike writ progress) should land whether or not the player
    is standing at the book.
  - **"Shop damage"** (from the original design brief) has no drawback branch — there's
    no shop-condition/durability stat anywhere in the game yet to damage, unlike
    `Shop.reputation` (system 5's existing, previously-unread stat, which
    `REPUTATION_LOSS` is now the first thing to actually decrement). Not stubbing a new
    stat for one drawback type keeps this in scope; a mechanical shop-damage system
    would be a prerequisite, not part of this feature.
- **The meter and diamonds** live entirely on `ContractBookInteractable`
  (`scripts/contract_book_interactable.gd` + `scenes/interactables/
  ContractBookInteractable.tscn`), following `BrewStationInteractable`'s pattern exactly
  (a `Panel`/`ProgressBar` child, a fill `StyleBoxFlat` duplicated per instance so
  recoloring one book doesn't bleed into others) but filling deep midnight indigo →
  violet instead of red → green. Two `GridContainer`s of 9 pre-placed,
  individually-toggled-visible `DiamondMarker` controls
  (`scripts/ui/components/diamond_marker.gd` — a plain `Control` that draws its own
  diamond polygon in `_draw()`, rather than a rotated `ColorRect`, since
  `Container.fit_child_in_rect()` resets a child's rotation to 0 on every layout pass
  and so silently un-rotates anything rotated inside a `GridContainer`) sit to either
  side of the meter: `OnesDiamonds` (violet, `revisions_completed % 10`) and
  `TensDiamonds` (gold, `revisions_completed / 10`, capped at 9, filled right-to-left
  via `_set_diamond_row()`'s `reversed` flag so both grids grow outward from the meter
  at the center). `RoomBuilder._sync_contract_indicator()` is the single function
  driving all of it from `Demonology.get_writ(book_id)`, called on every relevant
  Demonology signal — no `Clock.minute_tick` polling hook needed here (unlike
  Brewing's indicator sync) since `writ_progress` already fires on exactly the ticks
  that matter. Reaching `MAX_REVISIONS` (100) auto-submits and files the writ away — an
  explicit edge case for something never expected to happen in normal play (most writs
  are expected to land around 3-7 revisions).
- **Save contract**: `Demonology.get_save_data()`/`load_save_data()` follow the same
  per-autoload shape as every other system (system 14) — registered in
  `SaveManager._SAVE_ORDER` right after `Academy`. `is_working` is deliberately never
  persisted as `true`: the player is never standing at the book at the instant a save
  loads, so every restored writ comes back paused, same state a real walk-away would
  leave it in.
- Not in scope for the prototype: a Contract Book UI/menu for reviewing writ history,
  a demon-specific "who you're bartering with" identity/relationship (drawbacks pick
  a uniformly random `Characters` id for `RELATIONSHIP_LOSS`, not a dedicated demon
  NPC), and the mechanical shop-damage stat noted above.

---

## 18. Transmutation / Workbench System **[BUILD]**

Breaking down Scrap into artificial ingredients at a Workbench interactable, and digging raw
Scrap (plus, occasionally, an artificial ingredient outright) out of a Scrap Heap interactable.
The Workbench half has no multi-minute phase to sit through — one interaction resolves a whole
piece of Scrap immediately, closer in shape to `StockBoxInteractable`'s instant action than to
`BrewStationInteractable`'s job. The Scrap Heap half is the opposite: a player-tethered dig job
shaped exactly like Draconology's Dragon's Stash (system 19) — see the dedicated subsection
below.

```
Scrap (Inventory.scrap: Array[Dictionary])
  - quality: float          # per-unit, never surfaced to the player

ScrapHeapJob (scripts/data/scrap_heap_job.gd, RefCounted)
  - heap_id: String
  - minutes_elapsed: int
  - minutes_required: int
  - quality: float          # hidden, rerolled fresh every start_heap()

Transmutation (autoload)
  - _heap_jobs: Dictionary           # heap_id -> ScrapHeapJob, actively being dug only
  - _collected_heap_ids: Dictionary  # heap_id -> true, forever
```

- **Scrap is not a uniform stack.** `ingredient_counts` (id → int) can't represent it, since
  every individual piece carries its own hidden `quality`. `Inventory.scrap` is instead an
  `Array[Dictionary]` of `{quality}` entries — `add_scrap(quality)` appends one,
  `take_scrap()` pops the oldest (FIFO; quality is hidden, so there's no meaningful ordering
  choice for the player to make) and returns `{}` if there's none left. Quality is
  deliberately never rendered anywhere in the UI.
- **`break_down_scrap()` is one call, not a job.** It pops one piece via
  `Inventory.take_scrap()`, rolls a visible `Rng.roll_2d10(Skills.get_bonus("transmute_ease"),
  BREAKDOWN_DC)` (`BREAKDOWN_DC := 11.0`), and shifts the popped piece's quality by
  `±CRIT_QUALITY_SWING` (15.0) on a crit — same "crit only nudges quality" rule
  `Demonology.submit_writ()` uses. Final quality drives ingredient count:
  `BASE_INGREDIENT_COUNT (1) + floor(quality / QUALITY_INGREDIENT_DIVISOR (20.0)) +
  Skills.get_bonus("transmute_yield")`, granted from `ARTIFICIAL_INGREDIENT_IDS`
  (`scrap_alloy`, `refined_component` — the first two `IngredientDef.Category.ARTIFICIAL`
  resources; `source_methods = [SourceMethod.CRAFT]`, `buy_price = 0`, only obtainable this
  way). Grants `XP_PER_BREAKDOWN` (15) Transmutation XP. Returns `{}` and does nothing else
  if there was no Scrap to break down.
- **No persistent state, no save contract.** Everything `break_down_scrap()` touches
  (the Scrap consumed, the ingredients granted) already lives in `Inventory`'s own save
  data — `Transmutation` itself owns nothing that needs restoring, so unlike Demonology it
  is not registered in `SaveManager._SAVE_ORDER`, the same reasoning that keeps
  `ContentRegistry`/`Characters` out of it.
- **`WorkbenchInteractable`** (`scripts/workbench_interactable.gd` +
  `scenes/interactables/WorkbenchInteractable.tscn`) calls `Transmutation.break_down_scrap()`
  directly on `interact()` — no `MenuScene` panel, matching `StockBoxInteractable`'s
  one-shot shape. Success feedback (dice result + ingredient log, both via the
  message wall) is driven off
  `Transmutation.scrap_broken_down` in `hud.gd`, same pattern as
  `Demonology.writ_submitted`; the interactable only has to handle the "nothing to break
  down" case itself, since no signal fires for a no-op.
- **`main.gd` still grants `STARTING_SCRAP_COUNT` (3) pieces** at random quality on a new game,
  the same stopgap role `STARTING_INGREDIENTS` plays for ingredients — a real starting stock, not
  the only acquisition path now that the Scrap Heap exists (see below).

### Scrap Heap

A hand-placed, single-use Interactable (`ScrapHeapInteractable`,
`scripts/scrap_heap_interactable.gd` + `scenes/interactables/ScrapHeapInteractable.tscn`) that
digs up raw Scrap, and occasionally an artificial ingredient outright. Mechanically it is
Draconology's Dragon's Stash (system 19) with the serial numbers filed off — same tether, same
cancel-on-walk-away, same single-use destroy-on-resolve — so read that system's write-up for the
full reasoning; only what differs is called out here.

- **Same job shape, `Transmutation`-owned instead of a dedicated autoload.** `start_heap()`/
  `cancel_heap()`/`_on_minute_tick()`/`_resolve_heap()` mirror `Draconology.start_stash()`/
  `cancel_stash()`/`_on_minute_tick()`/`_resolve()` exactly, including the constant shapes
  (`HEAP_MINUTES` (5) vs. `STASH_MINUTES`, `HEAP_QUALITY_MIN/MAX` (20–120) vs. `QUALITY_MIN/MAX`,
  `HEAP_ROLL_DC`/`HEAP_CRIT_QUALITY_SWING` vs. `ROLL_DC`/`CRIT_QUALITY_SWING`). It lives on
  `Transmutation` rather than a new autoload because the roll it makes is a Transmutation check
  (modifier = `transmute_ease`, same as `break_down_scrap()`'s roll) and the loot it grants sits
  squarely in Transmutation's existing domain (raw/artificial Scrap-adjacent materials) — there
  was no `Draconology`-shaped reason to split it out.
- **Resolution grants Scrap, not ingredients.** `_resolve_heap()` rolls
  `Rng.roll_2d10(Skills.get_bonus("transmute_ease"), HEAP_ROLL_DC)`, shifts quality by
  `±HEAP_CRIT_QUALITY_SWING` on a crit (same "crit only nudges quality" rule every other roll in
  the prototype uses), then grants `HEAP_BASE_SCRAP_COUNT (1) + floor(quality /
  HEAP_QUALITY_SCRAP_DIVISOR (20.0)) + Skills.get_bonus("transmute_yield")` pieces of Scrap via
  `Inventory.add_scrap(final_quality)` — every piece from one dig shares that dig's final quality,
  the same "one roll seeds every unit granted" shape `Draconology._grant_ingredients()` uses.
  Additionally, a flat `HEAP_ARTIFICIAL_CHANCE` (0.2) roll can hand over one artificial ingredient
  (from `ARTIFICIAL_INGREDIENT_IDS`) directly, on top of the Scrap — the fictional read is that the
  heap occasionally turns up something already refined instead of raw material, without needing a
  trip to the Workbench. Grants `XP_PER_HEAP` (20) Transmutation XP, then erases the job and
  records the heap as collected.
- **Both hand-placed and spawner-scattered.** `scrap_heap_1` in `Shop.tscn` is a fixed fixture with
  no spawner behind it, same as before. But the Scrap Yard (`scenes/rooms/ScrapYard.tscn`,
  `room_id = "scrap_yard"` — a large room reachable from the Shop's `StairsToScrapYard`, visually
  the Dragons' Ground's layout minus the dragons) carries a `ScrapHeapSpawnerNode`
  (`scripts/scrap_heap_spawner_node.gd`, wrapped as `scenes/spawners/ScrapHeapSpawner.tscn`,
  `spawner_id = "scrap_yard_heaps"`) linked to its own `SpawnZones` container. It's
  `DragonStashSpawnerNode` (system 19) with the serial numbers filed off exactly the same way the
  hand-placed heap mirrors the hand-placed stash: `spawn_zone_path`/`max_heaps`/`avg_days_to_max`/
  `min_separation` exports, `SpawnZoneUtils.random_point()` for placement, and the same
  "spawner only owns *where* and *how often*, RoomBuilder does the actual instancing/wiring" split
  — it emits `spawn_requested(heap_id, world_position)`, which `RoomBuilder._on_heap_spawn_requested()`
  (connected in `_load_room()`, mirroring `_on_stash_spawn_requested()`) turns into a real
  `ScrapHeapInteractable` parented under the spawner node. `Transmutation.register_heap_spawner()`/
  `_on_day_started()` (now wired to `Clock.day_started`, alongside the pre-existing `minute_tick`
  hook) mirror `Draconology.register_spawner()`/`_on_day_started()`'s asymptotic per-slot nightly
  roll line for line, and `ground_heaps_spawned(spawner_id, heap_ids)` mirrors
  `ground_stashes_spawned`. `_resolve_heap()` frees a resolved id back out of `_spawner_heap_ids` the
  same way `Draconology._resolve()` does, so a spawner's population approaches its cap again instead
  of only ever draining.
- **`RoomBuilder._wire_interactable()`** still guards the reload path the same way it would for a
  runtime-instanced stash: on load, a heap whose id is already in `Transmutation._collected_heap_ids`
  has its node discarded on sight (`interactable.queue_free()`) instead of being registered, so a
  collected heap — hand-placed or spawner-scattered — stays gone across a save/load even though a
  hand-placed node would otherwise just reappear from the room scene every time. This is also why,
  unlike `Draconology`, `Transmutation` needs a save contract at all — `get_save_data()`/
  `load_save_data()` now persist `_collected_heap_ids` plus `_spawner_heap_ids`/`_spawner_counters`
  (mirroring `Draconology`'s spawner persistence exactly; active jobs are still dropped on load/
  walk-away, same reasoning as every other tethered job) — and is registered in
  `SaveManager._SAVE_ORDER` right after `Summoning`.
- **The bar fills deep brown → bright gold**, `ScrapHeapInteractable`'s cosmetic answer to the
  Dragon's Stash's pale-green → maroon — "raw material giving way to something valuable" instead
  of "danger climbing." Otherwise the bar follows `DragonStashInteractable`'s geometry/tween
  pattern exactly (see system 19's "bar fills" note for why the tween exists at all).
  `RoomBuilder._sync_heap_indicator()`/`_on_heap_resolved()` mirror `_sync_stash_indicator()`/
  `_on_stash_resolved()` line for line, including the `player_exited` disconnect-before-`queue_free`
  guard against a stale `body_exited` reaching `main.gd`'s menu-closing logic.
- **Placeholder color is brass** (`Color(0.72, 0.55, 0.22, 1)`) rather than the Dragon's Stash's
  red, consistent with every other Interactable's `visual_color` being a rough color-code for what
  it is before real art lands.

---

## 19. Draconology / Dragon's Stash System **[BUILT]**

Digging draconic ingredients out of a Dragon's Stash interactable, scattered through the Dragons'
Ground. Player-tethered like the Contract Book (system 17) — progress only advances while the
player stands at it — but with no pause/resume: walking away doesn't freeze a writ's progress in
place, it throws the whole dig away, forcing a full restart (and a freshly rolled hidden quality)
next time. It's also single-use: once resolved, the stash Interactable is destroyed and doesn't
come back until a future overnight roll happens to refill its slot.

**Fictional framing (why this system looks the way it does):** a Dragon's Stash isn't a shop
fixture like the Contract Book or Workbench — it's procedurally scattered through the Dragons'
Ground, a large exploration-layer room (system 12) the player has no business lingering in.
Digging one out is a commitment made under threat, not a safe errand: the player
should feel the same tension a Contract Book gives them (a meter climbing, deciding whether to
keep watching it) but sharpened by the possibility of a dragon showing up mid-dig. That's the
whole reason walking away *cancels* instead of *pausing* — the Contract Book lets the player
step away and pick a writ back up later because nothing in a shop punishes hesitation, but a
stash is meant to force a real decision in the moment: commit to finishing the dig, or cut
losses and flee, knowing that bailing costs everything gathered so far. It's also why a stash is
destroyed on collection rather than reset to idle like a brew station or grow plot: the ground's
overnight spawn roll gradually backfills the population a collected stash vacated (see below), so
"gone until the ground itself replenishes it" is the intended read, not "gone forever" — even
though it's a fresh id refilling the slot rather than that exact stash respawning (see the
per-stash regeneration note below). Both of these are departures from
every other interactable in the prototype, and only make sense in that light — see the "Walking
away cancels" and "Single-use, and actually destroyed" notes below for the mechanical
consequences.

```
DragonStashJob (scripts/data/dragon_stash_job.gd, RefCounted)
  - stash_id: String
  - minutes_elapsed: int
  - minutes_required: int
  - quality: float          # hidden, rerolled fresh every start_stash()

Draconology (autoload)
  - _jobs: Dictionary            # stash_id -> DragonStashJob, actively being dug only
  - _collected_stash_ids: Dictionary  # stash_id -> true, forever
  - _spawner_configs: Dictionary      # spawner_id -> {max, avg_days_to_max}, in-memory only
  - _spawner_stash_ids: Dictionary    # spawner_id -> Array[String], ids currently scattered
  - _spawner_counters: Dictionary     # spawner_id -> int, next <spawner_id>_stash_N to hand out

DragonStashSpawnerNode (scripts/dragon_stash_spawner_node.gd, Node2D;
scenes/spawners/DragonStashSpawner.tscn)
  - spawner_id: String       # unique key into Draconology's spawner dicts above
  - spawn_zone_path: NodePath  # resolved node's Polygon2D children mark the zone -- see note below
  - max_stashes: int
  - avg_days_to_max: float   # ~average in-game days for this spawner's population to fill
  - min_separation: float
```

- **`interact()` only ever starts the dig.** `DragonStashInteractable.interact()` calls
  `Draconology.start_stash(stash_id)` if no job is running yet, or just logs a flavor message if
  one already is — there's no submit/collect action for the player to take, unlike
  `BrewStationInteractable`/`ContractBookInteractable`. `start_stash()` sets `minutes_required =
  STASH_MINUTES` (5, deliberately much shorter than a writ or a brew) and rolls the job's hidden
  `quality` from `Rng.range_f(QUALITY_MIN, QUALITY_MAX)` — independent of the player's Draconology
  skill level, since this is meant to read as a property of *this particular stash* (some are just
  better than others), the same "hidden per-instance quality" shape as `Inventory.scrap`'s per-unit
  quality, not `WritJob.quality`'s skill-seeded roll.
- **Engagement, not a deadline — and no pause.** A job existing in `Draconology._jobs` at all means
  it's actively being dug: there's no separate `is_working` flag like `WritJob`'s, because
  `RoomBuilder` guarantees a job is cancelled the instant the player leaves (see below), so
  `_on_minute_tick()` just increments `minutes_elapsed` for every job that still exists. This is
  the same "accumulator, not a `Clock.get_timestamp()` deadline" shape `WritJob` uses, deliberately
  *not* `BrewJob`/`GrowPlotInstance`'s fire-and-forget shape — the loop is meant to be about staying
  put, the same way a writ is.
- **Walking away cancels, it doesn't pause.** `DragonStashInteractable`'s `player_exited` is wired
  in `RoomBuilder._wire_interactable()` straight to `Draconology.cancel_stash(stash_id)`, which
  erases the job outright and emits `stash_cancelled` — unlike `ContractBookInteractable`'s
  `player_exited`, which calls `Demonology.pause_writ()` to freeze progress for a later resume.
  This is the one deliberate behavioral difference from the Contract Book, and it's a fictional
  one, not just a mechanical one: per the framing above, a stash sits out in dangerous
  dragons' grounds territory, so stepping away is meant to read as fleeing a threat, not idly
  wandering off from a shop fixture. Losing all progress on exit is what makes "keep digging or
  cut losses and run" an actual decision under pressure instead of a free pause button. Opening
  the Escape menu doesn't need special handling either way — `Clock.is_paused` already halts every
  `minute_tick`, writs and stashes both.
- **Resolution is automatic** once `minutes_elapsed >= minutes_required`, with nobody needing to
  press anything further. `_resolve()` rolls `Rng.roll_2d10(Skills.get_bonus("draconic_safety"),
  ROLL_DC)`; a critical success/failure shifts `quality` by `±CRIT_QUALITY_SWING`, same "crit only
  nudges quality" rule `Demonology.submit_writ()`/`Transmutation.break_down_scrap()` both use.
  Final quality drives ingredient count: `BASE_INGREDIENT_COUNT (1) + floor(quality /
  QUALITY_INGREDIENT_DIVISOR (20.0)) + Skills.get_bonus("draconic_yield")`, granted from
  `DRACONIC_INGREDIENT_IDS` (`dragon_scale`, `ember_dust` — the first two
  `IngredientDef.Category.DRACONIC` resources; `source_methods = [SourceMethod.FORAGE]`,
  `buy_price = 0`, only obtainable this way). Grants `XP_PER_STASH` (20) Draconology XP.
- **The bar fills pale green → rich maroon** instead of Brewing's red → green or the Contract
  Book's indigo → violet, purely a cosmetic choice to read as "danger climbing" rather than
  "potion topping off." `DragonStashInteractable` follows `BrewStationInteractable`'s pattern for
  geometry exactly (same `Panel`/`ProgressBar` dimensions, a fill `StyleBoxFlat` duplicated per
  instance) so the bar reads at the same size as every other station's, not the oversized/squat
  one an early draft accidentally shipped with. `RoomBuilder._sync_stash_indicator()` drives it
  off `Draconology.get_job(stash_id)`, called on `stash_started`/`stash_progress`/
  `stash_cancelled` — the same "no `Clock.minute_tick` polling needed" shape
  `_sync_contract_indicator()` uses, since progress only ever changes on an engaged tick and
  `stash_progress` already fires exactly then; a cancel clears the bar back to empty instead of
  freezing it like a paused writ's meter would. Because `STASH_MINUTES` is only 5, each
  `minute_tick` is just a fraction of a real second apart at normal speed — snapping
  `ProgressBar.value` straight to the new fraction on every tick reads as a visible staircase
  rather than a fill on a bar this short, so `DragonStashInteractable.set_stash_progress()` tweens
  `value` to the new target over roughly one tick's real-world duration
  (`1.0 / Clock.tick_rate_minutes_per_second`) instead of snapping it, which is enough to read as
  a continuous fill without `Draconology` itself needing to know or care about real time.
- **Single-use, and actually destroyed.** `Draconology.stash_resolved` (fired from `_resolve()`,
  after the job is erased and the stash id is recorded into `_collected_stash_ids`) is wired in
  `RoomBuilder.build_rooms()` to `queue_free()` the stash's Interactable node and drop it from
  `_stash_nodes` — unlike every other Interactable type, which persists or gets cleared back to an
  idle state, a resolved Dragon's Stash is just gone. This is the other departure the fictional
  framing above explains: a permanent fixture like a brew station makes sense in a shop, but a
  stash is a one-time find in the wild, and "gone" here specifically means gone-until-the-ground-
  regenerates-it, not gone-forever. `DragonStashInteractable` nodes are runtime-instanced (see
  below), so there's no hand-placed node for a collected id to leave behind — but
  `_wire_interactable()` still guards the reload path the same way it would for a hand-placed one:
  on load, each `DragonStashSpawnerNode` re-requests every id `Draconology.register_spawner()`
  still reports for it (uncollected by definition, since a collected id is dropped from that
  spawner's list), which is what keeps a collected stash from reappearing after a save/load.
- **Destroying the node while the player is standing on it needed one extra guard.** Because the
  tether guarantees the player is still overlapping the stash's `Area2D` at the exact moment it's
  freed, Godot's physics-server cleanup fires a `body_exited` for it — which would otherwise
  forward through `player_exited_interactable` into `main.gd`'s `_on_player_exited_interactable()`
  and immediately `close_menu()` the dice-roll popup `hud.gd` just opened for this very
  resolution (that handler's `close_menu()` call is correct for every other Interactable, where
  the signal really does mean "the player walked away," but wrong here, where it only means "the
  Interactable got destroyed"). `RoomBuilder._on_stash_resolved()` disconnects the node's
  `player_exited` before freeing it and emits a dedicated `interactable_destroyed` signal instead,
  which `main.gd`'s `_on_interactable_destroyed()` handles by clearing `_current_interactable`/the
  HUD prompt *without* touching the menu. `_on_interact_pressed()` also gained an
  `is_instance_valid()` guard as a defensive backstop against acting on a stale reference to a
  freed Interactable.
- **Feedback is the same dice-popup pattern as Demonology/Transmutation.** `hud.gd`'s
  `Draconology.stash_resolved` handler opens `_dice_popup` in `MenuScene` (`show_roll(roll,
  "Draconology")`) plus logs the ingredient summary, same as `Demonology.writ_submitted`/
  `Transmutation.scrap_broken_down`. This is safe specifically because the tethering makes it safe:
  a stash only ever resolves while the player is standing right there and `Clock` is unpaused (any
  open `MenuScene` panel — including this one — sets `Clock.is_paused = true`, so a resolution can
  never land underneath an already-open menu), which is the same guarantee a direct E-press gives
  the other two systems.
- **Save contract**: `Draconology.get_save_data()`/`load_save_data()` follow the same per-autoload
  shape as system 14, registered in `SaveManager._SAVE_ORDER` right after `Demonology`. Active
  jobs are deliberately *not* persisted — the player is never standing at the stash the instant a
  save loads, and unlike a writ there's no paused state to restore into, so a save/load is simply
  treated as another walk-away (any in-progress dig is just gone on reload, same as it would be if
  the player had stepped away). `_collected_stash_ids` is persisted so a finished stash stays
  gone, alongside `_spawner_stash_ids`/`_spawner_counters` (both keyed by `spawner_id`) so every
  spawner's current population and next id both survive a save/load intact — each
  `DragonStashSpawnerNode` re-requests every id it's still owed on load (see below), so without
  persisting this every uncollected stash would vanish on reload instead of just the in-progress
  digs. `_spawner_configs` (max/rate) is deliberately *not* persisted — it's re-supplied by each
  spawner node's own exported values every time its room loads, the same "exported tunable, not
  save data" split `Rng` uses for never reseeding on load.
- **Spawning is owned by `DragonStashSpawnerNode`, not the room or `Draconology`.** Drop a
  `scenes/spawners/DragonStashSpawner.tscn` instance into any room scene, link `spawn_zone_path`
  (the inspector's "Assign..." button gives a node picker restricted to that scene, same as it
  would for a typed `Node2D` export) to a `Node2D` whose `Polygon2D` children mark the diggable
  area, and set `max_stashes`/`avg_days_to_max`/`min_separation`/a unique `spawner_id`. This is
  deliberately a plain `NodePath` export, resolved with `get_node_or_null()` in script, rather than
  a typed `@export var spawn_zone: Node2D` — Godot's typed Node export only auto-resolves paths
  that stay inside the exporting node's own instanced sub-scene, so a path reaching out to a
  sibling in the parent room scene (as `spawn_zone_path` always does, since the linked zone lives
  in the room, not inside `DragonStashSpawner.tscn`) silently resolves to `null` and every stash
  lands at the room's origin instead of its zone — this bit a first pass at this system and is
  worth remembering before "fixing" it back to a typed export. The
  Dragons' Ground (`scenes/rooms/DragonsGround.tscn`, `room_id = "dragons_ground"` — a large room
  reached from the Shop via a `StairsInteractable` doorway, with a `StairsBack` returning the
  favor) carries one such spawner (`spawner_id = "dragons_ground_stashes"`) linked to its
  `SpawnZones` container, but nothing stops a future room from having its own with different
  tuning. `DragonStashSpawnerNode` doesn't instance the `DragonStashInteractable` itself, though —
  stashes need the same proximity wiring (HUD prompts, `player_exited` → `cancel_stash()`, the
  `is_collected()` reload guard) every other Interactable gets from `RoomBuilder._wire_interactable()`,
  and duplicating that wiring in a second place isn't worth it. Instead the spawner node only owns
  *where* and *how often*: it calls `Draconology.register_spawner(spawner_id, max_stashes,
  avg_days_to_max)` once in `_ready()` (getting back whichever of its ids are already scattered,
  from a loaded save or an earlier visit this session) and emits `spawn_requested(stash_id,
  world_position)` for each one to place; `RoomBuilder._load_room()` connects to that signal
  *before* `add_child(room)` triggers the room's `_ready()` (connecting after would miss the
  initial re-placement burst) and `_on_stash_spawn_requested()` does the actual
  instantiate-and-wire, parenting the new Interactable under the spawner node itself — the same
  "code-instanced, not hand-placed" exception `add_grow_plot_interactable()` is for grow plots.
- **Where a stash can land is drawn, not painted.** A spawner's `spawn_zone_path` points at a
  container of one or more `Polygon2D` nodes — reshape or add a dig zone by dragging its points in the 2D
  editor, the same way a `CollisionPolygon2D` is authored, rather than a tileset terrain parameter.
  `SpawnZoneUtils.random_point()` (`scripts/spawn_zone_utils.gd`, shared with system 21's dragon
  spawner) rejection-samples a point inside a randomly chosen zone polygon
  (`Geometry2D.is_point_in_polygon`), rerolling if it lands too close to an already-placed stash
  from the same spawner (`min_separation`). The position is seeded from `hash(stash_id)` rather
  than stored anywhere, so a stash lands in the same spot whether it's being freshly placed this
  session or re-placed after a save load — the same "derived, not persisted" shape
  `add_grow_plot_interactable()`'s index-based formula uses for plots.
- **Each spawner approaches its own stash limit instead of filling up outright.**
  `Draconology._on_day_started()` (wired to `Clock.day_started`, i.e. every sleep/collapse) loops
  every registered spawner and makes up to `max_stashes` independent rolls, each attempt's chance
  (`1.0 / avg_days_to_max`) scaled down linearly by how full that spawner's population already is —
  `chance * (1.0 - current_count / max_stashes)` — so the population climbs quickly while empty and
  asymptotically slows as it nears `max_stashes` rather than jumping from empty to packed in one
  night; `avg_days_to_max` is therefore an approximate target, not a hard deadline. All ids rolled
  for a spawner in a night are batched into one `ground_stashes_spawned(spawner_id, stash_ids)`
  emission, which only that `spawner_id`'s `DragonStashSpawnerNode` acts on. Collecting a stash
  (`_resolve()`) erases its id from whichever spawner's list holds it as well as marking it
  collected, freeing that spawner's slot back up for a future night's roll — its population drains
  as stashes are dug and refills gradually over subsequent nights, rather than only ever emptying.
- Not in scope for the prototype, but load-bearing for the fictional framing above and worth
  keeping in mind when touching this system: a **per-stash regeneration timer**, so a specific
  collected stash can respawn (possibly in a new spot) after a period of days rather than the
  ground's overall population just being backfilled by unrelated fresh ids — this is the piece
  that would turn `Draconology.is_collected()`'s permanence into something temporary; and
  `learn_speed_draconic` (no ingredient-learning system exists yet for any category).

---

## 20. Ley Line Node System **[BUILT]**

Gathering spectral ingredients by interacting with a Ley Line Node and playing a short minigame at
it. Unlike the Contract Book or Dragon's Stash, there's no background timer or tether: `MenuScene`
already pauses `Clock` and freezes the player for as long as it's open, so the whole interaction is
synchronous — nothing to tick, nothing that needs to survive the player walking away.

```
LeyLines (autoload)
  - _active_node_id: String       # "" when no minigame is running
  - _active_difficulty: float     # base_difficulty - leyline_ease, floored at 0
  - _active_rounds: int
```

- **`LeyLineNodeInteractable`** (`scripts/ley_line_node_interactable.gd`) carries its own
  per-instance `difficulty: float` and `rounds: int` exports — different nodes can be tuned
  harder/longer with no code change. `interact()` calls `LeyLines.start_minigame(target_id,
  difficulty, rounds)` and otherwise does nothing; it has no progress meter and needs no wiring in
  `RoomBuilder`, unlike the Dragon's Stash.
- **`start_minigame()`** applies `Skills.get_bonus("leyline_ease")` against the node's base
  difficulty before handing it to the minigame, then emits `minigame_started(node_id, difficulty,
  rounds)`. `hud.gd` reacts by opening a minigame content `Control` in `MenuScene`, the same
  "autoload signal → HUD opens a panel" shape `AttemptPuzzlePanel` uses.
- **The minigame** (`scripts/ui/ley_line_minigame_panel.gd`, `LeyLineMinigamePanel`) is a real-time
  positioning game hosted in `MenuScene`. Its outer `VBoxContainer` owns only a status/hint label;
  the play itself lives in the inner `LeyArena extends Control`, kept in the same file so the whole
  minigame stays a single swappable unit. A big circle is the ley line node — *everything* in it is
  dangerous except a few small glowing safe zones. The player steers a small icon (WASD or arrow
  keys, polled in `_process` — `MenuScene` only flips `Clock.is_paused`, it never pauses the
  SceneTree, so `_process`/`_draw` run normally) around the arena. Each round a **resonance ring**
  collapses from the wall to the center; when it snaps shut the game measures, via circle-circle lens
  area, what fraction of the icon overlaps the best-covering safe zone. **Movement is velocity-based**
  (acceleration + friction, clamped to a max speed, with a solid wall at the arena edge) so it has
  weight but stays responsive — feel is the priority.
- **Difficulty and Arcane History are separate levers.** The `difficulty` handed in (already softened
  by `leyline_ease` upstream) is normalised over `difficulty_span` (3.0) and, as it rises, shrinks
  the safe zones, shortens the round timer, drops the zone count (3→1), and makes the zones **drift
  and shrink as the ring collapses** — the high-skill element is tracking that moving, shrinking
  target and arriving centered. Arcane History (`Skills.level("arcane_history")`, curved over
  `level_cap` 6) instead tunes the icon itself: a higher level makes it **smaller, faster, snappier,
  and sharper-turning** (more accel/friction, plus a turn-responsiveness factor that lets steering
  overrule existing momentum — a novice's icon is deliberately awkward and slow to reverse), so a
  skilled arcanist both fits zones more easily and commits to them more precisely. Lower difficulties
  use noticeably bigger safe zones partly to compensate for that early-game sluggishness. Every curve
  endpoint is a `Vector2` (easy→hard / novice→skilled) `@export` on the panel's scene root, editable in
  the inspector on `scenes/ui/LeyLineMinigamePanel.tscn` — hud.gd instances that scene (rather than
  `.new()`ing the script, as the other menu panels do) so the tunables are inspector-editable, and
  `build()` forwards them into the inner `LeyArena` (whose own `@export`s Godot wouldn't surface).
- **Resolve is charged per round, at each snap**, proportional to the danger fraction (`1 - safe`)
  and weighted up by difficulty (`max_resolve_per_round` 12 × `0.6 + 0.6·norm`) — the minigame calls
  `Resolve.spend()` directly, the same "a mishap event charges Resolve" shape Brewing's botch uses,
  rather than routing it through `LeyLines`. Getting caught costs immediately; it isn't a run-ending
  failure. The icon **bounces off the arena wall** (outward velocity reflected, damped by
  `wall_bounce`) rather than stopping dead, so overshooting the edge is a recoverable mistake with
  consequences, not a soft wall to lean on.
- **Bonus motes** add a risk/reward beat. Each round has a `bonus_chance` of spawning one glowing gold
  mote, placed clear of the safe zones (and the player's current spot), so committing to grab it
  genuinely trades away safe position as the ring collapses. Touching it (a cheap circle overlap
  checked every movement frame) banks one extra spectral ingredient. The arena tracks the count and
  passes it to `LeyLines.resolve_minigame(performance, bonus_ingredients)`; those bonus ingredients are
  granted **regardless of tier** — even on a run that clears no tier — since the mote is its own earned
  reward and the risk was already paid in resolve/position. They fold into the same ingredients dict as
  the tier reward, so hud.gd's "Received: …" summary shows them together.
- After the last round the arena averages the per-round safe fractions into a single `performance` and,
  after a short on-screen grade readout (which also shows any `+N bonus`), reports it via
  `LeyLines.resolve_minigame(performance, bonus_ingredients)` — the `performance` half is the same
  0.0–1.0 contract the old placeholder satisfied and `bonus_ingredients` defaults to 0, so
  `LeyLineNodeInteractable`, `hud.gd`'s signal wiring, and the abort-on-close guard were untouched.
  `abort_minigame()` (Esc/close) still bails with no reward, and any Resolve already spent during the
  run stays spent.
- **Performance maps to a reward tier**, not a continuous formula like Draconology's quality/divisor
  — `great` (≥0.85) / `good` (≥0.6) / `poor` (≥0.25) / below that, nothing. Each tier has a base
  spectral-ingredient count (3/2/1), with `Skills.get_bonus("leyline_yield")` (Arcane History) added
  on top before ingredients are granted from `SPECTRAL_INGREDIENT_IDS` (`glimmer_dust`,
  `echo_shard` — the first two `IngredientDef.Category.SPECTRAL` resources; `source_methods =
  [SourceMethod.FORAGE]`, `buy_price = 0`, only obtainable this way). Grants `XP_PER_MINIGAME` (20)
  Arcane History XP — the skill's `leyline_ease`/`leyline_yield`/`learn_speed_spectral` triplet is
  now consumed by the first two (`learn_speed_spectral` remains **[STUB]**, same as every other
  category's ingredient-learning effect).
- **Aborting grants nothing** — `abort_minigame()` throws the session away with no ingredients and
  no XP, same "walking away costs everything" shape as `Draconology.cancel_stash()`, just triggered
  by the player choosing to quit the minigame (or closing the menu by any route — Esc, the close
  button) rather than leaving the node's proximity, since the player can't physically walk away
  mid-session anyway. `hud.gd` wires `MenuScene.closed` to check `LeyLines.is_active()` and call
  `abort_minigame()` if a session is still open when the menu closes for any reason, so an Esc-press
  mid-minigame can't leave a dangling session.
- **No save contract.** Same as Transmutation, there's no state that outlives a single synchronous
  interaction — `LeyLines` has no `get_save_data()`/`load_save_data()` and isn't in
  `SaveManager._SAVE_ORDER`.

---

## 21. Dragons / Roaming Threats **[BUILT]**

Ambient hazards roaming a room's dragon spawn zones. Not enemies to be defeated — the player has
no attack of any kind — purely obstacles to be avoided while digging Dragon's Stashes (system 19)
or just passing through. A dragon wanders near its spawn point until the player gets too close,
chases until it either lands a hit or the player breaks away, and — unlike a Dragon's Stash — is
never persisted: the whole population is cleared and rerolled fresh every morning rather than
accumulating or surviving a save/load.

```
DragonDef (scripts/data/dragon_def.gd, Resource; data/dragons/*.tres)
  - id, display_name
  - spawn_weight              # this tier's own global rarity, see DragonSpawnEntry below
  - visual_color, visual_radius
  - provoke_range             # base distance at which the dragon notices the player
  - never_provoke_draconology_level  # 0 = always provokable; >0 = never provokes at/above this level
  - roam_speed, roam_radius, chase_speed
  - attack_range, resolve_damage, knockback_force, attack_pause_seconds

DragonSpawnEntry (scripts/data/dragon_spawn_entry.gd, Resource)
  - dragon: DragonDef
  - weight: float             # spawn weight local to one DragonSpawnerNode's roster

DragonSpawnerNode (scripts/dragon_spawner_node.gd, Node2D; scenes/spawners/DragonSpawner.tscn)
  - spawn_zone_path: NodePath  # resolved node's Polygon2D children mark the zone -- see system 19's note on why this is a plain NodePath, not a typed Node export
  - roster: Array[DragonSpawnEntry]
  - count_min, count_max: int
  - min_separation: float
```

- **Four size tiers, small to extra-large, common to rare** (`data/dragons/wyrmling.tres` →
  `drake.tres` → `wyvern.tres` → `ancient_wyrm.tres`). `DragonDef.spawn_weight` runs 10/5/2/1
  respectively — dragged straight onto a `DragonSpawnerNode`'s `roster` array (each entry pairing
  a `DragonDef` with its own local `weight`, defaulted to that global rarity but overridable per
  spawner — a room that wants "70% drakes, 30% wyrmlings" just sets those two entries' weights
  directly), a weighted pick (`DragonSpawnerNode._pick_weighted_entry()`) is what actually turns
  that into "small dragons everywhere, an Ancient Wyrm is a rare, dangerous find." Bigger tiers
  scale up both `provoke_range` and `resolve_damage` together, per design: a larger dragon is
  dangerous from further away *and* hits harder, not just tougher up close.
- **`Dragon`** (`scripts/dragon.gd`, `scenes/Dragon.tscn`, a `CharacterBody2D` on physics layer 3
  "Enemies", mask `Walls` only — no physical collision with the player, every player-facing
  interaction is a plain distance check, not a hitbox) is a small state machine —
  `ROAMING` / `CHASING` / `ATTACK_PAUSE` — driven entirely in `_physics_process`, the same
  "no autoload owns this, the node owns its own behavior" shape `player.gd` uses for movement.
  `DragonSpawnerNode.setup(def, spawn_position)` configures the placeholder `Visual`/
  `CollisionShape2D` size and color from the def and anchors `home_position` for roaming, the same
  runtime-instancing shape `add_grow_plot_interactable()` uses for grow plots.
- **Spawning is owned by `DragonSpawnerNode`, one per zone.** Drop a
  `scenes/spawners/DragonSpawner.tscn` instance into any room scene, link `spawn_zone_path` to a
  `Node2D` whose `Polygon2D` children mark the roaming area, populate `roster`, and set
  `count_min`/`count_max`/`min_separation` — see system 19's note on why this is a plain `NodePath`
  export rather than a typed `Node2D` one. Unlike
  `DragonStashSpawnerNode` (system 19), this node is fully self-contained: dragons are ambient
  hazards with no persisted state and aren't Interactables, so it instances/frees its own `Dragon`
  children directly in `_ready()`/`_respawn()` rather than asking `RoomBuilder` to own the
  lifecycle — no signal round-trip, no wiring step in `RoomBuilder._load_room()`. The Dragons'
  Ground (`scenes/rooms/DragonsGround.tscn`) carries one such spawner linked to the same
  `SpawnZones` container its `DragonStashSpawnerNode` uses, but a future room could have its own
  with a different roster or zone.
- **Position sampling is shared with system 19.** `SpawnZoneUtils.random_point()`
  (`scripts/spawn_zone_utils.gd`) rejection-samples a point inside a randomly chosen zone polygon
  (`Geometry2D.is_point_in_polygon`), rerolling if it lands too close to an already-placed dragon
  from the same spawner this batch (`min_separation`) — the same rejection-sampling shape
  `DragonStashSpawnerNode` uses, but called with no seed (`seed_value` left `null`), so positions
  are freshly rolled from the shared `Rng` autoload every call rather than seeded from an id —
  dragons have nothing that needs to land in the same spot across a save/load the way a stash does.
- **Roaming**: picks a random point within `roam_radius` of `home_position`, walks to it at
  `roam_speed`, waits a random 1–3s, repeats. Every roaming tick also checks whether the player has
  wandered inside the dragon's *effective* provoke range — see below — and provokes into `CHASING`
  if so and the dragon is willing to (`never_provoke_draconology_level`).
- **Draconology skill shrinks how close a dragon senses the player from, and can shut some off
  entirely.** `_effective_provoke_range()` subtracts `PROVOKE_RANGE_PER_DRACONOLOGY_LEVEL` (6.0)
  per player Draconology level from `provoke_range`, floored at `MIN_PROVOKE_RANGE_FRACTION` (25%)
  of the base — a skilled player can walk closer before anything notices. Separately,
  `never_provoke_draconology_level` (only set on the Wyrmling, at 4) means a sufficiently skilled
  player stops provoking that tier *at all*, regardless of distance — "smaller, lower-level dragons
  might not even bother with a skilled player," per design, while every other tier stays provokable
  no matter how skilled the player gets.
- **Chasing and losing sight.** While `CHASING`, the dragon closes at `chase_speed` until either it's
  within `attack_range` (attacks — see below) or the player gets outside an *expanded* range —
  `provoke_range * LOSE_SIGHT_MULTIPLIER` (1.5×, and deliberately the dragon's *base* provoke_range,
  not the skill-shrunk effective one) — at which point it gives up and returns to `ROAMING` from
  wherever it currently is.
- **Landing a hit.** `Dragon._attack()` (only reachable from `CHASING`, once within `attack_range`)
  calls `Player.apply_knockback(global_position, knockback_force)` — pushes the player directly away
  from the dragon and starts their invincibility window — and `Resolve.spend(resolve_damage, ...)`,
  the same failure-event shape Brewing's botched-brew roll uses (system 8). The dragon then enters
  `ATTACK_PAUSE` for `attack_pause_seconds`, standing still — this is the deliberate window that lets
  a hit player actually get away rather than eating repeated hits, not just a cosmetic recovery
  beat. On expiry it resumes `CHASING` if the player's still within the lose-sight range, or drops
  back to `ROAMING` otherwise. `_attack()` also no-ops (dragon just stands still) if the player is
  already invincible, so a dragon that catches up mid-flinch doesn't re-trigger anything.
- **`Player` (`scripts/player.gd`) owns its own knockback/invincibility state**, not `Dragon` — it's
  player state that has to persist independent of which dragon (if any) caused it.
  `apply_knockback()` shoves the player away from the attacker's position with a velocity that
  decays via `move_toward` (`KNOCKBACK_DECAY`) each physics frame, overriding WASD input for as long
  as it's still nonzero, and starts a flat `INVINCIBILITY_SECONDS` (1.2) window during which the
  `Visual` `ColorRect` flashes on/off every `FLASH_INTERVAL` (0.1s) and `apply_knockback()` itself is
  a no-op — both the visual tell and the actual protection, so nothing needs to check
  `is_invincible()` twice. `player.gd` gained a `class_name Player` for this since `Dragon` needs a
  concrete type to call `apply_knockback()`/`is_invincible()` on.
- **Cleared and rerolled every morning, never persisted.** `DragonSpawnerNode._respawn()` is called
  once from `_ready()` (so the zone isn't empty on the very first visit) and wired to
  `Clock.day_started` (every sleep/collapse, same trigger as system 19's stash spawn roll). Unlike
  `Draconology`'s stashes, which persist and only asymptotically approach a population cap, this is
  a hard reset: every existing `Dragon` node this spawner owns is `queue_free()`'d and a fresh
  `Rng.range_i(count_min, count_max)` batch is spawned via the weighted pick above. No save
  contract: `Dragon`/`DragonSpawnerNode` carry no `get_save_data()`, since a loaded save just gets
  a fresh morning-equivalent spawn from each spawner's own `_ready()`.

---

## 22. Summoning / Planar Rift System **[BUILT]**

Gathering extraplanar ingredients (and other outcomes) by reaching through a Planar Rift interactable.
Deadline-based like Brewing/Herbalism, not tethered like the Contract Book or Dragon's Stash — a summon
can run anywhere from minutes to multiple days, so it has to keep advancing while the player is off
doing something else entirely, not just while they stand at the rift.

```
RiftBundleDef (scripts/data/rift_bundle_def.gd, Resource; data/planar_rifts/*.tres)
  - id, display_name
  - sequence                      # Array[String] of symbol ids the minigame must build, see below
  - weight                       # legacy odds from the old random stand-in; unused by the live path
  - duration_minutes
  - ingredient_ids, ingredient_quantities   # BASE reward: always granted, quality-independent
  - material_delta                # base Materials on collection, +/-
  - resolve_delta                 # applied via Resolve.spend()/restore() on collection, +/-
  - scaled_ingredient_ids/_quantities    # quality-SCALED: round(qty * quality) granted on top
  - scaled_material_bonus         # quality-scaled Materials bonus: round(bonus * quality)
  - gated_ingredient_ids/_quantities/_min_quality   # quality-GATED: full qty iff quality >= threshold
  - flavor_text                   # shown in the collection log message

PlanarRiftJob (scripts/data/planar_rift_job.gd, RefCounted)
  - rift_id: String
  - bundle_id: String
  - start_timestamp, ready_timestamp: int
  - status: Status(SUMMONING, READY)
  - quality: float                # 0..1, locked in at sequence completion, scales/gates rewards

Summoning (autoload)
  - _jobs: Dictionary            # rift_id -> PlanarRiftJob
  - _known_bundles: Dictionary   # learned-sequence set (bundle_id -> true), persisted
  - _active_minigame_rift: String  # rift whose minigame is open, "" when none (transient)
  - SUMMONING_SYMBOLS            # const: the 12 symbols (id/name/color), canonical glyph order
```

- **The minigame is "a complex but learnable system of choosing a bundle": a symbol-sequence puzzle.**
  `PlanarRiftMinigamePanel` (`scripts/ui/planar_rift_minigame_panel.gd`, instanced from
  `scenes/ui/PlanarRiftMinigamePanel.tscn` so its portal-timer tunables are inspector-editable, same
  as the ley line panel) is hosted in `MenuScene`. The portal is open and **slowly closing** (a
  countdown, drawn as a depleting rim arc + a dark iris swelling from the center); four symbol options
  sit on the portal rim, and the player picks one with a **movement key** (W/A/S/D or arrows →
  up/right/down/left) to append it to the sequence queue, which then deals four fresh options. Building
  a queue that exactly matches a `RiftBundleDef.sequence` summons that bundle — the panel calls
  `Summoning.complete_rift_minigame(rift_id, bundle_id, time_fraction)`, which rolls the summon's
  quality (see below) and starts the same background job the old random pick did. Pressing **E wipes the queue** but takes `wipe_time` (~0.75s) while the portal keeps
  closing. If the portal shuts first, `Summoning.fail_rift_minigame()` charges `FAIL_RESOLVE_COST` (8)
  Resolve (a mishap event, same shape as a botched brew) and the run ends with nothing. Which bundle
  gets built already fully determines the outcome, so — unlike Demonology/Draconology — there's no
  further roll at collection time; choosing the sequence *is* the whole mechanic.
- **The four options only *sometimes* include a valid continuation.** Each deal has a
  `continuation_chance` (~0.7, inspector export) of seeding one symbol that continues a bundle's
  sequence from the current queue (`_valid_next_symbols()`); the other slots — and the whole deal, the
  rest of the time — are random filler. So knowing a sequence isn't enough: the needed symbol also has
  to come up, or the player wipes (E) and re-deals against the closing portal. That gamble is
  deliberate — it forces guesswork, makes wiping a real decision, and rewards trying unknown symbols to
  discover new combinations. Filler is random, so a continuation can still surface by chance even on a
  deal that didn't seed one (effective odds run a bit above the raw chance); longer sequences
  (`deep_communion`, 6 symbols) are correspondingly much harder to land. **Sequences must be authored
  prefix-free** (no bundle's sequence a prefix of another's, or the shorter always matches first) —
  giving each a distinct *first* symbol satisfies this; the four starting bundles do.
- **Learned-sequence knowledge.** `Summoning._known_bundles` is the set of sequences the player knows,
  listed in the minigame's right-hand **"Known Sequences" reference panel** (each row a bundle's name +
  its sequence as mini-glyphs) which lights up the row the current queue is tracking. A fresh game
  knows only `faint_echo` (seeded in `main.gd._grant_starting_summoning_knowledge()` as a tutorial);
  **successfully building a bundle's sequence blind teaches it** (`complete_rift_minigame` →
  `learn_bundle`), so the known set grows through play. (Dedicated in-game teaching methods beyond
  experimentation stay out of scope.)
- **`PlanarRiftInteractable`** (`scripts/planar_rift_interactable.gd`) is a permanent, hand-placed
  fixture (`scenes/rooms/Orrery.tscn`), same shape as the Brew Station and Contract Book, not a
  spawner-driven one-shot like a Dragon's Stash. `interact()` **opens the minigame** if no rift is running (via
  `Summoning.open_rift_minigame()` → the `rift_minigame_requested` signal → hud.gd opens the panel,
  the same "autoload signal → HUD opens a panel" shape LeyLines uses), collects a ready one, or just
  logs "still summoning" otherwise — the same three-way shape `BrewStationInteractable` uses.
  Its progress bar/ready-popup pair (`set_rift_progress()`/`show_rift_ready()`/`clear_rift_indicator()`)
  is a direct copy of `BrewStationInteractable`'s, since both are Clock-timestamp-deadline jobs;
  `RoomBuilder._sync_rift_indicator()` drives it the same way `_sync_station_indicator()` drives a
  brew station, including the `Clock.minute_tick` hook needed to advance the fill while nothing else
  is happening.
- **The summon has a 0..1 quality, rolled when the sequence completes** and locked onto the job
  (`PlanarRiftJob.quality`, persisted). It's `QUALITY_TIME_WEIGHT`·(portal time still remaining) +
  `QUALITY_ROLL_WEIGHT`·(a Summoning roll), each half, with a small `QUALITY_CRIT_SWING` nudge on a
  natural crit — the same "crit only shifts quality" rule Draconology/Demonology use. The roll is
  `Rng.roll_2d10(Skills.level("summoning"), QUALITY_ROLL_DC)` normalised over the 2d10 span, so
  finishing *fast* and *skilled* both raise quality. `complete_rift_minigame(rift_id, bundle_id,
  time_fraction)` computes it, emits `rift_quality_rolled` (hud.gd renders the dice via the message
  wall, same as Draconology/Transmutation), then starts the job. `Summoning.quality_word()` bands it
  Faint/Fair/Strong/Pristine for log/UI text.
- **Collection applies the bundle's reward scaled and gated by that quality.** Base
  `ingredient_ids`/`material_delta`/`resolve_delta` are the always-granted floor (never blocked by
  insufficient funds — the exchange already happened out on the plane — mirroring Demonology's
  drawbacks always landing). On top: **scaled** rewards grant `round(qty * quality)` (the authored
  number is the quality-1.0 figure) via `scaled_ingredient_*` and `scaled_material_bonus`, and
  **gated** rewards (`gated_ingredient_*` + `gated_ingredient_min_quality`) grant their full quantity
  only once quality clears the paired threshold — the "only a flawless summon brings this through"
  payoffs. The four starting bundles scale up in this respect with their duration/risk: `faint_echo`
  just adds a scaled `rift_glass`, while `deep_communion` (3 days) scales up to +3 `warped_ichor` and
  +15 Materials and gates 2 more `warped_ichor` behind a 0.9 quality.
- **Two new `IngredientDef.Category.EXTRAPLANAR` ingredients** back the initial bundle set:
  `rift_glass` (tier 2) and `warped_ichor` (tier 3), both `source_methods = [SourceMethod.SUMMON]`,
  `buy_price = 0` — only obtainable this way, same as the Ley Line System's spectral ingredients.
  Four starting bundles (`data/planar_rifts/*.tres`) span the design's "5 minutes to multiple days"
  range and a risk/reward spread: `faint_echo` (5 min, small free gain, 4-symbol sequence),
  `modest_exchange` (4h, small Materials/Resolve cost), `generous_tide` (1 day, bigger reward and
  cost), `deep_communion` (3 days, rare and steep, a longer 6-symbol sequence). All four have distinct
  first symbols (prefix-free).
- **Grants `XP_PER_RIFT` (25) Summoning XP on collection.** Of the Summoning skill's
  `summon_range`/`summon_control`/`learn_speed_extraplanar` triplet, **`summon_control` is now live**:
  the minigame adds `seconds_per_control` (~4s) of portal time per point of
  `Skills.get_bonus("summon_control")`, so a steadier summoner holds the portal open longer. The other
  two stay **[STUB]** — `summon_range` (which/how many bundles are reachable) and
  `learn_speed_extraplanar` (ingredient-learning speed) have no consumer yet.
- **Save contract.** Registered in `SaveManager._SAVE_ORDER` right after Draconology. Like
  Brewing/Herbalism, an active job is itself persisted (its deadline is a `Clock.get_timestamp()`
  comparison, valid across a save/load with no special catch-up logic — an already-elapsed rift just
  resolves on the next `minute_tick`), unlike Demonology/Draconology's tethered jobs which are
  deliberately dropped on save. The learned-sequence set (`_known_bundles`) is persisted alongside
  the jobs; the transient minigame session (`_active_minigame_rift`) is not, same as LeyLines.
- **Not in scope for the prototype**: `summon_range`/`learn_speed_extraplanar` effects, dedicated
  in-game sequence-teaching methods beyond blind experimentation, and more than one hand-placed rift.

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
9. ~~Recipe-learning minigame~~ [BUILT] (system 3); remaining ingredient sourcing
   methods; exploration polish
10. VN/relationship layer (systems 12–13) and curse mechanical interventions (system 11)
11. Quest/Journal system (system 15) — reuses the VN expression language, so it slots in
    any time after system 13's expression evaluator exists

## Open Design Questions (not yet decided)

- Shop reputation: `Shop.reputation` is now decremented by botched demonic writs
  (system 17), but nothing reads it as an input yet — sale-chance is still
  flat/price-only. What should move it upward, and how should it weight into
  sale-chance/pricing?
- Exact grade formula (attendance weight vs. exam performance vs. prep actions).
- Resolve regen curve on sleep (full reset vs. partial) and whether any daytime rest
  action should exist in the prototype.
- Target real-world length of a full in-game day (drives `tick_rate` tuning).
