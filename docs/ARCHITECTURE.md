# Sudan Runner — Architecture & Design Notes
### عدّاء السودان — المخطط المعماري ودليل البناء

This document is the technical companion to `README.md`: scene graph, system
contracts, tuning constants, the mobile UI spec and a performance checklist.

---

## 1. Project structure

```
res://
├── scenes/main.tscn                  the only 3D scene
├── scripts/core/*.gd                 4 autoload singletons + localization
├── scripts/player/*.gd               controller + procedural character
├── scripts/world/*.gd                track, props, scenery, camera, fx, glue
├── scripts/ui/*.gd                   theme + all screens (built in code)
├── assets/{art,textures,audio,fonts} generated / licensed content
└── tools/*.py                        content + CI tooling
```

### Autoload order (matters!)

| # | Singleton | Responsibility | Why this order |
| - | --- | --- | --- |
| 1 | `Settings` | persisted prefs, haptics wrapper | everyone reads it |
| 2 | `Loc` | AR/EN dictionary, RTL flag | needs `Settings.language` |
| 3 | `Perf` | hardware tier, quality, dynamic resolution | reads `Settings.graphics_preset` |
| 4 | `Audio` | pooled players, volumes | reads `Settings` volumes |
| 5 | `Game` | run state machine, score, best run | last: depends on Audio/Perf only |

`Perf._ready()` waits one frame (`await get_tree().process_frame`) before it
touches the root viewport, which guarantees the window/viewport exists in every
launch mode (editor, desktop, Android, headless).

---

## 2. Scene graph

```
World (Node3D)                       ← world.gd: lighting + wiring + run lifecycle
├── WorldEnvironment                 ← Environment built in code (dusk sky, fog)
├── Sun (DirectionalLight3D)         ← warm low sun, shadows per tier
├── Track (Node3D)                   ← track_manager.gd
│   ├── Segments (Node3D)            ← 6 pooled TrackSegment nodes
│   └── Objects  (Node3D)            ← 44 pooled TrackProp + 68 pooled Collectible
├── Player (Node3D)                  ← player_controller.gd
│   ├── Model (RunnerModel)          ← flag suit, 11 boxes + cape, procedural anim
│   └── BlobShadow (MeshInstance3D)  ← cheap ground contact when shadows are off
├── CameraRig (Camera3D)             ← chase camera, shake, speed FOV
├── FX (Node3D)                      ← 3 pooled CPUParticles3D
└── UI (CanvasLayer)                 ← ui_root.gd, built entirely from code
```

### Why a moving world instead of a moving player

* The camera target stays at z ≈ 0 → no floating point drift after 10 km.
* Spawning/recycling is a plain array pass over ~110 nodes.
* Collision is a z-window test (`|z| < depth + 1.2`), no physics bodies, no broad
  phase, no `Area3D` signals — a handful of comparisons per frame.

---

## 3. System contracts (signals)

| Emitter | Signal | Listener | Effect |
| --- | --- | --- | --- |
| `UiRoot` | `play_requested` / `restart_requested` | `World` | start a run |
| `UiRoot` | `resume_requested` / `menu_requested` | `World` | pause flow |
| `UiRoot` | `milestone_passed(m)` | `World` | shake + confetti |
| `TrackManager` | `prop_hit(reason_key)` | `World` | player death, camera shake, FX, toast |
| `TrackManager` | `cup_collected(kind, at)` | `World` | sparkle at the cup |
| `PlayerController` | `landed` | `World` | dust puff |
| `GameManager` | `state_changed/score_changed/combo_changed/run_finished/milestone_reached` | `UiRoot` | HUD & screens |
| `Perf` | `tier_changed` | `World` | re-apply environment, sun, camera, FX |
| `Settings` | `language_changed` | `UiRoot` | full retranslate + RTL |

`GameManager` never touches nodes; `TrackManager` never touches UI. Anything that
crosses a boundary does it through these signals.

---

## 4. Core loops

