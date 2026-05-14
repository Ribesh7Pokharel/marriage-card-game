extends Control

# ─────────────────────────────────────────────
#  MainMenu.gd
#  Attached to: scenes/screens/MainMenu.tscn
# ─────────────────────────────────────────────

@onready var btn_2p      : Button = $CenterContainer/VBoxContainer/BtnPlay2P
@onready var btn_3p      : Button = $CenterContainer/VBoxContainer/BtnPlay3P
@onready var btn_4p      : Button = $CenterContainer/VBoxContainer/BtnPlay4P
@onready var btn_5p      : Button = $CenterContainer/VBoxContainer/BtnPlay5P
@onready var btn_online  : Button = $CenterContainer/VBoxContainer/BtnOnline
@onready var btn_rules   : Button = $CenterContainer/VBoxContainer/BtnRules
@onready var title_label : Label  = $CenterContainer/VBoxContainer/TitleLabel

const GAME_SCENE  := "res://scenes/screens/GameScene.tscn"
const RULES_SCENE := "res://scenes/screens/RulesScreen.tscn"
const LOBBY_SCENE := "res://scenes/screens/LobbyScreen.tscn"

func _ready() -> void:
	btn_2p.pressed.connect(func(): _start_local(2))
	btn_3p.pressed.connect(func(): _start_local(3))
	btn_4p.pressed.connect(func(): _start_local(4))
	btn_5p.pressed.connect(func(): _start_local(5))
	btn_online.pressed.connect(_open_lobby)
	btn_rules.pressed.connect(_open_rules)

	# Fade in animation
	modulate.a = 0.0
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, 0.6)

func _start_local(num_players: int) -> void:
	GameState.num_players    = num_players
	GameState.is_multiplayer = false
	get_tree().change_scene_to_file(GAME_SCENE)

func _open_lobby() -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)

func _open_rules() -> void:
	get_tree().change_scene_to_file(RULES_SCENE)
