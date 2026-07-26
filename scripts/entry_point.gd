class_name EntryPoint
extends Marker2D
## A named, hand-placed destination within a room that a TransferInteractable
## elsewhere can target by id instead of a raw x,y. See docs/design/systems.md,
## system 12. Moving this marker in the editor moves every Transfer that
## targets entry_id along with it -- the same "single source of truth" a
## room's SpawnPoint already gives the default landing spot. Lives under a
## room's "EntryPoints" container, a sibling of "Interactables"; RoomBuilder
## scans that container in _load_room() to build its room_id -> (entry_id ->
## position) lookup.

@export var entry_id: String = ""
