extends Resource
class_name CardData

# ═══════════════════════════════════════════════════════
#  CardData.gd
#  What it does: Represents ONE playing card in the game.
#  Every card in the 162-card deck is a CardData object.
#
#  LEARNING: We extend "Resource" not "Node" because this
#  is pure DATA with no visual. Think of it like a struct
#  or a plain object. No scene needed, no position, just data.
# ═══════════════════════════════════════════════════════


# ── ENUMS ───────────────────────────────────────────────
# Enums are named sets of constants. Instead of using
# magic numbers like suit=0 or suit=1, we use Suit.HEARTS
# which is much more readable and less error-prone.

enum Suit {
	SPADES,    # 0 - Black
	HEARTS,    # 1 - Red
	DIAMONDS,  # 2 - Red
	CLUBS,     # 3 - Black
	JOKER      # 4 - Wild (Man) Joker
}

enum Rank {
	ACE   = 1,
	TWO   = 2,
	THREE = 3,
	FOUR  = 4,
	FIVE  = 5,
	SIX   = 6,
	SEVEN = 7,
	EIGHT = 8,
	NINE  = 9,
	TEN   = 10,
	JACK  = 11,
	QUEEN = 12,
	KING  = 13,
	WILD  = 14  # Wild (Man) Joker rank
}

# ── CARD ROLE IN RELATION TO TIPLU ─────────────────────
# Once the Tiplu is revealed, every card gets a role.
# This makes point calculation much cleaner.
enum Role {
	NORMAL,         # Regular card, no special value
	TIPLU,          # The trump card itself (3 pts)
	JHIPLU,         # One below Tiplu, same suit (2 pts)
	POPLU,          # One above Tiplu, same suit (2 pts)
	ALTER,          # Same rank as Tiplu, same color, diff suit (5 pts)
	ORDINARY_JOKER, # Same rank as Tiplu, different color (0 pts, but wildcard)
	WILD_JOKER      # The printed Joker card (5 pts, always wildcard)
}


# ── PROPERTIES ──────────────────────────────────────────
@export var suit       : Suit   = Suit.SPADES
@export var rank       : Rank   = Rank.ACE
@export var deck_index : int    = 0
@export var unique_id  : String = ""

var role : Role = Role.NORMAL


# ── COMPUTED PROPERTIES ─────────────────────────────────
var is_wild_joker : bool:
	get: return suit == Suit.JOKER

var is_red : bool:
	get: return suit == Suit.HEARTS or suit == Suit.DIAMONDS

var is_black : bool:
	get: return suit == Suit.SPADES or suit == Suit.CLUBS

var rank_value : int:
	get: return rank as int

var is_wildcard : bool:
	get: return role != Role.NORMAL and role != Role.TIPLU


# ── STATIC LOOKUP TABLES ────────────────────────────────
static var RANK_LABELS : Dictionary = {
	Rank.ACE:   "A",  Rank.TWO:   "2",  Rank.THREE: "3",
	Rank.FOUR:  "4",  Rank.FIVE:  "5",  Rank.SIX:   "6",
	Rank.SEVEN: "7",  Rank.EIGHT: "8",  Rank.NINE:  "9",
	Rank.TEN:   "10", Rank.JACK:  "J",  Rank.QUEEN: "Q",
	Rank.KING:  "K",  Rank.WILD:  "JK"
}

static var SUIT_SYMBOLS : Dictionary = {
	Suit.SPADES:   "\u2660",
	Suit.HEARTS:   "\u2665",
	Suit.DIAMONDS: "\u2666",
	Suit.CLUBS:    "\u2663",
	Suit.JOKER:    "\u2605"
}

static var SUIT_NAMES : Dictionary = {
	Suit.SPADES:   "SPADES",
	Suit.HEARTS:   "HEARTS",
	Suit.DIAMONDS: "DIAMONDS",
	Suit.CLUBS:    "CLUBS",
	Suit.JOKER:    "JOKER"
}


# ── DISPLAY HELPERS ─────────────────────────────────────
func rank_label() -> String:
	return RANK_LABELS[rank]

func suit_symbol() -> String:
	return SUIT_SYMBOLS[suit]

func display_name() -> String:
	if is_wild_joker:
		return "Wild Joker"
	return "%s%s" % [rank_label(), suit_symbol()]

func role_label() -> String:
	match role:
		Role.TIPLU:          return "Tiplu"
		Role.JHIPLU:         return "Jhiplu"
		Role.POPLU:          return "Poplu"
		Role.ALTER:          return "Alter"
		Role.ORDINARY_JOKER: return "Ord.Joker"
		Role.WILD_JOKER:     return "Wild Joker"
		_:                   return ""

func card_to_string() -> String:
	return "[%s|deck%d|%s]" % [display_name(), deck_index, role_label()]


# ── POINT VALUE ─────────────────────────────────────────
func point_value() -> int:
	match role:
		Role.WILD_JOKER:     return 5
		Role.TIPLU:          return 3
		Role.JHIPLU:         return 2
		Role.POPLU:          return 2
		Role.ALTER:          return 5
		Role.ORDINARY_JOKER: return 0
		_:                   return 0


# ── COMPARISON HELPERS ──────────────────────────────────
func same_face_as(other: CardData) -> bool:
	return suit == other.suit and rank == other.rank

func identical_to(other: CardData) -> bool:
	return same_face_as(other) and deck_index == other.deck_index


# ── SERIALIZATION ───────────────────────────────────────
func to_dict() -> Dictionary:
	return {
		"suit":       suit,
		"rank":       rank,
		"deck_index": deck_index,
		"unique_id":  unique_id,
		"role":       role
	}

static func from_dict(d: Dictionary) -> CardData:
	var c          := CardData.new()
	c.suit         = d["suit"]    as Suit
	c.rank         = d["rank"]    as Rank
	c.deck_index   = d["deck_index"]
	c.unique_id    = d["unique_id"]
	c.role         = d["role"]    as Role
	return c