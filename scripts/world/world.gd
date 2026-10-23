## Scene orchestrator: builds the dusk lighting, wires the systems together and
## translates UI intents into run lifecycle calls.
##
## Everything gameplay-related lives in a dedicated node (Track, Player, FX, UI);
## this script is only the glue, which keeps each system independently testable.
extends Node3D

@onready var world_environment: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun
@onready var track: TrackManager = $Track
@onready var player: PlayerController = $Player
@onready var camera_rig: CameraRig = $CameraRig
@onready var fx: Fx = $FX
@onready var ui: UiRoot = $UI

var _environment: Environment
var _suit_probe: ReflectionProbe
## Second, shadowless directional light: the warm bounce off the dusty street.
## Without it every wall that faces away from the low sun went black, which is
## what made the photographic facades read as flat cardboard.
var _bounce: DirectionalLight3D


func _ready() -> void:
	# _setup_lighting() creates the skyline too (see _apply_sky), so the two paths
	# cannot add the band twice.
	_setup_lighting()
	_setup_suit_reflections()
	track.set_player(player)
	player.track = track
	camera_rig.setup(player, track)

	track.prop_hit.connect(_on_prop_hit)
	track.cup_collected.connect(_on_cup_collected)
	track.obstacle_smashed.connect(_on_obstacle_smashed)
	track.player_stumbled.connect(_on_player_stumbled)
	player.landed.connect(_on_player_landed)
	player.slide_started.connect(_on_player_slide)
	player.action_intensity_changed.connect(camera_rig.set_action_intensity)
	ui.play_requested.connect(_on_play_requested)
	ui.restart_requested.connect(_on_play_requested)
	ui.resume_requested.connect(_on_resume_requested)
	ui.menu_requested.connect(_on_menu_requested)
	ui.milestone_passed.connect(_on_milestone)
	ui.control_pressed.connect(_on_control_pressed)
	Perf.tier_changed.connect(_on_tier_changed)
	Settings.changed.connect(_on_setting_changed)

	_to_menu()
	Audio.play_music()
	_warm_up()
	# First launch: explain the four gestures before the run starts. Automated
	# sessions (CI smoke test / screenshots) skip it so they measure the game.
	var automated := "--smoke" in OS.get_cmdline_user_args() or \
			"--screenshot" in OS.get_cmdline_user_args()
	if not Settings.tutorial_seen and not automated:
		ui.open_howto()

	if "--smoke" in OS.get_cmdline_user_args():
		_run_smoke_test()
	if "--screenshot" in OS.get_cmdline_user_args():
		_run_screenshot_session()


# ---------------------------------------------------------------------------
# Boot warm-up
# ---------------------------------------------------------------------------
## Everything expensive is built while the menu is up: the 21 district meshes,
## the obstacle + cup meshes, and every photographic material (which is what
## actually decodes the JPEGs and compiles the shaders). Two frames are awaited
## first so `Perf` has resolved the hardware tier and its density - building
## with the wrong density would just have to be thrown away.
func _warm_up() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var started := Time.get_ticks_msec()
	var materials := MeshKit.warm_materials()
	track.warm_for_quality()
	print("[Warmup] %d materials, %s, %d ms" % [
		materials, SegmentBuilder.stats(), Time.get_ticks_msec() - started])
	await _warm_shaders()


