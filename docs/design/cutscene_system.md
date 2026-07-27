# Cutscene / Staged-Movement System **[PLANNED — not yet built]**

Extends system 13 (VN / Relationship System) in `docs/design/systems.md` to let a `.vnscript`
scene move real actors (the player, love interests) around real rooms — walking between rooms,
facing directions, panning the camera, playing one-shot animations/effects, changing an
interactable's appearance, and screen effects (fade/flash/shake) — interleaved with the
dialogue lines and `CALL` actions the VN engine already supports. Everything below is a plan to
build against, not current behavior; update the status banner and fold the relevant parts back
into system 13 once it's built, same convention as every other system in `systems.md`.

Motivating example (from design discussion): the player meets Lyra in the Shop, the two of them
walk up to the Bedroom together, talk along the way, and by the end a flag is set that changes
the Art Studio interactable's appearance and unlocks it — a single `.vnscript` scene driving both
dialogue and world staging, triggered by the same data-driven condition/priority mechanism every
other VN scene already uses.

## Prerequisites

Nothing below should be started until these are in place — each is a blocker for a specific part
of the spec, noted inline.

- **Facing-direction convention decided: 4-directional or 8-directional.** Blocks sprite
  authoring and the `FACE`/movement-driven animation-state mapping. Changing this later means
  re-cutting every sprite sheet, so decide before any art is drawn.
- **Idle + walk sprites for the PC and all 5 love interests** (callie, larissa, haerin, zara,
  lyra), cut per the facing convention above.
- **Real sprites on `Player` and `NPCInteractable`, replacing their current placeholder
  `ColorRect` visual.** Neither has an `AnimatedSprite2D`/`Sprite2D` today — this is a
  prerequisite for any `ANIMATE` command or idle/walk state to have something to drive.
- **A shared idle/walk/facing-direction animation-state helper**, used by both `Player` and
  `NPCInteractable` — both already compute a per-frame velocity vector, so the state logic
  (velocity → facing + idle/walk clip) is naturally one reusable piece rather than duplicated.
- **`DialogueRunner`'s instruction loop generalized to suspend on any pending async task, not
  just `SHOW_LINE`/`SHOW_CHOICE`.** Currently every other instruction resolves synchronously
  inline within one `advance()` call. Blocking cutscene commands (see below) need the same
  "suspend until a completion signal fires" treatment `SHOW_LINE` already gets.
- **An actor resolver**: `actor_id` (`"player"`, or an `npc_id`) → the node currently
  representing them. Player is a single persistent node; NPCs are reparented room-to-room by
  `NPCDirector` and only present in a room if `NPCScheduler` currently has them scheduled there
  — a cutscene needs to pull an NPC into a specific room regardless of their schedule, and hand
  them back to `NPCScheduler` when the scene ends.
- **A controllable camera API.** `RoomBuilder` builds a plain `Camera2D` (`room_builder.gd:121`)
  with no pan/follow-toggle methods today; `CAMERA_PAN`/`CAMERA_FOLLOW` need at least
  start-pan-to-point and resume-follow-player exposed.
- **A `Marker2D` naming convention for cutscene destinations**, placed in room scenes (e.g.
  `"bedroom_art_station"`), so scripts reference named points instead of hardcoded coordinates.
- **`day_number()` added to `VNExpressionEvaluator._call_function()`** (a one-line case mirroring
  the existing `minute_of_day()` one) — needed by any trigger gated on "day 5 or later," which
  the motivating example above requires and the language doesn't expose yet.

## Addressing scheme

- **`actor_id`** — `"player"` or any `npc_id` `NPCScheduler`/`NPCState` already use.
- **Position markers** — a `Marker2D`'s string name, scoped to the room it's placed in. Commands
  that cross rooms take a `room_id` + marker name pair.
- **`object_id`** — reuses `Interactable`'s existing `target_id` for `SHOW`/`HIDE`/
  `SET_APPEARANCE`, so no new id system is needed for interactables.

## Command vocabulary

New `.vnscript` instructions, compiled by `VNScriptCompiler` alongside the existing
`STAGE_*`/`CALL`/dialogue instructions.

**Movement**
- `MOVE(actor_id, room_id, marker)` — walk to a point, crossing rooms if needed. Blocks by
  default (see async model below).
- `WARP(actor_id, room_id, marker)` — instant teleport, no walk animation.
- `FACE(actor_id, direction)` — snap facing without moving.

**Camera**
- `CAMERA_PAN(marker_or_actor, duration)` — pans and blocks until arrived.
- `CAMERA_FOLLOW()` — resumes normal follow-player behavior.
- `CAMERA_ZOOM(value, duration)` — deferred to a later pass; not required for the first version.

