## Pooled audio playback.
##
## Every sound goes through a fixed pool of AudioStreamPlayers created at boot:
## no `AudioStreamPlayer.new()` during gameplay means no allocation spikes, which
## is exactly what causes those 40 ms hitches on 2 GB phones.
extends Node

const MUSIC_PATH := "res://assets/audio/music_khartoum.ogg"
const MUSIC_VOLUME_DB := -6.0

const SFX_FILES := {
	"pickup": "res://assets/audio/sfx_pickup.ogg",
	"combo": "res://assets/audio/sfx_combo.ogg",
	"jump": "res://assets/audio/sfx_jump.ogg",
	"slide": "res://assets/audio/sfx_slide.ogg",
	"hit": "res://assets/audio/sfx_hit.ogg",
	"gameover": "res://assets/audio/sfx_gameover.ogg",
	"click": "res://assets/audio/sfx_click.ogg",
	"milestone": "res://assets/audio/sfx_milestone.ogg",
	"cheer": "res://assets/audio/sfx_cheer.ogg",
}

const POOL_SIZE := 8

var _music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _pool_index := 0
var _streams: Dictionary = {}
var _music_volume := 0.75
var _sfx_volume := 0.9
var _music_wanted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_streams()

	_music = AudioStreamPlayer.new()
	_music.name = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)

	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % i
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_pool.append(player)

	if has_node("/root/Settings"):
		var settings := get_node("/root/Settings")
		apply_volumes(settings.music_volume, settings.sfx_volume)


func _load_streams() -> void:
	for key in SFX_FILES:
		if ResourceLoader.exists(SFX_FILES[key]):
			_streams[key] = load(SFX_FILES[key])
	var music: AudioStream = null
	if ResourceLoader.exists(MUSIC_PATH):
		music = load(MUSIC_PATH)
	if music:
		# Ogg import defaults to non-looping; the runner track must loop forever.
		if music is AudioStreamOggVorbis:
			music.loop = true
		elif music is AudioStreamWAV:
			music.loop_mode = AudioStreamWAV.LOOP_FORWARD
			music.loop_end = int(music.get_length() * music.mix_rate)
		_streams["music"] = music


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------
func play_music() -> void:
	_music_wanted = true
	if _music == null or _streams.get("music") == null:
		return
	if _music.playing:
		return
	_music.stream = _streams["music"]
	_music.volume_db = _volume_to_db(_music_volume) + MUSIC_VOLUME_DB
	_music.play()


func stop_music(fade: float = 0.4) -> void:
	_music_wanted = false
	if _music and _music.playing:
		var tween := create_tween()
		tween.tween_property(_music, "volume_db", -60.0, maxf(fade, 0.01))
		tween.tween_callback(_music.stop)


func set_music_paused(paused: bool) -> void:
	if _music == null:
		return
	var target := -60.0 if paused else _volume_to_db(_music_volume) + MUSIC_VOLUME_DB
	create_tween().tween_property(_music, "volume_db", target, 0.25)


# ---------------------------------------------------------------------------
# SFX
# ---------------------------------------------------------------------------
func play_sfx(key: String, pitch_variation: float = 0.06, volume_scale: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null or _pool.is_empty() or _sfx_volume <= 0.001:
		return
	var player := _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	player.volume_db = _volume_to_db(_sfx_volume) + linear_to_db(clampf(volume_scale, 0.05, 2.0))
	player.play()


func play_click() -> void:
	play_sfx("click", 0.02, 0.7)


func apply_volumes(music: float, sfx: float) -> void:
	_music_volume = clampf(music, 0.0, 1.0)
	_sfx_volume = clampf(sfx, 0.0, 1.0)
	if _music and _music.playing:
		_music.volume_db = _volume_to_db(_music_volume) + MUSIC_VOLUME_DB


func _volume_to_db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(linear)
