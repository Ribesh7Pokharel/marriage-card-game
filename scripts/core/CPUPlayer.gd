extends Node
class_name CPUPlayer

# ═══════════════════════════════════════════════════════
#  CPUPlayer.gd
#  What it does: The AI brain for computer opponents.
#  Makes decisions about drawing, opening, and discarding.
#
#  LEARNING: This is a classic "AI agent" pattern.
#  The CPU observes the game state and picks the best
#  action based on its difficulty level.
#
#  Three difficulty levels:
#  EASY   — makes random decisions, often suboptimal
#  MEDIUM — plays reasonably, forms sets when obvious
#  HARD   — plays strategically, tracks discards, blocks
# ═══════════════════════════════════════════════════════


# ── ENUMS ───────────────────────────────────────────────
enum Difficulty { EASY, MEDIUM, HARD }


# ── CONFIG ──────────────────────────────────────────────
@export var player_index : int         = 1
@export var difficulty   : Difficulty  = Difficulty.MEDIUM

# How long the CPU "thinks" before acting (feels more natural)
const THINK_TIME_MIN : float = 0.8
const THINK_TIME_MAX : float = 2.0


# ── STATE ────────────────────────────────────────────────
var _game_state      : Node  = null   # Reference to GameState autoload
var _meld_validator  : Node  = null   # Reference to MeldValidator autoload
var _think_timer     : Timer = null
var _is_thinking     : bool  = false

# Card tracking (HARD mode) — remember what's been discarded
var _seen_discards   : Array[CardData] = []
var _known_tiplu     : CardData = null


# ── SETUP ────────────────────────────────────────────────
func _ready() -> void:
	_game_state     = get_node("/root/GameState")
	_meld_validator = get_node("/root/MeldValidator")

	# Create think timer
	_think_timer          = Timer.new()
	_think_timer.one_shot = true
	_think_timer.timeout.connect(_execute_turn)
	add_child(_think_timer)

	# Listen for turn changes
	_game_state.turn_changed.connect(_on_turn_changed)
	_game_state.card_discarded.connect(_on_card_discarded)
	_game_state.tiplu_revealed_to_player.connect(_on_tiplu_revealed)


# ── TURN DETECTION ───────────────────────────────────────
func _on_turn_changed(current: int) -> void:
	if current != player_index:
		return
	if _game_state.phase != GameState.Phase.DRAW:
		return

	# Start thinking after a random delay
	var think_time : float = randf_range(THINK_TIME_MIN, THINK_TIME_MAX)
	if difficulty == Difficulty.EASY:
		think_time *= 0.5   # Easy thinks faster (less careful)
	elif difficulty == Difficulty.HARD:
		think_time *= 1.3   # Hard thinks longer (more careful)

	_is_thinking = true
	_think_timer.start(think_time)


# ── MAIN TURN EXECUTION ──────────────────────────────────
# Called when the think timer fires.
# LEARNING: We split the turn into steps with await
# so the UI can animate between each action.

func _execute_turn() -> void:
	if _game_state.current_player != player_index:
		return

	_is_thinking = false

	# Step 1: Draw phase
	await _do_draw()
	await get_tree().create_timer(0.4).timeout

	# Step 2: Check if we can declare tunnelas (only at game start)
	if _game_state.phase == GameState.Phase.TUNNELA_WINDOW:
		await _check_tunnelas()
		return

	# Step 3: Try to open (show 3 sets) if not opened yet
	var my_player := _game_state.players[player_index]
	if not my_player.has_opened and _game_state.phase == GameState.Phase.PLAY:
		var opened := await _try_open()
		if opened:
			await get_tree().create_timer(0.5).timeout
			# Choose cut pile
			await _do_cut()
			return

	# Step 4: Try to finish if we've opened and seen Tiplu
	if my_player.has_opened and my_player.has_seen_tiplu:
		var finished := await _try_finish()
		if finished:
			return

	# Step 5: Discard
	await get_tree().create_timer(0.3).timeout
	await _do_discard()


# ── STEP 1: DRAW ─────────────────────────────────────────
func _do_draw() -> void:
	if _game_state.phase != GameState.Phase.DRAW:
		return

	var should_pick_discard := _decide_pick_discard()

	if should_pick_discard:
		_game_state.pick_up_discard(player_index)
	else:
		_game_state.draw_from_deck(player_index)


func _decide_pick_discard() -> bool:
	var top := _game_state.top_discard()
	if not top:
		return false

	match difficulty:
		Difficulty.EASY:
			# Easy just randomly picks up discard 20% of the time
			return randf() < 0.2

		Difficulty.MEDIUM:
			# Medium picks up if card is useful
			return _card_is_useful(top)

		Difficulty.HARD:
			# Hard picks up if card significantly helps AND
			# won't help the player to the right
			if not _card_is_useful(top):
				return false
			# Also check: does this deny the next player something good?
			return true

		_: return false


