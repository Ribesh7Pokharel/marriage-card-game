extends Node
class_name CPUPlayer

# ─────────────────────────────────────────────
#  CPUPlayer.gd
#  AI opponent for the Marriage card game.
#  Difficulty levels: EASY, MEDIUM, HARD
# ─────────────────────────────────────────────

enum Difficulty { EASY, MEDIUM, HARD }

@export var player_index : int         = 1
@export var difficulty   : Difficulty  = Difficulty.MEDIUM
@export var think_time   : float       = 1.2   # seconds before acting

var _timer : Timer = null

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_take_turn)
	add_child(_timer)

	GameState.turn_changed.connect(_on_turn_changed)

func _on_turn_changed(current: int) -> void:
	if current == player_index and GameState.phase == GameState.Phase.DRAW:
		var jitter := randf_range(0.3, 0.6)
		_timer.start(think_time + jitter)

func _take_turn() -> void:
	if GameState.current_player != player_index:
		return

	var hand := GameState.players[player_index].hand

	# ── 1. DRAW phase ──────────────────────────
	_decide_draw(hand)

	await get_tree().create_timer(0.5).timeout

	# ── 2. PLAY phase — try to lay melds ───────
	_try_lay_melds()

	await get_tree().create_timer(0.4).timeout

	# ── 3. DISCARD ──────────────────────────────
	_discard_worst(hand)

func _decide_draw(hand: Array[CardData]) -> void:
	var top := GameState.top_discard()
	if top and _should_pick_discard(top, hand):
		GameState.draw_from_discard(player_index)
	else:
		GameState.draw_from_deck(player_index)

func _should_pick_discard(card: CardData, hand: Array[CardData]) -> bool:
	if card.is_joker:
		return true   # Always take a joker

	# Check if it completes or extends a sequence or set in hand
	var test_hand := hand.duplicate()
	test_hand.append(card)
	var suggestions := CardManager.suggest_melds(test_hand)

	for s in suggestions:
		var meld_cards: Array = s["cards"]
		if meld_cards.has(card):
			return true

	return false

func _try_lay_melds() -> void:
	var hand := GameState.players[player_index].hand
	var suggestions := CardManager.suggest_melds(hand)

	for suggestion in suggestions:
		if GameState.phase != GameState.Phase.PLAY:
			break
		var ids := (suggestion["cards"] as Array).map(func(c: CardData): return c.unique_id)
		var meld := GameState.lay_meld(player_index, ids)
		if meld:
			await get_tree().create_timer(0.3).timeout

	# Try adding to existing melds
	if difficulty >= Difficulty.MEDIUM:
		_try_add_to_melds()

func _try_add_to_melds() -> void:
	var player     := GameState.players[player_index]
	var hand_copy  := player.hand.duplicate()

	for mi in player.melds.size():
		for card in hand_copy:
			if GameState.phase != GameState.Phase.PLAY:
				return
			var ok := GameState.add_to_meld(player_index, mi, card.unique_id)
			if ok:
				await get_tree().create_timer(0.2).timeout
				break

func _discard_worst(hand: Array[CardData]) -> void:
	if hand.is_empty() or GameState.phase != GameState.Phase.PLAY:
		return

	var card_to_discard := _pick_worst_card(hand)
	if card_to_discard:
		GameState.discard_card(player_index, card_to_discard)

func _pick_worst_card(hand: Array[CardData]) -> CardData:
	# Score each card by how useful it is
	var scored := []
	for card in hand:
		scored.append({ "card": card, "value": _card_utility(card, hand) })
	scored.sort_custom(func(a, b): return a["value"] < b["value"])

	# Easy: random from bottom half; Medium/Hard: true worst
	if difficulty == Difficulty.EASY:
		var pool_size: int = max(1, scored.size() / 2)
		return scored[randi() % pool_size]["card"]
	return scored[0]["card"]

func _card_utility(card: CardData, hand: Array[CardData]) -> float:
	if card.is_joker:
		return 100.0   # Never discard jokers

	var score := 0.0

	# Check if this card is part of any potential meld
	var test := hand.filter(func(c): return c.unique_id != card.unique_id)
	test.append(card)
	var suggestions := CardManager.suggest_melds(test)
	for s in suggestions:
		if (s["cards"] as Array).any(func(c: CardData): return c.unique_id == card.unique_id):
			score += float(s["score"])

	# Prefer keeping middle ranks (easier to form sequences)
	var mid_bonus: float = 1.0 - abs(float(card.rank_value - 7) / 7.0)
	score += mid_bonus * 5.0

	return score
