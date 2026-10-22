## Automatic hardware tiering + dynamic quality scaling.
##
## Detection order of preference:
##   1. RAM reported by the OS        (the strongest low-end signal)
##   2. CPU core count
##   3. GPU family parsed from the adapter name (Adreno / Mali / PowerVR / Xclipse)
##   4. Display refresh rate (90/120/144 Hz phones are almost always flagship)
##   5. Screen DPI + resolution
##
## The result is one of three tiers. Everything the renderer needs (shadow
## distance, fog, prop density, particles, render scale, fps cap) is stored here
## so gameplay code never hard-codes a quality decision.
##
## A lightweight watchdog also lowers the 3D render scale when the measured FPS
## sits below the target for a while and restores it once there is headroom.
## This is what keeps a 2016 phone from dropping to 20 FPS in the market scene.
extends Node

signal tier_changed(tier: int, info: Dictionary)
signal quality_scaled(render_scale: float)

enum Tier { LOW, MEDIUM, HIGH }

const TIER_NAMES := ["low", "medium", "high"]

## Wall-clock budget for the watchdog. Never touch quality in the first seconds
## of a run: shader compilation makes the first frames unrepresentative.
const WATCHDOG_WARMUP := 6.0
const WATCHDOG_WINDOW := 2.0

var tier: int = Tier.MEDIUM
var device_info: Dictionary = {}
var target_fps: int = 60
var refresh_rate: float = 60.0
var auto_preset: bool = true

var render_scale: float = 1.0
var shadows_enabled: bool = true
var shadow_distance: float = 40.0
var fog_density: float = 0.010
var fog_depth_begin: float = 45.0
var fog_depth_end: float = 190.0
var fog_color: Color = Color(0.62, 0.55, 0.58)
var prop_density: float = 1.0
var particle_amount: float = 1.0
var draw_distance: float = 230.0
var msaa: int = Viewport.MSAA_DISABLED

var _elapsed := 0.0
var _fps_accum := 0.0
var _fps_frames := 0
var _low_streak := 0
var _high_streak := 0
var _base_render_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Process after the tree is ready so the root viewport exists everywhere.
	await get_tree().process_frame
	refresh_rate = _query_refresh_rate()
	device_info = detect_device()
	apply_preset(Settings.graphics_preset)
	set_process(true)


func _exit_tree() -> void:
	# Leave the project defaults intact when play stops inside the editor.
	if Engine.is_editor_hint():
		Engine.max_fps = 0


# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------
func detect_device() -> Dictionary:
	var mem := OS.get_memory_info()
	var physical_mb := int(mem.get("physical", 0)) / (1024.0 * 1024.0)
	var available_mb := int(mem.get("available", 0)) / (1024.0 * 1024.0)
	if physical_mb <= 0.0:
		physical_mb = 4096.0  # unknown: assume a mid-range phone
	if available_mb <= 0.0:
		available_mb = physical_mb * 0.5

	var cores := OS.get_processor_count()
	var gpu := String(RenderingServer.get_video_adapter_name())
	var vendor := String(RenderingServer.get_video_adapter_vendor())
	var screen := Vector2i(DisplayServer.screen_get_size())
	var dpi := DisplayServer.screen_get_dpi()
	var is_mobile := OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")

	var score := 0
	if physical_mb >= 7500.0:
		score += 3
	elif physical_mb >= 5500.0:
		score += 2
	elif physical_mb >= 3500.0:
		score += 1
	if available_mb < 700.0:
		score -= 1

	if cores >= 8:
		score += 2
	elif cores >= 6:
		score += 1
	elif cores <= 4:
		score -= 1

	var gpu_lower := gpu.to_lower()
	for weak in ["mali-4", "mali-t", "mali-400", "mali-450", "adreno (tm) 3",
			"adreno (tm) 4", "adreno (tm) 5", "powervr sgx", "powervr rogue ge8"]:
		if gpu_lower.contains(weak):
			score -= 3
			break
	for strong in ["adreno (tm) 7", "adreno (tm) 8", "mali-g7", "mali-g8", "immortalis",
			"xclipse", "apple gpu", "apple m"]:
		if gpu_lower.contains(strong):
			score += 2
			break

	if refresh_rate >= 90.0 and is_mobile:
		score += 1
	if is_mobile and screen.x > 0 and screen.x * screen.y >= 2400000:  # 1440p phone
		score += 1
	if not is_mobile:
		score += 3  # desktop / editor: high tier while developing

	var detected_tier := Tier.MEDIUM
	if score >= 4:
		detected_tier = Tier.HIGH
	elif score <= 0:
		detected_tier = Tier.LOW
	# Very low available memory overrides everything, whatever the SoC says.
	if available_mb > 0.0 and available_mb < 450.0:
		detected_tier = Tier.LOW

	return {
		"tier": detected_tier,
		"ram_mb": int(physical_mb),
		"available_mb": int(available_mb),
		"cores": cores,
		"gpu": gpu,
		"vendor": vendor,
		"screen": screen,
		"dpi": dpi,
		"refresh": refresh_rate,
		"mobile": is_mobile,
		"models": OS.get_model_name() if is_mobile else OS.get_name(),
		"score": score,
	}


func _query_refresh_rate() -> float:
	var rate := 60.0
	if DisplayServer.get_name() == "headless":
		return 60.0
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = 0
	var hz := DisplayServer.screen_get_refresh_rate(screen)
	if hz > 10.0:
		rate = hz
	return clampf(rate, 30.0, 165.0)


