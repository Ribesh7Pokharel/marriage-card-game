extends Node2D

# ═══════════════════════════════════════════════════════
#  GameScene.gd
#  Attached to: scenes/screens/GameScene.tscn
#  What it does: The main game table controller.
#  Listens to GameState signals and updates the UI.
#  Handles player input and forwards to GameState.
#
#  LEARNING: This script is the "View + Controller"
#  in MVC. It never contains game logic — it only:
#  1. Listens to GameState signals (View)
#  2. Forwards player actions to GameState (Controller)
#
#  All the @onready vars below will be connected to
#  nodes you build in the Godot editor.
# ═══════════════════════════════════════════════════════


# ── NODE REFERENCES ─────────────────────────────────────
# These match the node names you'll create in the editor.
# We'll build the scene tree together after this script.

# Top bar
@onready var turn_label    : Label  = $UI/TopBar/TopBarHBox/TurnLabel
@onready var phase_label   : Label  = $UI/TopBar/TopBarHBox/PhaseLabel
@onready var deck_count    : Label  = $UI/TopBar/TopBarHBox/DeckCount
@onready var btn_quit      : Button = $UI/TopBar/TopBarHBox/BtnQuit

# Table center
@onready var status_label  : Label  = $UI/TableCenter/StatusLabel
@onready var btn_draw_deck : Button = $UI/TableCenter/BtnDrawDeck
@onready var btn_draw_disc : Button = $UI/TableCenter/BtnDrawDiscard
@onready var discard_label : Label  = $UI/TableCenter/DiscardLabel
@onready var tiplu_label   : Label  = $UI/TableCenter/TipluLabel

# Cut window (shown when player needs to cut deck)
@onready var cut_panel     : Panel  = $UI/CutPanel
@onready var btn_cut_left  : Button = $UI/CutPanel/HBox/BtnCutLeft
@onready var btn_cut_right : Button = $UI/CutPanel/HBox/BtnCutRight
@onready var cut_label     : Label  = $UI/CutPanel/CutLabel

# Player hand area
@onready var hand_container : HBoxContainer = $UI/HandArea/HandScroll/HandContainer
@onready var hand_label     : Label         = $UI/HandArea/HandLabel

# Action buttons
@onready var btn_open_sets  : Button = $UI/ActionBar/BtnOpenSets
@onready var btn_finish     : Button = $UI/ActionBar/BtnFinish
@onready var btn_discard    : Button = $UI/ActionBar/BtnDiscard
@onready var btn_hint       : Button = $UI/ActionBar/BtnHint

# Opponent area
@onready var opponents_area : HBoxContainer = $UI/OpponentsArea

# Tunnela window
@onready var tunnela_panel  : Panel  = $UI/TunnelPanel
@onready var btn_declare_tun: Button = $UI/TunnelPanel/BtnDeclareTunnela
@onready var btn_skip_tun   : Button = $UI/TunnelPanel/BtnSkipTunnela

# Win panel
@onready var win_panel      : Panel  = $UI/WinPanel
@onready var win_label      : Label  = $UI/WinPanel/WinLabel
@onready var scores_container: VBoxContainer = $UI/WinPanel/ScoresContainer
@onready var btn_play_again : Button = $UI/WinPanel/BtnPlayAgain


# ── STATE ────────────────────────────────────────────────
var _selected_card_ids : Array  = []   # IDs of selected cards in hand
var _cpu_players       : Array  = []   # CPUPlayer nodes
var _status_tween      : Tween  = null


# ══════════════════════════════════════════════════════════
#  SETUP
# ══════════════════════════════════════════════════════════

func _ready() -> void:
	_connect_signals()
	_connect_buttons()
	_hide_all_panels()
	_spawn_cpu_players()
	_start_game()


func _start_game() -> void:
	GameState.start_game(
		GameState.num_players,
		GameState.is_multiplayer,
		GameState.game_mode,
		GameState.rate_per_point
	)


func _spawn_cpu_players() -> void:
	var difficulty : CPUPlayer.Difficulty = GameState.get_meta(
		"cpu_difficulty",
		CPUPlayer.Difficulty.MEDIUM
	)

	for i in range(1, GameState.num_players):
		var cpu          := CPUPlayer.new()
		cpu.player_index = i
		cpu.difficulty   = difficulty
		add_child(cpu)
		_cpu_players.append(cpu)


