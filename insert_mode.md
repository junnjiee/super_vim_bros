# Insert Mode Obstacle Creation - Implementation Plan

## Overview
Add vim-style insert mode that allows players to create collision obstacles by typing letters. Players enter insert mode with 'i', type letters to spawn grid-aligned blocks, and exit with Esc/Ctrl+C.

## Design Decisions
- **Persistence**: Temporary obstacles with 10-15 second auto-cleanup
- **Limit**: Maximum 8 obstacles per player
- **Overflow**: Queue behavior (oldest obstacle removed when limit exceeded)
- **Movement**: Player locked in place during insert mode
- **Direction**: Obstacles spawn in player's facing direction (left/right)
- **Positioning**: Grid-aligned (64px cells), "pushed" outward with each new letter

## Implementation Steps

### 1. Add INSERT State to State Machine
**File**: `player/statemachine.gd`

- Add `INSERT` to State enum (after DASH)
- Add state variables:
  ```gdscript
  var in_insert_mode := false
  var insert_obstacle_count := 0
  var insert_obstacles: Array = []
  const MAX_INSERT_OBSTACLES = 8
  ```
- Implement state handlers:
  - `enter_state(State.INSERT)`: Play idle animation, add yellow tint (modulate), lock movement, disable hitbox
  - `exit_state(State.INSERT)`: Reset color, cleanup obstacles
  - `state_insert(delta)`: Lock horizontal movement, apply gravity if airborne

### 2. Add Input Handlers
**File**: `player/statemachine.gd` (in `_input()` function)

- **Enter insert mode**: 'i' key from IDLE/WALK states → change_state(State.INSERT)
- **Exit insert mode**: Esc or Ctrl+C → cleanup obstacles, return to IDLE/FALL
- **Letter input**: A-Z keys → create obstacle at cursor position

### 3. Create Obstacle Scene
**New File**: `player/insert_obstacle.tscn`

Scene structure:
- **StaticBody2D** (root, collision_layer=2 for walls)
  - **CollisionShape2D**: RectangleShape2D (64x64)
  - **ColorRect**: Visual block (64x64, semi-transparent, player-colored)
  - **Label**: Display typed letter (centered, 32pt font)

**New File**: `player/insert_obstacle.gd`

- Properties: letter (String), lifetime (10.0s), player_color (Color)
- Auto-cleanup after lifetime using timer
- Setup collision and visuals in _ready()

### 4. Implement Obstacle Spawning Logic
**File**: `player/statemachine.gd`

Add functions:
- `_create_obstacle_at_cursor(letter)`:
  - Check limit (8 max), remove oldest if needed
  - Calculate spawn position: player position + (obstacle_count + 1) * 64px * facing_direction
  - Grid-align position (round to 64px)
  - Call spawn function (local or RPC based on multiplayer mode)

- `_spawn_obstacle_local(pos, letter)`:
  - Instantiate obstacle scene
  - Set position, letter, and player color
  - Add to stage (get_parent())
  - Track in insert_obstacles array

- `_spawn_obstacle_rpc(pos, letter, owner_id)`:
  - RPC wrapper for multiplayer synchronization
  - Calls _spawn_obstacle_local

- `_cleanup_insert_obstacles()`:
  - Queue_free all obstacles in array
  - Clear array and reset counter

### 5. Visual Feedback
**File**: `player/statemachine.gd`

- In INSERT state: Apply yellow modulate to animated_sprite (Color(1.0, 1.0, 0.7))
- On exit: Reset modulate to white (Color(1.0, 1.0, 1.0))
- Obstacles color-coded by player (blue tint for P1, red tint for P2)

### 6. Multiplayer Synchronization (Optional)
**File**: `player/player.tscn`

- Add `in_insert_mode` property to MultiplayerSynchronizer's replication config
- Ensures insert mode state syncs across clients

## Critical Files

### Files to Modify:
- `player/statemachine.gd` - Add INSERT state, input handlers, obstacle spawning logic (~150 lines added)

### Files to Create:
- `player/insert_obstacle.tscn` - Obstacle scene with collision
- `player/insert_obstacle.gd` - Obstacle script with lifetime and visuals

## Verification Plan

### Manual Testing:
1. **Enter/Exit**: Press 'i' → player gets yellow tint, locked in place. Press Esc → returns to normal
2. **Create obstacles**: Type A, B, C → three blocks spawn in facing direction, 64px apart
3. **Grid alignment**: Obstacles snap to 64px grid regardless of player sub-grid position
4. **Direction**: Face left, type letters → obstacles spawn leftward. Face right → rightward
5. **Collision**: Walk into obstacles → player blocked, cannot pass through
6. **Limit**: Type 9 letters → 9th obstacle removes 1st obstacle
7. **Lifetime**: Wait 10-15 seconds → obstacles disappear automatically
8. **State lock**: In insert mode, cannot attack, dash, or move

### Multiplayer Testing (if applicable):
- Player 1 creates blue obstacles, Player 2 creates red obstacles
- Both players can collide with all obstacles
- Obstacles sync correctly across clients

## Technical Notes

- Obstacle preload: `const OBSTACLE_SCENE = preload("res://player/insert_obstacle.tscn")`
- Grid size constant: `dash_unit_size = 64` (already exists)
- Facing direction: `animated_sprite.flip_h` (true = left, false = right)
- Collision layer 2 = "walls" (already configured for platform collision)
