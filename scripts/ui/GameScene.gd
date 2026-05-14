extends Node2D

# ─────────────────────────────────────────────
#  GameScene.gd
# ─────────────────────────────────────────────

# ── UI node references ─────────────────────────
@onready var turn_label        : Label         = $UI/TopBar/TopBarHBox/TurnLabel
@onready var score_label       : Label         = $UI/TopBar/TopBarHBox/ScoreLabel
@onready var phase_label       : Label         = $UI/TopBar/TopBarHBox/PhaseLabel
@onready var quit_btn          : Button        = $UI/TopBar/TopBarHBox/QuitBtn
@onready var opponents_area    : HBoxContainer = $UI/OpponentsArea
@onready var status_label      : Label         = $UI/TableCenter/PilesRow/CenterInfo/StatusMsg/StatusLabel
@onready var btn_draw_deck     : Button        = $UI/TableCenter/PilesRow/CenterInfo/DrawDiscardBtns/BtnDrawDeck
@onready var btn_draw_discard  : Button        = $UI/TableCenter/PilesRow/CenterInfo/DrawDiscardBtns/BtnDrawDiscard
@onready var deck_count        : Label         = $UI/TableCenter/PilesRow/DeckArea/DeckCount
@onready var discard_top_label : Label         = $UI/TableCenter/PilesRow/DiscardArea/DiscardCardVisual/DiscardTopLabel
@onready var discard_info      : Label         = $UI/TableCenter/PilesRow/DiscardArea/DiscardInfo
@onready var melds_container   : HBoxContainer = $UI/TableCenter/MeldsSection/MeldsPanelContainer/MeldsContainer
@onready var hand_label        : Label         = $UI/HandSection/HandTopRow/HandLabel
@onready var hand_cards_cont   : HBoxContainer = $UI/HandSection/HandCardsPanel/HandCardsScroll/HandCardsContainer
@onready var btn_select_all    : Button        = $UI/HandSection/HandTopRow/BtnSelectAll
@onready var btn_clear         : Button        = $UI/HandSection/HandTopRow/BtnClear
@onready var btn_lay_meld      : Button        = $UI/HandSection/ActionBar/BtnLayMeld
@onready var btn_discard       : Button        = $UI/HandSection/ActionBar/BtnDiscard
@onready var btn_hint          : Button        = $UI/HandSection/ActionBar/BtnHint
@onready var win_panel         : PanelContainer = $UI/WinPanel
@onready var win_label         : Label         = $UI/WinPanel/WinVBox/WinLabel
@onready var win_sub           : Label         = $UI/WinPanel/WinVBox/WinSub
@onready var win_back_btn      : Button        = $UI/WinPanel/WinVBox/WinBackBtn

# ── Card colours ───────────────────────────────
const COLOR_RED   := Color("#C0392B")
const COLOR_BLACK := Color("#1A1A2E")
const COLOR_JOKER_BG := Color("#2d1b4e")

# ── State ──────────────────────────────────────
var _selected_ids  : Array  = []
var _cpu_players   : Array  = []
var _status_tween  : Tween  = null

# ──────────────────────────────────────────────
func _ready() -> void:
	win_panel.hide()
	_connect_signals()
	_start_game()

func _start_game() -> void:
	var num_players : int = GameState.num_players
	# Spawn CPU players
	for i in range(1, num_players):
		var cpu          := CPUPlayer.new()
		cpu.player_index = i
		cpu.difficulty   = CPUPlayer.Difficulty.MEDIUM
		add_child(cpu)
		_cpu_players.append(cpu)

	GameState.setup_game(num_players)
	_build_opponents_ui()
	_refresh_hand()
	_update_ui()
	_flash_status("Game started! Draw a card to begin.", false)

# ── Signal wiring ──────────────────────────────
func _connect_signals() -> void:
	GameState.turn_changed.connect(_on_turn_changed)
	GameState.card_drawn.connect(_on_card_drawn)
	GameState.card_discarded.connect(_on_card_discarded)
	GameState.meld_laid.connect(_on_meld_laid)
	GameState.game_over.connect(_on_game_over)
	GameState.hand_updated.connect(_on_hand_updated)

	quit_btn.pressed.connect(_on_quit)
	btn_draw_deck.pressed.connect(_on_draw_deck)
	btn_draw_discard.pressed.connect(_on_draw_discard)
	btn_lay_meld.pressed.connect(_on_lay_meld)
	btn_discard.pressed.connect(_on_discard)
	btn_hint.pressed.connect(_on_hint)
	btn_select_all.pressed.connect(_on_select_all)
	btn_clear.pressed.connect(_on_clear_selection)
	win_back_btn.pressed.connect(_on_quit)

