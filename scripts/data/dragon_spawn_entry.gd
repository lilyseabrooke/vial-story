class_name DragonSpawnEntry
extends Resource
## One weighted roster entry in a DragonSpawnerNode. Pairs a DragonDef with a
## spawn weight local to that spawner -- unlike DragonDef.spawn_weight (that
## tier's global rarity), this lets the same DragonDef be common in one
## spawner's roster and rare (or absent) in another's.

@export var dragon: DragonDef
@export var weight: float = 1.0
