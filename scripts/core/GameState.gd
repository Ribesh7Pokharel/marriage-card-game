extends Node

# ═══════════════════════════════════════════════════════
#  GameState.gd  (Autoload singleton)
#  What it does: The BRAIN of the game.
#  Every action a player takes goes through here.
#  It coordinates DeckManager, MeldValidator, and PlayerData.
#
#  LEARNING: This is the "Model" in MVC pattern.
#  - Model (GameState) = data + rules
#  - View (scenes)     = visuals
#  - Controller (UI scripts) = handles input
#
#  Because this is an Autoload, any scene can access it
#  directly: GameState.draw_card(0)
#  No need to find the node or pass references around.
# ═══════════════════════════════════════════════════════


# ── SIGNALS ─────────────────────────────────────────────
# LEARNING: Signals are how GameState tells the UI what
# happened. The UI never calls GameState directly for
# display — it listens to signals and reacts.

signal game_started
signal game_over(winner_index: int)
signal turn_changed(player_index: int)
signal phase_changed(new_phase: Phase)

signal card_drawn(player_index: int, card: CardData)
signal card_discarded(player_index: int, card: CardData)

signal tunnela_declared(player_index: int, tunnela: Array)
signal player_opened(player_index: int, sets: Array)
signal tiplu_revealed_to_player(player_index: int, tiplu: CardData)
signal cut_initiated(player_index: int)

signal game_won(winner_index: int, scores: Array)
signal scores_calculated(results: Array)

signal status_message(message: String, is_error: bool)


# ── GAME PHASES ─────────────────────────────────────────
# LEARNING: The game has distinct phases. Using an enum
# prevents bugs — you can't accidentally set phase to
# a string like "drwa" (typo). The compiler catches it.

enum Phase {
	WAITING,          # Not started yet
	SETUP,            # Players picking cards for seating
	TUNNELA_WINDOW,   # Brief window to declare tunnelas
	DRAW,             # Current player must draw
	PLAY,             # Current player can meld/discard
	CUT_WINDOW,       # Player choosing which pile to cut
	GAME_OVER         # Game has ended
}


# ── REFERENCES TO OTHER SYSTEMS ─────────────────────────
# LEARNING: We get these in _ready() using the autoload names.
# They're set up in project.godot under [autoload].

var deck_manager   : DeckManager    = null
var meld_validator : MeldValidator  = null


# ── GAME CONFIGURATION ──────────────────────────────────
var num_players    : int  = 2
var is_multiplayer : bool = false
var local_player   : int  = 0   # Which seat is "you"
var game_mode      : String = "normal"  # "normal", "murder", "kidnap"
var rate_per_point : int  = 10  # Money per point


# ── LIVE GAME STATE ─────────────────────────────────────
var players        : Array[PlayerData] = []
var current_player : int   = 0
var phase          : Phase = Phase.WAITING
var turn_number    : int   = 0

# Track who has opened (shown 3 sets)
# This determines who can pick up discarded jokers
var players_who_opened : Array[int] = []

# The player currently waiting to cut
var cutter_index   : int = -1


# ══════════════════════════════════════════════════════════
#  SETUP
# ══════════════════════════════════════════════════════════

func _ready() -> void:
	# Get references to other autoloads
	# LEARNING: get_node("/root/Name") gets an autoload by name
	deck_manager   = get_node("/root/DeckManager")
	meld_validator = get_node("/root/MeldValidator")

	# Connect to DeckManager signals
	deck_manager.tiplu_revealed.connect(_on_tiplu_revealed)
	deck_manager.waiting_for_cut.connect(_on_waiting_for_cut)