# ── CONNECT GAMESTATE SIGNALS ───────────────────────────
# LEARNING: We connect to ALL GameState signals here.
# When GameState emits a signal, our function runs
# and updates the UI to match the new state.

func _connect_signals() -> void:
	GameState.game_started.connect(_on_game_started)
	GameState.turn_changed.connect(_on_turn_changed)
	GameState.phase_changed.connect(_on_phase_changed)
	GameState.card_drawn.connect(_on_card_drawn)
	GameState.card_discarded.connect(_on_card_discarded)
	GameState.status_message.connect(_on_status_message)
	GameState.tunnela_declared.connect(_on_tunnela_declared)
	GameState.player_opened.connect(_on_player_opened)
	GameState.tiplu_revealed_to_player.connect(_on_tiplu_revealed)
	GameState.cut_initiated.connect(_on_cut_initiated)
	GameState.game_won.connect(_on_game_won)
	GameState.scores_calculated.connect(_on_scores_calculated)

	# DeckManager signals
	DeckManager.waiting_for_cut.connect(_on_waiting_for_cut)


func _connect_buttons() -> void:
	btn_quit.pressed.connect(_on_quit)
	btn_draw_deck.pressed.connect(_on_draw_deck_pressed)
	btn_draw_disc.pressed.connect(_on_draw_discard_pressed)
	btn_open_sets.pressed.connect(_on_open_sets_pressed)
	btn_finish.pressed.connect(_on_finish_pressed)
	btn_discard.pressed.connect(_on_discard_pressed)
	btn_hint.pressed.connect(_on_hint_pressed)
	btn_cut_left.pressed.connect(_on_cut_left)
	btn_cut_right.pressed.connect(_on_cut_right)
	btn_declare_tun.pressed.connect(_on_declare_tunnela)
	btn_skip_tun.pressed.connect(_on_skip_tunnela)
	btn_play_again.pressed.connect(_on_play_again)


func _hide_all_panels() -> void:
	if cut_panel:    cut_panel.hide()
	if tunnela_panel: tunnela_panel.hide()
	if win_panel:    win_panel.hide()
	if tiplu_label:  tiplu_label.hide()


# ══════════════════════════════════════════════════════════
#  GAMESTATE SIGNAL HANDLERS
#  These run whenever GameState emits a signal
# ══════════════════════════════════════════════════════════

func _on_game_started() -> void:
	_refresh_hand()
	_refresh_opponents()
	_update_top_bar()
	_update_action_buttons()

	# Show tunnela window if it's the tunnela phase
	if GameState.phase == GameState.Phase.TUNNELA_WINDOW:
		if tunnela_panel:
			tunnela_panel.show()


func _on_turn_changed(player_index: int) -> void:
	_update_top_bar()
	_update_action_buttons()
	_refresh_opponents()

	# Highlight whose turn it is
	var pname := GameState.players[player_index].player_name
	if player_index == GameState.local_player:
		_flash_status("Your turn! Draw a card.", false)
	else:
		_flash_status("%s is thinking..." % pname, false)


func _on_phase_changed(new_phase: GameState.Phase) -> void:
	_update_action_buttons()
	_update_top_bar()

	# Show/hide cut panel
	if cut_panel:
		cut_panel.visible = (new_phase == GameState.Phase.CUT_WINDOW)

	# Show/hide tunnela panel
	if tunnela_panel:
		tunnela_panel.visible = (new_phase == GameState.Phase.TUNNELA_WINDOW)


func _on_card_drawn(player_index: int, _card: CardData) -> void:
	if player_index == GameState.local_player:
		_refresh_hand()
	_update_deck_display()
	_update_action_buttons()


func _on_card_discarded(player_index: int, card: CardData) -> void:
	if player_index == GameState.local_player:
		_refresh_hand()
		_clear_selection()
	_update_discard_display()
	_update_action_buttons()
	_refresh_opponents()


func _on_status_message(message: String, is_error: bool) -> void:
	_flash_status(message, is_error)


func _on_tunnela_declared(player_index: int, _tunnela: Array) -> void:
	if player_index == GameState.local_player:
		_refresh_hand()
	_refresh_opponents()


func _on_player_opened(player_index: int, _sets: Array) -> void:
	_refresh_opponents()
	if player_index == GameState.local_player:
		_refresh_hand()


