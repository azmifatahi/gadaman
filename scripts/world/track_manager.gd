## Endless track: procedural rows, object pooling, collision and speed.
##
## The world never moves the player: the track moves toward the player. Every
## segment, obstacle and cup is recycled from a fixed pool, therefore a 20 minute
## run allocates exactly as much memory as the first 10 seconds. That is the
## single most important property for cheap Android phones (no GC hitches).
##
## Coordinate convention: the player stands at z = 0 and faces -Z, so the track
## flows from -Z toward +Z.
class_name TrackManager
extends Node3D

signal cup_collected(kind: int, at: Vector3)
signal prop_hit(reason_key: String)
signal speed_changed(speed: float)
signal obstacle_smashed(at: Vector3)
signal player_stumbled(reason_key: String)
signal delivery_updated(time_left: float, distance_left: float)
signal delivery_completed(kind: int, elapsed: float)
signal delivery_failed

enum RunMode { ENDLESS, DELIVERY }

const LANE_COUNT := 3
const LANE_WIDTH := 2.4
const SEGMENT_LENGTH := SegmentBuilder.LENGTH
const SEGMENT_COUNT := 6

const BASE_SPEED := 11.0
const MAX_SPEED := 27.0
const SPEED_PER_METER := 0.012

const SPAWN_FRONT := -168.0
const DESPAWN_Z := 14.0
const PROP_POOL_SIZE := 44
const CUP_POOL_SIZE := 68

const START_CLEAR_DISTANCE := 34.0

var speed := BASE_SPEED
var distance := 0.0
var running := false
var run_mode: int = RunMode.ENDLESS
var delivery_kind := PropLibrary.CUP_KARKADEH
var delivery_distance := 0.0
var delivery_time_limit := 0.0
var delivery_time_left := 0.0
var player: PlayerController

var _segments: Array[TrackSegment] = []
var _prop_pool: Array[TrackProp] = []
var _cup_pool: Array[Collectible] = []
var _active_props: Array[TrackProp] = []
var _active_cups: Array[Collectible] = []
var _prop_cursor := 0
var _cup_cursor := 0
var _spawn_cursor := 0.0
var _row_index := 0
var _last_kind := -1
var _speed_penalty := 0.0
var _rng := RandomNumberGenerator.new()
var _segments_root: Node3D
var _objects_root: Node3D
## -1 = rotate through every district, otherwise a fixed SegmentBuilder variant.
## Settings owns the value; the player picks a street in the Settings screen.
var district: int = -1
## The variant currently shown, so a district change can rebuild immediately.
var _current_variant: int = 0
## Density the visible chunks were built with; a quality refresh rebuilds only
## when it actually changes.
var _quality_density: float = -1.0
var _quality_refresh_running: bool = false


func _ready() -> void:
	_rng.randomize()
	_segments_root = Node3D.new()
	_segments_root.name = "Segments"
	add_child(_segments_root)
	_objects_root = Node3D.new()
	_objects_root.name = "Objects"
	add_child(_objects_root)

	for i in SEGMENT_COUNT:
		var seg := TrackSegment.new()
		seg.name = "Segment%d" % i
		_segments_root.add_child(seg)
		seg.position = Vector3(0, 0, -float(i) * SEGMENT_LENGTH)
		seg.apply(i % SegmentBuilder.VARIANT_COUNT, i % SegmentBuilder.CACHE_SLOTS,
				Perf.prop_density)
		_segments.append(seg)

	for i in PROP_POOL_SIZE:
		var prop := TrackProp.new()
		prop.name = "Prop%d" % i
		prop.visible = false
		_objects_root.add_child(prop)
		_prop_pool.append(prop)

	for i in CUP_POOL_SIZE:
		var cup := Collectible.new()
		cup.name = "Cup%d" % i
		cup.visible = false
		_objects_root.add_child(cup)
		cup.set_process(false)
		_cup_pool.append(cup)

	reset_world()


func set_player(node: PlayerController) -> void:
	player = node


func lane_x(lane: int) -> float:
	return (float(clampi(lane, 0, LANE_COUNT - 1)) - 1.0) * LANE_WIDTH


