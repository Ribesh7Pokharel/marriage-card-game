extends Node
class_name MeldValidator

# ═══════════════════════════════════════════════════════
#  MeldValidator.gd
#  What it does: Validates ALL card combinations in Marriage.
#  This is the referee of the game — it decides if a group
#  of cards is a legal combination or not.
#
#  Combinations it validates:
#  - Pure Sequence (same suit, consecutive, no wildcards)
#  - Dirty Sequence (same suit, consecutive, with wildcards)
#  - Tunnela (3 identical — same rank + suit)
#  - Triplet/Trial (3 same rank, ALL different suits)
#  - Dirty Triplet (2 same rank diff suits + wildcard)
#  - Dublee (2 identical — same rank + suit)
#  - Marriage Ground (Jhiplu-Tiplu-Poplu on floor)
#  - Marriage Hand (Tiplu at end of sequence + hand card)
#
#  LEARNING: This is a "pure logic" class — no visuals,
#  no signals, just functions that take cards and return
#  true/false or a result. Easy to test independently!
# ═══════════════════════════════════════════════════════


# ── RESULT CLASS ────────────────────────────────────────
# Instead of just returning true/false, we return a
# ValidationResult that tells us WHAT type it is.
# LEARNING: Inner classes are classes defined inside another
# class. They're only accessible through MeldValidator.

class ValidationResult:
	var is_valid    : bool   = false
	var meld_type   : String = ""    # "pure_sequence", "dirty_sequence", etc.
	var is_marriage : bool   = false
	var marriage_type: String = ""   # "ground" or "hand"
	var points      : int    = 0     # Base points for this meld

	func _init(valid: bool, type: String = "") -> void:
		is_valid  = valid
		meld_type = type

	static func invalid() -> ValidationResult:
		return ValidationResult.new(false, "")

	static func valid(type: String) -> ValidationResult:
		return ValidationResult.new(true, type)


# ── MAIN VALIDATION ENTRY POINT ─────────────────────────
# This is the function GameState will call.
# Pass in cards and whether the player has seen the Tiplu.
# Returns a ValidationResult.
#
# LEARNING: "tiplu_seen" changes what's valid —
# before seeing Tiplu: only Pure Sequence and Tunnela allowed
# after seeing Tiplu: Dirty Sequence, Triplet, Dirty Triplet too

func validate(cards: Array[CardData], tiplu_seen: bool = false) -> ValidationResult:
	if cards.size() < 2:
		return ValidationResult.invalid()

	# Always check pure combinations first (no wildcards)
	var pure_result := _check_pure(cards)
	if pure_result.is_valid:
		return pure_result

	# Dirty combinations only available after seeing Tiplu
	if tiplu_seen:
		var dirty_result := _check_dirty(cards)
		if dirty_result.is_valid:
			return dirty_result

	return ValidationResult.invalid()


# ── VALIDATE FOR OPENING (showing 3 sets) ───────────────
# Stricter rules — only Pure Sequence or Tunnela allowed.
# NO wildcards, NO dirty sequences, NO triplets.

func validate_for_opening(cards: Array[CardData]) -> ValidationResult:
	if cards.size() < 3:
		return ValidationResult.invalid()

	# Check Pure Sequence
	var seq := _check_pure_sequence(cards)
	if seq.is_valid:
		return seq

	# Check Tunnela (3 identical same suit)
	var tun := _check_tunnela(cards)
	if tun.is_valid:
		return tun

	return ValidationResult.invalid()


# ── VALIDATE DUBLEE ─────────────────────────────────────
# Dublee = exactly 2 identical cards (same rank + same suit)
# from different physical decks.
# NO jokers allowed as wildcards for Dublees.

func validate_dublee(cards: Array[CardData]) -> ValidationResult:
	if cards.size() != 2:
		return ValidationResult.invalid()

	var a := cards[0]
	var b := cards[1]

	# Must be same rank and same suit
	if not a.same_face_as(b):
		return ValidationResult.invalid()

	# Must be from different physical decks
	if a.deck_index == b.deck_index:
		return ValidationResult.invalid()

	# No jokers allowed
	if a.is_wild_joker or b.is_wild_joker:
		return ValidationResult.invalid()

	return ValidationResult.valid("dublee")


# ── CHECK MARRIAGE ───────────────────────────────────────
# Marriage Ground: player shows Jhiplu-Tiplu-Poplu as
# one of their opening 3 sets.
#
# Marriage Hand: Tiplu is at EITHER END of a shown sequence
# AND the player holds the extending card in hand.
#
# LEARNING: We pass the tiplu card explicitly so this
# function works without needing access to DeckManager.