func _on_tiplu_revealed(player_index: int, tiplu: CardData) -> void:
	if player_index == GameState.local_player:
		# Show the Tiplu to the local player
		if tiplu_label:
			tiplu_label.text = "Tiplu: %s" % tiplu.display_name()
			tiplu_label.show()
		_refresh_hand()  # Roles have changed — refresh card colors
		_flash_status(
			"Your Tiplu is %s! Jhiplu=%s, Poplu=%s" % [
				tiplu.display_name(),
				_jhiplu_label(tiplu),
				_poplu_label(tiplu)
			],
			false
		)
	else:
		_flash_status(
			"%s has seen the Tiplu!" % GameState.players[player_index].player_name,
			false
		)


func _on_cut_initiated(player_index: int) -> void:
	if player_index == GameState.local_player:
		if cut_panel:
			cut_panel.show()
		_flash_status("Cut the deck — choose a pile!", false)


func _on_waiting_for_cut(top_count: int, bottom_count: int) -> void:
	if cut_label:
		cut_label.text = "Choose a pile to cut:"
	if btn_cut_left:
		btn_cut_left.text  = "Left\n(%d cards)" % top_count
	if btn_cut_right:
		btn_cut_right.text = "Right\n(%d cards)" % bottom_count


func _on_game_won(_winner_index: int, _scores: Array) -> void:
	if win_panel:
		win_panel.show()


func _on_scores_calculated(results: Array) -> void:
	if not scores_container:
		return

	# Clear old scores
	for child in scores_container.get_children():
		child.queue_free()

	# Add score rows
	for result in results:
		var lbl      := Label.new()
		var money    : int  = result["money"]
		var seen_str : String = "(seen)" if result["has_seen"] else "(unseen)"
		var arrow    : String = "+" if money >= 0 else ""

		lbl.text = "%s %s — %d pts — %s%d pts" % [
			result["player_name"],
			seen_str,
			result["card_points"],
			arrow,
			money
		]

		# Color winners green, losers red
		if result["is_winner"]:
			lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3))
		elif money < 0:
			lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

		scores_container.add_child(lbl)

	if win_label:
		var winner_name := ""
		for r in results:
			if r["is_winner"]:
				winner_name = r["player_name"]
				break
		win_label.text = "%s Wins! 🎉" % winner_name


# ══════════════════════════════════════════════════════════
#  BUTTON HANDLERS — Player Input
# ══════════════════════════════════════════════════════════

func _on_draw_deck_pressed() -> void:
	GameState.draw_from_deck(GameState.local_player)

func _on_draw_discard_pressed() -> void:
	GameState.pick_up_discard(GameState.local_player)

func _on_cut_left() -> void:
	GameState.player_cuts_top(GameState.local_player)
	if cut_panel: cut_panel.hide()

func _on_cut_right() -> void:
	GameState.player_cuts_bottom(GameState.local_player)
	if cut_panel: cut_panel.hide()

func _on_declare_tunnela() -> void:
	if _selected_card_ids.size() != 3:
		_flash_status("Select exactly 3 cards for a Tunnela!", true)
		return
	var ok := GameState.declare_tunnela(GameState.local_player, _selected_card_ids)
	if ok:
		_clear_selection()

func _on_skip_tunnela() -> void:
	GameState.end_tunnela_window()
	if tunnela_panel: tunnela_panel.hide()

func _on_open_sets_pressed() -> void:
	# For opening, player selects cards and clicks this button
	# We need at least 9 cards selected (3 sets of 3)
	if _selected_card_ids.size() < 9:
		_flash_status("Select at least 9 cards (3 sets of 3) to open!", true)
		return

	# Split selected cards into groups of 3
	var sets : Array = []
	var ids   := _selected_card_ids.duplicate()
	while ids.size() >= 3:
		sets.append(ids.slice(0, 3))
		ids = ids.slice(3)

	var ok := GameState.show_opening_sets(GameState.local_player, sets)
	if ok:
		_clear_selection()

