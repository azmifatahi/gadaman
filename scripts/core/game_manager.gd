## Run state machine, scoring, combos and the local high-score table.
##
## The manager deliberately owns *no* gameplay nodes: it only reacts to signals.
## That keeps the run loop testable and lets the UI be built in isolation.
extends Node

signal state_changed(state: int)
signal score_changed(score: int, distance: float, cups: int)
signal combo_changed(combo: int, multiplier: int)
signal combo_ended(combo: int)
signal milestone_reached(meters: int)
signal run_finished(summary: Dictionary)
signal best_changed(best_score: int, best_distance: float)

enum State { MENU, RUNNING, PAUSED, GAME_OVER }

const SAVE_PATH := "user://sudan_runner_progress.cfg"
const MILESTONE_STEP := 250.0
const COMBO_WINDOW := 2.2      # seconds to chain another cup
const COMBO_STEP := 5          # picks per multiplier step
const MAX_MULTIPLIER := 5
const CUP_POINTS := 10

var state: int = State.MENU
var score: int = 0
var distance: float = 0.0
var cups: int = 0
var combo: int = 0
var multiplier: int = 1

var best_score: int = 0
var best_distance: float = 0.0
var total_runs: int = 0
var total_cups: int = 0
var total_distance: float = 0.0

var _combo_timer := 0.0
var _next_milestone := MILESTONE_STEP
var _config := ConfigFile.new()
var _last_summary: Dictionary = {}
var _score_signal_budget := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_progress()


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return
	if combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			_end_combo()
	# The HUD does not need 120 updates/s; 20 Hz is smooth for counters.
	_score_signal_budget += delta
	if _score_signal_budget >= 0.05:
		_score_signal_budget = 0.0
		score_changed.emit(score, distance, cups)


# ---------------------------------------------------------------------------
# Run lifecycle
# ---------------------------------------------------------------------------
func start_run() -> void:
	score = 0
	distance = 0.0
	cups = 0
	combo = 0
	multiplier = 1
	_combo_timer = 0.0
	_next_milestone = MILESTONE_STEP
	_last_summary = {}
	_set_state(State.RUNNING)
	score_changed.emit(score, distance, cups)
	combo_changed.emit(combo, multiplier)


func end_run(crash_reason: String = "") -> void:
	if state == State.GAME_OVER:
		return
	var is_best := score > best_score
	best_score = maxi(best_score, score)
	best_distance = maxf(best_distance, distance)
	total_runs += 1
	total_cups += cups
	total_distance += distance
	save_progress()
	_last_summary = {
		"score": score,
		"distance": distance,
		"cups": cups,
		"best_score": best_score,
		"best_distance": best_distance,
		"is_best": is_best,
		"reason": crash_reason,
	}
	_set_state(State.GAME_OVER)
	Audio.play_sfx("gameover", 0.0)
	best_changed.emit(best_score, best_distance)
	run_finished.emit(_last_summary)


func toggle_pause() -> void:
	if state == State.RUNNING:
		_set_state(State.PAUSED)
		get_tree().paused = true
		Audio.set_music_paused(true)
	elif state == State.PAUSED:
		get_tree().paused = false
		_set_state(State.RUNNING)
		Audio.set_music_paused(false)


func resume() -> void:
	if state == State.PAUSED:
		get_tree().paused = false
		_set_state(State.RUNNING)
		Audio.set_music_paused(false)


func to_menu() -> void:
	get_tree().paused = false
	_set_state(State.MENU)


func _set_state(new_state: int) -> void:
	state = new_state
	state_changed.emit(state)


func last_summary() -> Dictionary:
	return _last_summary


func is_playing() -> bool:
	return state == State.RUNNING


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------
func add_distance(meters: float) -> void:
	if state != State.RUNNING or meters <= 0.0:
		return
	distance += meters
	score += int(meters)
	if distance >= _next_milestone:
		_next_milestone += MILESTONE_STEP
		milestone_reached.emit(int(distance))
		Audio.play_sfx("milestone", 0.0, 0.8)
		Settings.vibrate(18)


func collect_cup(_kind: int = 0) -> void:
	if state != State.RUNNING:
		return
	cups += 1
	combo += 1
	multiplier = mini(1 + int(combo / COMBO_STEP), MAX_MULTIPLIER)
	_combo_timer = COMBO_WINDOW
	score += CUP_POINTS * multiplier
	combo_changed.emit(combo, multiplier)
	Audio.play_sfx("pickup", 0.10, 0.9)
	if combo > 0 and combo % COMBO_STEP == 0:
		Audio.play_sfx("combo", 0.0, 0.85)


func _end_combo() -> void:
	var finished_combo := combo
	combo = 0
	multiplier = 1
	_combo_timer = 0.0
	combo_changed.emit(combo, multiplier)
	combo_ended.emit(finished_combo)


func bonus(points: int) -> void:
	if state == State.RUNNING:
		score += points
		score_changed.emit(score, distance, cups)


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------
func load_progress() -> void:
	if _config.load(SAVE_PATH) != OK:
		return
	best_score = int(_config.get_value("progress", "best_score", 0))
	best_distance = float(_config.get_value("progress", "best_distance", 0.0))
	total_runs = int(_config.get_value("progress", "total_runs", 0))
	total_cups = int(_config.get_value("progress", "total_cups", 0))
	total_distance = float(_config.get_value("progress", "total_distance", 0.0))


func save_progress() -> void:
	_config.set_value("progress", "best_score", best_score)
	_config.set_value("progress", "best_distance", best_distance)
	_config.set_value("progress", "total_runs", total_runs)
	_config.set_value("progress", "total_cups", total_cups)
	_config.set_value("progress", "total_distance", total_distance)
	_config.save(SAVE_PATH)


func reset_progress() -> void:
	best_score = 0
	best_distance = 0.0
	total_runs = 0
	total_cups = 0
	total_distance = 0.0
	save_progress()
	best_changed.emit(best_score, best_distance)
