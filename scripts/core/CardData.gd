extends Resource
class_name CardData

# ─────────────────────────────────────────────
#  CardData.gd
#  Data class representing a single playing card.
#  Stored in arrays, serialized for networking.
# ─────────────────────────────────────────────

enum Suit  { SPADES, HEARTS, DIAMONDS, CLUBS, JOKER }
enum Rank  { ACE=1, TWO, THREE, FOUR, FIVE, SIX, SEVEN,
			 EIGHT, NINE, TEN, JACK, QUEEN, KING, WILD }

@export var suit       : Suit  = Suit.SPADES
@export var rank       : Rank  = Rank.ACE
@export var deck_index : int   = 0   # which of the 3 decks (0,1,2)
@export var unique_id  : String = "" # e.g. "A_SPADES_0"

var is_joker : bool:
	get: return suit == Suit.JOKER

var rank_value : int:
	get: return rank as int  # ACE=1, KING=13

var is_red : bool:
	get: return suit == Suit.HEARTS or suit == Suit.DIAMONDS

# ── Display ────────────────────────────────────
static var RANK_LABELS := {
	Rank.ACE:   "A",  Rank.TWO:   "2",  Rank.THREE: "3",
	Rank.FOUR:  "4",  Rank.FIVE:  "5",  Rank.SIX:   "6",
	Rank.SEVEN: "7",  Rank.EIGHT: "8",  Rank.NINE:  "9",
	Rank.TEN:   "10", Rank.JACK:  "J",  Rank.QUEEN: "Q",
	Rank.KING:  "K",  Rank.WILD:  "JK"
}

static var SUIT_SYMBOLS := {
	Suit.SPADES:   "♠", Suit.HEARTS:   "♥",
	Suit.DIAMONDS: "♦", Suit.CLUBS:    "♣",
	Suit.JOKER:    "★"
}

static var SUIT_NAMES := {
	Suit.SPADES:   "SPADES",   Suit.HEARTS:   "HEARTS",
	Suit.DIAMONDS: "DIAMONDS", Suit.CLUBS:    "CLUBS",
	Suit.JOKER:    "JOKER"
}

func rank_label()  -> String: return RANK_LABELS[rank]
func suit_symbol() -> String: return SUIT_SYMBOLS[suit]
func display_name()-> String:
	if is_joker: return "Joker"
	return "%s%s" % [rank_label(), suit_symbol()]

func card_to_string() -> String:
	return "[%s|deck%d]" % [display_name(), deck_index]

# ── Serialization (for multiplayer) ───────────────
func to_dict() -> Dictionary:
	return { "suit": suit, "rank": rank, "deck": deck_index, "id": unique_id }

static func from_dict(d: Dictionary) -> CardData:
	var c          := CardData.new()
	c.suit         = d["suit"]
	c.rank         = d["rank"]
	c.deck_index   = d["deck"]
	c.unique_id    = d["id"]
	return c

# ── Equality (cards from different decks are different) ──
func equals_face(other: CardData) -> bool:
	return suit == other.suit and rank == other.rank

func is_identical(other: CardData) -> bool:
	return equals_face(other) and deck_index == other.deck_index