### 4.1 PlayerController (`scripts/player/player_controller.gd`)

```
lane ∈ {0,1,2} ──target_x = (lane-1) * 2.4
position.x → target_x            exponential smoothing, τ = 80 ms
jump: v0 = 12.6 m/s, g = 38 m/s² → apex 2.09 m, air time 0.66 s
slide: 0.62 s duck, head 0.9 m instead of 1.75 m
swipe threshold: 46 logical px (≈ 8 mm on a 6" phone)
tilt: |accel.x - baseline| > 0.22 with 0.32 s cooldown (calibrated at run start)
```

Input funnel: `InputEventScreenTouch/Drag` only. `emulate_touch_from_mouse` is
enabled in `project.godot`, so desktop and Android share one code path (no double
firing). Buttons consume their own events; the HUD is `MOUSE_FILTER_IGNORE`, so a
swipe that starts on the HUD still reaches the player.

### 4.2 TrackManager (`scripts/world/track_manager.gd`)

```
every frame while running:
    speed  = min(27, 11 + distance * 0.012)
    travel = speed * delta
    segments.position.z += travel      (recycle at z > 40 → z -= 240)
    props/cups.position.z += travel    (recycle at z > 14)
    while spawn_cursor > -168: spawn_row()
    check pickups → check obstacles
```

Row generation (`_spawn_row`):

1. `gap = clamp(speed * 0.62, 9.5, 20)` → constant ~0.6 s reaction window even at
   top speed.
2. 10 % breather rows (plus the first two of a run).
3. Block 1 lane, or 2 lanes with probability `0.12 + 0.42 * difficulty`.
   **At least one lane is always free.**
4. Obstacle kind is rolled from a weighted table and can never repeat back to back.
5. Cups: a 5-cup **arc over a jumpable obstacle** (55 %) or a 3–5 cup line in a
   free lane (72 %) — so cups are always reachable.

Data-driven obstacles (`PropLibrary.DATA`) keep gameplay and geometry separate:

```gdscript
BUS: { pass = PASS_DODGE, half_width = 1.2, depth_half = 2.7 }
BARRIER: { pass = PASS_JUMP, clear = 1.0 }
LOW_BAR: { pass = PASS_SLIDE, clear = 1.25 }
```

Adding a new obstacle = one mesh builder + one `DATA` entry.

### 4.3 GameManager (`scripts/core/game_manager.gd`)

State machine `MENU → RUNNING ⇄ PAUSED → GAME_OVER → MENU`.

* `add_distance()`: +1 point per metre, milestone every 250 m.
* `collect_cup()`: +10 × multiplier; 5 picks within 2.2 s step the multiplier up
  (max ×5).
* `end_run()`: persists best score/distance/totals in `user://sudan_runner_progress.cfg`,
  emits `run_finished(summary)`.
* `_process` throttles score signals to 20 Hz (UI does not need 120 Hz rebuilds).

### 4.4 PerformanceManager (`scripts/core/performance_manager.gd`)

Detection score → tier (`LOW/MEDIUM/HIGH`), then:

| Knob | Where it is applied |
| --- | --- |
| render scale | `Viewport.scaling_3d_scale` (BILINEAR) |
| MSAA / TAA / debanding | `Viewport.*` |
| shadow atlas 1024/2048 | `RenderingServer.directional_shadow_atlas_set_size` |
| shadow distance | `DirectionalLight3D.directional_shadow_max_distance` |
| fog density/range/colour | `Environment.fog_*` |
| prop density | `SegmentBuilder` rebuild (`TrackSegment.apply`) |
| particle amount | `Fx.apply_quality()` |
| fps cap | `Engine.max_fps`, clamped to panel refresh |
| per-vertex shading | `MeshKit.vertex_material_cheap()` in the `LOW` tier |

Dynamic resolution watchdog: after a 6 s warm-up (shader compilation), samples
FPS every 2 s; two consecutive samples under 82 % of target drop the scale by
0.08 (floor 0.55); four samples above 97 % raise it by 0.04 up to the tier base.
Disabled when the player picks a manual preset.