# ---------------------------------------------------------------------------
# Run control
# ---------------------------------------------------------------------------
func start_run() -> void:
	run_mode = RunMode.ENDLESS
	_begin_run()


## Starts a finite delivery stage. UI/mission selection can call this instead
## of start_run without creating another track implementation.
func start_delivery(kind: int, target_distance: float = 850.0, time_limit: float = 72.0) -> void:
	run_mode = RunMode.DELIVERY
	delivery_kind = clampi(kind, 0, 2)
	delivery_distance = maxf(target_distance, 100.0)
	delivery_time_limit = maxf(time_limit, 10.0)
	delivery_time_left = delivery_time_limit
	_begin_run()


## Builds every district mesh / obstacle mesh the run can possibly need, *before*
## `running` flips to true. This is the fix for the freeze that appeared "after
## a distance": the landmark layouts (Bahri 250 m, Mac Nimir 400 m, Shambat
## 650 m) used to be generated on the frame they first scrolled in, which is a
## multi-second main-thread stall on a phone - and the first frame that draws a
## photographic material also pays for its shader compile.
##
## Nothing here runs more than once per density: every call after the first is a
## dictionary lookup, which is why this is cheap enough to call on every start.
func ensure_warm() -> void:
	var built := SegmentBuilder.warm_all(Perf.prop_density)
	var props := PropLibrary.warm_all()
	if built > 0 or props > 0:
		print("[TrackManager] warm-up: %d street meshes + %d prop meshes" % [built, props])
	SegmentBuilder.run_guard = true


## Builds every district mesh up-front without starting a run (the boot path,
## called from World._warm_up once the hardware tier is known).
func warm_for_quality() -> void:
	SegmentBuilder.warm_all(Perf.prop_density)
	PropLibrary.warm_all()


func _begin_run() -> void:
	ensure_warm()
	reset_world()
	speed = BASE_SPEED
	distance = 0.0
	_rng.randomize()
	_row_index = 0
	_speed_penalty = 0.0
	_spawn_cursor = -START_CLEAR_DISTANCE
	running = true
	# Fill the whole visible corridor before the first frame of gameplay.
	var guard := 0
	while _spawn_cursor > SPAWN_FRONT and guard < 200:
		_spawn_row()
		guard += 1
	speed_changed.emit(speed)


func stop_run() -> void:
	running = false


func reset_world() -> void:
	running = false
	for prop in _active_props:
		prop.deactivate()
	_active_props.clear()
	for cup in _active_cups:
		cup.deactivate()
	_active_cups.clear()
	_prop_cursor = 0
	_cup_cursor = 0
	for i in _segments.size():
		_segments[i].position.z = -float(i) * SEGMENT_LENGTH
		if district >= 0:
			_segments[i].apply(district, i % SegmentBuilder.CACHE_SLOTS, Perf.prop_density)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not running:
		return

	# 1. speed ramp: the run gets faster the further you go, asymptotically.
	_speed_penalty = move_toward(_speed_penalty, 0.0, delta * 1.8)
	speed = maxf(BASE_SPEED, minf(MAX_SPEED, BASE_SPEED + distance * SPEED_PER_METER) - _speed_penalty)
	var travel := speed * delta
	distance += travel
	Game.add_distance(travel)

	# 2. move the world
	_scroll_segments(travel)
	_scroll_objects(travel)

	# 3. generate ahead
	_spawn_cursor += travel
	var guard := 0
	while _spawn_cursor > SPAWN_FRONT and guard < 8:
		_spawn_row()
		guard += 1

	# 4. gameplay
	_check_pickups()
	_check_obstacles()
	_update_delivery(delta)


func _update_delivery(delta: float) -> void:
	if run_mode != RunMode.DELIVERY or not running:
		return
	delivery_time_left = maxf(0.0, delivery_time_left - delta)
	var left := maxf(0.0, delivery_distance - distance)
	delivery_updated.emit(delivery_time_left, left)
	if left <= 0.0:
		running = false
		Game.bonus(maxi(250, int(delivery_time_left * 20.0)))
		delivery_completed.emit(delivery_kind, delivery_time_limit - delivery_time_left)
	elif delivery_time_left <= 0.0:
		running = false
		delivery_failed.emit()
		Game.end_run("delivery.timeout")