# ---------------------------------------------------------------------------
# Presets
# ---------------------------------------------------------------------------
func apply_preset(preset: int) -> void:
	auto_preset = preset == 0
	var resolved := preset - 1 if preset > 0 else int(device_info.get("tier", Tier.MEDIUM))
	tier = clampi(resolved, Tier.LOW, Tier.HIGH)

	match tier:
		Tier.LOW:
			shadows_enabled = false
			shadow_distance = 0.0
			fog_density = 0.020
			fog_depth_begin = 24.0
			fog_depth_end = 118.0
			fog_color = Color(0.66, 0.55, 0.50)
			prop_density = 0.55
			particle_amount = 0.45
			draw_distance = 150.0
			msaa = Viewport.MSAA_DISABLED
			_base_render_scale = 0.78
		Tier.MEDIUM:
			shadows_enabled = true
			shadow_distance = 32.0
			fog_density = 0.012
			fog_depth_begin = 50.0
			fog_depth_end = 195.0
			fog_color = Color(0.60, 0.53, 0.58)
			prop_density = 1.0
			particle_amount = 0.8
			draw_distance = 215.0
			msaa = Viewport.MSAA_DISABLED
			_base_render_scale = 0.92
		Tier.HIGH:
			shadows_enabled = true
			shadow_distance = 70.0
			fog_density = 0.0075
			fog_depth_begin = 85.0
			fog_depth_end = 250.0
			fog_color = Color(0.56, 0.51, 0.60)
			prop_density = 1.35
			particle_amount = 1.0
			draw_distance = 280.0
			msaa = Viewport.MSAA_2X
			_base_render_scale = 1.0

	render_scale = _base_render_scale
	_low_streak = 0
	_high_streak = 0
	_apply_rendering_settings()
	apply_fps_cap(Settings.fps_cap)
	tier_changed.emit(tier, device_info)
	size_changed_reapply()


## Settings.fps_cap: 0 = follow refresh rate (capped to what the tier can do).
func apply_fps_cap(cap: int) -> void:
	if cap > 0:
		target_fps = cap
	else:
		match tier:
			Tier.LOW:
				target_fps = 30
			Tier.MEDIUM:
				target_fps = 60
			_:
				target_fps = int(min(refresh_rate, 120.0))
	# Never ask for more than the panel can present: that only burns battery.
	target_fps = clampi(target_fps, 30, int(max(30.0, refresh_rate)))
	Engine.max_fps = target_fps


func _apply_rendering_settings() -> void:
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = render_scale
		vp.msaa_3d = msaa
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = false
		vp.use_debanding = tier == Tier.HIGH
	# Shadow atlas size lives on the RenderingServer (and in project settings),
	# not on World3D. 2048 only for the high tier: a 1024 atlas is 4x cheaper.
	var atlas_size := 2048 if tier == Tier.HIGH else 1024
	if DisplayServer.get_name() != "headless":
		ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", atlas_size)
		RenderingServer.directional_shadow_atlas_set_size(atlas_size, true)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)


func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.5, 1.0)
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale
	quality_scaled.emit(render_scale)


## Called by World when the environment / light nodes are ready (and whenever a
## new preset is selected) so fog, shadows and culling match the tier.
func apply_to_environment(env: Environment) -> void:
	if env == null:
		return
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_light_energy = 0.8
	env.fog_density = fog_density
	env.fog_sky_affect = 0.35
	env.fog_aerial_perspective = 0.0 if tier == Tier.LOW else 0.4
	# The Compatibility renderer has no glow / SSAO passes: bloom is faked by the
	# emissive materials (cups, lamps) instead, which is free on mobile.
	env.glow_enabled = false
	env.ssao_enabled = false
	env.adjustment_enabled = tier == Tier.HIGH
	env.adjustment_saturation = 1.06
	env.adjustment_contrast = 1.02


func apply_to_sun(light: DirectionalLight3D, _camera: Camera3D = null) -> void:
	if light == null:
		return
	light.shadow_enabled = shadows_enabled
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = maxf(shadow_distance, 20.0)
	light.directional_shadow_fade_start = 0.75
	light.shadow_bias = 0.06
	light.shadow_normal_bias = 1.6


func apply_to_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	camera.far = draw_distance
	camera.near = 0.15


## The HUD can call this after a resolution change (window resize, split screen).
func size_changed_reapply() -> void:
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_scale = render_scale


# ---------------------------------------------------------------------------
# Dynamic resolution watchdog
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not auto_preset:
		return
	_elapsed += delta
	_fps_accum += Engine.get_frames_per_second()
	_fps_frames += 1
	if _elapsed < WATCHDOG_WARMUP or _fps_frames < 30:
		return

	var fps := _fps_accum / float(_fps_frames)
	_fps_accum = 0.0
	_fps_frames = 0
	_elapsed = 0.0

	if fps < target_fps * 0.82:
		_low_streak += 1
		_high_streak = 0
		if _low_streak >= 2 and render_scale > 0.55:
			set_render_scale(render_scale - 0.08)
			_low_streak = 0
	elif fps > target_fps * 0.97:
		_high_streak += 1
		_low_streak = 0
		if _high_streak >= 4 and render_scale < _base_render_scale:
			set_render_scale(render_scale + 0.04)
			_high_streak = 0
	else:
		_low_streak = 0
		_high_streak = 0


func tier_label() -> String:
	return TIER_NAMES[tier]


func summary() -> String:
	return "%s tier · %d cores · %d MB RAM · %s · %.0f Hz" % [
		tier_label(), int(device_info.get("cores", 0)), int(device_info.get("ram_mb", 0)),
		String(device_info.get("gpu", "?")), refresh_rate
	]