---

## 5. UI/UX specification (`scripts/ui/ui_root.gd`)

**Design language**: the Sudanese flag as the palette — deep ink panels, red
primary action, gold highlights, white text, green for "new best". Font: Cairo
(Arabic + Latin, OFL).

```
┌──────────────────────────────────────────────────────────────┐
│ [SCORE 12,340]                         [cup 0 23]  [ II ]    │  HUD (top)
│ [ 1,240 m ]                                                  │
│              (toast: 250 m!)                                 │
│                                                              │
│                     gameplay, 3 lanes                        │
└──────────────────────────────────────────────────────────────┘
```

* **HUD** — `MarginContainer` (28 px sides, 20 px top) → `HBoxContainer`.
  Score panel on the leading edge (auto-flips for RTL), cups + pause on the
  trailing edge (thumb reachable in landscape). Everything is
  `MOUSE_FILTER_IGNORE` so swipes pass through.
* **Combo chip** appears at 3+ picks with a 1.08× scale pop.
* **Menu** — full-bleed `menu_bg.png` (dusk Khartoum skyline, blurred flag), a
  centred `VBoxContainer` inside a `CenterContainer`: flag icon (104 px) → logo
  (560×196) → best score → primary 380×84 play button → settings/how to play
  row → quit (desktop only).
* **Pause / Game over / Settings / How to play** — dimmed overlay
  (`Color(0.02,0.02,0.03,0.72)`) + `PanelContainer` (460–700 px wide) that
  consumes input while visible.
* **Game over** is delayed 0.85 s so the crash animation is readable; stats are
  score / distance / cups, with a green "NEW BEST" badge + crowd cheer.
* **Settings** — graphics preset chips (AUTO/LOW/MEDIUM/HIGH), FPS cap
  (AUTO/30/60/120), tilt & haptics toggles, language switch, music/SFX sliders,
  live device tier + GPU/RAM summary, reset progress.
* **Responsiveness** — every screen is anchored; `window/stretch/mode =
  canvas_items` with `aspect = expand` keeps the HUD margins constant on
  18:9 → 21:9 and on tablets. Text is vector (TTF) so it stays sharp at 1440p.
* **RTL** — `Control.layout_direction` is switched with the language, so
  containers (HBox/VBox, margins) mirror automatically.

All strings live in `scripts/core/localization.gd`; `retranslate()` re-labels
every control in one pass (no scene reload, no restart).

---

## 6. Content pipeline (no binary assets needed)

```bash
python3 tools/generate_assets.py     # Pillow
python3 tools/generate_audio.py      # numpy, optional ffmpeg for OGG
```

* `generate_assets.py` draws the flag (exact 1:2 construction), the 512 px app
  icon + 432 px adaptive icon layers, the 1280×720 boot splash, the 1920×1080
  menu background (dusk skyline, Nile, minaret, acacia, amjad), the HUD cups and
  the tileable asphalt/sand/puff/shadow textures.
* `generate_audio.py` synthesises a 20 s looping 96 BPM Sudanese percussion
  groove (doum/tek/clap/shaker/cowbell + bass + Karplus–Strong pluck hook) and
  nine sound effects. Encoding to OGG keeps the APK small; loops are seamless
  (tails wrapped, 4 ms fade at the seam).

3D geometry is **never imported**: `MeshKit` + `SegmentBuilder` + `PropLibrary`
build every street, obstacle and cup at runtime and cache the results.

---

## 7. Android build

* `export_presets.cfg` targets package `com.gadaman.sudanrunner`, ABI
  `arm64-v8a` + `armeabi-v7a`, `screen/immersive_mode = true`, vibrate permission,
  launcher icons from the generated flag artwork.