## Fixed district (-1 = automatic). Rebuilds the visible chunks immediately when
## the player changes it from the pause menu, so the new street appears without
## restarting the run.
func set_district(value: int) -> void:
	district = value
	if value >= 0:
		for i in _segments.size():
			_segments[i].apply(value, i % SegmentBuilder.CACHE_SLOTS, Perf.prop_density)
		_current_variant = value


## Variant for the next recycled chunk.
func _pick_variant() -> int:
	if district >= 0:
		return district
	# Automatic: keep bridges and old Bahri rare enough to feel like landmarks.
	var roll := _rng.randf()
	if distance > 400.0 and roll < 0.18:
		return 4          # Mac Nimir bridge
	if distance > 650.0 and roll < 0.26:
		return 5          # Shambat bridge
	if distance > 250.0 and roll < 0.38:
		return 6          # old Bahri shopfronts
	return [0, 0, 2, 3, 1][_rng.randi_range(0, 4)]   # street / corniche / houses / market


func _scroll_segments(travel: float) -> void:
	for seg in _segments:
		seg.position.z += travel
		if seg.position.z > SEGMENT_LENGTH:
			seg.position.z -= SEGMENT_LENGTH * float(SEGMENT_COUNT)
			# Re-roll the layout so the street never visibly repeats.
			seg.apply(_pick_variant(), _rng.randi_range(0, SegmentBuilder.CACHE_SLOTS - 1),
					Perf.prop_density)


func _scroll_objects(travel: float) -> void:
	for prop in _active_props:
		prop.position.z += travel
	for cup in _active_cups:
		cup.position.z += travel

	# Recycle anything behind the camera. Iterate backwards so removal is safe.
	for i in range(_active_props.size() - 1, -1, -1):
		if _active_props[i].position.z > DESPAWN_Z:
			_release_prop(_active_props[i], i)
	for i in range(_active_cups.size() - 1, -1, -1):
		if _active_cups[i].position.z > DESPAWN_Z:
			_release_cup(_active_cups[i], i)


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------
func _spawn_row() -> void:
	_row_index += 1
	var z := _spawn_cursor
	var difficulty := clampf((speed - BASE_SPEED) / (MAX_SPEED - BASE_SPEED), 0.0, 1.0)

	# Gap scales with speed so the player always gets a constant ~0.6 s to react.
	var gap := clampf(speed * 0.62, 9.5, 20.0) + _rng.randf_range(0.0, 2.0)
	_spawn_cursor -= gap

	# Breather rows: the first metres of a run are always clean.
	var is_breather := _row_index <= 2 or _rng.randf() < 0.10
	if is_breather:
		_spawn_cup_line(_rng.randi_range(0, LANE_COUNT - 1), z)
		return

	var lanes := [0, 1, 2]
	_shuffle(lanes)
	var blocked_count := 1
	if _rng.randf() < 0.12 + 0.42 * difficulty:
		blocked_count = 2
	var blocked: Array = lanes.slice(0, blocked_count)
	var free: Array = lanes.slice(blocked_count, lanes.size())
	var jump_lane := -1

	for lane in blocked:
		var kind := _pick_kind()
		var data := PropLibrary.info(kind)
		_spawn_prop(kind, int(lane), z - float(data.get("depth_half", 0.5)))
		if int(data.get("pass", PropLibrary.PASS_DODGE)) == PropLibrary.PASS_JUMP:
			jump_lane = int(lane)

	# Cups sit where the player can actually reach them:
	#  * an arc over a jumpable obstacle (risk = reward), or
	#  * a line in a free lane on the safe path.
	if jump_lane >= 0 and _rng.randf() < 0.55:
		_spawn_cup_arc(jump_lane, z)
	elif not free.is_empty() and _rng.randf() < 0.72:
		_spawn_cup_line(int(free[_rng.randi_range(0, free.size() - 1)]), z)


