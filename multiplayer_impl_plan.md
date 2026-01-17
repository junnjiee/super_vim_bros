# Local Network Multiplayer Implementation Plan

## Overview

Implement local network (LAN) multiplayer for the Vim fighting game using Godot 4.5's built-in ENet high-level multiplayer system. Two developers on the same network will be able to host/join games and battle using vim keybindings.

**Architecture:** Server-authoritative peer-to-peer model where the host acts as server. Uses MultiplayerSynchronizer for automatic state replication and RPCs for combat events.

## Key Design Decisions

1. **ENetMultiplayerPeer** - Godot's built-in networking (no external dependencies)
2. **Dynamic Player Spawning** - Server spawns players when peers connect (no hardcoded instances)
3. **Hybrid Synchronization** - MultiplayerSynchronizer for movement/state, RPCs for damage
4. **Server-Authoritative Combat** - Host calculates all hitbox collisions to prevent cheating
5. **Authority-Based Input** - Each player only processes input for their own character

## Files to Create

### 1. `/autoload/network_manager.gd` (~70 lines)
**Purpose:** Global networking singleton

**Responsibilities:**
- Create ENet server/client
- Emit connection lifecycle signals
- Handle disconnection cleanup

**Key Methods:**
- `host_game(port: int)` - Create server on specified port
- `join_game(ip: String, port: int)` - Connect to host
- `disconnect_from_game()` - Clean shutdown

**Signals:**
- `player_connected(peer_id: int)`
- `player_disconnected(peer_id: int)`
- `connection_succeeded` (client only)
- `connection_failed` (client only)

**Constants:**
- `DEFAULT_PORT = 7777`
- `MAX_PLAYERS = 2`

### 2. `/stages/player_spawner.gd` (~65 lines)
**Purpose:** Dynamic player instantiation

**Exports:**
- `player_scene: PackedScene` - Reference to player.tscn
- `spawn_point_1: NodePath` - Left spawn (host)
- `spawn_point_2: NodePath` - Right spawn (client)

**Logic:**
- Listen to `NetworkManager.player_connected` (server only)
- Instantiate player at correct spawn point based on peer_id
- Call `set_multiplayer_authority(peer_id)` on spawned player
- Handle player removal on disconnect

### 3. `/ui/lobby/lobby_ui.tscn`
**Purpose:** Host/Join UI

**Structure:**
```
CanvasLayer (LobbyUI)
  └─ Panel
      └─ VBoxContainer
          ├─ Label ("Multiplayer Lobby")
          ├─ LineEdit (IPInput) - default: "127.0.0.1"
          ├─ LineEdit (PortInput) - default: "7777"
          ├─ Button (HostButton) - "Host Game"
          ├─ Button (JoinButton) - "Join Game"
          └─ Label (StatusLabel) - "Ready"
```

### 4. `/ui/lobby/lobby_ui.gd` (~75 lines)
**Purpose:** Lobby UI logic

**Features:**
- Host button → `NetworkManager.host_game(port)`
- Join button → `NetworkManager.join_game(ip, port)`
- Connection status updates
- Hide lobby when game starts
- Error handling for failed connections

## Files to Modify

### 1. `/project.godot`
**Change:** Add NetworkManager autoload

```ini
[autoload]
NetworkManager="*res://autoload/network_manager.gd"
```

### 2. `/player/statemachine.gd` (~15 lines modified)

**Add authority checks:**
```gdscript
func _input(event) -> void:
    if not is_multiplayer_authority():
        return
    # ... existing input logic

func get_input_direction(delta) -> Vector2:
    if not is_multiplayer_authority():
        return Vector2.ZERO
    # ... existing direction logic
```

**Add network damage RPC:**
```gdscript
@rpc("authority", "call_local", "reliable")
func network_apply_damage(amount: int):
    apply_damage(amount)
```

**Modify hitbox collision (line 431-437):**
```gdscript
func _on_attack_hitbox_body_entered(body: Node) -> void:
    if current_state != State.ATTACK:
        return
    if body == self:
        return
    # Only server calculates damage
    if not multiplayer.is_server():
        return
    if body.has_method("network_apply_damage"):
        body.network_apply_damage.rpc(10)
```

### 3. `/player/player.tscn`

**Add MultiplayerSynchronizer:**
- Add as child of CharacterBody2D root node
- Create SceneReplicationConfig resource
- Configure 6 properties to sync:

| Property | Purpose |
|----------|---------|
| `.:position` | Character world position |
| `.:velocity` | Movement velocity (smooth interpolation) |
| `.:current_state` | State machine state (IDLE/WALK/ATTACK/etc) |
| `.:health` | HP value |
| `AnimatedSprite2D:flip_h` | Sprite facing direction |
| `AnimatedSprite2D:animation` | Current animation name |

All properties use **replication_mode = 1 (Server)** - each player has authority over their own instance.

### 4. `/stages/vim_dojo_2d_stage.tscn`

