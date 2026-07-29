class_name CustomerDirector
extends Node
## Presentation-only layer over Shop's always-on customer-visit simulation.
## See docs/design/systems.md, system 5.
##
## Not a scene -- code-instanced by RoomBuilder.build_rooms() the same way
## NPCDirector is. Shop.active_visits is the single source of truth for
## which visits exist and how they resolve; this class only decides whether
## a given visit is currently worth drawing a CustomerInteractable for, and
## keeps that sprite in sync with the (already-decided) resolution. Nothing
## here ever calls into Shop's purchase-resolution API -- see shop.gd.

const CUSTOMER_INTERACTABLE_SCENE := preload("res://scenes/interactables/CustomerInteractable.tscn")

## Room-clutter cap on simultaneous *sprites* -- Shop keeps simulating every
## active visit regardless of this; it only limits how many are ever drawn
## at once.
const MAX_VISIBLE_CUSTOMERS := 3

var room_builder: RoomBuilder

var _visible: Dictionary = {}   # visit_id -> CustomerInteractable


func setup(builder: RoomBuilder) -> void:
	room_builder = builder
	Shop.customer_visit_started.connect(_on_visit_started)
	Shop.customer_visit_resolved.connect(_on_visit_resolved)


## Called by RoomBuilder.switch_room() whenever the Shop becomes the active
## room -- shows every visit already in progress (started while the player
## was elsewhere) that isn't already visualized, up to the visible cap.
## There's no "still walking in" concept in Shop's model (see shop.gd), so a
## visit picked up here always spawns already browsing.
func on_shop_room_activated() -> void:
	_reconcile_visible_with_active_visits()
	for visit in Shop.active_visits:
		if _visible.size() >= MAX_VISIBLE_CUSTOMERS:
			return
		if not _visible.has(visit.visit_id):
			_spawn(visit, true)


## Defensive cleanup, run on every Shop-room entry: a _visible entry whose
## visit_id no longer has a matching Shop.active_visits entry means its
## CustomerInteractable missed the customer_visit_resolved signal somehow
## (this actually happened -- see the long comment on
## CustomerInteractable.on_visit_resolved() for the specific bug that caused
## it) and is stuck wandering forever, permanently occupying one of
## MAX_VISIBLE_CUSTOMERS' slots and starving out every future customer. Since
## on_visit_resolved() is now unconditional/idempotent, just calling it again
## here is enough to send a stray sprite walking out properly whatever the
## original cause.
func _reconcile_visible_with_active_visits() -> void:
	var active_ids := {}
	for visit in Shop.active_visits:
		active_ids[visit.visit_id] = true
	for visit_id in _visible.keys():
		if active_ids.has(visit_id):
			continue
		var interactable: CustomerInteractable = _visible[visit_id]
		if is_instance_valid(interactable):
			interactable.on_visit_resolved()
		else:
			_visible.erase(visit_id)


func _on_visit_started(visit: Dictionary) -> void:
	if room_builder.current_room_id != RoomBuilder.SHOP_ROOM_ID:
		return
	if _visible.size() >= MAX_VISIBLE_CUSTOMERS:
		return
	_spawn(visit, false)


func _on_visit_resolved(visit: Dictionary, _purchased: Array) -> void:
	var interactable: CustomerInteractable = _visible.get(visit.visit_id)
	if interactable != null:
		interactable.on_visit_resolved()


func _spawn(visit: Dictionary, already_browsing: bool) -> void:
	var room := room_builder.get_room(RoomBuilder.SHOP_ROOM_ID)
	if room == null:
		return
	var entry_point := room.get_node_or_null("CustomerSpawnPoint")
	if entry_point == null:
		push_warning("CustomerDirector: Shop room is missing CustomerSpawnPoint")
		return
	var browse_points := _browse_points_for_room(room)
	if browse_points.is_empty():
		push_warning("CustomerDirector: Shop room's CustomerBrowsePoints container has no points")
		return

	var interactable: CustomerInteractable = CUSTOMER_INTERACTABLE_SCENE.instantiate()
	room.get_node("Interactables").add_child(interactable)
	room_builder.wire_interactable(interactable)
	interactable.bind_visit(visit, entry_point.position, browse_points, already_browsing)
	interactable.despawn_requested.connect(_on_despawn_requested)

	_visible[visit.visit_id] = interactable


## Every Marker2D (or Node2D) child of the room's CustomerBrowsePoints
## container counts as a browse point -- drag as many in (or move the
## existing ones) as a room needs, no script changes required. Read fresh
## per spawn rather than cached, so editing point placement in the editor
## takes effect on the next customer without a restart.
func _browse_points_for_room(room: Room) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var container := room.get_node_or_null("CustomerBrowsePoints")
	if container == null:
		return points
	for child in container.get_children():
		if child is Node2D:
			points.append(child.position)
	return points


func _on_despawn_requested(interactable: CustomerInteractable) -> void:
	_visible.erase(interactable.visit.get("visit_id"))
	interactable.queue_free()