# ── Build opponent slots ───────────────────────
func _build_opponents_ui() -> void:
	for child in opponents_area.get_children():
		child.queue_free()

	for i in range(1, GameState.num_players):
		var p    := GameState.players[i]
		var panel := _make_opponent_panel(p.player_name, i)
		opponents_area.add_child(panel)

func _make_opponent_panel(p_name: String, idx: int) -> PanelContainer:
	var pc    := PanelContainer.new()
	pc.name   = "Opponent%d" % idx
	pc.custom_minimum_size = Vector2(160, 80)

	var sb := StyleBoxFlat.new()
	sb.bg_color            = Color(0, 0, 0, 0.3)
	sb.border_width_left   = 1
	sb.border_width_top    = 1
	sb.border_width_right  = 1
	sb.border_width_bottom = 1
	sb.border_color        = Color(1, 1, 1, 0.15)
	sb.corner_radius_top_left     = 10
	sb.corner_radius_top_right    = 10
	sb.corner_radius_bottom_right = 10
	sb.corner_radius_bottom_left  = 10
	sb.content_margin_left   = 10
	sb.content_margin_right  = 10
	sb.content_margin_top    = 8
	sb.content_margin_bottom = 8
	pc.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.name = "NameLabel"
	lbl.text = p_name
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.66, 0.85, 0.70, 1))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var card_lbl := Label.new()
	card_lbl.name = "CardLabel"
	card_lbl.text = "21 cards"
	card_lbl.add_theme_font_size_override("font_size", 12)
	card_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	card_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var meld_lbl := Label.new()
	meld_lbl.name = "MeldLabel"
	meld_lbl.text = "0 melds"
	meld_lbl.add_theme_font_size_override("font_size", 11)
	meld_lbl.add_theme_color_override("font_color", Color(0.961, 0.651, 0.137, 0.7))
	meld_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	vb.add_child(lbl)
	vb.add_child(card_lbl)
	vb.add_child(meld_lbl)
	pc.add_child(vb)
	return pc

# ── Hand rendering ─────────────────────────────
func _refresh_hand() -> void:
	for child in hand_cards_cont.get_children():
		child.queue_free()
	_selected_ids.clear()

	var hand := GameState.get_my_hand()
	# Sort: suit then rank
	var sorted := hand.duplicate()
	sorted.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.suit != b.suit: return a.suit < b.suit
		return a.rank_value < b.rank_value
	)

	for card_data in sorted:
		var btn := _make_card_button(card_data)
		hand_cards_cont.add_child(btn)

	hand_label.text = "YOUR HAND (%d cards)" % hand.size()

func _make_card_button(card_data: CardData) -> Button:
	var btn         := Button.new()
	btn.name        = card_data.unique_id
	btn.custom_minimum_size = Vector2(52, 74)
	btn.tooltip_text = card_data.display_name()

	# Style based on card type
	var sb         := StyleBoxFlat.new()
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left  = 6
	sb.content_margin_left   = 2
	sb.content_margin_right  = 2
	sb.content_margin_top    = 2
	sb.content_margin_bottom = 2

	if card_data.is_joker:
		sb.bg_color     = COLOR_JOKER_BG
		sb.border_width_left   = 2
		sb.border_width_top    = 2
		sb.border_width_right  = 2
		sb.border_width_bottom = 2
		sb.border_color = Color(0.961, 0.651, 0.137, 1)
		btn.text        = "JK\n★"
		btn.add_theme_color_override("font_color", Color.YELLOW)
	else:
		sb.bg_color     = Color.WHITE
		sb.border_width_left   = 1
		sb.border_width_top    = 1
		sb.border_width_right  = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0, 0, 0, 0.2)
		var ink         := COLOR_RED if card_data.is_red else COLOR_BLACK
		btn.text        = "%s\n%s" % [card_data.rank_label(), card_data.suit_symbol()]
		btn.add_theme_color_override("font_color", ink)

	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_font_size_override("font_size", 13)

	btn.pressed.connect(_on_card_pressed.bind(card_data.unique_id))
	return btn

func _on_card_pressed(uid: String) -> void:
	if not GameState.is_my_turn() or GameState.phase != GameState.Phase.PLAY:
		_flash_status("Draw a card first!", true)
		return

	var btn := hand_cards_cont.find_child(uid, false, false) as Button
	if not btn: return

	if _selected_ids.has(uid):
		_selected_ids.erase(uid)
		_set_card_selected(btn, false)
	else:
		_selected_ids.append(uid)
		_set_card_selected(btn, true)

