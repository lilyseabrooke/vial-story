class_name SpawnZoneUtils
extends RefCounted
## Shared rejection-sampling helper for spawner nodes that scatter instances
## across a hand-drawn zone -- a linked Node2D whose Polygon2D children mark
## the eligible area, the same "designer-drawn shapes, not a tileset
## parameter" approach system 19/21 originally used inline in RoomBuilder.
## DragonSpawnerNode and DragonStashSpawnerNode both call random_point()
## instead of each keeping their own copy of this logic.

const MAX_ATTEMPTS := 64


## Picks a point inside one of zone's Polygon2D children, at least
## min_separation from every position in `occupied`, retrying up to
## MAX_ATTEMPTS times before falling back to the first polygon's bounds
## center. Returns Vector2.ZERO if zone has no Polygon2D children.
##
## seed_value == null rolls from the shared Rng autoload (fresh every call --
## what roaming dragons want, since their positions are never persisted).
## Passing a seed_value (e.g. hash(stash_id)) draws from a locally seeded
## RandomNumberGenerator instead, so the same id always lands in the same
## spot across a save/load, without touching Rng's save-tracked stream.
static func random_point(zone: Node2D, min_separation: float, occupied: Array[Vector2], seed_value: Variant = null) -> Vector2:
	var polygons: Array[Polygon2D] = []
	if zone != null:
		for child in zone.get_children():
			if child is Polygon2D:
				polygons.append(child)
	if polygons.is_empty():
		return Vector2.ZERO

	var local_rng: RandomNumberGenerator = null
	if seed_value != null:
		local_rng = RandomNumberGenerator.new()
		local_rng.seed = seed_value

	var fallback := polygons[0]
	for attempt in MAX_ATTEMPTS:
		var polygon: Polygon2D
		if local_rng:
			polygon = polygons[local_rng.randi() % polygons.size()]
		else:
			polygon = polygons[Rng.range_i(0, polygons.size() - 1)]

		var bounds := _polygon_bounds(polygon.polygon)
		var candidate_local: Vector2
		if local_rng:
			candidate_local = Vector2(
				local_rng.randf_range(bounds.position.x, bounds.end.x),
				local_rng.randf_range(bounds.position.y, bounds.end.y)
			)
		else:
			candidate_local = Vector2(
				Rng.range_f(bounds.position.x, bounds.end.x),
				Rng.range_f(bounds.position.y, bounds.end.y)
			)

		if not Geometry2D.is_point_in_polygon(candidate_local, polygon.polygon):
			continue
		var candidate_world := polygon.position + candidate_local
		if _far_enough(candidate_world, occupied, min_separation):
			return candidate_world

	return fallback.position + _polygon_bounds(fallback.polygon).get_center()


static func _polygon_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


static func _far_enough(candidate: Vector2, occupied: Array[Vector2], min_separation: float) -> bool:
	for pos in occupied:
		if pos.distance_to(candidate) < min_separation:
			return false
	return true
