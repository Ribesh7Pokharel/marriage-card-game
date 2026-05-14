extends Node

# ─────────────────────────────────────────────
#  NetworkManager.gd  (Autoload singleton)
# ─────────────────────────────────────────────

signal player_connected(peer_id: int, p_name: String)
signal player_disconnected(peer_id: int)
signal connection_failed
signal connection_succeeded
signal game_action_received(action: Dictionary)

const PORT        := 7777
const MAX_CLIENTS := 4

var peer             : ENetMultiplayerPeer = null
var is_host          : bool                = false
var player_name      : String              = "Player"
var connected_peers  : Dictionary          = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

# ── Host ───────────────────────────────────────
func host_game(p_name: String) -> void:
	self.player_name = p_name
	peer             = ENetMultiplayerPeer.new()
	var err          := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		push_error("Failed to create server: %d" % err)
		return
	multiplayer.multiplayer_peer = peer
	is_host                      = true
	connected_peers[1]           = p_name
	print("[Net] Hosting on port %d" % PORT)

# ── Join ───────────────────────────────────────
func join_game(host_ip: String, p_name: String) -> void:
	self.player_name = p_name
	peer             = ENetMultiplayerPeer.new()
	var err          := peer.create_client(host_ip, PORT)
	if err != OK:
		push_error("Failed to connect: %d" % err)
		emit_signal("connection_failed")
		return
	multiplayer.multiplayer_peer = peer
	is_host                      = false
	print("[Net] Connecting to %s:%d" % [host_ip, PORT])

# ── Disconnect ─────────────────────────────────
func disconnect_game() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	peer                         = null
	connected_peers.clear()
	is_host                      = false

# ── Send game actions (RPC) ────────────────────
@rpc("any_peer", "call_local", "reliable")
func send_action(action: Dictionary) -> void:
	if multiplayer.is_server():
		var validated := _validate_action(action)
		if validated:
			_broadcast_action.rpc(action)
	else:
		send_action.rpc_id(1, action)

@rpc("authority", "call_local", "reliable")
func _broadcast_action(action: Dictionary) -> void:
	emit_signal("game_action_received", action)

func _validate_action(action: Dictionary) -> bool:
	if not action.has("type"):
		return false
	var sender_idx := _peer_to_player_index(action.get("peer_id", 0))
	if sender_idx != GameState.current_player:
		return false
	return true

# ── Announce player name when connecting ───────
@rpc("any_peer", "call_local", "reliable")
func announce_player(p_name: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	connected_peers[sender_id] = p_name
	emit_signal("player_connected", sender_id, p_name)

# ── Callbacks ──────────────────────────────────
func _on_peer_connected(id: int) -> void:
	print("[Net] Peer connected: %d" % id)
	if not is_host:
		announce_player.rpc_id(1, player_name)

func _on_peer_disconnected(id: int) -> void:
	print("[Net] Peer disconnected: %d" % id)
	connected_peers.erase(id)
	emit_signal("player_disconnected", id)

func _on_connected_to_server() -> void:
	print("[Net] Connected to server!")
	announce_player.rpc_id(1, player_name)
	emit_signal("connection_succeeded")

func _on_connection_failed() -> void:
	print("[Net] Connection failed")
	emit_signal("connection_failed")

# ── Helpers ────────────────────────────────────
func _peer_to_player_index(peer_id: int) -> int:
	var peers := connected_peers.keys()
	return peers.find(peer_id)

func get_peer_count() -> int:
	return connected_peers.size()

func my_peer_id() -> int:
	return multiplayer.get_unique_id()
