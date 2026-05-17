extends Node
class_name DeckManager

# ═══════════════════════════════════════════════════════
#  DeckManager.gd
#  What it does: Builds the 162-card deck, shuffles it,
#  handles drawing, discarding, and most importantly —
#  assigns card ROLES once the Tiplu is revealed.
#
#  LEARNING: This extends Node (not Resource) because it
#  has BEHAVIOUR — it does things, manages state over time.
#  Resources are data. Nodes are actors.
#
#  This will be an Autoload (singleton) — meaning there's
#  only ONE DeckManager in the whole game and every scene
#  can access it directly by name.
# ═══════════════════════════════════════════════════════


# ── SIGNALS ─────────────────────────────────────────────
signal tiplu_revealed(tiplu_card: CardData)
signal deck_reshuffled
signal card_drawn(card: CardData)
signal card_discarded(card: CardData)
# UI listens to show TWO FACE-DOWN piles for blind selection
# Player picks a pile WITHOUT seeing the cards first!
signal waiting_for_cut(top_count: int, bottom_count: int)


# ── CONSTANTS ───────────────────────────────────────────
const NUM_DECKS       : int = 3
const JOKERS_PER_DECK : int = 2
const HAND_SIZE       : int = 21


# ── STATE ────────────────────────────────────────────────
var draw_pile    : Array[CardData] = []
var discard_pile : Array[CardData] = []
var tiplu        : CardData = null

# Cut state — stored temporarily while player chooses
var _cut_top_half    : Array[CardData] = []  # Top half of cut deck
var _cut_bottom_half : Array[CardData] = []  # Bottom half of cut deck
var _waiting_for_cut : bool = false          # Is the game waiting for player's cut choice?


# ── BUILD DECK ──────────────────────────────────────────
func build_and_shuffle() -> void:
	draw_pile.clear()
	discard_pile.clear()
	tiplu = null
	_cut_top_half.clear()
	_cut_bottom_half.clear()
	_waiting_for_cut = false

	for deck_idx in NUM_DECKS:
		for suit in [
			CardData.Suit.SPADES,
			CardData.Suit.HEARTS,
			CardData.Suit.DIAMONDS,
			CardData.Suit.CLUBS
		]:
			for rank_val in range(1, 14):
				var card          := CardData.new()
				card.suit         = suit as CardData.Suit
				card.rank         = rank_val as CardData.Rank
				card.deck_index   = deck_idx
				card.unique_id    = "%s_%s_%d" % [
					CardData.RANK_LABELS[rank_val as CardData.Rank],
					CardData.SUIT_NAMES[suit as CardData.Suit],
					deck_idx
				]
				card.role = CardData.Role.NORMAL
				draw_pile.append(card)

		for joker_idx in JOKERS_PER_DECK:
			var joker          := CardData.new()
			joker.suit         = CardData.Suit.JOKER
			joker.rank         = CardData.Rank.WILD
			joker.deck_index   = deck_idx
			joker.unique_id    = "JOKER_%d_%d" % [deck_idx, joker_idx]
			joker.role         = CardData.Role.WILD_JOKER
			draw_pile.append(joker)

	draw_pile.shuffle()
	print("[DeckManager] Built deck: %d cards" % draw_pile.size())


# ── DEAL CARDS ──────────────────────────────────────────
func deal(num_players: int) -> Array:
	var hands : Array = []
	for i in num_players:
		var hand : Array[CardData] = []
		for _j in HAND_SIZE:
			hand.append(draw_pile.pop_back())
		hands.append(hand)

	var first_discard := draw_pile.pop_back()
	discard_pile.append(first_discard)

	print("[DeckManager] Dealt to %d players. Deck remaining: %d" % [num_players, draw_pile.size()])
	return hands


# ── DRAW FROM DECK ──────────────────────────────────────
func draw_from_deck() -> CardData:
	if draw_pile.size() <= 1:
		_reshuffle_discard_into_deck()

	if draw_pile.is_empty():
		push_error("[DeckManager] No cards left to draw!")
		return null

	var card := draw_pile.pop_back()
	emit_signal("card_drawn", card)
	return card


# ── PICK UP DISCARD ─────────────────────────────────────
func pick_up_discard() -> CardData:
	if discard_pile.is_empty():
		push_error("[DeckManager] Discard pile is empty!")
		return null

	var card := discard_pile.pop_back()
	emit_signal("card_drawn", card)
	return card


# ── DISCARD CARD ────────────────────────────────────────
func discard_card(card: CardData) -> void:
	discard_pile.append(card)
	emit_signal("card_discarded", card)


# ── INITIATE CUT ────────────────────────────────────────
# Called when a player qualifies to see the Tiplu.
# Splits the deck in half and waits for player to choose.
#
# LEARNING: We emit a signal here instead of doing anything
# with the UI directly. The UI scene listens to this signal
# and shows the cut choice buttons. DeckManager doesn't
# need to know ANYTHING about buttons or visuals!

func initiate_cut() -> void:
	if _waiting_for_cut:
		push_warning("[DeckManager] Already waiting for cut!")
		return

	if draw_pile.size() < 2:
		push_error("[DeckManager] Not enough cards to cut!")
		return

	# Split deck at the middle
	# LEARNING: slice(start, end) returns a sub-array
	# draw_pile[-1] is the TOP (last element = top of stack)
	# draw_pile[0] is the BOTTOM (first element = bottom of stack)
	var mid : int = draw_pile.size() / 2

	# Top half = upper portion of deck (indices mid to end)
	_cut_top_half    = draw_pile.slice(mid)

	# Bottom half = lower portion of deck (indices 0 to mid)
	_cut_bottom_half = draw_pile.slice(0, mid)

	_waiting_for_cut = true

	# Tell the UI how many cards are in each half
	# so it can display "Top (45 cards)" / "Bottom (44 cards)"
	emit_signal("waiting_for_cut", _cut_top_half.size(), _cut_bottom_half.size())
	print("[DeckManager] Deck cut — Top: %d cards, Bottom: %d cards" % [
		_cut_top_half.size(), _cut_bottom_half.size()
	])


