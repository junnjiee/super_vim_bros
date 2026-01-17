# Plan: Vim-Style Number+Movement Dashing

## Overview

Add vim-style `[count]+movement` commands to allow dashing to specific positions:
- `[count]h` - dash left by count units
- `[count]l` - dash right by count units
- `[count]j` - dash down by count rows (integrates with relative line numbers)
- `[count]k` - dash up by count rows

## Design Decisions

| Decision | Choice |
|----------|--------|
| Unit size | 64 pixels (matches row_height from relative line numbers) |
| Dash physics | Velocity-based with collision detection |
| Dash speed | 800 px/sec (configurable) |
| Max count | 99 (two digits max) |
| Count timeout | 0.25s (matches existing input_buffer_time) |

### Key Behavior (Confirmed)

| Key | Without Count | With Count |
|-----|---------------|------------|
| `H` | Walk left | Dash left |
| `L` | Walk right | Dash right |
| `J` | Nothing | Dash down |
| `K` | Jump | Dash up |

**Gravity**: Suspended during horizontal dash (straight-line movement)

## Implementation

### 1. Add DASH State

```gdscript
enum State {
    IDLE,
    WALK,
    ATTACK,
    HITSTUN,
    DASH,  # NEW
}
```

### 2. Add New Variables

```gdscript
# Count input buffering
var pending_count: String = ""
var pending_count_timer: float = 0.0

# Dash tracking
var dash_target: Vector2 = Vector2.ZERO
var dash_direction: Vector2 = Vector2.ZERO
var dash_remaining_time: float = 0.0

# Configuration
@export var dash_speed: float = 800.0
@export var dash_unit_size: int = 64
```

### 3. Input Handling in `_input()`

Add number key detection (KEY_0 to KEY_9):
- Accumulate digits into `pending_count` (max 2 digits)
- Reset `pending_count_timer` on each digit

Add movement key detection with count:
- If `pending_count` has value and h/l/j/k pressed → initiate dash
- Clear `pending_count` after consuming
- Without count prefix, h/l/k behave as normal (walk/jump)

### 4. Dash State Logic

```gdscript
func _initiate_dash(direction: Vector2, count: int, is_vertical: bool):
    var distance = count * dash_unit_size

    # For vertical: snap to row grid
    if is_vertical:
        var current_row = floor(global_position.y / dash_unit_size)
        var target_row = current_row + (count * int(direction.y))
        dash_target.y = target_row * dash_unit_size
        dash_target.x = global_position.x
    else:
        dash_target = global_position + direction * distance

    dash_direction = direction
    dash_remaining_time = distance / dash_speed
    change_state(State.DASH)

func state_dash(delta):
    dash_remaining_time -= delta

    # Set velocity for collision detection via move_and_slide()
    if dash_direction.y != 0:
        velocity.y = dash_direction.y * dash_speed
        velocity.x = 0
    else:
        velocity.x = dash_direction.x * dash_speed
        velocity.y = 0  # Suspend gravity during horizontal dash

    # End conditions
    if dash_remaining_time <= 0 or is_on_wall():
        velocity = Vector2.ZERO
        change_state(State.IDLE)
```

### 5. Timer Update in `_physics_process()`

```gdscript
# Add count buffer timeout
if pending_count_timer > 0.0:
    pending_count_timer -= delta
    if pending_count_timer <= 0.0:
        pending_count = ""
```

## Files to Modify

| File | Changes |
|------|---------|
| `player/statemachine.gd` | Add DASH state, count buffering, dash logic |

## Verification

1. Run game, type `3h` → player dashes 3 units (192px) left
2. Type `5l` → player dashes 5 units (320px) right
3. Type `4j` → player dashes down 4 rows, aligning with relative line numbers
4. Type `2k` → player dashes up 2 rows
5. Plain `K` still jumps when on floor
6. Plain `H`/`L` still walks normally
7. Dashing into a wall stops early (collision works)
8. Count times out after 0.25s if no movement key pressed
9. Cannot dash during ATTACK or HITSTUN states