func start_game(
	p_num_players  : int    = 2,
	p_multiplayer  : bool   = false,
	p_game_mode    : String = "normal",
	p_rate         : int    = 10
) -> void:
	num_players    = p_num_players
	is_multiplayer = p_multiplayer
	game_mode      = p_game_mode
	rate_per_point = p_rate
	turn_number    = 0
	cutter_index   = -1
	players_who_opened.clear()

	# Create player data objects
	players.clear()
	for i in num_players:
		var p              := PlayerData.new()
		p.player_index     = i
		p.player_name      = "You" if i == 0 else "CPU %d" % i
		p.is_human         = (i == 0) if not is_multiplayer else true
		players.append(p)

	# Build and shuffle the deck
	deck_manager.build_and_shuffle()

	# Deal 21 cards to each player
	var hands := deck_manager.deal(num_players)
	for i in num_players:
		players[i].hand = hands[i]

	# Enter tunnela window — players can declare tunnelas
	_set_phase(Phase.TUNNELA_WINDOW)
	emit_signal("game_started")

	# Start with player 0
	current_player = 0
	emit_signal("turn_changed", current_player)

	_status("Game started! Declare any Tunnelas before play begins.")
	print("[GameState] Game started with %d players" % num_players)


# ══════════════════════════════════════════════════════════
#  TUNNELA DECLARATION
#  Must happen BEFORE any draw or discard
# ══════════════════════════════════════════════════════════

func declare_tunnela(player_index: int, card_ids: Array) -> bool:
	if phase != Phase.TUNNELA_WINDOW:
		_status("Tunnelas can only be declared at the very start!", true)
		return false

	var player := players[player_index]

	if player.tunnelas_declared:
		_status("You have already declared your tunnelas!", true)
		return false

	# Collect the cards
	var cards := _get_cards_from_hand(player_index, card_ids)
	if cards.is_empty() and not card_ids.is_empty():
		_status("Cards not found in hand!", true)
		return false

	# Validate as tunnela
	var result := meld_validator.validate_for_opening(cards)
	if not result.is_valid or result.meld_type != "tunnela":
		_status("Not a valid Tunnela! Need 3 identical cards (same rank + suit).", true)
		return false

	# Remove from hand and add to tunnelas
	for card in cards:
		player.remove_card(card)
	player.tunnelas.append(cards)
	player.tunnelas_declared = true

	emit_signal("tunnela_declared", player_index, cards)
	_status("Tunnela declared by %s!" % player.player_name)
	return true


func end_tunnela_window() -> void:
	# Mark all players as having passed tunnela window
	for p in players:
		p.tunnelas_declared = true

	# Begin actual play
	_set_phase(Phase.DRAW)
	_status("Play begins! %s draws first." % players[current_player].player_name)


# ══════════════════════════════════════════════════════════
#  DRAW PHASE
# ══════════════════════════════════════════════════════════

func draw_from_deck(player_index: int) -> bool:
	if not _validate_turn(player_index, Phase.DRAW):
		return false

	var card := deck_manager.draw_from_deck()
	if not card:
		return false

	players[player_index].hand.append(card)
	_set_phase(Phase.PLAY)

	emit_signal("card_drawn", player_index, card)
	_status("Drew a card from the deck.")
	return true


func pick_up_discard(player_index: int) -> bool:
	if not _validate_turn(player_index, Phase.DRAW):
		return false

	if deck_manager.discard_pile.is_empty():
		_status("Discard pile is empty!", true)
		return false

	var top := deck_manager.top_discard()

	# Special joker discard rule:
	# A discarded joker/wildcard can only be picked up if:
	# - You have seen the Tiplu, AND
	# - No OTHER player who has seen Tiplu has opened yet
	# (simplified: you must be the ONLY one who has seen it)
	if top and (top.is_wild_joker or top.role != CardData.Role.NORMAL):
		if not _can_pick_up_wildcard_discard(player_index):
			_status("You cannot pick up that card right now!", true)
			return false

	var card := deck_manager.pick_up_discard()
	if not card:
		return false

	players[player_index].hand.append(card)
	# Remember which card was picked up (can't discard it same turn)
	players[player_index].set_meta("picked_up_id", card.unique_id)
	_set_phase(Phase.PLAY)

	emit_signal("card_drawn", player_index, card)
	_status("Picked up %s from discard." % card.display_name())
	return true


