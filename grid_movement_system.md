# 2D Tiling System Implementation Plan

## Overview

Implement a grid-based movement and visual system where:
1. Player moves cell-by-cell (instant snap) rather than continuous movement
2. A subtle visual grid helps players see the cells
3. All vim movements (h/j/k/l) work both with and without counts

## Part 1: Movement System Refactor

### Current Behavior
- `h/l`: Continuous walking movement (WALK state)
- `[count]h/l`: Dash horizontally by count × 64px
- `k`: Jump when grounded
- `[count]j/k`: Dash vertically by count × 64px

### New Behavior
- `h`: Instantly move one cell left (64px)
- `l`: Instantly move one cell right (64px)
- `j`: Instantly move one cell down (64px)
- `k`: Instantly move one cell up (64px)
- `[count]h/j/k/l`: Instantly move count cells in that direction

### Files to Modify

#### `player/statemachine.gd`

**Changes required:**

1. **Remove WALK state usage** - Replace continuous walking with instant grid movement

2. **Refactor `_input()` function** to handle all h/j/k/l as grid movements:
   ```
   h/l/j/k pressed:
     - If pending_count exists: move count cells
     - Otherwise: move 1 cell
     - Snap position to grid
   ```

3. **New movement function** - Replace `_initiate_dash()` with instant snap:
   ```gdscript
   func _move_grid(direction: Vector2, count: int = 1):
       var distance = count * dash_unit_size

       # Calculate target position (snapped to grid)
       var target = global_position + direction * distance
       target.x = round(target.x / dash_unit_size) * dash_unit_size
       target.y = round(target.y / dash_unit_size) * dash_unit_size

       # Instant move (no animation/tweening)
       global_position = target
   ```

4. **Remove jump behavior from K key** - k now moves up one cell
   - Remove: `if is_on_floor() and Input.is_key_pressed(KEY_K): velocity.y = -jump_force`
   - Vertical movement handled by grid system

5. **Simplify state machine**:
   - IDLE: Default state, waiting for input
   - ATTACK: Attack animation (keep as-is)
   - HITSTUN: Getting hit (keep as-is)
   - Remove or repurpose: WALK, DASH states

6. **Handle key press vs key hold**:
   - Grid movement triggers on key press only (not hold)
   - Use `_input()` for movement instead of `_physics_process()`

**Key sections to modify**:
- Lines 80-81: Remove jump on K key
- Lines 150-162: Remove walk state transition in `state_idle()`
- Lines 164-184: Remove or simplify `state_walk()`
- Lines 198-213: Remove `state_dash()`
- Lines 217-224: Remove `get_input_direction()` (no longer needed)
- Lines 227-299: Refactor `_input()` to handle grid movement
- Lines 301-315: Replace `_initiate_dash()` with `_move_grid()`

## Part 2: Grid Overlay

### Files to Create

#### `ui/grid_overlay/grid_overlay.gd`

A Node2D script that renders grid lines in world space using Line2D nodes:

```
grid_overlay.gd
├── Configuration (exported)
│   ├── cell_size: int = 64 (matches dash_unit_size)
│   ├── line_color: Color = Color(0.3, 0.3, 0.3, 0.25)
│   ├── line_width: float = 1.0
│
├── References
│   ├── camera: Camera2D
│   ├── horizontal_lines: Array[Line2D]
│   ├── vertical_lines: Array[Line2D]
│
├── Methods
│   ├── _ready() → Create line pools
│   ├── _process() → Update line positions based on camera viewport
│   └── _update_grid_lines() → Position lines to cover visible area
```

**Implementation details**:
- Use ~50 horizontal + ~50 vertical Line2D nodes (pooled)
- Calculate visible bounds from camera position and viewport size
- Snap line positions to grid boundaries (multiples of 64px)
- Z-index set behind player/stage elements

#### `ui/grid_overlay/grid_overlay.tscn`

Scene file instantiating the grid overlay as a Node2D.

### Files to Modify

#### `stages/vim_dojo_2d_stage.tscn`

Add the grid overlay as a child node:
- Instance `grid_overlay.tscn`
- Position at origin (0, 0)
- Set z-index to render behind gameplay elements

## Implementation Steps

1. **Movement refactor** (statemachine.gd):
   - Implement `_move_grid()` function for instant cell movement
   - Refactor `_input()` to use grid movement for h/j/k/l
   - Remove continuous walk logic and WALK state
   - Remove DASH state (instant movement doesn't need it)
   - Remove jump from K key

2. **Grid overlay**:
   - Create `ui/grid_overlay/` directory
   - Implement `grid_overlay.gd` with Line2D pooling
   - Create `grid_overlay.tscn` scene
   - Add grid overlay instance to stage

3. **Testing and polish**

## Visual Specifications

| Property | Value |
|----------|-------|
| Cell size | 64x64 pixels |
| Line color | `Color(0.3, 0.3, 0.3, 0.25)` - subtle dark gray |
| Line width | 1.0 pixel |
| Z-index | -10 (behind stage and player) |

## Verification

1. **Movement**:
   - Press `l` once → player snaps exactly 64px right
   - Press `h` once → player snaps exactly 64px left
   - Press `j` once → player snaps exactly 64px down
   - Press `k` once → player snaps exactly 64px up
   - Press `5l` → player snaps exactly 320px (5 cells) right
   - Holding keys should NOT cause continuous movement
   - Player position should always be aligned to 64px grid

2. **Grid overlay**:
   - Grid lines visible but subtle
   - Grid stays aligned with camera
   - Each cell is exactly 64x64px
   - Player movement corresponds to visible cells
