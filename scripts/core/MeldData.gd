extends Resource
class_name MeldData

# ─────────────────────────────────────────────
#  MeldData.gd
#  Represents a validated group of cards laid on the table.
# ─────────────────────────────────────────────

@export var type         : GameState.MeldType = GameState.MeldType.SEQUENCE
@export var owner_index  : int                = 0
@export var cards        : Array[CardData]    = []

func type_label() -> String:
	match type:
		GameState.MeldType.SEQUENCE: return "Sequence"
		GameState.MeldType.DUBLEE:   return "Dublee"
		GameState.MeldType.TUNNALA:  return "Tunnala"
		_: return "Unknown"

func card_count() -> int:
	return cards.size()

func meld_to_string() -> String:
	var card_names := cards.map(func(c): return c.display_name())
	return "[%s: %s]" % [type_label(), ", ".join(card_names)]
