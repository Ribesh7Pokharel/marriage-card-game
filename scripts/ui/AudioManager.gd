extends Node

# ─────────────────────────────────────────────
#  AudioManager.gd  (Autoload singleton)
#  Centralised sound + music management.
#  Uses AudioStreamPlayer nodes created at runtime.
#  Replace placeholder paths with your actual .ogg/.wav files.
# ─────────────────────────────────────────────

# ── Volume settings ────────────────────────────
var sfx_volume   : float = 0.8   # 0.0 – 1.0
var music_volume : float = 0.5

# ── Sound effect paths (drop your files in assets/sounds/) ──
const SFX := {
	"card_deal"   : "res://assets/sounds/card_deal.ogg",
	"card_flip"   : "res://assets/sounds/card_flip.ogg",
	"card_slide"  : "res://assets/sounds/card_slide.ogg",
	"meld_lay"    : "res://assets/sounds/meld_lay.ogg",
	"win"         : "res://assets/sounds/win.ogg",
	"error"       : "res://assets/sounds/error.ogg",
	"shuffle"     : "res://assets/sounds/shuffle.ogg",
	"button_click": "res://assets/sounds/button_click.ogg",
}

var _sfx_pool    : Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer        = null
var _pool_size   : int                      = 8

func _ready() -> void:
	# Pre-create SFX pool (avoids allocation mid-game)
	for i in _pool_size:
		var p := AudioStreamPlayer.new()
		p.bus  = "SFX"
		add_child(p)
		_sfx_pool.append(p)

	# Music player
	_music_player = AudioStreamPlayer.new()
	_music_player.bus    = "Music"
	_music_player.volume_db = linear_to_db(music_volume)
	add_child(_music_player)

func play_sfx(sound_name: String) -> void:
	if not SFX.has(sound_name):
		return
	var path: String = SFX[sound_name]
	if not ResourceLoader.exists(path):
		return   # File not found — silent fail (placeholder)

	var player := _get_free_player()
	if not player:
		return

	player.stream    = load(path)
	player.volume_db = linear_to_db(sfx_volume)
	player.play()

func play_music(path: String, loop: bool = true) -> void:
	if not ResourceLoader.exists(path):
		return
	_music_player.stream = load(path)
	if _music_player.stream is AudioStreamOggVorbis:
		(_music_player.stream as AudioStreamOggVorbis).loop = loop
	_music_player.volume_db = linear_to_db(music_volume)
	_music_player.play()

func stop_music() -> void:
	_music_player.stop()

func set_sfx_volume(value: float) -> void:
	sfx_volume = clamp(value, 0.0, 1.0)

func set_music_volume(value: float) -> void:
	music_volume = clamp(value, 0.0, 1.0)
	_music_player.volume_db = linear_to_db(music_volume)

func _get_free_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	# All busy — steal the first one
	return _sfx_pool[0]
