# Plan: Relative Row Numbers for Vim Fighting Game

## Overview

Add vim-style relative row numbers displayed along the left side of the game viewport. Numbers show vertical distance from the player's current row, with "0" at the player's position and increasing numbers above/below.

## Design Decisions

| Decision | Choice |
|----------|--------|
| Row unit | 64 pixels (configurable) - half of sprite size for good granularity |
| Display location | Left side of viewport via CanvasLayer (like vim's gutter) |
| Scrolling | Numbers fixed to viewport, values update as player moves |
| Rendering | Label node pooling (~24 labels) for performance |
| Styling | Vim aesthetic: monospace font, yellow "0", gray relative numbers |

## Architecture

### New Files
```
ui/
  relative_line_numbers/
    relative_line_numbers.tscn    # CanvasLayer scene
    relative_line_numbers.gd      # Control script
```

### Scene Structure
```
RelativeLineNumbers (CanvasLayer, layer=10)
├── GutterBackground (ColorRect) - semi-transparent dark panel
└── NumberContainer (Control)
    └── LineLabel_0..N (Label pool)
```

## Implementation Steps

### Step 1: Create UI Directory and Scene
Create `ui/relative_line_numbers/relative_line_numbers.tscn` with:
- CanvasLayer (layer 10) as root
- ColorRect for gutter background (60px wide, dark semi-transparent)
- Control node to hold label pool

### Step 2: Create Main Script
Create `ui/relative_line_numbers/relative_line_numbers.gd`:
- Configurable exports: `row_height`, `visible_rows`, `gutter_width`, colors
- `_ready()`: Set up gutter, create label pool, find player/camera references
- `_process()`: Update label text values based on player Y position
- Key calculation: `player_row = floor(player.global_position.y / row_height)`
- Relative distance: `world_row - player_row`

### Step 3: Add Player to Group
Modify `player/statemachine.gd`:
- Add `add_to_group("player")` in `_ready()` for easy lookup

### Step 4: Instance in Stage
Modify `stages/vim_dojo_2d_stage.tscn`:
- Add instance of RelativeLineNumbers scene

### Step 5: (Future) Vim Motion Integration
*Not included in this implementation - can be added later*
- API hooks: `get_player_row()`, `get_world_y_for_row()`
- Signal for `5j`/`3k` style row-based movement

## Files to Modify/Create

| File | Action |
|------|--------|
| `ui/relative_line_numbers/relative_line_numbers.tscn` | Create |
| `ui/relative_line_numbers/relative_line_numbers.gd` | Create |
| `player/statemachine.gd` | Modify (add to group) |
| `stages/vim_dojo_2d_stage.tscn` | Modify (add instance) |

## Verification

1. Run the game and verify numbers appear on left side
2. Confirm "0" aligns with player's vertical position
3. Jump/fall and verify numbers update correctly
4. Check numbers above show 1, 2, 3... and below also show 1, 2, 3...
5. Verify no performance issues (check debugger FPS)
6. Test camera movement - numbers should stay on screen