func _can_pick_up_wildcard_discard(player_index: int) -> bool:
	# Must have seen the Tiplu
	if not players[player_index].has_seen_tiplu:
		return false
	# No other player who has seen Tiplu should have opened
	for i in num_players:
		if i != player_index and players[i].has_seen_tiplu and players[i].has_opened:
			return false
	return true


# ══════════════════════════════════════════════════════════
#  PLAY PHASE — OPENING (showing 3 sets to see Tiplu)
# ══════════════════════════════════════════════════════════

func show_opening_sets(player_index: int, sets: Array) -> bool:
	# sets = Array of Arrays of card unique_ids
	# e.g. [["A_SPADES_0","2_SPADES_1","3_SPADES_2"], [...], [...]]

	if not _validate_turn(player_index, Phase.PLAY):
		return false

	var player := players[player_index]

	if player.has_opened:
		_status("You have already opened!", true)
		return false

	if sets.size() < 3:
		_status("You need to show at least 3 sets!", true)
		return false

	# Validate each set
	var validated_sets : Array = []
	for set_ids in sets:
		var cards := _get_cards_from_hand(player_index, set_ids)
		if cards.size() < 3:
			_status("Each set needs at least 3 cards!", true)
			return false

		var result := meld_validator.validate_for_opening(cards)
		if not result.is_valid:
			_status("Invalid set! Only Pure Sequences and Tunnelas allowed for opening.", true)
			return false

		validated_sets.append(cards)

	# Add tunnelas to count — tunnelas shown at start count toward 3 sets
	var total_sets : int = validated_sets.size() + player.tunnelas.size()
	if not player.is_dublee_play and total_sets < 3:
		_status("Need 3 sets total (including any tunnelas shown at start)!", true)
		return false

	# Remove cards from hand and store in open_sets
	for set_cards in validated_sets:
		for card in set_cards:
			player.remove_card(card)
		player.open_sets.append(set_cards)

	player.has_opened = true
	players_who_opened.append(player_index)

	emit_signal("player_opened", player_index, player.open_sets)
	_status("%s has opened! Now cut the deck to reveal the Tiplu." % player.player_name)

	# Initiate the cut — player chooses which pile
	cutter_index = player_index
	deck_manager.initiate_cut()
	_set_phase(Phase.CUT_WINDOW)
	emit_signal("cut_initiated", player_index)
	return true


# ── DUBLEE OPENING ──────────────────────────────────────
func show_dublee_opening(player_index: int, dublee_ids: Array) -> bool:
	# dublee_ids = Array of Arrays, each inner array has 2 card ids
	if not _validate_turn(player_index, Phase.PLAY):
		return false

	var player := players[player_index]

	if dublee_ids.size() < 7:
		_status("Need 7 Dublees to open with Dublee play!", true)
		return false

	var validated_dublees : Array = []
	for pair_ids in dublee_ids:
		var cards := _get_cards_from_hand(player_index, pair_ids)
		var result := meld_validator.validate_dublee(cards)
		if not result.is_valid:
			_status("Invalid Dublee! Need 2 identical cards (same rank + suit).", true)
			return false
		validated_dublees.append(cards)

	# Remove from hand
	for pair in validated_dublees:
		for card in pair:
			player.remove_card(card)
		player.dublees.append(pair)

	player.is_dublee_play = true
	player.has_opened     = true
	players_who_opened.append(player_index)

	_status("%s opened with Dublee play! Cut the deck." % player.player_name)
	cutter_index = player_index
	deck_manager.initiate_cut()
	_set_phase(Phase.CUT_WINDOW)
	emit_signal("cut_initiated", player_index)
	return true


# ══════════════════════════════════════════════════════════
#  CUT PHASE
# ══════════════════════════════════════════════════════════

