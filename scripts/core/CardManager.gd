extends Node

# ─────────────────────────────────────────────
#  CardManager.gd  (Autoload singleton)
#  Handles: deck construction, shuffling,
#  and ALL meld validation logic for Marriage.
# ─────────────────────────────────────────────

# ── Deck building ──────────────────────────────
func build_full_deck(num_decks: int = 3, jokers_per_deck: int = 2) -> Array[CardData]:
	var deck: Array[CardData] = []

	for d in num_decks:
		# Standard 52 cards
		for suit in [CardData.Suit.SPADES, CardData.Suit.HEARTS,
					 CardData.Suit.DIAMONDS, CardData.Suit.CLUBS]:
			for rank in range(CardData.Rank.ACE, CardData.Rank.KING + 1):
				var c          := CardData.new()
				c.suit         = suit
				c.rank         = rank as CardData.Rank
				c.deck_index   = d
				c.unique_id    = "%s_%s_%d" % [
					CardData.RANK_LABELS[rank],
					CardData.SUIT_NAMES[suit],
					d
				]
				deck.append(c)

		# Jokers
		for j in jokers_per_deck:
			var jk         := CardData.new()
			jk.suit        = CardData.Suit.JOKER
			jk.rank        = CardData.Rank.WILD
			jk.deck_index  = d
			jk.unique_id   = "JK_%d_%d" % [d, j]
			deck.append(jk)

	return deck

func shuffle_deck(deck: Array[CardData]) -> void:
	deck.shuffle()   # Godot's built-in Fisher-Yates

# ── Meld validation ────────────────────────────
# Returns a MeldData if valid, null otherwise.
func validate_meld(cards: Array[CardData]) -> MeldData:
	if cards.size() < 2:
		return null

	var jokers     := cards.filter(func(c): return c.is_joker)
	var non_jokers := cards.filter(func(c): return not c.is_joker)
	var joker_count: int = jokers.size()

	if non_jokers.is_empty():
		return null  # All jokers — not a valid meld

	# ── Tunnala: exactly 3 identical cards ──────
	if cards.size() == 3 and joker_count == 0:
		if _all_identical(non_jokers):
			return _make_meld(cards, GameState.MeldType.TUNNALA)

	# ── Dublee: exactly 2 identical cards ───────
	if cards.size() == 2 and joker_count == 0:
		if _all_same_face(non_jokers):
			# Must be from different physical decks
			if non_jokers[0].deck_index != non_jokers[1].deck_index:
				return _make_meld(cards, GameState.MeldType.DUBLEE)

	# ── Sequence: 3+ cards, same suit, consecutive ──
	if cards.size() >= 3:
		var result := _validate_sequence(non_jokers, joker_count)
		if result:
			return _make_meld(cards, GameState.MeldType.SEQUENCE)

	return null

# ── Sequence validation ────────────────────────
func _validate_sequence(non_jokers: Array, joker_count: int) -> bool:
	if non_jokers.is_empty():
		return false

	# All non-jokers must share the same suit
	var target_suit: CardData.Suit = non_jokers[0].suit
	for c in non_jokers:
		if c.suit != target_suit:
			return false
		if c.is_joker:
			return false

	# Sort by rank value
	var sorted := non_jokers.duplicate()
	sorted.sort_custom(func(a, b): return a.rank_value < b.rank_value)

	# Count gaps — each gap can be filled by one joker
	var gaps := 0
	for i in range(1, sorted.size()):
		var diff: int = sorted[i].rank_value - sorted[i - 1].rank_value
		if diff == 0:
			return false   # Duplicate rank in same suit = invalid sequence
		gaps += diff - 1

	# Jokers can fill gaps, and also extend either end
	return gaps <= joker_count