func _on_finish_pressed() -> void:
	var player := GameState.get_my_player()

	if player.is_dublee_play:
		# For dublee finish, need exactly 2 cards selected
		if _selected_card_ids.size() != 2:
			_flash_status("Select 2 cards for your final Dublee!", true)
			return
		GameState.declare_finish_dublee(GameState.local_player, _selected_card_ids)
	else:
		# For sequence finish, need 12 cards (4 sets of 3)
		if _selected_card_ids.size() < 12:
			_flash_status("Select 12 cards (4 sets of 3) to finish!", true)
			return

		var sets : Array = []
		var ids   := _selected_card_ids.duplicate()
		while ids.size() >= 3:
			sets.append(ids.slice(0, 3))
			ids = ids.slice(3)

		GameState.declare_finish_sequence(GameState.local_player, sets)

func _on_discard_pressed() -> void:
	if _selected_card_ids.size() != 1:
		_flash_status("Select exactly 1 card to discard!", true)
		return
	var ok := GameState.discard_card(GameState.local_player, _selected_card_ids[0])
	if ok:
		_clear_selection()

func _on_hint_pressed() -> void:
	var hand := GameState.get_my_hand()
	var sets  := MeldValidator.find_opening_sets(hand)
	if sets.is_empty():
		_flash_status("No obvious opening sets found — keep drawing!", false)
		return

	# Highlight the first suggested set
	var first_set : Array = sets[0][0]
	_clear_selection()
	for set_cards in sets[0]:
		for card in set_cards:
			var c := card as CardData
			if not _selected_card_ids.has(c.unique_id):
				_selected_card_ids.append(c.unique_id)
	_refresh_hand()
	_flash_status("Hint: try selecting the highlighted cards!", false)

func _on_quit() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/MainMenu.tscn")

func _on_play_again() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/MainMenu.tscn")


# ══════════════════════════════════════════════════════════
#  HAND RENDERING
#  Draws the player's cards as buttons in the hand area
# ══════════════════════════════════════════════════════════

func _refresh_hand() -> void:
	if not hand_container:
		return

	# Clear existing card buttons
	for child in hand_container.get_children():
		child.queue_free()

	var hand := GameState.get_my_hand()

	# Sort hand: by suit then rank
	# LEARNING: sort_custom takes a function that returns
	# true if a should come before b
	var sorted := hand.duplicate()
	sorted.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit != b.suit:
			return a.suit < b.suit
		return a.rank_value < b.rank_value
	)

	# Create a button for each card
	for card in sorted:
		var btn := _make_card_button(card)
		hand_container.add_child(btn)

	# Update hand count label
	if hand_label:
		hand_label.text = "Your Hand (%d cards)" % hand.size()


func _make_card_button(card: CardData) -> Button:
	var btn                 := Button.new()
	btn.name                = card.unique_id
	btn.custom_minimum_size = Vector2(56, 80)
	btn.text                = "%s\n%s" % [card.rank_label(), card.suit_symbol()]

	# Color based on card type
	# LEARNING: add_theme_color_override sets a specific
	# theme color just for this button instance
	var is_selected := _selected_card_ids.has(card.unique_id)

	if card.is_wild_joker:
		btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	elif card.is_red:
		btn.add_theme_color_override("font_color", Color(0.8, 0.1, 0.1))
	else:
		btn.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))

	# Show role label for special cards (after Tiplu revealed)
	if card.role != CardData.Role.NORMAL and card.role != CardData.Role.WILD_JOKER:
		btn.text += "\n[%s]" % card.role_label()
		btn.add_theme_color_override("font_color", Color(0.961, 0.651, 0.137))

	# Selected state — moved up visually
	if is_selected:
		btn.position.y = -15

	# Connect press to selection toggle
	btn.pressed.connect(_on_card_pressed.bind(card.unique_id))
	return btn


func _on_card_pressed(uid: String) -> void:
	# Only allow selection during PLAY phase on your turn
	if not GameState.is_my_turn():
		return
	if GameState.phase not in [GameState.Phase.PLAY, GameState.Phase.TUNNELA_WINDOW]:
		return

	# Toggle selection
	if _selected_card_ids.has(uid):
		_selected_card_ids.erase(uid)
	else:
		_selected_card_ids.append(uid)

	_refresh_hand()


func _clear_selection() -> void:
	_selected_card_ids.clear()
	_refresh_hand()


# ══════════════════════════════════════════════════════════
#  UI UPDATES
# ══════════════════════════════════════════════════════════