func _set_card_selected(btn: Button, selected: bool) -> void:
	var sb         := StyleBoxFlat.new()
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_right = 6
	sb.corner_radius_bottom_left  = 6
	sb.content_margin_left   = 2
	sb.content_margin_right  = 2
	sb.content_margin_top    = 2
	sb.content_margin_bottom = 2

	if selected:
		sb.bg_color     = Color(0.961, 0.651, 0.137, 0.3)
		sb.border_width_left   = 3
		sb.border_width_top    = 3
		sb.border_width_right  = 3
		sb.border_width_bottom = 3
		sb.border_color = Color(0.961, 0.651, 0.137, 1)
		btn.position.y  = -12
	else:
		sb.bg_color     = Color.WHITE
		sb.border_width_left   = 1
		sb.border_width_top    = 1
		sb.border_width_right  = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0, 0, 0, 0.2)
		btn.position.y  = 0

	btn.add_theme_stylebox_override("normal",  sb)
	btn.add_theme_stylebox_override("hover",   sb)
	btn.add_theme_stylebox_override("pressed", sb)

# ── Player actions ─────────────────────────────
func _on_draw_deck() -> void:
	if not GameState.is_my_turn() or GameState.phase != GameState.Phase.DRAW:
		_flash_status("Not your turn to draw!", true)
		return
	GameState.draw_from_deck(0)

func _on_draw_discard() -> void:
	if not GameState.is_my_turn() or GameState.phase != GameState.Phase.DRAW:
		_flash_status("Not your turn!", true)
		return
	if GameState.discard_pile.is_empty():
		_flash_status("Discard pile is empty!", true)
		return
	GameState.draw_from_discard(0)

func _on_lay_meld() -> void:
	if not GameState.is_my_turn() or GameState.phase != GameState.Phase.PLAY:
		_flash_status("Draw a card first!", true)
		return
	if _selected_ids.size() < 2:
		_flash_status("Select at least 2 cards!", true)
		return
	var meld := GameState.lay_meld(0, _selected_ids)
	if not meld:
		_flash_status("❌ Not a valid meld! Need: Sequence (3+ same suit), Dublee (2 identical), or Tunnala (3 identical)", true)
		return
	_flash_status("✅ %s laid!" % meld.type_label(), false)
	_refresh_melds()

func _on_discard() -> void:
	if not GameState.is_my_turn() or GameState.phase != GameState.Phase.PLAY:
		_flash_status("Draw a card first!", true)
		return
	if _selected_ids.size() != 1:
		_flash_status("Select exactly 1 card to discard!", true)
		return
	var hand  := GameState.get_my_hand()
	var card  := hand.filter(func(c: CardData) -> bool: return c.unique_id == _selected_ids[0])
	if card.is_empty(): return
	GameState.discard_card(0, card[0])

func _on_hint() -> void:
	var hints := CardManager.suggest_melds(GameState.get_my_hand())
	if hints.is_empty():
		_flash_status("💡 No obvious melds — try discarding a lone card", false)
		return
	var best  : Dictionary = hints[0]
	var names := (best["cards"] as Array).map(func(c: CardData) -> String: return c.display_name())
	_flash_status("💡 Try a %s with: %s" % [best["type"], ", ".join(names)], false)

func _on_select_all() -> void:
	if GameState.phase != GameState.Phase.PLAY: return
	_selected_ids.clear()
	for c in GameState.get_my_hand():
		_selected_ids.append(c.unique_id)
	for btn in hand_cards_cont.get_children():
		_set_card_selected(btn as Button, true)

func _on_clear_selection() -> void:
	_selected_ids.clear()
	for btn in hand_cards_cont.get_children():
		_set_card_selected(btn as Button, false)

func _on_quit() -> void:
	get_tree().change_scene_to_file("res://scenes/screens/MainMenu.tscn")

# ── State callbacks ────────────────────────────
func _on_turn_changed(player_index: int) -> void:
	_update_ui()
	_update_opponents_ui()
	var pname := GameState.players[player_index].player_name
	_flash_status("%s's turn" % pname, false)

func _on_card_drawn(player_index: int, card: CardData) -> void:
	_update_deck_display()
	_update_discard_display()
	if player_index == 0:
		_refresh_hand()
		_flash_status("Drew %s — now meld or discard" % card.display_name(), false)

func _on_card_discarded(_idx: int, _card: CardData) -> void:
	_update_discard_display()
	_update_ui()

func _on_meld_laid(player_index: int, meld: MeldData) -> void:
	if player_index != 0:
		_flash_status("🃏 %s laid a %s!" % [GameState.players[player_index].player_name, meld.type_label()], false)
	_update_opponents_ui()