# ── Helpers ────────────────────────────────────
func _all_identical(cards: Array) -> bool:
	# Same rank + suit + different decks
	if cards.size() < 2: return false
	var ref: CardData = cards[0]
	var decks_seen := {}
	for c in cards:
		if c.rank != ref.rank or c.suit != ref.suit:
			return false
		if decks_seen.has(c.deck_index):
			return false     # Can't use same physical deck twice
		decks_seen[c.deck_index] = true
	return true

func _all_same_face(cards: Array) -> bool:
	if cards.size() < 2: return false
	var ref: CardData = cards[0]
	for c in cards:
		if c.rank != ref.rank or c.suit != ref.suit:
			return false
	return true

func _make_meld(cards: Array[CardData], type: GameState.MeldType) -> MeldData:
	var m       := MeldData.new()
	m.type      = type
	m.cards     = cards.duplicate()
	return m

# ── Meld suggestions (AI hint system) ──────────
# Given a hand, returns suggested melds sorted by value.
func suggest_melds(hand: Array[CardData]) -> Array:
	var suggestions := []

	# Find tunnala (3 identical)
	var face_groups := _group_by_face(hand)
	for key in face_groups:
		var group: Array = face_groups[key]
		if group.size() >= 3:
			var combos := _combinations(group, 3)
			for combo in combos:
				if _all_identical(combo):
					suggestions.append({ "type": "tunnala", "cards": combo, "score": 30 })

	# Find dublee (2 identical from different decks)
	for key in face_groups:
		var group: Array = face_groups[key]
		if group.size() >= 2:
			var combos := _combinations(group, 2)
			for combo in combos:
				if combo[0].deck_index != combo[1].deck_index:
					suggestions.append({ "type": "dublee", "cards": combo, "score": 15 })

	# Find sequences per suit
	for suit in [CardData.Suit.SPADES, CardData.Suit.HEARTS,
				 CardData.Suit.DIAMONDS, CardData.Suit.CLUBS]:
		var suit_cards := hand.filter(func(c): return c.suit == suit and not c.is_joker)
		suit_cards.sort_custom(func(a, b): return a.rank_value < b.rank_value)
		var jokers     := hand.filter(func(c): return c.is_joker)

		var seqs := _find_sequences(suit_cards, jokers)
		for seq in seqs:
			suggestions.append({ "type": "sequence", "cards": seq, "score": seq.size() * 10 })

	# Sort by score descending
	suggestions.sort_custom(func(a, b): return a["score"] > b["score"])
	return suggestions

func _group_by_face(hand: Array[CardData]) -> Dictionary:
	var groups := {}
	for c in hand:
		if c.is_joker: continue
		var key := "%s_%s" % [c.rank, c.suit]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(c)
	return groups

func _find_sequences(suit_cards: Array, jokers: Array) -> Array:
	var results := []
	if suit_cards.size() < 2:
		return results

	# Sliding window approach — find best sequences of 3+
	var n := suit_cards.size()
	for start in n:
		var seq    := [suit_cards[start]]
		var j_used := 0
		for i in range(start + 1, n):
			var gap: int = suit_cards[i].rank_value - seq.back().rank_value - 1
			if gap < 0: continue   # duplicate rank
			if j_used + gap <= jokers.size():
				j_used += gap
				# Fill gap with joker references
				for _g in gap:
					seq.append(jokers[j_used - gap + _g] if j_used - gap + _g < jokers.size() else null)
				seq.append(suit_cards[i])
			else:
				break
		seq = seq.filter(func(c): return c != null)
		if seq.size() >= 3:
			results.append(seq)
	return results

func _combinations(arr: Array, k: int) -> Array:
	var result := []
	var combo  := []
	_combo_helper(arr, k, 0, combo, result)
	return result

func _combo_helper(arr: Array, k: int, start: int, current: Array, result: Array) -> void:
	if current.size() == k:
		result.append(current.duplicate())
		return
	for i in range(start, arr.size()):
		current.append(arr[i])
		_combo_helper(arr, k, i + 1, current, result)
		current.pop_back()
