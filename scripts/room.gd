class_name Room
extends Node2D
## Root script for a hand-authored room scene. See docs/design/systems.md,
## system 12. Children are looked up by fixed name from RoomBuilder:
## Floor/Walls (TileMapLayer), CameraCenter/SpawnPoint (Marker2D),
## Interactables (pre-placed Interactable instances, including Grow Plots).

@export var room_id: String = ""
## Room bounds in pixels, top-left at (0, 0) — used to clamp the follow
## camera so it never shows past the room's walls. Defaults match the
## hand-authored Shop/Bedroom floor size; override per-room if a future
## room is a different size.
@export var room_size: Vector2 = Vector2(704, 576)
## How this room lights itself — see docs/design/systems.md, system 24.
## Defaults to the shared day/night cycle; a windowless or magically-lit room
## overrides with a STATIC LightingProfileDef instead (see Altar.tscn).
@export var lighting_profile: LightingProfileDef = preload("res://data/lighting/default_time_of_day.tres")