func _pick_kind() -> int:
	var roll := _rng.randf()
	var kind := PropLibrary.BARRIER
	if roll < 0.24:
		kind = PropLibrary.BARRIER
	elif roll < 0.38:
		kind = PropLibrary.POTHOLE
	elif roll < 0.52:
		kind = PropLibrary.CRATES
	elif roll < 0.66:
		kind = PropLibrary.LOW_BAR
	elif roll < 0.80:
		kind = PropLibrary.CART
	elif roll < 0.90:
		kind = PropLibrary.BUS
	else:
		kind = PropLibrary.TABLE
	# Never the same obstacle twice in a row: variety reads as "designed".
	if kind == _last_kind:
		kind = PropLibrary.LOW_BAR if kind != PropLibrary.LOW_BAR else PropLibrary.BARRIER
	_last_kind = kind
	return kind


func _spawn_prop(kind: int, lane: int, z: float) -> void:
	if _prop_pool.is_empty():
		return
	# Reuse a free slot; if the pool is exhausted, skip this prop (never allocate).
	var prop: TrackProp = null
	for i in _prop_pool.size():
		var idx := (_prop_cursor + i) % _prop_pool.size()
		if not _prop_pool[idx].active:
			prop = _prop_pool[idx]
			_prop_cursor = (idx + 1) % _prop_pool.size()
			break
	if prop == null:
		return
	prop.activate(kind, lane, lane_x(lane), z)
	_active_props.append(prop)


func _spawn_cup_line(lane: int, z: float) -> void:
	var count := _rng.randi_range(3, 5)
	var kind := _rng.randi_range(0, 2)
	for i in count:
		_spawn_cup(kind, lane, z + 3.0 + float(i) * 2.3, 0.95)


## A 3-5 cup arc shaped like the jump trajectory, hovering over the obstacle.
func _spawn_cup_arc(lane: int, z: float) -> void:
	var count := 5
	var kind := _rng.randi_range(0, 2)
	for i in count:
		var t := float(i) / float(count - 1)
		var height := 0.95 + sin(t * PI) * 1.45
		_spawn_cup(kind, lane, z + 2.6 + t * 5.4, height)


func _spawn_cup(kind: int, lane: int, z: float, y: float) -> void:
	if _cup_pool.is_empty():
		return
	var cup: Collectible = null
	for i in _cup_pool.size():
		var idx := (_cup_cursor + i) % _cup_pool.size()
		if not _cup_pool[idx].active:
			cup = _cup_pool[idx]
			_cup_cursor = (idx + 1) % _cup_pool.size()
			break
	if cup == null:
		return
	cup.activate(kind, lane_x(lane), y, z)
	_active_cups.append(cup)


func _release_prop(prop: TrackProp, index: int) -> void:
	prop.deactivate()
	var last := _active_props.size() - 1
	if index != last:
		_active_props[index] = _active_props[last]
	_active_props.resize(last)


func _release_cup(cup: Collectible, index: int) -> void:
	cup.deactivate()
	var last := _active_cups.size() - 1
	if index != last:
		_active_cups[index] = _active_cups[last]
	_active_cups.resize(last)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


# ---------------------------------------------------------------------------
# Collision (cheap AABB-ish checks - no physics engine involved)
# ---------------------------------------------------------------------------
func _check_obstacles() -> void:
	if player == null or not player.is_controllable():
		return
	var px: float = player.position.x
	var feet: float = player.position.y
	var sliding: bool = player.is_sliding

	for prop in _active_props:
		var dz: float = prop.position.z
		if dz < -(prop.depth_half + 1.2) or dz > prop.depth_half + 1.2:
			continue
		if absf(prop.position.x - px) > prop.half_width + 0.36:
			continue
		if prop.is_passed_by(feet, sliding):
			continue
		# Recovery grace prevents one obstacle from immediately escalating to death.
		if not player.can_take_hit():
			continue
		# Cardboard/wooden cargo becomes a chest-bump set-piece at sprint speed.
		if prop.kind == PropLibrary.CRATES and player.can_smash_soft_obstacle():
			var hit_pos := prop.global_position
			var idx := _active_props.find(prop)
			if idx != -1:
				_release_prop(prop, idx)
			player.smash()
			Game.bonus(35)
			obstacle_smashed.emit(hit_pos)
			return
		# Small mistakes cost momentum and trigger a recovery, not the whole run.
		if prop.kind in [PropLibrary.BARRIER, PropLibrary.POTHOLE] and player.can_take_hit():
			var reason := prop.reason_key()
			var idx := _active_props.find(prop)
			if idx != -1:
				_release_prop(prop, idx)
			player.stumble()
			_speed_penalty = maxf(_speed_penalty, 4.5)
			speed = maxf(BASE_SPEED, speed - _speed_penalty)
			player_stumbled.emit(reason)
			return
		_trigger_hit(prop)
		return


