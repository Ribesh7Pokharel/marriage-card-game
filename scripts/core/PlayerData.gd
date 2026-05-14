extends Resource
class_name PlayerData

# ─────────────────────────────────────────────
#  PlayerData.gd
#  Holds everything about one player's state.
# ─────────────────────────────────────────────

@export var index    : int    = 0
@export var player_name : String = "Player"
@export var is_human : bool   = true
@export var peer_id  : int    = 0   # multiplayer peer ID (0 = local)

var hand  : Array[CardData] = []
var melds : Array           = []    # Array[MeldData]

func hand_count() -> int:
	return hand.size()

func to_dict() -> Dictionary:
	return {
		"index":    index,
		"name":     player_name,
		"is_human": is_human,
		"peer_id":  peer_id,
		"hand":     hand.map(func(c): return c.to_dict()),
	}
