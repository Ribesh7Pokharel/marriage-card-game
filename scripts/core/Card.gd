extends Node2D
class_name Card

# ─────────────────────────────────────────────
#  Card.gd  (Scene: scenes/components/Card.tscn)
#  Visual representation of a playing card.
#  Handles: rendering, drag-drop, flip animation,
#           hover effects, selection state.
# ─────────────────────────────────────────────

signal clicked(card: Card)
signal drag_started(card: Card)
signal drag_ended(card: Card, drop_position: Vector2)

# ── Colours ────────────────────────────────────
const COLOR_RED        := Color("#C0392B")
const COLOR_BLACK      := Color("#1A1A2E")
const COLOR_CARD_BG    := Color("#FAFAF8")
const COLOR_CARD_BACK  := Color("#1A3A6B")
const COLOR_SELECTED   := Color("#F5A623")
const COLOR_HOVER      := Color("#FFFFFF", 0.15)
const COLOR_JOKER_A    := Color("#E74C3C")
const COLOR_JOKER_B    := Color("#8E44AD")

# ── Layout ─────────────────────────────────────
const CARD_WIDTH   := 80.0
const CARD_HEIGHT  := 112.0
const CORNER_RAD   := 8.0

# ── State ──────────────────────────────────────
var data          : CardData  = null
var is_face_up    : bool      = true
var is_selected   : bool      = false
var is_hovering   : bool      = false
var is_dragging   : bool      = false
var is_interactive: bool      = true
var drag_offset   : Vector2   = Vector2.ZERO
var home_position : Vector2   = Vector2.ZERO  # where this card rests in hand

# ── Tween references ───────────────────────────
var _flip_tween    : Tween = null
var _move_tween    : Tween = null
var _hover_tween   : Tween = null

# ── Nodes (set up in _ready via code — no .tscn needed for logic) ──
@onready var _area   : Area2D       = $Area2D
@onready var _col    : CollisionShape2D = $Area2D/CollisionShape2D

func _ready() -> void:
	z_index = 0
	if _area:
		_area.mouse_entered.connect(_on_mouse_entered)
		_area.mouse_exited.connect(_on_mouse_exited)
		_area.input_event.connect(_on_input_event)

# ── Setup ──────────────────────────────────────
func setup(card_data: CardData, face_up: bool = true) -> void:
	data       = card_data
	is_face_up = face_up
	queue_redraw()

# ── Drawing ────────────────────────────────────
func _draw() -> void:
	if not data:
		return

	var rect := Rect2(-CARD_WIDTH / 2, -CARD_HEIGHT / 2, CARD_WIDTH, CARD_HEIGHT)

	# Shadow
	draw_rect(Rect2(rect.position + Vector2(3, 4), rect.size), Color(0, 0, 0, 0.25), true, 0.0)

	# Card body
	var bg_color := COLOR_CARD_BG if is_face_up else COLOR_CARD_BACK
	draw_rect(rect, bg_color, true, CORNER_RAD)

	# Border — gold if selected, subtle otherwise
	var border_color := COLOR_SELECTED if is_selected else Color(0, 0, 0, 0.12)
	var border_width := 3.0 if is_selected else 1.0
	draw_rect(rect, border_color, false, CORNER_RAD, border_width)

	# Hover tint
	if is_hovering and not is_dragging:
		draw_rect(rect, COLOR_HOVER, true, CORNER_RAD)

	if is_face_up:
		_draw_face(rect)
	else:
		_draw_back(rect)

func _draw_face(rect: Rect2) -> void:
	if data.is_joker:
		_draw_joker(rect)
		return

	var ink := COLOR_RED if data.is_red else COLOR_BLACK
	var rl  := data.rank_label()
	var ss  := data.suit_symbol()

	# Top-left rank + suit
	draw_string(
		ThemeDB.fallback_font,
		rect.position + Vector2(6, 16),
		rl, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink
	)
	draw_string(
		ThemeDB.fallback_font,
		rect.position + Vector2(6, 30),
		ss, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink
	)

	# Center large suit symbol
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-10, 8),
		ss, HORIZONTAL_ALIGNMENT_CENTER, -1, 28, ink
	)

	# Bottom-right (rotated 180°)
	draw_string(
		ThemeDB.fallback_font,
		rect.end - Vector2(6, 4),
		rl, HORIZONTAL_ALIGNMENT_RIGHT, -1, 14, ink
	)