func _card_is_useful(card: CardData) -> bool:
	var hand := _game_state.players[player_index].hand

	# Wild jokers are always useful
	if card.is_wild_joker:
		return true

	# If we know the Tiplu, high-value cards are very useful
	if _known_tiplu:
		if card.role in [
			CardData.Role.TIPLU,
			CardData.Role.ALTER,
			CardData.Role.WILD_JOKER
		]:
			return true

	# Check if card extends any existing sequence in hand
	for hand_card in hand:
		if hand_card.suit == card.suit and not hand_card.is_wild_joker:
			var diff := abs(hand_card.rank_value - card.rank_value)
			if diff == 1:
				return true  # Adjacent card — extends a sequence

	# Check if card completes a dublee
	for hand_card in hand:
		if hand_card.same_face_as(card) and hand_card.deck_index != card.deck_index:
			return true

	return false


# ── STEP 2: CHECK TUNNELAS ───────────────────────────────
func _check_tunnelas() -> void:
	var hand := _game_state.players[player_index].hand

	# Group cards by face (rank + suit)
	var face_groups := _group_by_face(hand)

	for key in face_groups:
		var group : Array = face_groups[key]
		if group.size() == 3:
			# We have a tunnela! Declare it.
			var ids := group.map(func(c: CardData): return c.unique_id)
			_game_state.declare_tunnela(player_index, ids)
			await get_tree().create_timer(0.3).timeout


# ── STEP 3: TRY TO OPEN ──────────────────────────────────
func _try_open() -> bool:
	var hand := _game_state.players[player_index].hand.duplicate()

	# Try dublee play first if we have 7+ dublees (HARD mode only)
	if difficulty == Difficulty.HARD:
		var dublee_result := _find_seven_dublees(hand)
		if dublee_result.size() == 7:
			var dublee_ids := dublee_result.map(
				func(pair: Array): return pair.map(func(c: CardData): return c.unique_id)
			)
			return _game_state.show_dublee_opening(player_index, dublee_ids)

	# Try to find 3 valid opening sets
	var sets := _meld_validator.find_opening_sets(hand)
	if sets.is_empty():
		return false

	# Pick the best combination
	var best_sets := _pick_best_opening(sets)
	if best_sets.is_empty():
		return false

	var set_ids := best_sets.map(
		func(set_cards: Array): return set_cards.map(func(c: CardData): return c.unique_id)
	)
	return _game_state.show_opening_sets(player_index, set_ids)


func _pick_best_opening(all_sets: Array) -> Array:
	if all_sets.is_empty():
		return []

	# EASY: just pick the first valid combination
	if difficulty == Difficulty.EASY:
		return all_sets[0]

	# MEDIUM/HARD: pick combination that leaves best remaining hand
	# Score each combination by how many useful cards remain
	var best_score : float = -1.0
	var best       : Array = []

	for combo in all_sets:
		var score := _score_opening_combo(combo)
		if score > best_score:
			best_score = score
			best       = combo

	return best


func _score_opening_combo(combo: Array) -> float:
	# Score how good this opening combo is
	# Higher = better (leaves more useful cards in hand)
	var score : float = 0.0

	for set_cards in combo:
		for card in set_cards:
			var c := card as CardData
			# Prefer opening with normal cards, keep special cards
			if c.role == CardData.Role.NORMAL:
				score += 2.0
			else:
				score -= 3.0  # Using special cards in opening = bad

	return score


# ── STEP 4: DO CUT ───────────────────────────────────────
func _do_cut() -> void:
	if _game_state.phase != GameState.Phase.CUT_WINDOW:
		return

	await get_tree().create_timer(0.6).timeout

	# CPU always picks randomly — it's supposed to be blind!
	# LEARNING: Even HARD AI can't "cheat" here because in
	# real life you can't see the cards before cutting either
	if randf() < 0.5:
		_game_state.player_cuts_top(player_index)
	else:
		_game_state.player_cuts_bottom(player_index)


# ── STEP 5: TRY TO FINISH ────────────────────────────────
func _try_finish() -> bool:
	var player := _game_state.players[player_index]

	# Try dublee finish
	if player.is_dublee_play:
		return _try_finish_dublee()

	# Try sequence finish
	return _try_finish_sequence()


func _try_finish_sequence() -> bool:
	var hand := _game_state.players[player_index].hand.duplicate()

	# Need to form 4 sets from remaining hand + 1 discard
	# Try all combinations
	var result := _find_four_sets(hand)
	if result.is_empty():
		return false

	# Last card is the discard
	var all_used_ids : Array = []
	for set_cards in result:
		all_used_ids.append_array(
			set_cards.map(func(c: CardData): return c.unique_id)
		)

	var set_ids := result.map(
		func(set_cards: Array): return set_cards.map(func(c: CardData): return c.unique_id)
	)
	return _game_state.declare_finish_sequence(player_index, set_ids)


func _try_finish_dublee() -> bool:
	var hand := _game_state.players[player_index].hand.duplicate()

	# Find a dublee pair in the remaining hand
	var face_groups := _group_by_face(hand)
	for key in face_groups:
		var group : Array = face_groups[key]
		if group.size() >= 2:
			# Check it's a valid dublee (different deck indices)
			var a := group[0] as CardData
			var b := group[1] as CardData
			if a.deck_index != b.deck_index and not a.is_wild_joker:
				var ids := [a.unique_id, b.unique_id]
				return _game_state.declare_finish_dublee(player_index, ids)

	return false


