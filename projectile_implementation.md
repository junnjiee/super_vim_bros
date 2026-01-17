# Ranged Attack Implementation Plan (d0 and d$)

## Overview
Add ranged attacks using vim delete commands:
- `d0` - Fire projectile LEFT
- `d$` - Fire projectile RIGHT
- Projectiles disappear on collision with players (dealing damage) or walls

## Files to Create

### 1. `/player/projectile.gd`
New Area2D script handling:
- Movement in specified direction at 600 px/s
- Collision detection via `body_entered` signal
- Damage application (10 HP, same as melee)
- Self-destruction on hit or max range (800px)
- Owner tracking to avoid self-damage

### 2. `/player/projectile.tscn`
New scene structure:
```
Projectile (Area2D)
├── CollisionShape2D (RectangleShape2D 32x16)
└── ColorRect (visual, 32x16, orange/player-colored)
```
- `collision_layer = 0` (doesn't block anything)
- `collision_mask = 3` (detects players on layer 1, walls on layer 2)

## Files to Modify

### `/player/statemachine.gd`

**Add near line 67:**
```gdscript
const PROJECTILE_SCENE = preload("res://player/projectile.tscn")
```

**Add near line 56 (variables):**
```gdscript
var ranged_cooldown_timer: float = 0.0
@export var ranged_cooldown: float = 0.75
```

**Add in `_physics_process` (near line 114):**
```gdscript
if ranged_cooldown_timer > 0.0:
    ranged_cooldown_timer -= delta
```

**Add in `_input()` inside the `pending_d` check block (after line 641):**
```gdscript
# Ranged attack: d0 (fire left)
if code == KEY_0:
    pending_d = false
    if ranged_cooldown_timer <= 0.0:
        _fire_projectile(Vector2.LEFT)
        ranged_cooldown_timer = ranged_cooldown
    return

# Ranged attack: d$ (fire right)
if code == KEY_4 and event.shift_pressed:
    pending_d = false
    if ranged_cooldown_timer <= 0.0:
        _fire_projectile(Vector2.RIGHT)
        ranged_cooldown_timer = ranged_cooldown
    return
```

**Add new function:**
```gdscript
func _fire_projectile(direction: Vector2) -> void:
    var projectile = PROJECTILE_SCENE.instantiate()
    var spawn_pos = global_position + direction * dash_unit_size
    projectile.initialize(direction, self)
    projectile.global_position = spawn_pos
    get_parent().add_child(projectile)
```

## Collision Behavior
| Collision With | Result |
|----------------|--------|
| Player (layer 1) | Deal 10 damage, destroy projectile |
| Wall/Platform (layer 2) | Destroy projectile (no damage) |
| Insert obstacles (layer 2) | Destroy projectile (blocked) |
| Max range reached | Destroy projectile |

## Input Flow
```
User presses 'd' → pending_d = true, timer starts (0.25s)
User presses '0' → check pending_d → fire LEFT, clear pending_d
User presses '$' → check pending_d → fire RIGHT, clear pending_d
```

Note: Standalone `0` and `$` (without prior `d`) still work as absolute dashes.

## Verification
1. Start the game in single player mode
2. Test `d0`: Press d, then 0 - projectile should fire left
3. Test `d$`: Press d, then Shift+4 - projectile should fire right
4. Verify projectile disappears when hitting the platform
5. Verify projectile damages opponent player on hit
6. Verify cooldown prevents rapid fire (0.75s between shots)
7. Verify standalone `0` and `$` still dash to platform edges