func player_cuts_top(player_index: int) -> bool:
	if phase != Phase.CUT_WINDOW or player_index != cutter_index:
		return false
	var tiplu := deck_manager.choose_top_half()
	if not tiplu:
		return false
	return true  # _on_tiplu_revealed handles the rest

func player_cuts_bottom(player_index: int) -> bool:
	if phase != Phase.CUT_WINDOW or player_index != cutter_index:
		return false
	var tiplu := deck_manager.choose_bottom_half()
	if not tiplu:
		return false
	return true


# ══════════════════════════════════════════════════════════
#  TIPLU REVEALED — assign roles to all cards
# ══════════════════════════════════════════════════════════

func _on_tiplu_revealed(tiplu_card: CardData) -> void:
	print("[GameState] Tiplu revealed: %s" % tiplu_card.card_to_string())

	# Assign roles to every card in the game
	var all_cards : Array[CardData] = []
	for p in players:
		all_cards.append_array(p.hand)
		for s in p.open_sets:
			all_cards.append_array(s)
		for s in p.tunnelas:
			all_cards.append_array(s)
		for d in p.dublees:
			all_cards.append_array(d)

	deck_manager.assign_roles_to_cards(all_cards)

	# Mark the cutter as having seen the Tiplu
	players[cutter_index].has_seen_tiplu = true
	emit_signal("tiplu_revealed_to_player", cutter_index, tiplu_card)
	_status("Tiplu revealed! %s now knows the trump card." % players[cutter_index].player_name)

	# Resume play
	cutter_index = -1
	_set_phase(Phase.PLAY)


func _on_waiting_for_cut(top_count: int, bottom_count: int) -> void:
	_status("Cut the deck! Left pile: %d cards, Right pile: %d cards" % [top_count, bottom_count])


# ── ANOTHER PLAYER OPENS — they get to see the Tiplu ────
func reveal_tiplu_to_player(player_index: int) -> void:
	# Called when another player shows their 3 sets
	# They get to see the Tiplu (look at the bottom of the deck)
	players[player_index].has_seen_tiplu = true

	# Assign roles to their cards now
	var all_cards : Array[CardData] = []
	all_cards.append_array(players[player_index].hand)
	deck_manager.assign_roles_to_cards(all_cards)

	emit_signal("tiplu_revealed_to_player", player_index, deck_manager.tiplu)
	_status("%s has seen the Tiplu!" % players[player_index].player_name)


# ══════════════════════════════════════════════════════════
#  DISCARD PHASE
# ══════════════════════════════════════════════════════════

func discard_card(player_index: int, card_id: String) -> bool:
	if not _validate_turn(player_index, Phase.PLAY):
		return false

	var player := players[player_index]
	var card   := player.find_card_by_id(card_id)

	if not card:
		_status("Card not found in hand!", true)
		return false

	# Cannot discard the card you just picked up from discard
	var picked_up_id : String = player.get_meta("picked_up_id", "")
	if picked_up_id == card_id:
		_status("You cannot discard the card you just picked up!", true)
		return false

	player.remove_card(card)
	player.set_meta("picked_up_id", "")
	deck_manager.discard_card(card)

	emit_signal("card_discarded", player_index, card)
	_status("%s discarded %s." % [player.player_name, card.display_name()])

	_advance_turn()
	return true


# ══════════════════════════════════════════════════════════
#  FINISHING THE GAME
# ══════════════════════════════════════════════════════════