func _on_game_over(winner_index: int) -> void:
	var wname := GameState.players[winner_index].player_name
	win_label.text = "%s Wins! 🎉" % wname
	win_sub.text   = "Score: %d pts" % GameState.get_score(winner_index)
	win_panel.show()

func _on_hand_updated(player_index: int) -> void:
	if player_index == 0:
		_refresh_hand()
	_update_ui()
	_update_opponents_ui()

# ── UI updates ─────────────────────────────────
func _update_ui() -> void:
	_update_deck_display()
	_update_discard_display()
	_update_turn_display()
	_update_action_buttons()
	_refresh_melds()

func _update_deck_display() -> void:
	deck_count.text = "%d cards" % GameState.deck.size()

func _update_discard_display() -> void:
	var top := GameState.top_discard()
	if top:
		var ink := COLOR_RED if top.is_red else COLOR_BLACK
		discard_top_label.text = "%s\n%s" % [top.rank_label(), top.suit_symbol()]
		discard_top_label.add_theme_color_override("font_color", ink if not top.is_joker else Color.YELLOW)
		discard_top_label.add_theme_font_size_override("font_size", 18)
		discard_info.text = "%d cards" % GameState.discard_pile.size()
	else:
		discard_top_label.text = "empty"
		discard_top_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		discard_info.text = "empty"

func _update_turn_display() -> void:
	var p := GameState.players[GameState.current_player]
	if GameState.is_my_turn():
		turn_label.text = "🟢 Your Turn"
		turn_label.add_theme_color_override("font_color", Color(0.961, 0.651, 0.137, 1))
	else:
		turn_label.text = "⏳ %s's turn" % p.player_name
		turn_label.add_theme_color_override("font_color", Color(0.66, 0.85, 0.70, 1))

	score_label.text = "Score: %d" % GameState.get_score(0)

	match GameState.phase:
		GameState.Phase.DRAW:  phase_label.text = "Phase: Draw"
		GameState.Phase.PLAY:  phase_label.text = "Phase: Play"
		_: phase_label.text = ""

func _update_action_buttons() -> void:
	var my_turn    := GameState.is_my_turn()
	var play_phase := GameState.phase == GameState.Phase.PLAY
	var draw_phase := GameState.phase == GameState.Phase.DRAW
	btn_draw_deck.disabled     = not (my_turn and draw_phase)
	btn_draw_discard.disabled  = not (my_turn and draw_phase)
	btn_lay_meld.disabled      = not (my_turn and play_phase)
	btn_discard.disabled       = not (my_turn and play_phase)

func _refresh_melds() -> void:
	for child in melds_container.get_children():
		child.queue_free()

	for meld in GameState.get_my_melds():
		var lbl      := Label.new()
		var names    := (meld.cards as Array).map(func(c: CardData) -> String: return c.display_name())
		lbl.text     = "[%s] %s" % [meld.type_label(), " ".join(names)]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.961, 0.651, 0.137, 1))
		melds_container.add_child(lbl)

	if GameState.get_my_melds().is_empty():
		var lbl  := Label.new()
		lbl.text = "No melds yet"
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
		melds_container.add_child(lbl)

func _update_opponents_ui() -> void:
	var panels := opponents_area.get_children()
	for i in panels.size():
		var pidx  : int         = i + 1
		if pidx >= GameState.players.size(): break
		var p     := GameState.players[pidx]
		var panel := panels[i]
		var vb    := panel.get_child(0)
		(vb.get_child(1) as Label).text = "%d cards" % p.hand.size()
		(vb.get_child(2) as Label).text = "%d melds" % p.melds.size()
		# Highlight active player
		var sb := panel.get_theme_stylebox("panel") as StyleBoxFlat
		if GameState.current_player == pidx:
			sb.border_color = Color(0.961, 0.651, 0.137, 0.8)
			sb.border_width_left   = 2
			sb.border_width_top    = 2
			sb.border_width_right  = 2
			sb.border_width_bottom = 2
		else:
			sb.border_color = Color(1, 1, 1, 0.15)
			sb.border_width_left   = 1
			sb.border_width_top    = 1
			sb.border_width_right  = 1
			sb.border_width_bottom = 1

# ── Status flash ───────────────────────────────
func _flash_status(msg: String, is_error: bool) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color",
		Color(1.0, 0.4, 0.4, 1) if is_error else Color.WHITE)
	if _status_tween:
		_status_tween.kill()
	_status_tween = create_tween()
	_status_tween.tween_interval(3.5)
	_status_tween.tween_property(status_label, "modulate:a", 0.6, 0.5)
	_status_tween.tween_property(status_label, "modulate:a", 1.0, 0.1)