func _draw_back(rect: Rect2) -> void:
	# Decorative back pattern
	var inner := rect.grow(-6)
	draw_rect(inner, Color(1, 1, 1, 0.08), false, 4.0, 1.5)
	# Simple diagonal pattern
	var step := 10
	for i in range(-int(CARD_HEIGHT), int(CARD_WIDTH + CARD_HEIGHT), step):
		var p1 := Vector2(rect.position.x + i, rect.position.y)
		var p2 := Vector2(rect.position.x + i + CARD_HEIGHT, rect.position.y + CARD_HEIGHT)
		draw_line(p1, p2, Color(1, 1, 1, 0.06), 1.0)

func _draw_joker(rect: Rect2) -> void:
	# Rainbow-ish gradient approximation with two rects
	draw_rect(Rect2(rect.position, Vector2(CARD_WIDTH / 2, CARD_HEIGHT)), COLOR_JOKER_A, true, CORNER_RAD)
	draw_rect(Rect2(rect.position + Vector2(CARD_WIDTH / 2, 0), Vector2(CARD_WIDTH / 2, CARD_HEIGHT)), COLOR_JOKER_B, true, CORNER_RAD)
	draw_rect(rect, Color(0, 0, 0, 0.1), false, CORNER_RAD, 1.0)
	draw_string(ThemeDB.fallback_font, Vector2(-10, 6), "JK", HORIZONTAL_ALIGNMENT_CENTER, -1, 20, Color.WHITE)
	draw_string(ThemeDB.fallback_font, Vector2(-8, 26), "★", HORIZONTAL_ALIGNMENT_CENTER, -1, 24, Color.YELLOW)

# ── Selection ──────────────────────────────────
func set_selected(value: bool) -> void:
	if is_selected == value:
		return
	is_selected = value
	var target_y := home_position.y - (20 if is_selected else 0)
	_tween_to(Vector2(home_position.x, target_y), 0.15)
	queue_redraw()

func toggle_selected() -> void:
	set_selected(not is_selected)

# ── Flip animation ─────────────────────────────
func flip(face_up: bool, duration: float = 0.25) -> void:
	if _flip_tween:
		_flip_tween.kill()
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "scale:x", 0.0, duration / 2)
	_flip_tween.tween_callback(func():
		is_face_up = face_up
		queue_redraw()
	)
	_flip_tween.tween_property(self, "scale:x", 1.0, duration / 2)

# ── Movement ───────────────────────────────────
func move_to(target: Vector2, duration: float = 0.3, ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	if _move_tween:
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.set_ease(ease_type)
	_move_tween.set_trans(Tween.TRANS_BACK)
	_move_tween.tween_property(self, "position", target, duration)

func _tween_to(target: Vector2, duration: float) -> void:
	move_to(target, duration, Tween.EASE_OUT)

# ── Drag & Drop ────────────────────────────────
func _on_input_event(_viewport, event: InputEvent, _shape_idx) -> void:
	if not is_interactive:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_dragging   = true
				drag_offset   = position - get_global_mouse_position()
				z_index       = 100
				emit_signal("drag_started", self)
			else:
				if is_dragging:
					is_dragging = false
					z_index     = 0
					emit_signal("drag_ended", self, get_global_mouse_position())
				elif not is_dragging:
					emit_signal("clicked", self)

func _process(_delta: float) -> void:
	if is_dragging:
		position = get_global_mouse_position() + drag_offset
		queue_redraw()

# ── Hover ──────────────────────────────────────
func _on_mouse_entered() -> void:
	if not is_interactive or is_dragging:
		return
	is_hovering = true
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1)
	queue_redraw()

func _on_mouse_exited() -> void:
	is_hovering = false
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	queue_redraw()

# ── Getters ────────────────────────────────────
func get_data() -> CardData:
	return data

func card_rect() -> Rect2:
	return Rect2(global_position - Vector2(CARD_WIDTH / 2, CARD_HEIGHT / 2), Vector2(CARD_WIDTH, CARD_HEIGHT))