func check_ground_marriage(open_sets: Array) -> bool:
	# Look through all shown sets for Jhiplu-Tiplu-Poplu
	for set_cards in open_sets:
		var cards : Array[CardData] = set_cards
		if _is_ground_marriage(cards):
			return true
	return false

func check_hand_marriage(open_sets: Array, hand: Array[CardData]) -> bool:
	# Check each shown set — is Tiplu at either end?
	# And does the hand contain the extending card?
	for set_cards in open_sets:
		var cards : Array[CardData] = set_cards
		if _is_hand_marriage(cards, hand):
			return true
	return false

func _is_ground_marriage(cards: Array[CardData]) -> bool:
	if cards.size() < 3:
		return false
	# A ground marriage set contains Jhiplu + Tiplu + Poplu
	var has_tiplu  := cards.any(func(c: CardData): return c.role == CardData.Role.TIPLU)
	var has_jhiplu := cards.any(func(c: CardData): return c.role == CardData.Role.JHIPLU)
	var has_poplu  := cards.any(func(c: CardData): return c.role == CardData.Role.POPLU)
	return has_tiplu and has_jhiplu and has_poplu

func _is_hand_marriage(set_cards: Array[CardData], hand: Array[CardData]) -> bool:
	if set_cards.is_empty():
		return false

	# Sort the set by rank value
	var sorted := set_cards.duplicate()
	sorted.sort_custom(func(a: CardData, b: CardData): return a.rank_value < b.rank_value)

	var lowest  := sorted.front() as CardData
	var highest := sorted.back()  as CardData

	# Is Tiplu at the LOW end? Then we need Jhiplu in hand
	if lowest.role == CardData.Role.TIPLU:
		return hand.any(func(c: CardData):
			return c.role == CardData.Role.JHIPLU and c.suit == lowest.suit
		)

	# Is Tiplu at the HIGH end? Then we need Poplu in hand
	if highest.role == CardData.Role.TIPLU:
		return hand.any(func(c: CardData):
			return c.role == CardData.Role.POPLU and c.suit == highest.suit
		)

	return false


# ══════════════════════════════════════════════════════════
#  PURE COMBINATION CHECKS (no wildcards)
# ══════════════════════════════════════════════════════════

func _check_pure(cards: Array[CardData]) -> ValidationResult:
	# Check each pure type
	var seq := _check_pure_sequence(cards)
	if seq.is_valid: return seq

	var tun := _check_tunnela(cards)
	if tun.is_valid: return tun

	var tri := _check_triplet(cards)
	if tri.is_valid: return tri

	var dub := validate_dublee(cards)
	if dub.is_valid: return dub

	return ValidationResult.invalid()


# ── PURE SEQUENCE ────────────────────────────────────────
# 3+ consecutive cards of the SAME suit, NO wildcards.
# Ace rule: A-2-3 valid, Q-K-A valid, K-A-2 INVALID.

func _check_pure_sequence(cards: Array[CardData]) -> ValidationResult:
	if cards.size() < 3:
		return ValidationResult.invalid()

	# No wildcards allowed in pure sequence
	if cards.any(func(c: CardData): return c.is_wild_joker):
		return ValidationResult.invalid()

	# All cards must be same suit
	var suit := cards[0].suit
	if suit == CardData.Suit.JOKER:
		return ValidationResult.invalid()

	if not cards.all(func(c: CardData): return c.suit == suit):
		return ValidationResult.invalid()

	# Sort by rank value
	var sorted := cards.duplicate()
	sorted.sort_custom(func(a: CardData, b: CardData): return a.rank_value < b.rank_value)

	# Check for duplicate ranks (can't have two of same rank in sequence)
	for i in range(1, sorted.size()):
		if sorted[i].rank_value == sorted[i-1].rank_value:
			return ValidationResult.invalid()

	# Check consecutive — each step must be exactly 1
	var is_consecutive := true
	for i in range(1, sorted.size()):
		if sorted[i].rank_value - sorted[i-1].rank_value != 1:
			is_consecutive = false
			break

	if is_consecutive:
		# Check for marriage (Jhiplu-Tiplu-Poplu)
		var result := ValidationResult.valid("pure_sequence")
		if _is_ground_marriage(cards):
			result.is_marriage    = true
			result.marriage_type  = "ground"
		return result

	# Special case: Q-K-A (Ace at high end)
	# sorted would be [A=1, Q=12, K=13]
	# Check if first card is Ace and rest are consecutive ending at K
	if sorted[0].rank == CardData.Rank.ACE and sorted[1].rank == CardData.Rank.QUEEN:
		# Check Q, K, A sequence: [Q=12, K=13, A=1 treated as 14]
		var high_sorted := sorted.slice(1)  # [Q, K]
		high_sorted.append(sorted[0])       # [Q, K, A]
		var all_consec := true
		for i in range(1, high_sorted.size()):
			var prev_val : int = high_sorted[i-1].rank_value
			var curr_val : int = high_sorted[i].rank_value if i < 2 else 14  # Ace = 14 at high end
			if i == 2:
				if prev_val != 13:
					all_consec = false
					break
			elif curr_val - prev_val != 1:
				all_consec = false
				break
		if all_consec:
			return ValidationResult.valid("pure_sequence")

	return ValidationResult.invalid()


