extends Resource
class_name PlayerData

# ═══════════════════════════════════════════════════════
#  PlayerData.gd
#  What it does: Holds ALL data for ONE player.
#  Think of it as the player's "profile" during a game.
#
#  LEARNING: Like CardData, this extends Resource because
#  it's pure data. No visuals, no scene, just a data container.
#  Each player in the game gets one PlayerData object.
# ═══════════════════════════════════════════════════════


# ── PLAYER IDENTITY ─────────────────────────────────────
@export var player_index : int    = 0        # 0=you, 1=CPU1, 2=CPU2 etc.
@export var player_name  : String = "Player" # Display name
@export var is_human     : bool   = true     # false = CPU player
@export var peer_id      : int    = 0        # For multiplayer (0 = local)


# ── GAME STATE ──────────────────────────────────────────
# LEARNING: Array[CardData] means a typed array — it can
# ONLY hold CardData objects. This catches bugs early if
# you accidentally try to put the wrong thing in.

var hand          : Array[CardData] = []  # Cards currently in hand
var open_sets     : Array           = []  # The 3 sets shown to see Tiplu (Array of Array[CardData])
var tunnelas      : Array           = []  # Tunnelas shown at start (Array of Array[CardData])
var final_sets    : Array           = []  # The 4 sets shown to finish game

# Dublee play tracking
var dublees       : Array           = []  # Collected dublee pairs (Array of Array[CardData])
var is_dublee_play: bool            = false  # Is this player doing dublee play?

# Game progress flags
var has_seen_tiplu   : bool = false  # Has this player revealed the Tiplu?
var has_opened       : bool = false  # Has shown 3 sets (opened the game)?
var has_finished     : bool = false  # Has this player finished the game?
var setup_card       : CardData     # The card picked during seating setup

# Tunnela timing — tunnelas must be shown at start
var tunnelas_declared: bool = false  # Did player declare tunnelas at start?


# ── SCORING ─────────────────────────────────────────────
var card_points   : int = 0   # Points from Maal cards
var total_points  : int = 0   # Final net points after calculation
var net_payment   : int = 0   # Amount to pay/receive (positive = receive)


# ── HAND HELPERS ────────────────────────────────────────

func hand_count() -> int:
	return hand.size()

# Find a card in hand by its unique_id
# LEARNING: This is a linear search — O(n). Fine for 21 cards.
func find_card_by_id(uid: String) -> CardData:
	for card in hand:
		if card.unique_id == uid:
			return card
	return null

# Remove a card from hand by reference
# Returns true if found and removed, false if not found
func remove_card(card: CardData) -> bool:
	var idx := hand.find(card)
	if idx == -1:
		return false
	hand.remove_at(idx)
	return true

# Remove a card from hand by unique_id
func remove_card_by_id(uid: String) -> bool:
	for i in hand.size():
		if hand[i].unique_id == uid:
			hand.remove_at(i)
			return true
	return false

# Check if player has a specific card (by face — rank + suit)
func has_card_face(rank: CardData.Rank, suit: CardData.Suit) -> bool:
	for card in hand:
		if card.rank == rank and card.suit == suit:
			return true
	return false


# ── OPEN SET HELPERS ────────────────────────────────────

# How many sets has this player shown to open?
# Tunnelas shown at start count toward the 3 needed!
func open_set_count() -> int:
	return open_sets.size() + tunnelas.size()

# Has this player shown enough sets to see the Tiplu?
func can_see_tiplu() -> bool:
	if is_dublee_play:
		return dublees.size() >= 7
	return open_set_count() >= 3

# Total dublee count (for dublee play finishing)
func dublee_count() -> int:
	return dublees.size()


# ── POINT CALCULATION ───────────────────────────────────
# Calculate this player's card points based on their
# special cards (Tiplu, Jhiplu, Poplu, Alter, Jokers)
# and any tunnelas shown at start.
#
# LEARNING: This is called at the END of the game.
# During the game we just track the cards.

func calculate_card_points() -> int:
	card_points = 0

	# Count special cards in hand + open sets + final sets
	var all_cards := _get_all_scoring_cards()

	# Group cards by role for double/triple detection
	var wild_jokers    := all_cards.filter(func(c: CardData): return c.role == CardData.Role.WILD_JOKER)
	var tiplus         := all_cards.filter(func(c: CardData): return c.role == CardData.Role.TIPLU)
	var jhiplus        := all_cards.filter(func(c: CardData): return c.role == CardData.Role.JHIPLU)
	var poplus         := all_cards.filter(func(c: CardData): return c.role == CardData.Role.POPLU)
	var alters         := all_cards.filter(func(c: CardData): return c.role == CardData.Role.ALTER)

	# Score each group using single/double/triple table
	card_points += _score_group(wild_jokers, 5, 15, 25)
	card_points += _score_group(tiplus,      3, 8,  0)   # Max 2 Tiplus possible
	card_points += _score_group(jhiplus,     2, 5,  10)
	card_points += _score_group(poplus,      2, 5,  10)
	card_points += _score_group(alters,      5, 15, 25)

	# Check for marriage (handled separately in GameState)
	# Tunnela points added by GameState after validation

	return card_points

# Score a group of same-role cards using single/double/triple values
func _score_group(cards: Array, single: int, double: int, triple: int) -> int:
	match cards.size():
		0: return 0
		1: return single
		2: return double
		3: return triple
		_: return triple  # More than 3 shouldn't happen but handle gracefully

# Get all cards that could score points
# (hand + open_sets + final_sets, but NOT tunnelas — those scored separately)
func _get_all_scoring_cards() -> Array:
	var all : Array[CardData] = []
	all.append_array(hand)
	for s in open_sets:
		all.append_array(s)
	for s in final_sets:
		all.append_array(s)
	return all.filter(func(c: CardData): return c.role != CardData.Role.NORMAL)


# ── SERIALIZATION ───────────────────────────────────────
func to_dict() -> Dictionary:
	return {
		"index":          player_index,
		"player_name":    player_name,
		"is_human":       is_human,
		"peer_id":        peer_id,
		"has_seen_tiplu": has_seen_tiplu,
		"has_opened":     has_opened,
		"has_finished":   has_finished,
		"is_dublee_play": is_dublee_play,
		"card_points":    card_points,
	}

func reset() -> void:
	hand.clear()
	open_sets.clear()
	tunnelas.clear()
	final_sets.clear()
	dublees.clear()
	is_dublee_play    = false
	has_seen_tiplu    = false
	has_opened        = false
	has_finished      = false
	tunnelas_declared = false
	setup_card        = null
	card_points       = 0
	total_points      = 0
	net_payment       = 0