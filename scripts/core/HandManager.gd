extends Node2D
class_name HandManager

# ─────────────────────────────────────────────
#  HandManager.gd
#  Manages the visual layout of a player's hand.
#  Fan layout, card spacing, selection tracking.
# ─────────────────────────────────────────────

signal selection_changed(selected_cards: Array)
signal card_double_clicked(card: Card)

# ── Config ─────────────────────────────────────
@export var max_fan_angle    : float = 20.0   # degrees either side
@export var card_spacing     : float = 52.0   # px between card centers
@export var hand_y_offset    : float = 0.0
@export var is_face_up       : bool  = true   # false for opponent hands
@export var interactive      : bool  = true

const CARD_SCENE := preload("res://scenes/components/Card.tscn")

# ── State ──────────────────────────────────────
var _cards        : Array[Card] = []
var _selected     : Array[Card] = []
var _last_click_time : float    = 0.0
var _last_clicked : Card        = null

# ──────────────────────────────────────────────
func _ready() -> void:
	GameState.hand_updated.connect(_on_hand_updated)

func _on_hand_updated(player_index: int) -> void:
	if player_index == GameState.local_player:
		refresh_hand(GameState.get_my_hand())

# ── Refresh from data ──────────────────────────
func refresh_hand(hand_data: Array[CardData]) -> void:
	# Remove cards no longer in hand
	var to_remove: Array[Card] = []
	for card_node in _cards:
		var still_exists := hand_data.any(func(d): return d.unique_id == card_node.data.unique_id)
		if not still_exists:
			to_remove.append(card_node)

	for card_node in to_remove:
		_cards.erase(card_node)
		_selected.erase(card_node)
		var t := create_tween()
		t.tween_property(card_node, "modulate:a", 0.0, 0.2)
		t.tween_callback(card_node.queue_free)

	# Add new cards
	for card_data in hand_data:
		if not _has_card_node(card_data.unique_id):
			_spawn_card(card_data)

	_layout_hand()

func _spawn_card(card_data: CardData) -> void:
	var card_node: Card = CARD_SCENE.instantiate()
	add_child(card_node)
	card_node.setup(card_data, is_face_up)
	card_node.is_interactive = interactive
	card_node.position       = Vector2(0, -200)  # fly in from above
	card_node.modulate.a     = 0.0

	card_node.clicked.connect(_on_card_clicked.bind(card_node))
	card_node.drag_started.connect(_on_drag_started.bind(card_node))
	card_node.drag_ended.connect(_on_drag_ended.bind(card_node))

	_cards.append(card_node)

	# Fly-in animation
	var t := create_tween()
	t.tween_property(card_node, "modulate:a", 1.0, 0.2)

func _has_card_node(uid: String) -> bool:
	return _cards.any(func(c): return c.data.unique_id == uid)

# ── Layout: fan or row ─────────────────────────
func _layout_hand(animate: bool = true) -> void:
	var count := _cards.size()
	if count == 0:
		return

	# Sort hand: suit then rank
	_cards.sort_custom(func(a, b):
		if a.data.suit != b.data.suit:
			return a.data.suit < b.data.suit
		return a.data.rank_value < b.data.rank_value
	)

	# Clamp spacing so hand doesn't overflow screen
	var max_width   := 900.0
	var spacing     := min(card_spacing, max_width / max(count, 1))
	var total_width := spacing * (count - 1)
	var start_x     := -total_width / 2.0

	for i in count:
		var card_node := _cards[i]
		var target_x  := start_x + i * spacing
		var target_y  := hand_y_offset

		# Slight arc: middle cards sit lower, edges sit higher
		var t_val    := float(i) / max(count - 1, 1)  # 0..1
		var arc_y    := sin(t_val * PI) * -10.0        # subtle arc
		target_y    += arc_y

		# Push selected cards up
		if card_node.is_selected:
			target_y -= 20.0

		var target := Vector2(target_x, target_y)
		card_node.home_position = target

		if animate:
			card_node.move_to(target, 0.25)
		else:
			card_node.position = target

		# z-index: right-most card on top
		card_node.z_index = i

# ── Interaction ────────────────────────────────
func _on_card_clicked(card_node: Card) -> void:
	if not interactive:
		return

	# Double-click detection
	var now := Time.get_ticks_msec() / 1000.0
	if card_node == _last_clicked and (now - _last_click_time) < 0.4:
		emit_signal("card_double_clicked", card_node)
		_last_clicked = null
		return

	_last_click_time = now
	_last_clicked    = card_node

	card_node.toggle_selected()
	if card_node.is_selected:
		_selected.append(card_node)
	else:
		_selected.erase(card_node)

	_layout_hand()
	emit_signal("selection_changed", get_selected_data())

func _on_drag_started(card_node: Card) -> void:
	card_node.z_index = 200

func _on_drag_ended(card_node: Card, drop_pos: Vector2) -> void:
	card_node.z_index = _cards.find(card_node)
	card_node.move_to(card_node.home_position, 0.2)

# ── Selection helpers ──────────────────────────
func get_selected_data() -> Array[CardData]:
	var result: Array[CardData] = []
	for c in _selected:
		result.append(c.data)
	return result

func get_selected_ids() -> Array:
	return _selected.map(func(c): return c.data.unique_id)

func clear_selection() -> void:
	for c in _selected:
		c.set_selected(false)
	_selected.clear()
	_layout_hand()
	emit_signal("selection_changed", [])

func select_all() -> void:
	for c in _cards:
		if not c.is_selected:
			c.set_selected(true)
			_selected.append(c)
	_layout_hand()
	emit_signal("selection_changed", get_selected_data())

func card_count() -> int:
	return _cards.size()