# ── TUNNELA ──────────────────────────────────────────────
# Exactly 3 cards — same rank AND same suit.
# All 3 must come from different physical decks.
# NO wildcards.

func _check_tunnela(cards: Array[CardData]) -> ValidationResult:
	if cards.size() != 3:
		return ValidationResult.invalid()

	# No wildcards
	if cards.any(func(c: CardData): return c.is_wild_joker):
		return ValidationResult.invalid()

	var ref := cards[0]

	# All must be same rank and same suit
	if not cards.all(func(c: CardData): return c.same_face_as(ref)):
		return ValidationResult.invalid()

	# All must be from different physical decks
	var deck_indices := cards.map(func(c: CardData): return c.deck_index)
	var unique_decks := {}
	for idx in deck_indices:
		if unique_decks.has(idx):
			return ValidationResult.invalid()  # Duplicate deck!
		unique_decks[idx] = true

	return ValidationResult.valid("tunnela")


# ── TRIPLET (TRIAL) ──────────────────────────────────────
# Exactly 3 cards — same rank, ALL DIFFERENT suits.
# This is the "Trial" or "Tanela" with different suits.
# NO wildcards.

func _check_triplet(cards: Array[CardData]) -> ValidationResult:
	if cards.size() != 3:
		return ValidationResult.invalid()

	# No wildcards
	if cards.any(func(c: CardData): return c.is_wild_joker):
		return ValidationResult.invalid()

	var ref := cards[0]

	# All must be same rank
	if not cards.all(func(c: CardData): return c.rank == ref.rank):
		return ValidationResult.invalid()

	# All must be DIFFERENT suits
	var suits := cards.map(func(c: CardData): return c.suit)
	var unique_suits := {}
	for s in suits:
		if unique_suits.has(s):
			return ValidationResult.invalid()  # Duplicate suit!
		unique_suits[s] = true

	# No joker suits
	if suits.has(CardData.Suit.JOKER):
		return ValidationResult.invalid()

	return ValidationResult.valid("triplet")


# ══════════════════════════════════════════════════════════
#  DIRTY COMBINATION CHECKS (with wildcards)
#  Only available AFTER seeing the Tiplu
# ══════════════════════════════════════════════════════════

func _check_dirty(cards: Array[CardData]) -> ValidationResult:
	var seq := _check_dirty_sequence(cards)
	if seq.is_valid: return seq

	var tri := _check_dirty_triplet(cards)
	if tri.is_valid: return tri

	return ValidationResult.invalid()


# ── DIRTY SEQUENCE ────────────────────────────────────────
# Consecutive cards same suit WITH wildcards filling gaps.
# Wildcards: Wild Joker, Tiplu, Jhiplu, Poplu, Alter,
#            Ordinary Joker (all can sub for missing cards)

func _check_dirty_sequence(cards: Array[CardData]) -> ValidationResult:
	if cards.size() < 3:
		return ValidationResult.invalid()

	var wildcards  := cards.filter(func(c: CardData): return c.is_wildcard or c.is_wild_joker)
	var non_wilds  := cards.filter(func(c: CardData): return not c.is_wildcard and not c.is_wild_joker)

	# Need at least 1 non-wildcard to determine the suit
	if non_wilds.is_empty():
		return ValidationResult.invalid()

	# All non-wildcards must be same suit
	var suit := (non_wilds[0] as CardData).suit
	if suit == CardData.Suit.JOKER:
		return ValidationResult.invalid()

	if not non_wilds.all(func(c: CardData): return c.suit == suit):
		return ValidationResult.invalid()

	# Sort non-wildcards by rank
	var sorted_nw := non_wilds.duplicate()
	sorted_nw.sort_custom(func(a: CardData, b: CardData): return a.rank_value < b.rank_value)

	# Count gaps between non-wildcards
	# Each gap requires one wildcard to fill
	var gaps_needed : int = 0
	for i in range(1, sorted_nw.size()):
		var diff : int = (sorted_nw[i] as CardData).rank_value - (sorted_nw[i-1] as CardData).rank_value
		if diff == 0:
			return ValidationResult.invalid()  # Duplicate rank
		gaps_needed += diff - 1

	# Wildcards can also extend the sequence at either end
	# Total wildcards available
	var wildcards_available : int = wildcards.size()

	if gaps_needed <= wildcards_available:
		var result := ValidationResult.valid("dirty_sequence")
		# Check if this forms a marriage (Jhiplu-Tiplu-Poplu dirty)
		if _is_ground_marriage(cards):
			result.is_marriage   = true
			result.marriage_type = "ground"
		return result

	return ValidationResult.invalid()