## Draws every material once, off to the side of the camera, behind the menu.
##
## This is the part of the freeze that has nothing to do with meshes: on Android
## GLES3 a *shader* is compiled the first time a material is drawn, and the
## photographic surfaces (asphalt with normal + roughness, water, truss steel,
## the three facades, the foliage cut-outs) each cost a visible stall - a second
## or more on a mid-range phone. They all first appeared 250-650 m into a run,
## which is exactly "the game hangs after a distance".
##
## One tiny quad per material for two frames compiles all of them while the menu
## is still up, so a run never compiles a shader again.
func _warm_shaders() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var mats: Array[Material] = []
	for m: StandardMaterial3D in MeshKit.materials():
		if m != null:
			mats.append(m)
	mats.append_array(Collectible.warm_materials())
	for child in fx.get_children():
		var particles := child as GPUParticles3D
		if particles != null and particles.draw_pass_1 != null:
			var pm: Material = particles.draw_pass_1.material
			if pm != null:
				mats.append(pm)
	var skyline := get_node_or_null("KhartoumSkyline") as MeshInstance3D
	if skyline != null and skyline.material_override != null:
		mats.append(skyline.material_override)

	var rig := Node3D.new()
	rig.name = "ShaderWarmup"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	for i in mats.size():
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mats[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(-0.12 + 0.008 * float(i), -0.06, -0.35)
		rig.add_child(mi)
	cam.add_child(rig)
	# Two full frames: the first queues the draw, the second guarantees the
	# renderer actually ran the pipelines with the menu still covering them.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	rig.queue_free()
	print("[Warmup] %d shader materials drawn" % mats.size())


# ---------------------------------------------------------------------------
# Lighting & atmosphere
# ---------------------------------------------------------------------------
func _setup_lighting() -> void:
	_environment = Environment.new()
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Photographic Khartoum sunset. `sky_khartoum.jpg` is a real 2:1 equirect
	# panorama produced by tools/build_textures.py from art_src/, so the clouds
	# and the light direction match the street photos used for the road and the
	# facades. It falls back to the old procedural gradient if the texture is
	# missing (a stripped build, or when the player turns photo art off).
	_apply_sky(_make_photo_sky())
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world_environment.environment = _environment
	Perf.apply_to_environment(_environment)
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_environment.volumetric_fog_enabled = Perf.tier == Perf.Tier.HIGH
		_environment.volumetric_fog_density = 0.018
		_environment.volumetric_fog_length = 72.0
		_environment.volumetric_fog_detail_spread = 1.6

	# Low, warm sun: long shadows across the asphalt, sun disc near the horizon.
	sun.rotation_degrees = Vector3(-26.0, -142.0, 0.0)
	sun.light_color = Color("#ffd0a0")
	sun.light_energy = 1.55
	sun.light_specular = 0.72
	# A 1.1 deg sun disc gives soft penumbrae on the awnings and the poles; a
	# point sun is what makes procedural scenes look like clip-art.
	sun.light_angular_distance = 1.1
	_perf_sun()

	# Bounce fill. The street is sand and pale concrete, so in reality a lot of
	# light comes back up from the ground into every shaded wall. A second,
	# shadowless light pointing slightly upward fakes that in one draw call and
	# is the single biggest "this looks photographed" change in the scene.
	_bounce = DirectionalLight3D.new()
	_bounce.name = "BounceFill"
	_bounce.light_color = Color("#ffcf9e")
	_bounce.light_energy = 0.42
	_bounce.light_specular = 0.0
	_bounce.shadow_enabled = false
	_bounce.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# Opposite side of the sun (sun yaw -142 deg) and tilted *up* (positive X
	# rotation points the light at the ground from below).
	_bounce.rotation_degrees = Vector3(11.0, 42.0, 0.0)
	add_child(_bounce)


## 2:1 equirectangular panorama photographed on the Blue Nile bank.
## Swap in the photographic or the painted sky, and keep the ambient light,
## the tonemapper and the Khartoum skyline in step with it. Used both at boot
## and when the Settings switch flips, so the two paths can never drift apart.
## `SkyMaterial` is not exposed to GDScript as a global type, so the concrete
## panorama material is the parameter type.
func _apply_sky(photo_sky: PanoramaSkyMaterial) -> void:
	var has_photo := photo_sky != null
	var sky := Sky.new()
	if photo_sky != null:
		sky.sky_material = photo_sky
	else:
		sky.sky_material = _make_procedural_sky()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_color = Color("#9a7f74") if has_photo \
			else Color("#7d6a72")
	_environment.ambient_light_energy = 1.15 if has_photo else 1.35
	# ACES keeps the photographic sky from clipping into a flat orange band.
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES if has_photo \
			else Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 1.05 if has_photo else 1.0
	# Equirect textures wrap at u = 0, which is exactly the -Z direction the chase
	# camera looks down: the seam landed dead centre of every frame. Turning the
	# dome 180 deg puts it behind the player.
	if has_photo:
		_environment.sky_rotation = Vector3(0.0, PI, 0.0)
	else:
		_environment.sky_rotation = Vector3.ZERO
	var skyline := get_node_or_null("KhartoumSkyline")
	if has_photo:
		if skyline == null:
			_setup_skyline()
	elif skyline != null:
		skyline.queue_free()


## Sun settings that must survive a quality change (Perf only touches shadows
## and distance, but re-applying them is what keeps the two paths in sync).
func _perf_sun() -> void:
	Perf.apply_to_sun(sun, camera_rig)
	Perf.apply_to_camera(camera_rig)


func _make_photo_sky() -> PanoramaSkyMaterial:
	if not Settings.photo_graphics:
		return null
	const PATH := "res://assets/textures/sky_khartoum.jpg"
	if not ResourceLoader.exists(PATH):
		return null
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = load(PATH)
	# A touch of blur removes the pixel-level grain of the source photo at the
	# zenith, where a 2048 px panorama is stretched the most.
	mat.filter = true
	return mat


func _make_procedural_sky() -> ProceduralSkyMaterial:
	var sky_mat := ProceduralSkyMaterial.new()
	# Khartoum dusk: indigo zenith, dust-orange horizon.
	sky_mat.sky_top_color = Color("#141c33")
	sky_mat.sky_horizon_color = Color("#e0905a")
	sky_mat.sky_curve = 0.18
	sky_mat.sky_energy_multiplier = 0.9
	sky_mat.ground_bottom_color = Color("#191713")
	sky_mat.ground_horizon_color = Color("#a9704a")
	sky_mat.ground_curve = 0.06
	sky_mat.use_debanding = Perf.tier == Perf.Tier.HIGH
	return sky_mat


## The Khartoum skyline (Al-Mogran towers, minarets, water towers) on a huge
## cylinder around the play area.
##
## Why a cylinder instead of baking it into the sky dome: an equirect panorama
## has to tile, so a skyline inside it would repeat once per 180 degrees of turn.
## On a cylinder the city sits exactly once in the distance, which is how it
## actually looks from the Blue Nile bridge - and it stays flat, so it never
## distorts as the camera moves.
func _setup_skyline() -> void:
	const PATH := "res://assets/textures/skyline_khartoum.png"
	if not Settings.photo_graphics or not ResourceLoader.exists(PATH):
		return
	if get_node_or_null("KhartoumSkyline") != null:
		return
	var tex: Texture2D = load(PATH)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.35
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Distance haze: the city is 200 m away, so it must melt into the sky.
	mat.albedo_color = Color(1, 1, 1, 1)

	var mesh := CylinderMesh.new()
	mesh.top_radius = 150.0
	mesh.bottom_radius = 150.0
	mesh.height = 34.0
	mesh.radial_segments = 48
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.name = "KhartoumSkyline"
	mi.mesh = mesh
	mi.material_override = mat
	# The band is 34 m tall and the photo is 320 px tall: the cylinder's natural
	# UV wraps it once around, which is exactly what we want.
	mi.position = Vector3(0, 14.0, -30.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 0.0
	add_child(mi)


func _setup_suit_reflections() -> void:
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return
	_suit_probe = ReflectionProbe.new()
	_suit_probe.name = "SuitReflectionProbe"
	_suit_probe.position = Vector3(0.0, 1.1, 0.0)
	_suit_probe.size = Vector3(8.0, 5.0, 12.0)
	_suit_probe.max_distance = 22.0
	_suit_probe.intensity = 1.15
	_suit_probe.box_projection = true
	_suit_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	add_child(_suit_probe)


## Live reaction to the Settings screen: street choice and the photo-art toggle
## must not require restarting the run.
func _on_setting_changed(key: String) -> void:
	match key:
		"district":
			track.set_district(Settings.district)
		"photo_graphics":
			# Rebuild the sky, the skyline and every segment's materials.
			_apply_sky(_make_photo_sky())
			MeshKit.invalidate_photo_cache()
			track.refresh_photo_materials()
		"tilt_enabled", "lane_control":
			player.recalibrate_tilt()


func _on_tier_changed(_tier: int, _info: Dictionary) -> void:
	Perf.apply_to_environment(_environment)
	Perf.apply_to_sun(sun, camera_rig)
	Perf.apply_to_camera(camera_rig)
	if _environment.sky and _environment.sky.sky_material is ProceduralSkyMaterial:
		(_environment.sky.sky_material as ProceduralSkyMaterial).use_debanding = Perf.tier == Perf.Tier.HIGH
	track.refresh_quality()
	fx.apply_quality()


# ---------------------------------------------------------------------------
# Run lifecycle
# ---------------------------------------------------------------------------
## On-screen pad press (see UiRoot._build_touch_buttons).
func _on_control_pressed(direction: String) -> void:
	player.handle_swipe(direction)


func _on_play_requested() -> void:
	get_tree().paused = false
	track.set_district(Settings.district)
	Game.start_run()
	player.start_running()
	track.start_run()
	camera_rig.snap_to_player()
	Audio.play_music()


func _on_resume_requested() -> void:
	Game.resume()


func _on_menu_requested() -> void:
	_to_menu()


func _to_menu() -> void:
	Game.to_menu()
	track.reset_world()
	player.reset()
	player.controlling = false
	camera_rig.snap_to_player()


func _on_prop_hit(reason_key: String) -> void:
	player.die()
	camera_rig.shake(0.55, 0.45)
	fx.crash(player.global_position)
	ui.show_crash_reason(reason_key)
	Settings.vibrate(90)


func _on_obstacle_smashed(at: Vector3) -> void:
	camera_rig.shake(0.28, 0.22)
	fx.crate_debris(at)
	Audio.play_sfx("hit", 0.04, 0.75)


func _on_player_stumbled(reason_key: String) -> void:
	camera_rig.shake(0.38, 0.3)
	fx.crash(player.global_position)
	ui.show_crash_reason(reason_key)
	Audio.play_sfx("hit", 0.0, 0.65)


func _on_player_slide() -> void:
	fx.slide_dust(player.global_position)


func _on_player_landed() -> void:
	fx.land_dust(player.global_position)


func _on_cup_collected(_kind: int, at: Vector3) -> void:
	fx.pickup_sparkle(at)


func _on_milestone(_meters: int) -> void:
	camera_rig.shake(0.12, 0.18)
	fx.celebrate(player.global_position)


# ---------------------------------------------------------------------------
# System notifications
#
# Pause / Android back button are handled by UiRoot instead: the UI runs with
# PROCESS_MODE_ALWAYS, while this node is paused (and stops receiving input) as
# soon as the player opens the pause menu.
# ---------------------------------------------------------------------------
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Phones lose focus all the time (notifications, calls): auto-pause.
			if Game.state == Game.State.RUNNING:
				Game.toggle_pause()


# ---------------------------------------------------------------------------
# Headless smoke test (CI): godot --headless --quit-after 900 -- --smoke
# ---------------------------------------------------------------------------
func _run_smoke_test() -> void:
	await get_tree().create_timer(0.25).timeout
	_on_play_requested()
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			return
		player.jump()
		await get_tree().create_timer(0.28).timeout
		if not is_inside_tree():
			return
		player.slide()
		player.change_lane(1 if i % 2 == 0 else -1)

	# --- soak -------------------------------------------------------------
	# ~100 minutes of running at top speed (≈160 km of track, a couple of
	# thousand segment recycles and tens of thousands of prop respawns) in a
	# fraction of a second. The assertion is that it allocates no meshes and
	# that the heap does not grow: the regression test for "the game freezes
	# after a distance".
	await get_tree().process_frame
	var mem_before := OS.get_static_memory_usage()
	track.speed = TrackManager.MAX_SPEED
	track.soak(6000.0, 1.0)
	await get_tree().process_frame
	var mem_after := OS.get_static_memory_usage()
	var growth_mb := float(mem_after - mem_before) / (1024.0 * 1024.0)
	var builds := SegmentBuilder.builds_in_run
	print("SOAK %s" % track.debug_stats())
	print("SOAK mem_before=%.1fMB mem_after=%.1fMB growth=%.2fMB builds_in_run=%d" % [
		float(mem_before) / (1024.0 * 1024.0), float(mem_after) / (1024.0 * 1024.0),
		growth_mb, builds])
	if builds == 0 and growth_mb < 16.0:
		print("SOAK_OK")
	else:
		print("SOAK_FAIL builds_in_run=%d growth=%.2fMB" % [builds, growth_mb])

	Game.end_run("smoke")
	await get_tree().create_timer(0.9).timeout
	print("SMOKE_OK score=%d distance=%d cups=%d props=%d cups_live=%d fps=%d" % [
		Game.score, int(Game.distance), Game.cups, track.active_prop_count(),
		track.active_cup_count(), Engine.get_frames_per_second()])
	get_tree().quit()


# ---------------------------------------------------------------------------
# Screenshot session (CI visual check):
#   xvfb-run godot --rendering-driver opengl3 -- --screenshot
# Saves PNGs to user:// so the workflow can publish them for review.
# ---------------------------------------------------------------------------
func _run_screenshot_session() -> void:
	await get_tree().create_timer(1.2).timeout
	await _save_shot("01_menu")
	ui.open_howto()
	await get_tree().create_timer(0.4).timeout
	await _save_shot("02_howto")
	ui.close_overlays()
	_on_play_requested()
	await get_tree().create_timer(2.2).timeout
	await _save_shot("03_gameplay")
	_dump_animation_state()
	# v1.3.0 art pass: show one of the photographic bridges and the on-screen
	# pad cluster, so the release notes have real captures instead of promises.
	Settings.set_district(4)
	await get_tree().create_timer(0.9).timeout
	await _save_shot("03b_bridge")
	Settings.set_show_buttons(true)
	await get_tree().create_timer(0.4).timeout
	await _save_shot("03c_buttons")
	Settings.set_show_buttons(false)
	# Corniche: the Nile palms. Their alpha fronds are the newest art, so they
	# get their own capture instead of hiding behind the market.
	Settings.set_district(2)
	await get_tree().create_timer(0.9).timeout
	await _save_shot("03d_corniche")
	Settings.set_district(-1)
	await get_tree().create_timer(0.4).timeout
	player.jump()
	await get_tree().create_timer(0.34).timeout
	await _save_shot("04_jump")
	await get_tree().create_timer(1.1).timeout
	player.slide()
	await get_tree().create_timer(0.2).timeout
	await _save_shot("05_slide")
	await get_tree().create_timer(0.8).timeout
	Game.toggle_pause()
	await get_tree().create_timer(0.5).timeout
	await _save_shot("06_pause")
	Game.toggle_pause()
	await get_tree().create_timer(0.2).timeout
	Game.end_run("screenshot")
	await get_tree().create_timer(1.4).timeout
	await _save_shot("07_gameover")
	ui.open_settings()
	await get_tree().create_timer(0.5).timeout
	await _save_shot("08_settings")
	Game.to_menu()
	print("SCREENSHOTS_DONE")
	get_tree().quit()


## Writes the live rig state next to the screenshots so CI can publish it.
func _dump_animation_state() -> void:
	if player == null or not player.has_method("animation_debug"):
		return
	var f := FileAccess.open("user://hero_state.txt", FileAccess.WRITE)
	if f == null:
		return
	f.store_string(String(player.call("animation_debug")))
	f.close()
	print("HERO_STATE_DUMPED")


func _save_shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://shot_%s.png" % shot_name
	var err := image.save_png(path)
	print("SHOT %s -> %s (err=%d)" % [shot_name, ProjectSettings.globalize_path(path), err])
