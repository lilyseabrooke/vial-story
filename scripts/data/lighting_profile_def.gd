class_name LightingProfileDef
extends Resource
## Static definition of how a Room lights itself. See docs/design/systems.md,
## system 24. One .tres per lighting "look" (outdoor day/night cycle, a
## windowed interior that only gets a hint of it, a windowless basement or
## magic space with none at all) — Room.lighting_profile points at one, same
## hand-authored-resource convention as RecipeDef/SkillDef.
##
## Lighting is graded as a shadow/highlight split (see shaders/
## day_night_grading.gdshader), not a single flat tint — shadow_*/highlight_*
## only pull toward each other's color in proportion to how dark/bright a
## given pixel already is, so a moody night tint darkens shadows without
## crushing anything already lit, and contrast controls how hard that split
## is pushed independently of the colors themselves.

## Sampled at Clock.minute_of_day() / 1439.0. A gradient authored with a
## brief spike key at dawn/dusk between the flat night/day keys *is* the
## golden-hour pulse — no separate mechanism needed. Left unset (null) is
## fine for a room with time_of_day_strength == 0 — nothing ever samples them.
@export var day_night_shadow_gradient: Gradient
@export var day_night_highlight_gradient: Gradient
## Contrast multiplier over the same 0..1 day fraction — typically peaks at
## golden hour/midday for visual "pop" and eases off at night for a flatter,
## moodier look.
@export var contrast_curve: Curve

## How much of the sampled time-of-day values above show through, blended
## against the base_* values below: 0.0 = fully base (a windowless room, or a
## magically-lit space with its own static ambience, same as the old STATIC
## mode), 1.0 = fully time-of-day (open-air outdoor rooms), and anywhere
## between for e.g. a small room with one window that should only catch a
## hint of the outside cycle.
@export_range(0.0, 1.0) var time_of_day_strength: float = 1.0
## The room's own baseline look — always present, and the only thing that
## matters at time_of_day_strength == 0.
@export var base_shadow_color: Color = Color.WHITE
@export var base_highlight_color: Color = Color.WHITE
@export var base_contrast: float = 1.0

## How long RoomLighting eases toward newly-sampled values on an ordinary
## minute-tick re-sample. Room-switch transitions use this as their "settle"
## leg instead — see RoomLighting.set_profile()'s overshoot-then-settle shape.
@export var transition_seconds: float = 1.5