# ── DIRTY TRIPLET ────────────────────────────────────────
# 2 cards same rank DIFFERENT suits + 1 wildcard.
# INVALID: 2 cards same rank SAME suit + wildcard.
# INVALID: 2 identical cards + wildcard (same rank + same suit).

func _check_dirty_triplet(cards: Array[CardData]) -> ValidationResult:
	if cards.size() != 3:
		return ValidationResult.invalid()

	var wildcards := cards.filter(func(c: CardData): return c.is_wildcard or c.is_wild_joker)
	var non_wilds := cards.filter(func(c: CardData): return not c.is_wildcard and not c.is_wild_joker)

	# Must have exactly 1 wildcard and 2 non-wildcards
	if wildcards.size() != 1 or non_wilds.size() != 2:
		return ValidationResult.invalid()

	var a := non_wilds[0] as CardData
	var b := non_wilds[1] as CardData

	# Both non-wildcards must be same rank
	if a.rank != b.rank:
		return ValidationResult.invalid()

	# Both non-wildcards must be DIFFERENT suits
	# (This is the critical rule — same suit = invalid!)
	if a.suit == b.suit:
		return ValidationResult.invalid()

	# No joker suits
	if a.suit == CardData.Suit.JOKER or b.suit == CardData.Suit.JOKER:
		return ValidationResult.invalid()

	return ValidationResult.valid("dirty_triplet")


# ══════════════════════════════════════════════════════════
#  HELPER UTILITIES
# ══════════════════════════════════════════════════════════

# Check if a full hand of 21 cards can be split into
# valid sets for opening (3 sets of 3+ cards each)
# Returns all valid 3-set combinations found
func find_opening_sets(hand: Array[CardData]) -> Array:
	# This is a simplified check — finds obvious sets
	# A full solver would be too slow for real-time play
	var valid_combinations : Array = []
	_find_sets_recursive(hand, [], valid_combinations, 0)
	return valid_combinations

func _find_sets_recursive(
	remaining : Array[CardData],
	current_sets : Array,
	results : Array,
	depth : int
) -> void:
	# Found 3 sets — check if remaining cards are valid
	if current_sets.size() == 3:
		results.append(current_sets.duplicate())
		return

	# Try all combinations of 3+ cards from remaining
	if remaining.size() < 3:
		return

	# Limit search depth to avoid performance issues
	if depth > 6:
		return

	for size in [3, 4, 5]:
		if remaining.size() < size:
			break
		var combos := _get_combinations(remaining, size)
		for combo in combos:
			var result := validate_for_opening(combo)
			if result.is_valid:
				var new_remaining := remaining.filter(
					func(c: CardData): return not combo.has(c)
				)
				var new_sets := current_sets.duplicate()
				new_sets.append(combo)
				_find_sets_recursive(new_remaining, new_sets, results, depth + 1)

# Generate all combinations of k cards from array
func _get_combinations(arr: Array[CardData], k: int) -> Array:
	var result : Array = []
	var combo  : Array[CardData] = []
	_combo_helper(arr, k, 0, combo, result)
	return result

func _combo_helper(
	arr    : Array[CardData],
	k      : int,
	start  : int,
	current: Array[CardData],
	result : Array
) -> void:
	if current.size() == k:
		result.append(current.duplicate())
		return
	for i in range(start, arr.size()):
		current.append(arr[i])
		_combo_helper(arr, k, i + 1, current, result)
		current.pop_back()

# Quick check: does this hand have any valid opening sets?
# Used by CPU AI to decide strategy
func has_any_opening_sets(hand: Array[CardData]) -> bool:
	return not find_opening_sets(hand).is_empty()

# Type label for display
func type_label(meld_type: String) -> String:
	match meld_type:
		"pure_sequence":  return "Pure Sequence"
		"dirty_sequence": return "Dirty Sequence"
		"tunnela":        return "Tunnela"
		"triplet":        return "Triplet"
		"dirty_triplet":  return "Dirty Triplet"
		"dublee":         return "Dublee"
		_:                return "Unknown"