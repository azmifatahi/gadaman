# Semi-realistic asset pipeline — Godot 4

## Mixamo character and animations

1. Create/sign into an Adobe Mixamo account. Pick **Y Bot**, X Bot, or a legally
   usable humanoid you own. This project does not redistribute Mixamo files.
2. Download the character once as **FBX Binary, T-pose, With Skin, 30 FPS**.
   Download separate clips **Without Skin**: Running, Sprint, Jump, Falling,
   Landing, Knee Slide, Stumble Backwards, Standing Recover, and Shoulder Hit.
   Enable *In Place* for run/sprint. Keep jump root translation only for authoring;
   gameplay owns Y and the moving track owns Z.
3. Import the FBXs into Blender. Import the skinned T-pose first, retarget each
   animation to that armature (Mixamo names match), clean actions, then export one
   `runner.glb` with all actions. Godot's GLB path is substantially more reliable
   than importing several FBXs directly.
4. Put it at `res://assets/models/runner/runner.glb`. Select it in Godot's Import
   dock: enable animation import, use 30 FPS, generate LODs/shadow mesh, then
   **Reimport**. Instantiate it beneath `Player/Model`; feet must be Y=0 and the
   character must face -Z. Apply scale in Blender rather than scaling the armature.
5. Rename imported animations to:
   `jog`, `sprint`, `ultra_sprint`, `jump`, `fall`, `land`, `slide`, `stumble`,
   `recover`, `chest_bump`, `hurdle`, `crash`. Loop only locomotion clips.
6. Add `AnimationTree`, assign the imported `AnimationPlayer`, and set Active.
   Make a StateMachine containing Locomotion, Air, Slide, Stumble, Bump and Crash.
   Locomotion contains a BlendSpace1D with jog=0, sprint=0.55, ultra=1. Feed it
   `PlayerController.run_blend`. Add a -1/0/1 lane additive blend fed by
   `PlayerController.lane_blend`. Transitions to one-shots should use the existing
   controller signals (`jumped`, `landed`, `slide_started`, `stumbled`,
   `recovered`, `obstacle_smashed`).
7. Select the imported hero root and run
   `scripts/tools/SetupRealisticRunner.gd` from the Script Editor. It applies the
   Sudan chrome PBR suit and creates a local reflection probe. Replace materials
   for face/eyes/shoes afterward if their node names do not contain those words.

## Poly Pizza / Sketchfab environment assets

Only download assets whose license permits your distribution. Record creator,
URL, license and modifications in `assets/models/ATTRIBUTION.md`. Prefer CC0 or
CC-BY. Never use editorial/non-commercial assets in a commercial build.

* Search for: asphalt road, concrete pavement, market stall, minibus, wooden cart,
  acacia, date palm, traffic cone and wooden crate.
* Download GLB when available. For FBX/OBJ, normalize materials and export GLB in
  Blender. Apply transforms, metres, +Y up, -Z forward. Pack textures beside each
  model under `assets/models/<asset>/`.
* Required maps: base color (sRGB), normal (Normal Map), roughness/metallic/AO
  (linear). Use 1K on mobile, 2K only for the hero/large atlases. Generate LOD0,
  LOD1 and LOD2 at approximately 100%, 45% and 12% triangles.
* Replace the mesh returned by `PropLibrary.obstacle_mesh()` or instantiate the
  imported scene once in `TrackProp._ready()`. Preserve pooling: never `load()` or
  instantiate while a run is active.

## Renderer checklist

For high-end builds change Project Settings > Rendering > Renderer to **Mobile**
(or Forward+) to receive reflection probes, glow, SSAO and volumetric fog. Keep a
Compatibility export preset for old Android GPUs. Set imported normal textures to
Normal Map, roughness to channel R, disable mipmaps only for tiny UI textures, and
preview all tiers through the in-game graphics setting.