func _update_top_bar() -> void:
	if turn_label:
		var p := GameState.players[GameState.current_player]
		if GameState.is_my_turn():
			turn_label.text = "🟢 Your Turn"
			turn_label.add_theme_color_override("font_color", Color(0.961, 0.651, 0.137))
		else:
			turn_label.text = "⏳ %s" % p.player_name
			turn_label.add_theme_color_override("font_color", Color(0.66, 0.85, 0.70))

	if phase_label:
		phase_label.text = GameState.phase_label()

	_update_deck_display()


func _update_deck_display() -> void:
	if deck_count:
		deck_count.text = "Deck: %d" % DeckManager.deck_count()


func _update_discard_display() -> void:
	var top := GameState.top_discard()
	if discard_label:
		if top:
			discard_label.text = "Discard:\n%s" % top.display_name()
		else:
			discard_label.text = "Discard:\nempty"


func _update_action_buttons() -> void:
	var my_turn    := GameState.is_my_turn()
	var play_phase := GameState.phase == GameState.Phase.PLAY
	var draw_phase := GameState.phase == GameState.Phase.DRAW
	var player     := GameState.get_my_player()

	if btn_draw_deck: btn_draw_deck.disabled = not (my_turn and draw_phase)
	if btn_draw_disc: btn_draw_disc.disabled  = not (my_turn and draw_phase)
	if btn_discard:   btn_discard.disabled    = not (my_turn and play_phase)
	if btn_hint:      btn_hint.disabled       = not my_turn

	# Open sets button — only if not opened yet
	if btn_open_sets:
		btn_open_sets.disabled = not (my_turn and play_phase and not player.has_opened)

	# Finish button — only if opened and seen tiplu
	if btn_finish:
		btn_finish.disabled = not (my_turn and play_phase and player.has_opened and player.has_seen_tiplu)


func _refresh_opponents() -> void:
	if not opponents_area:
		return

	# Clear and rebuild opponent panels
	for child in opponents_area.get_children():
		child.queue_free()

	for i in GameState.num_players:
		if i == GameState.local_player:
			continue
		var panel := _make_opponent_panel(i)
		opponents_area.add_child(panel)


func _make_opponent_panel(player_index: int) -> PanelContainer:
	var p     := GameState.players[player_index]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(140, 80)

	var vb    := VBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = p.player_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.66, 0.85, 0.70))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var cards_lbl := Label.new()
	cards_lbl.text = "%d cards" % p.hand_count()
	cards_lbl.add_theme_font_size_override("font_size", 12)
	cards_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var status_lbl := Label.new()
	var status_parts : Array[String] = []
	if p.has_opened:     status_parts.append("Opened")
	if p.has_seen_tiplu: status_parts.append("Seen Tiplu")
	if p.is_dublee_play: status_parts.append("Dublee")
	status_lbl.text = " | ".join(status_parts) if not status_parts.is_empty() else "Playing"
	status_lbl.add_theme_font_size_override("font_size", 11)
	status_lbl.add_theme_color_override("font_color", Color(0.961, 0.651, 0.137, 0.8))
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# Highlight current player's panel
	if GameState.current_player == player_index:
		name_lbl.add_theme_color_override("font_color", Color(0.961, 0.651, 0.137))

	vb.add_child(name_lbl)
	vb.add_child(cards_lbl)
	vb.add_child(status_lbl)
	panel.add_child(vb)
	return panel


# ── STATUS FLASH ─────────────────────────────────────────
func _flash_status(message: String, is_error: bool) -> void:
	if not status_label:
		return

	status_label.text = message
	status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.4, 0.4) if is_error else Color.WHITE
	)

	# Fade out after 4 seconds
	if _status_tween:
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_interval(4.0)
	_status_tween.tween_property(status_label, "modulate:a", 0.5, 0.5)
	_status_tween.tween_property(status_label, "modulate:a", 1.0, 0.1)


# ── HELPERS ──────────────────────────────────────────────
func _jhiplu_label(tiplu: CardData) -> String:
	var rank := tiplu.rank_value - 1
	if rank == 0: rank = 13
	return CardData.RANK_LABELS[rank as CardData.Rank] + tiplu.suit_symbol()

func _poplu_label(tiplu: CardData) -> String:
	var rank := tiplu.rank_value + 1
	if rank == 14: rank = 1
	return CardData.RANK_LABELS[rank as CardData.Rank] + tiplu.suit_symbol()
