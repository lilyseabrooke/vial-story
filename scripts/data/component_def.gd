@icon("res://assets/editor_icons/icon_upgrade.svg")
class_name ComponentDef
extends Resource
## Static definition of a purchasable, placeable zone component (Alembic,
## Pantry, Accelerator, ...). See docs/design/systems.md, system 4 (Placement
## System). Deliberately zone-type-agnostic — Placement/ComponentInstance
## know nothing about "alembic"/"accelerator" as concepts, only `category`/
## `effect_target` strings, so this same def shape is meant to be reused by a
## future Shop rework, not just the alchemy lab.
##
## Cost is materials_cost (a flat Materials amount, spent via
## Inventory.try_spend_materials()) plus parallel ingredient_ids/
## ingredient_quantities arrays -- mirroring RecipeDef's convention exactly so
## a component's cost stays simple to hand-author as a .tres.
##
## effect_target/effect_amount reuse the same generic pair UpgradeDef/SkillDef
## already use (e.g. "brew_speed") -- only meaningful for a component whose
## category contributes an adjacency bonus (Accelerator); zero/empty is a
## no-op for everything else.

@export var id: String
@export var display_name: String
@export var description: String = ""
@export var icon: Texture2D
## Shifts icon relative to the world node's origin -- see
## InteractableBase.use_texture(). Only needed when the art reaches beyond
## its own footprint (art centered on its footprint leaves this zero).
@export var icon_offset: Vector2 = Vector2.ZERO
## A path rather than a PackedScene export -- a Resource loaded eagerly by
## ContentRegistry._ready() shouldn't also eagerly resolve a nested scene
## dependency at parse time; RoomBuilder loads this lazily instead, only when
## a component is actually placed (_spawn_component_node()).
@export var scene_path: String
@export var footprint: Vector2i = Vector2i(1, 1)
@export var category: String = ""
## Whether this component's world node should block player movement --
## opt-in, since untextured placeholder-box components still read fine as
## walk-through. See InteractableBase.set_solid().
@export var solid: bool = false
## Which zone_types offer this in their Zone Console catalog -- an explicit
## allowlist, so a future Shop zone never lists an Alembic by accident.
@export var zone_types: Array[String] = []

@export var materials_cost: int = 0
@export var ingredient_ids: Array[String] = []
@export var ingredient_quantities: Array[int] = []

@export var effect_target: String = ""
@export var effect_amount: float = 0.0