**Animation / effects**
- `ANIMATE(actor_id, animation_name)` — plays a one-shot clip on an actor. Blocking optional per
  call (some one-shots matter to wait for, most don't).
- `SPAWN_EFFECT(effect_id, marker_or_actor)` — transient scene-attached VFX with no actor
  identity. Always non-blocking. Deliberately a separate command from `ANIMATE` rather than
  folded into it, since effects have no persistent actor to mutate.
- `PLAY_SOUND(sound_id)` — always non-blocking.

**Visibility / appearance**
- `SHOW(object_id)` / `HIDE(object_id)` — toggle visibility on any actor or interactable
  addressable by id.
- `SET_APPEARANCE(object_id, state_name)` — swaps an interactable's sprite/frame/tint by a named
  state the object itself defines (state → asset mapping lives on the object, not the script).
  This is the mechanism for "the Art Studio looks different now." A permanent unlock additionally
  needs a `CALL set_flag(...)` alongside it in the script, since appearance should re-derive from
  the flag on scene/room reload, not from having played the cutscene once.

**Popups**
- Dialogue-shaped text keeps using `SHOW_LINE`/`SHOW_CHOICE`. A non-blocking floating popup
  independent of the dialogue box (e.g. "+5 Affection") is a separate `POPUP(text,
  marker_or_actor, duration)` command.

**Screen effects**
- `FADE(direction, duration, color)` — blocks.
- `FLASH(color, duration)` — non-blocking or short-blocking.
- `SHAKE(intensity, duration)` — non-blocking.

**Control flow**
- `WAIT(duration)` — explicit pause between beats. Blocks.

## Async execution model

Default is blocking/sequential (least surprising for a linear beat-by-beat script). Getting
"dialogue plays while an actor keeps walking" needs three pieces:

1. **Blocking is per-command, async is an explicit opt-in on the authored line**, e.g.
   `MOVE ASYNC lyra bedroom bedroom_art_station`. An async `MOVE` starts the walk and returns
   control to the instruction pointer immediately; the very next line (say, `SHOW_LINE`) then
   blocks on player input as it already does today, independently of the walk still running.
   `SPAWN_EFFECT`/`PLAY_SOUND` don't need the modifier — they're always fire-and-forget.
2. **In-flight async work is tracked as a handle per actor** — a `Dictionary[actor_id, Signal]`
   (or equivalent) on the cutscene runner. A new async command on an actor that already has one
   pending replaces/cancels it rather than queuing — an actor only ever has one async task in
   flight at a time.
3. **`JOIN(actor_id)` is the explicit sync point** — suspends the instruction pointer (same
   mechanism as `SHOW_LINE`) until that actor's tracked task resolves. A blocking `MOVE` is sugar
   for `MOVE ASYNC` immediately followed by an implicit `JOIN` on the same actor — exactly one
   thing ever suspends the pointer: an unresolved async future, whether that's "waiting for the
   player to click through a line" or "waiting for an actor's walk to finish."

**On `END` (scene closes with async work still pending): snap to destination.** Every actor with
an in-flight task has its tween/movement force-completed and control handed back to whatever
owns them normally (`NPCScheduler` for NPCs, player input for the player) — never left to keep
resolving after the dialogue box has closed.

## Triggering (unchanged from system 13)

No new triggering mechanism — a cutscene is just a `.vnscript` scene registered the normal way:
a `SceneTriggerDef` `.tres` (`condition`, `priority`, `repeatable`) with its path added to
`SceneDirector.TRIGGER_PATHS`. `RoomBuilder.switch_room()` already calls `SceneDirector.recheck()`
on every room change, so a room-entry-gated cutscene (e.g. "on entering the Shop, day ≥ 5,
Lyra's affection ≥ 1") needs no new wiring — only the `day_number()` evaluator function noted
under Prerequisites.

## Build order

1. Facing-direction decision, then sprite assets + `Player`/`NPCInteractable` sprite swap +
   shared animation-state helper.
2. Generalize `DialogueRunner`'s suspend model to any pending async task (not just
   `SHOW_LINE`/`SHOW_CHOICE`).
3. Actor resolver + `Marker2D` convention + camera pan/follow API.
4. `day_number()` evaluator function.
5. The commands themselves: movement (`MOVE`/`WARP`/`FACE`) and `JOIN`/async model first, since
   everything else is comparatively mechanical once the suspend model and actor resolver exist;
   then camera, animation/effects, visibility/appearance, screen effects, popups.
6. One worked example scene (mirroring how system 13 used `kaelith_greeting.vnscript` and the
   Mira demo NPC to prove the base VN pipeline end-to-end) — likely the Lyra/Art Studio scene
   from the motivating example above, since it exercises every command category at once.

## Open questions (deferred, not blocking)

- `CAMERA_ZOOM` — worth adding once a real use case needs it; no camera zoom exists anywhere yet.
- Whether an actor's async task can ever legitimately be interrupted by player action mid-scene
  (e.g. closing the game) rather than only by scene `END` — current assumption is no, since
  `Clock.is_paused` during a scene already blocks normal player input the same way `MenuScene`
  does.