* Renderer `gl_compatibility` → works on Android 7+ and any GLES3 GPU.
* `.github/workflows/build.yml`:
  1. **validate** — `gdparse` all scripts, `godot --headless --import`, then a
     real gameplay smoke test (`-- --smoke`) that exercises generation,
     collisions, pickups, game over and the HUD, failing the build on any
     `SCRIPT ERROR`.
  2. **apk** — installs JDK 17 + Android cmdline-tools/build-tools, points
     Godot's EditorSettings at them (`tools/ci_configure_android.py`), exports a
     debug-signed APK, verifies the native libs are inside, uploads the artifact
     and (on a `v*` tag) attaches it to the GitHub release.
* For a Play Store build, add a release keystore in the export preset and call
  `--export-release` instead of `--export-debug`.

---

## 8. Performance checklist for budget phones

- [x] Zero allocations during gameplay (pre-built pools, cached meshes/materials)
- [x] No `RigidBody`/`Area3D`; collisions are AABB checks over ~44 props
- [x] One material per scenery surface → 6 segments × 3 surfaces ≈ 18 draw calls
- [x] Back-face culling disabled only on opaque geometry (no overdraw cost)
- [x] `Engine.max_fps` clamped to the panel refresh (30 on low tier)
- [x] Fog hides the spawn boundary; `Camera3D.far` = 150 m on low tier
- [x] No runtime `load()` inside `_process`; audio streams loaded once
- [x] Textures are 256 px tiles + one 512 px flag → ~300 KB of VRAM
- [x] Player animation is sine-driven (no skinning, no AnimationPlayer CPU cost)
- [x] UI is built once; HUD updates throttled to 20 Hz

---

## 9. Extending the game

| Goal | Steps |
| --- | --- |
| New obstacle | add const + `DATA` entry in `prop_library.gd`, write `_build_x(st)`, add to `_pick_kind()` |
| New street style | add a `_build_x()` branch in `segment_builder.gd` and bump `VARIANT_COUNT` |
| New drink | add colour + texture to `CUP_COLORS`/`CUP_TEXTURES` (and draw it in `generate_assets.py`) |
| Power-ups | new pooled node + `TrackManager._spawn_row()` slot + `Game` effect |
| Missions/daily goals | listen to `Game.run_finished` and persist in `GameManager` |
| Localization to a third language | add a table in `localization.gd`, extend `set_language` |

Keep the rules: **no node creation during a run**, **no physics engine**, and
**every visual decision goes through `Perf`**.

---

## 10. Semi-realistic asset and animation upgrade path (Godot 4)

This repository is a **Godot 4/GDScript project, not Unity/URP**. The equivalent
production pipeline is Godot's Forward+/Mobile PBR renderer. Do not add Unity
`.cs` files: they cannot run in this project. The gameplay interfaces above are
kept independent from the visual model so an art team can replace generated
meshes without rewriting the runner.

### Hero import contract

1. Export a smooth-shaded, skinned GLB in metres, facing **-Z**, with the feet at
   Y=0. Use one armature and no more than four bone weights per vertex.
2. Author three 2K texture sets (1K for mobile): Sudan red/white/black suit,
   green accents, and chrome trim. Pack roughness/metallic/AO into channels.
   Chrome should use metallic 0.75–0.9 and roughness 0.18–0.32; cloth uses
   metallic 0 and roughness 0.55–0.75. Never make the entire suit mirror-like.
3. Create clips named `jog`, `sprint`, `ultra_sprint`, `lane_left`, `lane_right`,
   `jump`, `fall`, `land`, `slide`, `hurdle`, `chest_bump`, `stumble`, `recover`,
   and `crash`. Enable looping only on the three locomotion clips.
4. In an `AnimationTree`, use a 1D locomotion BlendSpace at 0/0.55/1 and a
   separate additive lane BlendSpace at -1/0/1. Drive them from
   `PlayerController.run_blend` and `lane_blend`. One-shot nodes own jump,
   landing, slide, hurdle, bump and recovery. Root motion should be disabled in
   Z because the track scrolls; lateral/root rotation may be consumed visually.
