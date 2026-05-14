extends Node

# ─────────────────────────────────────────────
#  GameState.gd  (Autoload singleton)
#  Single source of truth for all game data.
#  Every scene reads from here; never from each other.
# ─────────────────────────────────────────────

signal game_started
signal turn_changed(player_index: int)
signal card_drawn(player_index: int, card: CardData)
signal card_discarded(player_index: int, card: CardData)
signal meld_laid(player_index: int, meld: MeldData)
signal game_over(winner_index: int)
signal hand_updated(player_index: int)

# ── Enums ──────────────────────────────────────
enum Phase { WAITING, DRAW, PLAY, DISCARD, GAME_OVER }
enum MeldType { SEQUENCE, DUBLEE, TUNNALA }

# ── Constants ──────────────────────────────────
const HAND_SIZE       := 21
const NUM_DECKS       := 3
const JOKERS_PER_DECK := 2

# ── Game config ────────────────────────────────
var num_players   : int  = 2
var is_multiplayer: bool = false
var local_player  : int  = 0       # which seat is "me" in multiplayer

# ── Live state ─────────────────────────────────
var deck          : Array[CardData] = []
var discard_pile  : Array[CardData] = []
var players       : Array[PlayerData] = []
var current_player: int   = 0
var phase         : Phase = Phase.WAITING
var turn_number   : int   = 0

# ── Score tracking ─────────────────────────────
var scores        : Array[int] = []

# ──────────────────────────────────────────────
func _ready() -> void:
	pass

# ── Setup ──────────────────────────────────────
func setup_game(player_count: int, multiplayer: bool = false) -> void:
	num_players    = player_count
	is_multiplayer = multiplayer
	turn_number    = 0

	# Build players
	players.clear()
	scores.clear()
	for i in player_count:
		var p       := PlayerData.new()
		p.index     = i
		p.player_name      = "Player %d" % (i + 1) if i > 0 else "You"
		p.is_human  = (i == 0) if not multiplayer else true
		players.append(p)
		scores.append(0)

	# Build & shuffle deck
	deck = CardManager.build_full_deck(NUM_DECKS, JOKERS_PER_DECK)
	CardManager.shuffle_deck(deck)
	discard_pile.clear()

	# Deal hands
	for p in players:
		p.hand.clear()
		p.melds.clear()
		for _i in HAND_SIZE:
			p.hand.append(deck.pop_back())

	current_player = 0
	phase          = Phase.DRAW
	emit_signal("game_started")
	emit_signal("turn_changed", 0)

# ── Draw ───────────────────────────────────────
func draw_from_deck(player_index: int) -> CardData:
	assert(phase == Phase.DRAW, "Not in draw phase")
	assert(player_index == current_player, "Not your turn")

	if deck.is_empty():
		_reshuffle_discard()
	if deck.is_empty():
		return null  # No cards anywhere

	var card: CardData = deck.pop_back()
	players[player_index].hand.append(card)
	phase = Phase.PLAY
	emit_signal("card_drawn", player_index, card)
	emit_signal("hand_updated", player_index)
	return card

func draw_from_discard(player_index: int) -> CardData:
	assert(phase == Phase.DRAW, "Not in draw phase")
	assert(player_index == current_player, "Not your turn")
	assert(not discard_pile.is_empty(), "Discard pile is empty")

	var card: CardData = discard_pile.pop_back()
	players[player_index].hand.append(card)
	phase = Phase.PLAY
	emit_signal("card_drawn", player_index, card)
	emit_signal("hand_updated", player_index)
	return card

# ── Discard ────────────────────────────────────
func discard_card(player_index: int, card: CardData) -> bool:
	assert(phase == Phase.PLAY, "Not in play phase")
	assert(player_index == current_player, "Not your turn")

	var hand := players[player_index].hand
	var idx  := hand.find(card)
	if idx == -1:
		push_error("Card not in hand: %s" % card.card_to_string())
		return false

	hand.remove_at(idx)
	discard_pile.append(card)
	emit_signal("card_discarded", player_index, card)
	emit_signal("hand_updated", player_index)

	if _check_win(player_index):
		return true

	_advance_turn()
	return true

# ── Melds ──────────────────────────────────────
func lay_meld(player_index: int, card_ids: Array) -> MeldData:
	assert(phase == Phase.PLAY, "Not in play phase")
	assert(player_index == current_player, "Not your turn")

	# Collect the actual CardData objects from the player's hand
	var cards: Array[CardData] = []
	var hand  := players[player_index].hand
	for cid in card_ids:
		var found := _find_card_by_id(hand, cid)
		if not found:
			push_error("Card ID not found: %s" % cid)
			return null
		cards.append(found)

	var meld := CardManager.validate_meld(cards)
	if not meld:
		return null

	# Remove from hand
	for c in cards:
		hand.erase(c)

	meld.owner_index = player_index
	players[player_index].melds.append(meld)
	scores[player_index] += _meld_score(meld)

	emit_signal("meld_laid", player_index, meld)
	emit_signal("hand_updated", player_index)

	if _check_win(player_index):
		return meld

	return meld

func add_to_meld(player_index: int, meld_index: int, card_id: String) -> bool:
	assert(phase == Phase.PLAY, "Not in play phase")

	var meld: MeldData = players[player_index].melds[meld_index]
	var hand  := players[player_index].hand
	var card  := _find_card_by_id(hand, card_id)
	if not card:
		return false

	var test_cards: Array[CardData] = meld.cards.duplicate()
	test_cards.append(card)
	var test_meld := CardManager.validate_meld(test_cards)
	if not test_meld:
		return false

	hand.erase(card)
	meld.cards.append(card)
	scores[player_index] += 5

	emit_signal("hand_updated", player_index)
	if _check_win(player_index):
		return true
	return true

# ── Internals ──────────────────────────────────
func _advance_turn() -> void:
	current_player = (current_player + 1) % num_players
	phase          = Phase.DRAW
	turn_number   += 1
	emit_signal("turn_changed", current_player)

func _check_win(player_index: int) -> bool:
	if players[player_index].hand.is_empty():
		phase = Phase.GAME_OVER
		scores[player_index] += 100  # Bonus for going out
		emit_signal("game_over", player_index)
		return true
	return false

func _reshuffle_discard() -> void:
	if discard_pile.size() <= 1:
		return
	var top: CardData = discard_pile.pop_back()
	deck     = discard_pile
	discard_pile.clear()
	discard_pile.append(top)
	CardManager.shuffle_deck(deck)

func _find_card_by_id(hand: Array, id: String) -> CardData:
	for c in hand:
		if c.unique_id == id:
			return c
	return null

func _meld_score(meld: MeldData) -> int:
	match meld.type:
		MeldType.TUNNALA:  return 30
		MeldType.DUBLEE:   return 15
		MeldType.SEQUENCE: return meld.cards.size() * 10
		_: return 0

# ── Getters ────────────────────────────────────
func get_my_hand() -> Array[CardData]:
	return players[local_player].hand

func get_my_melds() -> Array:
	return players[local_player].melds

func top_discard() -> CardData:
	return discard_pile.back() if not discard_pile.is_empty() else null

func is_my_turn() -> bool:
	return current_player == local_player

func get_score(player_index: int) -> int:
	return scores[player_index]