# ── PLAYER CHOOSES TOP HALF CARD ─────────────────────────
# Player clicked the LEFT pile (top half) — blind choice!
# They don't see the card until AFTER they click.
# Tiplu = bottom card of the top half (first element).

func choose_top_half() -> CardData:
	if not _waiting_for_cut:
		push_error("[DeckManager] Not currently waiting for a cut!")
		return null
	# Remove the bottom card of top half (index 0)
	var chosen_card := _cut_top_half[0]
	_cut_top_half.remove_at(0)
	return _complete_cut(chosen_card, _cut_top_half, _cut_bottom_half)


# ── PLAYER CHOOSES BOTTOM HALF CARD ──────────────────────
# Player clicked the RIGHT pile (bottom half) — blind choice!
# They don't see the card until AFTER they click.
# Tiplu = top card of the bottom half (last element).

func choose_bottom_half() -> CardData:
	if not _waiting_for_cut:
		push_error("[DeckManager] Not currently waiting for a cut!")
		return null
	# Remove the top card of bottom half (last element)
	var chosen_card := _cut_bottom_half.back()
	_cut_bottom_half.pop_back()
	return _complete_cut(chosen_card, _cut_bottom_half, _cut_top_half)


# ── COMPLETE THE CUT ────────────────────────────────────
# chosen_card  = the card player picked as Tiplu
# same_half    = remaining cards from chosen side
# other_half   = the other half of the deck

func _complete_cut(chosen_card: CardData, same_half: Array[CardData], other_half: Array[CardData]) -> CardData:
	tiplu = chosen_card

	# Rebuild draw pile:
	# Tiplu at the BOTTOM (index 0)
	# Then same_half cards
	# Then other_half cards on top
	draw_pile.clear()
	draw_pile.append(tiplu)
	draw_pile.append_array(same_half)
	draw_pile.append_array(other_half)

	# Clear cut state
	_cut_top_half.clear()
	_cut_bottom_half.clear()
	_waiting_for_cut = false

	_assign_all_roles()

	print("[DeckManager] Tiplu revealed: %s | Deck rebuilt: %d cards" % [
		tiplu.card_to_string(), draw_pile.size()
	])
	emit_signal("tiplu_revealed", tiplu)
	return tiplu


# ── ASSIGN CARD ROLES ────────────────────────────────────
func assign_roles_to_cards(all_cards: Array[CardData]) -> void:
	if not tiplu:
		push_error("[DeckManager] Cannot assign roles — no Tiplu set!")
		return
	for card in all_cards:
		card.role = _determine_role(card)

func _determine_role(card: CardData) -> CardData.Role:
	# Wild (Man) Jokers are always Wild Jokers
	if card.is_wild_joker:
		return CardData.Role.WILD_JOKER

	# Is this the Tiplu? (same rank + same suit)
	if card.rank == tiplu.rank and card.suit == tiplu.suit:
		return CardData.Role.TIPLU

	# Is this the Jhiplu? (one rank BELOW Tiplu, same suit)
	if card.suit == tiplu.suit:
		var jhiplu_rank : int = tiplu.rank_value - 1
		if jhiplu_rank == 0:
			jhiplu_rank = 13  # Below Ace = King
		if card.rank_value == jhiplu_rank:
			return CardData.Role.JHIPLU

	# Is this the Poplu? (one rank ABOVE Tiplu, same suit)
	if card.suit == tiplu.suit:
		var poplu_rank : int = tiplu.rank_value + 1
		if poplu_rank == 14:
			poplu_rank = 1  # Above King = Ace
		if card.rank_value == poplu_rank:
			return CardData.Role.POPLU

	# Is this an Alter or Ordinary Joker? (same rank, different suit)
	if card.rank == tiplu.rank and card.suit != tiplu.suit:
		if card.is_red == tiplu.is_red:
			return CardData.Role.ALTER          # Same color = Alter (5pts)
		else:
			return CardData.Role.ORDINARY_JOKER # Diff color = Ordinary Joker (0pts)

	return CardData.Role.NORMAL

func _assign_all_roles() -> void:
	for card in draw_pile:
		card.role = _determine_role(card)
	for card in discard_pile:
		card.role = _determine_role(card)


# ── RESHUFFLE ────────────────────────────────────────────
func _reshuffle_discard_into_deck() -> void:
	if discard_pile.size() <= 1:
		push_error("[DeckManager] Cannot reshuffle — not enough cards!")
		return

	print("[DeckManager] Reshuffling discard pile into deck...")

	var top_discard := discard_pile.pop_back()
	var new_cards   := discard_pile.duplicate()
	new_cards.shuffle()

	draw_pile.clear()
	if tiplu:
		draw_pile.append(tiplu)
	draw_pile.append_array(new_cards)

	discard_pile.clear()
	discard_pile.append(top_discard)

	emit_signal("deck_reshuffled")
	print("[DeckManager] Reshuffle complete. New deck: %d cards" % draw_pile.size())


# ── GETTERS ─────────────────────────────────────────────
func top_discard() -> CardData:
	if discard_pile.is_empty():
		return null
	return discard_pile.back()

func deck_count() -> int:
	return draw_pile.size()

func discard_count() -> int:
	return discard_pile.size()

func has_tiplu_been_revealed() -> bool:
	return tiplu != null

func is_waiting_for_cut() -> bool:
	return _waiting_for_cut