5. Keep the generated `RunnerModel` as the low-tier LOD. Use the imported skinned
   hero for medium/high, and create 35k / 15k / 4k triangle LODs with transition
   distances around 14 m and 32 m. All variants must share the same silhouette
   and animation names.

### Generated hero scene (`assets/models/hero/hero.tscn`)

`HeroBuilder` (scripts/tools/hero_builder.gd) is the only consumer of the
character folder. It runs headless in CI (tools/ci_build_hero.gd) and from the
editor (scripts/tools/ImportArabicFolderHero.gd); the game itself never touches
FBX at runtime because exported builds do not ship the source files.

Pipeline invariants:

1. **Content-based skin selection.** Each candidate is instantiated and its
   real mesh vertex count is measured; the richest file is the skin. File
   names, file sizes and byte sniffing are not used (in an APK the `.fbx`
   sources report size 0, which previously selected a motion-only clip and
   produced a hero without geometry).
2. **Track retargeting.** Every animation track is rewritten onto
   `Mesh/<skeleton path>:<bone>` by normalised bone name
   (`mixamorig:Hips`, `mixamorig_Hips` and `Hips` are equivalent). Motion-only
   Mixamo exports store bone motion as plain `Node3D` tracks; those are mapped
   onto bones as well, and hip X/Z translation is pinned so the runner cannot
   drift out of its collision box.
3. **Normalised presentation.** Uniform scale to 1.78 m, feet on Y=0, centred
   on X/Z and yawed so the character faces -Z (away from the chase camera).
   Bounds are computed by walking local transforms because
   `Node3D.global_transform` is invalid outside the SceneTree.
4. **Ownership before packing.** `PackedScene.pack()` drops any node whose
   `owner` is not the packed root (`SceneState::_parse_node()` returns early and
   skips the whole subtree). The builder assigns `owner` recursively, which is
   what makes the skeleton, skinned mesh and materials end up in the saved
   scene at all.
5. **Self-verification.** The builder re-loads the file it just wrote and
   `HeroBuilder.verify()` asserts: >= 1 visible mesh with surfaces, >= 200
   vertices, height within 1.2-2.4 m, feet within +/-0.2 m of the ground, a
   skeleton with >= 10 bones and a non-collapsed rest pose, an AnimationTree,
   and every required clip (jog/jump/fall/land/slide/stumble) having at least
   one track that resolves inside the scene. CI runs the same check with
   `--strict` and refuses to export an APK when it fails.
6. **Runtime fallback.** `PlayerController._hero_is_drawable()` repeats the
   cheap part of that check on the loaded scene and falls back to the
   procedural `RunnerModel` instead of rendering nothing.

Suit material: `scripts/player/hero_material.gd`. It is deliberately dielectric
(metallic 0.05) — with the Compatibility renderer and reflections disabled a
metallic suit renders black.

### Environment and lighting

* Import asphalt, concrete, brick, rusty metal and wood as tileable PBR sets;
  use decals/secondary UV overlays for cracks and pothole edges rather than
  unique 4K maps. Build Amjad, karu, palm and acacia assets with three LODs.
* For high-spec devices switch the project renderer to **Mobile** or Forward+
  and enable reflection probes, subtle glow, SSAO and motion blur. Keep the
  current Compatibility renderer and baked/emissive fallback for low-end
  Android. The warm sun, filmic tone map, fog and tier controls are configured
  in `world.gd` and `performance_manager.gd`.
* Keep transparent dust overdraw small. `Fx` and track props are pooled; imported
  replacements must preserve pooling and must not instantiate during a run.

### New action-runner contracts

`TrackManager.start_delivery(drink, distance, seconds)` starts a timed Aradaib,
Karkadeh or Gongolez delivery stage. It emits `delivery_updated`,
`delivery_completed`, and `delivery_failed` for a mission HUD. At ultra-sprint,
crates are chest-bumped for bonus points. Barrier/pothole mistakes trigger a
stumble, speed penalty and recovery grace period; major obstacles still crash.
Camera banking uses real lateral velocity, while action intensity widens FOV.
