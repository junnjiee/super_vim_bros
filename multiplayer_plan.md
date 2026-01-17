# Multiplayer Implementation Plan

## Overview
Add peer-to-peer LAN multiplayer to enable two developers to play against each other during development. Uses Godot 4.5's built-in ENet networking for direct IP connection.

## Architecture

```
NetworkManager (autoload) - Connection lifecycle
     |
Stage Scene
  +-- PlayerSpawner - Spawns players dynamically based on connected peers
  +-- Player 1 (authority: host)
  +-- Player 2 (authority: client)
  +-- LobbyUI - Host/Join interface
```

## Implementation Phases

### Phase 1: NetworkManager Autoload
**Create:** `autoload/network_manager.gd`

Core responsibilities:
- `host_game(port)` - Create ENet server on port 7777
- `join_game(ip, port)` - Connect to host
- `disconnect_game()` - Clean disconnect
- Signals: `player_connected`, `player_disconnected`, `connection_succeeded`, `connection_failed`

**Modify:** `project.godot` - Register autoload

### Phase 2: Modify Player for Multiplayer
**Modify:** `player/statemachine.gd`

Key changes:
1. Add authority check helper:
   ```gdscript
   func is_local_player() -> bool:
       return is_multiplayer_authority()
   ```

2. Guard input processing (only local player processes input):
   ```gdscript
   func _input(event) -> void:
       if not is_multiplayer_authority():
           return
       # ... existing code

   func get_input_direction(delta) -> Vector2:
       if not is_multiplayer_authority():
           return Vector2.ZERO
       # ... existing code
   ```

3. Server-authoritative damage:
   ```gdscript
   @rpc("authority", "call_local", "reliable")
   func network_apply_damage(amount: int):
       apply_damage(amount)

   func _on_attack_hitbox_body_entered(body: Node) -> void:
       # ... existing checks ...
       if not multiplayer.is_server():
           return  # Only server calculates damage
       if body.has_method("network_apply_damage"):
           body.network_apply_damage.rpc(amount)
   ```

**Modify:** `player/player.tscn`

Add MultiplayerSynchronizer node as child of CharacterBody2D:
- Sync properties: `position`, `velocity`, `current_state`, `health`
- Sync animated_sprite: `flip_h`, `animation`

### Phase 3: Player Spawning
**Modify:** `stages/vim_dojo_2d_stage.tscn`

1. Remove hardcoded player instance (CharacterBody2D2)
2. Add two Marker2D spawn points (left side, right side)
3. Add PlayerSpawner node

**Create:** `stages/player_spawner.gd`

Spawns players when peers connect:
- Host spawns at SpawnPoint1 (left)
- Client spawns at SpawnPoint2 (right)
- Sets `set_multiplayer_authority(peer_id)` for each player

### Phase 4: Lobby UI
**Create:** `ui/lobby/lobby_ui.tscn` and `lobby_ui.gd`

Simple UI with:
- IP address input (default: 127.0.0.1 for same-machine testing)
- Port input (default: 7777)
- Host button
- Join button
- Status label

Add to stage scene as CanvasLayer.

### Phase 5: Fix Relative Line Numbers for Multiplayer
**Modify:** `ui/relative_line_numbers/relative_line_numbers.gd`

Currently finds `players[0]`. Update to find the local player:
```gdscript
func _find_local_player():
    var players = get_tree().get_nodes_in_group("player")
    for player in players:
        if player.is_multiplayer_authority():
            return player
    return players[0] if players.size() > 0 else null
```

## Files to Create
| File | Purpose |
|------|---------|
| `autoload/network_manager.gd` | Connection management singleton |
| `stages/player_spawner.gd` | Dynamic player spawning |
| `ui/lobby/lobby_ui.tscn` | Host/Join UI scene |
| `ui/lobby/lobby_ui.gd` | Lobby UI logic |

## Files to Modify
| File | Changes |
|------|---------|
| `project.godot` | Add NetworkManager autoload |
| `player/statemachine.gd` | Add authority checks, network damage RPC |
| `player/player.tscn` | Add MultiplayerSynchronizer node |
| `stages/vim_dojo_2d_stage.tscn` | Remove hardcoded player, add spawn points + spawner + lobby UI |
| `ui/relative_line_numbers/relative_line_numbers.gd` | Track local player only |

## Combat Synchronization Model
- **Movement**: Each player has authority over their own position (synced via MultiplayerSynchronizer)
- **Damage**: Server-authoritative - only host calculates hitbox collisions and applies damage via RPC
- **State**: Synced automatically via MultiplayerSynchronizer

## Testing
1. **Same machine**: Run two Godot instances
   - Instance 1: Host on port 7777
   - Instance 2: Join `127.0.0.1:7777`

2. **LAN**:
   - Find host IP: `hostname -I` (Linux)
   - Host: Start game, click Host
   - Client: Enter host IP, click Join

## Verification Checklist
- [ ] Both players spawn at correct positions
- [ ] Each player can only control their own character
- [ ] Movement syncs smoothly between clients
- [ ] Attacks deal damage to opponent
- [ ] Health syncs correctly
- [ ] Death state triggers properly
- [ ] Disconnect handled gracefully