func declare_finish_sequence(player_index: int, final_sets: Array) -> bool:
	# final_sets = Array of Arrays of card_ids (4 sets of 3 cards)
	if not _validate_turn(player_index, Phase.PLAY):
		return false

	var player := players[player_index]

	if not player.has_seen_tiplu:
		_status("You must see the Tiplu before finishing!", true)
		return false

	if final_sets.size() < 4:
		_status("Need 4 more sets to finish!", true)
		return false

	# Validate each final set (dirty sequences/triplets allowed now)
	var validated : Array = []
	for set_ids in final_sets:
		var cards  := _get_cards_from_hand(player_index, set_ids)
		var result := meld_validator.validate(cards, true)  # true = tiplu seen
		if not result.is_valid:
			_status("Invalid set: %s" % str(set_ids), true)
			return false
		validated.append(cards)

	# Must use all cards (hand should be empty after 4 sets + 1 discard)
	var total_cards_used : int = 0
	for s in validated:
		total_cards_used += s.size()

	# After 4 sets, player discards 1 remaining card
	if player.hand.size() - total_cards_used != 1:
		_status("You must use exactly enough cards for 4 sets plus 1 discard!", true)
		return false

	# Remove cards and store final sets
	for set_cards in validated:
		for card in set_cards:
			player.remove_card(card)
		player.final_sets.append(set_cards)

	player.has_finished = true
	_finish_game(player_index)
	return true


func declare_finish_dublee(player_index: int, final_dublee_ids: Array) -> bool:
	if not _validate_turn(player_index, Phase.PLAY):
		return false

	var player := players[player_index]

	if not player.is_dublee_play:
		_status("You are not playing Dublee mode!", true)
		return false

	if not player.has_seen_tiplu:
		_status("You must see the Tiplu before finishing!", true)
		return false

	# Validate the 8th dublee
	var cards  := _get_cards_from_hand(player_index, final_dublee_ids)
	var result := meld_validator.validate_dublee(cards)
	if not result.is_valid:
		_status("Not a valid Dublee!", true)
		return false

	# Remove from hand
	for card in cards:
		player.remove_card(card)
	player.dublees.append(cards)
	player.has_finished = true

	_finish_game(player_index)
	return true


func _finish_game(winner_index: int) -> void:
	_set_phase(Phase.GAME_OVER)
	print("[GameState] Game over! Winner: %s" % players[winner_index].player_name)

	# Calculate scores for all players
	var scores := _calculate_all_scores(winner_index)

	emit_signal("game_over", winner_index)
	emit_signal("game_won", winner_index, scores)
	emit_signal("scores_calculated", scores)
	_status("%s wins!" % players[winner_index].player_name)


# ══════════════════════════════════════════════════════════
#  SCORING CALCULATION
#  Formula: each player pays winner T + w - (n * S)
#  T = total of all card points
#  w = 3 (seen Tiplu) or 10 (unseen) + 5 if winner had 8 dublees
#  n = number of players
#  S = individual player's card points
# ══════════════════════════════════════════════════════════

func _calculate_all_scores(winner_index: int) -> Array:
	var results : Array = []
	var winner  := players[winner_index]

	# Step 1: Calculate each player's card points
	for p in players:
		p.calculate_card_points()
		# Add tunnela points
		p.card_points += _calculate_tunnela_points(p)
		# Check for marriage
		p.card_points += _calculate_marriage_points(p)

	# Step 2: Calculate total of all card points
	var total_points : int = 0
	for p in players:
		total_points += p.card_points

	# Step 3: Dublee bonus (winner gets extra 5 from each if finished with 8 dublees)
	var dublee_bonus : int = 5 if (winner.is_dublee_play and winner.dublees.size() == 8) else 0

	# Step 4: Calculate each player's net payment to winner
	for p in players:
		# w = seen/unseen point + dublee bonus
		var w : int = 3 if p.has_seen_tiplu else 10
		w += dublee_bonus

		# Formula: T + w - (n * S)
		var net : int = total_points + w - (num_players * p.card_points)

		# Apply game mode modifiers
		if game_mode == "murder" and not p.has_seen_tiplu:
			net = 0  # Unseen player's maal points disregarded
		elif game_mode == "kidnap" and not p.has_seen_tiplu:
			net += p.card_points  # Unseen player also pays for their own maal

		p.net_payment = net

		results.append({
			"player_index": p.player_index,
			"player_name":  p.player_name,
			"card_points":  p.card_points,
			"has_seen":     p.has_seen_tiplu,
			"net_payment":  net,
			"money":        net * rate_per_point,
			"is_winner":    p.player_index == winner_index
		})

		print("[GameState] %s: card_pts=%d, net=%d, money=%d" % [
			p.player_name, p.card_points, net, net * rate_per_point
		])

	return results


