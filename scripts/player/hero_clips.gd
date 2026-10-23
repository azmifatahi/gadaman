## Small, engine-independent helpers shared by the hero builder and the runtime
## animation driver.
##
## Why this file exists
## --------------------
## v1.2.2 shipped a runner frozen in its T-pose because the game relied on an
## `AnimationTree` whose `tree_root` did not survive `PackedScene.pack()`. Building
## animation graphs through `AnimationNode*` resources is fragile (nested resource
## graphs, editor-only properties such as `start_node`, duplicated "output"
## nodes…). The game therefore drives the imported `AnimationPlayer` directly and
## only keeps the naming/blending rules here, in one place:
##
##   * which clip is which kind (locomotion / one-shot / cutscene)
##   * which locomotion clip belongs to a given run speed
##   * how a file inside the character folder maps to a clip name
extends RefCounted

## Locomotion clips and the blend value (0..1) at which they become current.
## The game drives `run_blend` from the track speed as (speed - 9) / 18, so a
## normal run sits around 0.10-0.30. Idle therefore has to end below that: the
## runner must be *jogging* for almost the whole session, and the static idle
## pose is only for menus, pause and the game-over screen.
const LOCOMOTION := {
	"idle": 0.10,
	"jog": 0.80,
	"sprint": 1.0,
}

## Clips that play once and then hand control back to the locomotion cycle.
const ONE_SHOTS := ["jump", "fall", "land", "slide", "stumble"]

## Folders that may hold the character (the Arabic one comes first on purpose).
const CLIP_NAMES := {
	"idle": ["idle", "breathing", "stand"],
	"jog": ["jog", "run forward", "run", "running"],
	"sprint": ["sprint", "fast run", "run fast", "sprint forward"],
	"jump": ["jump", "jumping", "jump up", "jump forward"],
	"fall": ["fall", "falling", "falling to landing", "fall to landing", "air"],
	"land": ["land", "landing", "falling to landing"],
	"slide": ["slide", "sliding", "running slide", "slide forward"],
	"stumble": ["stumble", "jogging stumble", "hit", "stumble forward"],
}

## Extra names Mixamo users export the same motions under.
const ALIASES := {
	"running slide": "slide",
	"run slide": "slide",
	"jogging stumble": "stumble",
	"falling to landing": "fall",
	"fall to landing": "fall",
	"run forward": "jog",
	"running forward": "jog",
}


## Classifies a file name (without extension) as one of the clip keys.
## Returns "" when nothing matches, so unknown files are simply ignored.
static func classify(file_name: String) -> String:
	var base := file_name.get_basename().to_lower()
	for ch in ["_", "-", ".", "  "]:
		base = base.replace(ch, " ")
	base = base.strip_edges()
	while base.contains("  "):
		base = base.replace("  ", " ")
	if ALIASES.has(base):
		return String(ALIASES[base])
	# "falling to landing" contains both "fall" and "land": prefer the landing
	# clip for the fall half so the pair is not duplicated.
	for key in CLIP_NAMES.keys():
		for alias in CLIP_NAMES[key]:
			if base == String(alias):
				return String(key)
	# Partial match, most specific first.
	if base.contains("slide"):
		return "slide"
	if base.contains("stumble"):
		return "stumble"
	if base.contains("land"):
		return "land"
	if base.contains("fall"):
		return "fall"
	if base.contains("jump"):
		return "jump"
	if base.contains("sprint"):
		return "sprint"
	if base.contains("idle") or base.contains("breath"):
		return "idle"
	if base.contains("jog") or base.contains("run"):
		return "jog"
	return ""


## Locomotion clip for a 0..1 blend value (see LOCOMOTION for the cutoffs).
static func locomotion_clip(blend: float) -> String:
	var value := clampf(blend, 0.0, 1.0)
	if value < float(LOCOMOTION["idle"]):
		return "idle"
	if value < float(LOCOMOTION["jog"]):
		return "jog"
	return "sprint"


## Cross-fade time for a clip, in seconds.
static func fade_time(clip: String) -> float:
	match clip:
		"idle", "jog", "sprint":
			return 0.25
		"jump":
			return 0.12
		"slide", "stumble":
			return 0.10
		_:
			return 0.15