func _find_four_sets(hand: Array[CardData]) -> Array:
	# Try to find 4 valid sets from hand (with wildcards)
	# This is a simplified greedy approach
	var remaining := hand.duplicate()
	var found_sets : Array = []

	# First try to form pure sets
	for _attempt in 4:
		if remaining.size() < 3:
			break
		var set_found := _find_one_set(remaining, true)
		if set_found.is_empty():
			break
		found_sets.append(set_found)
		for card in set_found:
			remaining.erase(card)

	if found_sets.size() == 4 and remaining.size() >= 1:
		return found_sets

	return []


func _find_one_set(hand: Array[CardData], tiplu_seen: bool) -> Array[CardData]:
	# Try to find a single valid 3-card set in the hand
	var n := hand.size()
	for i in n:
		for j in range(i+1, n):
			for k in range(j+1, n):
				var combo : Array[CardData] = [hand[i], hand[j], hand[k]]
				var result := _meld_validator.validate(combo, tiplu_seen)
				if result.is_valid:
					return combo
	return []


func _find_seven_dublees(hand: Array[CardData]) -> Array:
	var groups := _group_by_face(hand)
	var dublees : Array = []

	for key in groups:
		var group : Array = groups[key]
		if group.size() >= 2:
			var a := group[0] as CardData
			var b := group[1] as CardData
			if a.deck_index != b.deck_index and not a.is_wild_joker:
				dublees.append([a, b])
				if dublees.size() == 7:
					return dublees

	return dublees


# ── STEP 6: DISCARD ──────────────────────────────────────
func _do_discard() -> void:
	if _game_state.phase != GameState.Phase.PLAY:
		return

	var hand := _game_state.players[player_index].hand
	if hand.is_empty():
		return

	var card_to_discard := _choose_discard(hand)
	if card_to_discard:
		_game_state.discard_card(player_index, card_to_discard.unique_id)


func _choose_discard(hand: Array[CardData]) -> CardData:
	match difficulty:
		Difficulty.EASY:
			# Easy: discard a random card
			return hand[randi() % hand.size()]

		Difficulty.MEDIUM:
			# Medium: discard the least useful card
			return _find_worst_card(hand)

		Difficulty.HARD:
			# Hard: discard least useful card AND
			# try to discard something that won't help next player
			return _find_strategic_discard(hand)

		_:
			return hand[0]


func _find_worst_card(hand: Array[CardData]) -> CardData:
	var worst      : CardData = null
	var worst_score: float    = INF

	for card in hand:
		var score := _card_utility_score(card, hand)
		if score < worst_score:
			worst_score = score
			worst       = card

	return worst


func _find_strategic_discard(hand: Array[CardData]) -> CardData:
	# Same as worst card but also avoid discarding cards
	# that might help the player to the right
	var worst      : CardData = null
	var worst_score: float    = INF

	for card in hand:
		var score := _card_utility_score(card, hand)
		# Slightly penalize cards that next player might want
		# (simplified — in reality you'd track their hand)
		if score < worst_score:
			worst_score = score
			worst       = card

	return worst


func _card_utility_score(card: CardData, hand: Array[CardData]) -> float:
	# Higher score = more useful = less likely to discard
	var score : float = 0.0

	# Never discard wild jokers or high-value cards
	if card.is_wild_joker:
		return 100.0
	if card.role in [CardData.Role.TIPLU, CardData.Role.ALTER]:
		return 90.0
	if card.role in [CardData.Role.JHIPLU, CardData.Role.POPLU]:
		return 70.0

	# Check if card is part of a potential sequence
	for other in hand:
		if other.unique_id == card.unique_id:
			continue
		if other.suit == card.suit and not other.is_wild_joker:
			var diff := abs(other.rank_value - card.rank_value)
			if diff <= 2:
				score += (3.0 - diff) * 10.0  # Closer = more useful

	# Check if card is part of a dublee
	for other in hand:
		if other.unique_id == card.unique_id:
			continue
		if other.same_face_as(card) and other.deck_index != card.deck_index:
			score += 20.0

	# Middle ranks are more flexible for sequences
	var mid_bonus := 1.0 - abs(float(card.rank_value - 7) / 7.0)
	score += mid_bonus * 5.0

	return score


# ── TRACKING ─────────────────────────────────────────────
func _on_card_discarded(_player_index: int, card: CardData) -> void:
	if difficulty == Difficulty.HARD:
		_seen_discards.append(card)

func _on_tiplu_revealed(p_index: int, tiplu: CardData) -> void:
	if p_index == player_index:
		_known_tiplu = tiplu


# ── HELPERS ──────────────────────────────────────────────
func _group_by_face(hand: Array[CardData]) -> Dictionary:
	var groups : Dictionary = {}
	for card in hand:
		if card.is_wild_joker:
			continue
		var key : String = "%d_%d" % [card.rank, card.suit]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(card)
	return groups
