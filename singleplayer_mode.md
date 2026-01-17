# Singleplayer Debug Mode Implementation Plan

## Overview
Add a singleplayer mode for debugging and testing character movement without requiring network connections.

## Current Architecture Challenges
1. **Multiplayer authority checks**: `statemachine.gd:86,343,429` uses `is_multiplayer_authority()` which returns `false` when no multiplayer peer exists
2. **Player spawning**: `player_spawner.gd` only spawns players when network peers connect
3. **Lobby UI**: Blocks gameplay until network connection established
4. **Damage RPC**: `_on_attack_hitbox_body_entered()` uses `multiplayer.is_server()` check

## Implementation Approach

### Option: Add "Singleplayer" button to Lobby UI
This is the simplest approach - add a button that starts offline play immediately.

---

## Files to Modify

### 1. `ui/lobby/lobby_ui.gd`
Add a "Singleplayer" button that:
- Emits a signal to start singleplayer mode
- Hides the lobby UI

### 2. `ui/lobby/lobby_ui.tscn`
Add a new Button node for singleplayer mode.

### 3. `stages/player_spawner.gd`
Add a function to spawn a local player without network:
- Create player instance
- Set multiplayer authority to 1 (default local)
- Position at spawn point 1

### 4. `player/statemachine.gd`
Modify multiplayer checks to work in offline mode:
- `is_multiplayer_authority()` returns `true` when `multiplayer.multiplayer_peer == null`
- Update damage logic to work locally

### 5. (Optional) Add debug features
- Respawn hotkey (R key)
- On-screen state/position display

---

## Detailed Changes

### lobby_ui.gd - Add singleplayer handling
```gdscript
# Add signal
signal singleplayer_requested

# Add button reference
@onready var singleplayer_button: Button = $Panel/VBoxContainer/SingleplayerButton

# In _ready()
singleplayer_button.pressed.connect(_on_singleplayer_button_pressed)

# New function
func _on_singleplayer_button_pressed():
    status_label.text = "Starting singleplayer..."
    singleplayer_requested.emit()
    hide()
```

### player_spawner.gd - Add local spawn function
```gdscript
func spawn_local_player() -> void:
    if not player_scene:
        push_error("Player scene not set")
        return

    var spawn_point = get_node(spawn_point_1) as Node2D
    if not spawn_point:
        push_error("Spawn point not found")
        return

    var player = player_scene.instantiate()
    player.name = "Player_Local"
    player.global_position = spawn_point.global_position
    # Authority defaults to 1 when no peer exists
    get_parent().add_child(player)
    spawned_players[1] = player
    print("Local player spawned at ", spawn_point.global_position)
```

### statemachine.gd - Handle offline mode
Modify `is_multiplayer_authority()` checks to also return true when offline:

```gdscript
func _is_local_authority() -> bool:
    # If no multiplayer peer, we're in singleplayer - always have authority
    if multiplayer.multiplayer_peer == null:
        return true
    return is_multiplayer_authority()
```

Replace `is_multiplayer_authority()` calls with `_is_local_authority()` at:
- Line 86 in `_physics_process()`
- Line 343 in `get_input_direction()`
- Line 429 in `_input()`

For damage in `_on_attack_hitbox_body_entered()`:
```gdscript
# Check if we should handle damage locally
if multiplayer.multiplayer_peer == null:
    body.apply_damage(10)
elif multiplayer.is_server():
    body.network_apply_damage.rpc(10)
```

### vim_dojo_2d_stage.tscn - Connect signal
Connect LobbyUI's `singleplayer_requested` signal to PlayerSpawner's `spawn_local_player()`.

---

## Verification Steps

1. **Launch game** → Lobby UI should show with Host, Join, and Singleplayer buttons
2. **Click Singleplayer** → Lobby hides, player spawns at left spawn point
3. **Test movement**:
   - H/L keys for walk left/right
   - K for jump
   - W/B for 5-tile dashes
   - Number + HJKL for counted dashes (e.g., 3H)
4. **Test attacks**:
   - DD for neutral combo
   - D+W / D+B for directional attacks
5. **Verify no errors** in Godot console related to multiplayer

---

## Summary

This implementation adds a minimal singleplayer mode for testing character movement by:
1. Adding a "Singleplayer" button to the lobby
2. Spawning a local player without network setup
3. Making multiplayer authority checks work offline

No additional debug features (overlay, respawn key, dummy enemies) are included.
