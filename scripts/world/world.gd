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


func _ready() -> void:
	_setup_lighting()
	track.set_player(player)
	player.track = track
	camera_rig.setup(player, track)

	track.prop_hit.connect(_on_prop_hit)
	track.cup_collected.connect(_on_cup_collected)
	player.landed.connect(_on_player_landed)
	ui.play_requested.connect(_on_play_requested)
	ui.restart_requested.connect(_on_play_requested)
	ui.resume_requested.connect(_on_resume_requested)
	ui.menu_requested.connect(_on_menu_requested)
	ui.milestone_passed.connect(_on_milestone)
	Perf.tier_changed.connect(_on_tier_changed)

	_to_menu()
	Audio.play_music()

	if "--smoke" in OS.get_cmdline_user_args():
		_run_smoke_test()
	if "--screenshot" in OS.get_cmdline_user_args():
		_run_screenshot_session()


# ---------------------------------------------------------------------------
# Lighting & atmosphere
# ---------------------------------------------------------------------------
func _setup_lighting() -> void:
	_environment = Environment.new()
	var sky := Sky.new()
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
	sky.sky_material = sky_mat

	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("#7d6a72")
	_environment.ambient_light_energy = 1.35
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.tonemap_exposure = 1.0
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world_environment.environment = _environment
	Perf.apply_to_environment(_environment)

	# Low, warm sun: long shadows across the asphalt, sun disc near the horizon.
	sun.rotation_degrees = Vector3(-26.0, -142.0, 0.0)
	sun.light_color = Color("#ffd0a0")
	sun.light_energy = 1.45
	sun.light_specular = 0.35
	Perf.apply_to_sun(sun, camera_rig)
	Perf.apply_to_camera(camera_rig)


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
func _on_play_requested() -> void:
	get_tree().paused = false
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


func _on_player_landed() -> void:
	fx.land_dust(player.global_position)


func _on_cup_collected(_kind: int, at: Vector3) -> void:
	fx.pickup_sparkle(at)


func _on_milestone(_meters: int) -> void:
	camera_rig.shake(0.12, 0.18)
	fx.celebrate(player.global_position)


# ---------------------------------------------------------------------------
# System input: pause / Android back button
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if Game.state == Game.State.RUNNING or Game.state == Game.State.PAUSED:
			Game.toggle_pause()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			# Phones lose focus all the time (notifications, calls): auto-pause.
			if Game.state == Game.State.RUNNING:
				Game.toggle_pause()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if Game.state == Game.State.RUNNING:
				Game.toggle_pause()
			elif Game.state == Game.State.PAUSED:
				_to_menu()
			else:
				get_tree().quit()


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
	_on_play_requested()
	await get_tree().create_timer(2.2).timeout
	await _save_shot("02_gameplay")
	player.jump()
	await get_tree().create_timer(0.34).timeout
	await _save_shot("03_jump")
	await get_tree().create_timer(1.1).timeout
	player.slide()
	await get_tree().create_timer(0.2).timeout
	await _save_shot("04_slide")
	await get_tree().create_timer(0.8).timeout
	Game.toggle_pause()
	await get_tree().create_timer(0.5).timeout
	await _save_shot("05_pause")
	Game.toggle_pause()
	await get_tree().create_timer(0.2).timeout
	Game.end_run("screenshot")
	await get_tree().create_timer(1.4).timeout
	await _save_shot("06_gameover")
	ui._open_settings()
	await get_tree().create_timer(0.5).timeout
	await _save_shot("07_settings")
	print("SCREENSHOTS_DONE")
	get_tree().quit()


func _save_shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := "user://shot_%s.png" % shot_name
	var err := image.save_png(path)
	print("SHOT %s -> %s (err=%d)" % [shot_name, ProjectSettings.globalize_path(path), err])