func _trigger_hit(prop: TrackProp) -> void:
	running = false
	Game.end_run(prop.reason_key())
	prop_hit.emit(prop.reason_key())


func _check_pickups() -> void:
	if player == null:
		return
	var px: float = player.position.x
	var feet: float = player.position.y
	var head: float = feet + (0.9 if player.is_sliding else 1.75)

	for cup in _active_cups:
		if absf(cup.position.z) > 1.0:
			continue
		if absf(cup.position.x - px) > 0.95:
			continue
		if cup.position.y < feet - 0.35 or cup.position.y > head + 0.35:
			continue
		cup.deactivate()
		var idx := _active_cups.find(cup)
		if idx != -1:
			var last := _active_cups.size() - 1
			if idx != last:
				_active_cups[idx] = _active_cups[last]
			_active_cups.resize(last)
		Game.collect_cup(cup.kind)
		cup_collected.emit(cup.kind, cup.position)
		return


## Rebuild every segment's surface materials after the photo-art switch flips.
func refresh_photo_materials() -> void:
	for seg in _segments:
		seg.refresh_materials()


## Re-apply quality-dependent visuals (density, shadow casting, shader variant).
##
## A density change invalidates every cached district mesh, so this is spread
## over frames (one chunk per frame) instead of re-generating six chunks - and
## therefore stalling the whole app - inside a single frame. `process_frame`
## keeps firing while the tree is paused, which is exactly when the player flips
## the preset (the settings panel pauses the game).
func refresh_quality() -> void:
	var density: float = Perf.prop_density
	if _quality_refresh_running and is_equal_approx(density, _quality_density):
		return
	_quality_density = density
	_quality_refresh_running = true
	# Warming is intentional work, not a mid-run allocation bug: keep it out of
	# the guard counter the soak test asserts on.
	var guard := SegmentBuilder.run_guard
	SegmentBuilder.run_guard = false
	SegmentBuilder.warm_all(density)
	SegmentBuilder.run_guard = guard
	for seg in _segments:
		seg.apply(seg.variant, seg.mesh_slot, density)
		await get_tree().process_frame
	for prop in _active_props:
		prop.apply_quality()
	# Only the new density is still reachable: free the rest.
	SegmentBuilder.prune_density(density)
	_quality_refresh_running = false


## One-line runtime state for the CI soak test and bug reports.
func debug_stats() -> String:
	return "distance=%.0f speed=%.1f segments=%d props=%d cups=%d %s" % [
		distance, speed, _segments.size(), _active_props.size(),
		_active_cups.size(), SegmentBuilder.stats()]


## Advances the world by `meters` without waiting for real time.
##
## Used by the CI soak test: 6 km of track in a fraction of a second exercises
## hundreds of segment recycles and thousands of prop respawns, which is the
## only way to prove "a long run allocates nothing" on a build server.
func soak(meters: float, step: float = 0.5) -> void:
	var remaining := meters
	while remaining > 0.0:
		var dt := minf(step, remaining)
		var travel := speed * dt
		distance += travel
		_scroll_segments(travel)
		_scroll_objects(travel)
		_spawn_cursor += travel
		var guard := 0
		while _spawn_cursor > SPAWN_FRONT and guard < 8:
			_spawn_row()
			guard += 1
		remaining -= dt


func active_prop_count() -> int:
	return _active_props.size()


func active_cup_count() -> int:
	return _active_cups.size()