**Changes:**
1. **Remove** hardcoded player instance (CharacterBody2D2 at line 42+)
2. **Add** SpawnPoint1 (Marker2D) at position (400, 694) - left side
3. **Add** SpawnPoint2 (Marker2D) at position (1500, 694) - right side
4. **Add** PlayerSpawner node with script:
   - `player_scene = preload("res://player/player.tscn")`
   - `spawn_point_1 = NodePath("../SpawnPoint1")`
   - `spawn_point_2 = NodePath("../SpawnPoint2")`
5. **Add** LobbyUI instance

### 5. `/ui/relative_line_numbers/relative_line_numbers.gd`

**Modify `_find_player()` to track local player:**
```gdscript
func _find_player():
    var players = get_tree().get_nodes_in_group("player")
    # Find the local player (the one this peer controls)
    for p in players:
        if p.is_multiplayer_authority():
            player = p
            return
    # Fallback for single-player
    if players.size() > 0:
        player = players[0]
```

## Implementation Steps

1. **Create NetworkManager autoload** - Core networking singleton
2. **Register autoload in project.godot** - Make it globally accessible
3. **Modify player statemachine.gd** - Add authority checks and RPC
4. **Add MultiplayerSynchronizer to player.tscn** - Configure state sync
5. **Create PlayerSpawner script** - Dynamic spawning logic
6. **Create LobbyUI scene and script** - Host/Join interface
7. **Modify stage scene** - Remove hardcoded player, add spawn points
8. **Fix RelativeLineNumbers** - Track local player only
9. **Test on same machine** - Verify basic functionality
10. **Test on LAN** - Two developers on different computers

## Synchronization Strategy

### Automatic via MultiplayerSynchronizer
- **Position/Velocity** - Smooth movement replication (60 Hz)
- **State** - Current state machine state (on change)
- **Health** - HP value (on change)
- **Visuals** - Sprite flip and animation (on change)

### Manual via RPC
- **Damage** - Server-authoritative combat
  - Server detects hitbox collision
  - Server calls `victim.network_apply_damage.rpc(10)`
  - Victim applies damage locally
  - Health syncs automatically via MultiplayerSynchronizer

## User Flow

### Host:
1. Game starts → Lobby UI visible
2. Click "Host Game"
3. NetworkManager creates server on port 7777
4. Host player spawns at left position
5. UI shows "Waiting for player..."
6. When client connects → "Starting game..." → Lobby hides

### Client:
1. Game starts → Lobby UI visible
2. Enter host's IP address (e.g., "192.168.1.100" or "127.0.0.1" for local testing)
3. Click "Join Game"
4. NetworkManager connects to host
5. On success → Client player spawns at right position → Lobby hides
6. On failure → Error message, UI re-enabled for retry

## Testing Approach

### Phase 1: Same-Machine Testing
Run two Godot instances or export debug builds:
- [ ] Both players spawn at correct positions (left/right)
- [ ] Each player controls only their own character
- [ ] Opponent movement syncs correctly
- [ ] Grid dashes sync (3h, 5l, etc.)
- [ ] Attack animations sync
- [ ] Damage applies correctly
- [ ] Hitstun state syncs
- [ ] Death state syncs (0 HP)
- [ ] RelativeLineNumbers tracks correct player

### Phase 2: LAN Testing
Two computers on same network:
- [ ] Connection succeeds via LAN IP
- [ ] All Phase 1 tests pass
- [ ] Latency is acceptable (<50ms)
- [ ] No visual stuttering

### Phase 3: Edge Cases
- [ ] Host disconnects → Client sees error
- [ ] Client disconnects → Host's opponent disappears
- [ ] Simultaneous attacks → Both take damage
- [ ] Reconnection handling

## Critical Files Summary

**Core Networking:**
- `/autoload/network_manager.gd` - Connection management
- `/stages/player_spawner.gd` - Dynamic spawning

**Player Modifications:**
- `/player/statemachine.gd` - Authority checks + RPC damage
- `/player/player.tscn` - MultiplayerSynchronizer

**UI:**
- `/ui/lobby/lobby_ui.tscn` - Host/Join interface
- `/ui/lobby/lobby_ui.gd` - Lobby logic
- `/ui/relative_line_numbers/relative_line_numbers.gd` - Local player tracking

**Scene Setup:**
- `/stages/vim_dojo_2d_stage.tscn` - Spawn points + lobby
- `/project.godot` - Autoload registration

## Verification

After implementation, verify:
1. **Single-player still works** - Multiplayer code doesn't break existing gameplay
2. **Host/Join flow** - Lobby UI connects successfully
3. **Player spawning** - Both players appear at correct positions
4. **Input isolation** - Each player controls only their character
5. **Combat sync** - Attacks deal damage on both screens
6. **Visual consistency** - Same animations/states on both clients
7. **Disconnection handling** - Graceful cleanup on disconnect

## Performance Expectations

**Network Bandwidth:** ~5 KB/s per client (negligible on LAN)
**CPU Overhead:** <1% (minimal processing)
**Latency:** <10ms on LAN
**FPS Impact:** None expected

## Future Enhancements (Post-MVP)

- Camera following local player
- Reconnection support