func _calculate_tunnela_points(player: PlayerData) -> int:
	var pts : int = 0
	# Tunnela points only count if:
	# 1. Declared at start
	# 2. Player has seen the Tiplu
	if not player.has_seen_tiplu:
		return 0

	for tunnela in player.tunnelas:
		var cards : Array[CardData] = tunnela
		if cards.is_empty():
			continue
		var ref := cards[0] as CardData
		match ref.role:
			CardData.Role.NORMAL:        pts += 5
			CardData.Role.ORDINARY_JOKER: pts += 10
			CardData.Role.JHIPLU:        pts += 20
			CardData.Role.POPLU:         pts += 20
			CardData.Role.ALTER:         pts += 35
			CardData.Role.WILD_JOKER:    pts += 35
			CardData.Role.TIPLU:         pts += 5  # Normal tunnela (Tiplu itself)

	return pts


func _calculate_marriage_points(player: PlayerData) -> int:
	var pts : int = 0
	if not player.has_seen_tiplu:
		return 0

	# Check ground marriage in open sets
	if meld_validator.check_ground_marriage(player.open_sets):
		pts += 15

	# Check hand marriage
	if meld_validator.check_hand_marriage(player.open_sets, player.hand):
		pts += 10

	return pts


# ══════════════════════════════════════════════════════════
#  TURN MANAGEMENT
# ══════════════════════════════════════════════════════════

func _advance_turn() -> void:
	current_player = (current_player + 1) % num_players
	turn_number   += 1
	_set_phase(Phase.DRAW)
	emit_signal("turn_changed", current_player)
	_status("%s's turn — draw a card." % players[current_player].player_name)


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	emit_signal("phase_changed", new_phase)


# ══════════════════════════════════════════════════════════
#  VALIDATION HELPERS
# ══════════════════════════════════════════════════════════

func _validate_turn(player_index: int, expected_phase: Phase) -> bool:
	if player_index != current_player:
		_status("It's not your turn!", true)
		return false
	if phase != expected_phase:
		_status("Wrong game phase for this action!", true)
		return false
	return true


func _get_cards_from_hand(player_index: int, card_ids: Array) -> Array[CardData]:
	var result : Array[CardData] = []
	var player := players[player_index]
	for uid in card_ids:
		var card := player.find_card_by_id(uid)
		if card:
			result.append(card)
	return result


func _status(message: String, is_error: bool = false) -> void:
	emit_signal("status_message", message, is_error)
	if is_error:
		push_warning("[GameState] " + message)
	else:
		print("[GameState] " + message)


# ══════════════════════════════════════════════════════════
#  PUBLIC GETTERS
# ══════════════════════════════════════════════════════════

func get_my_hand() -> Array[CardData]:
	return players[local_player].hand

func get_my_player() -> PlayerData:
	return players[local_player]

func is_my_turn() -> bool:
	return current_player == local_player

func get_tiplu() -> CardData:
	return deck_manager.tiplu

func top_discard() -> CardData:
	return deck_manager.top_discard()

func phase_label() -> String:
	match phase:
		Phase.WAITING:        return "Waiting"
		Phase.SETUP:          return "Setup"
		Phase.TUNNELA_WINDOW: return "Declare Tunnelas"
		Phase.DRAW:           return "Draw"
		Phase.PLAY:           return "Play"
		Phase.CUT_WINDOW:     return "Cut the Deck"
		Phase.GAME_OVER:      return "Game Over"
		_:                    return ""
