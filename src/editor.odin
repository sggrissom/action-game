package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

PANEL_WIDTH :: 260

Editor_Tool :: enum {
	None,
	Tile,
	Spike,
	Enemy,
	Falling_Log,
	Checkpoint,
	Power_Up,
	Level,
	Level_Resize,
}

Dir8 :: enum {
	NE,
	SE,
	SW,
	NW,
	N,
	E,
	S,
	W,
}

Resize_Cursor := [Dir8]rl.MouseCursor {
	.N  = .RESIZE_NS,
	.NE = .RESIZE_NESW,
	.E  = .RESIZE_EW,
	.SE = .RESIZE_NWSE,
	.S  = .RESIZE_NS,
	.SW = .RESIZE_NESW,
	.W  = .RESIZE_EW,
	.NW = .RESIZE_NWSE,
}

Editor_State :: struct {
	tool:              Editor_Tool,
	previous_tool:     Editor_Tool,
	area_begin:        Vec2i,
	area_end:          Vec2i,
	resize_level_dir:  Dir8,
	resize_rect:       Rect,
	resize_start_pos:  Vec2,
	cmd_arena:         virtual.Arena,
	cmd_allocator:     mem.Allocator,
	command_history:   [dynamic]Cmd_Entry,
	undo_count:        int,
	spike_orientation: Direction,
	enemy_type:        Enemy_Type,
	tileset:           Tileset,
	is_dragging:       bool,
	drag_start:        Vec2,
	drag_end:          Vec2,
	deleted_levels:    [dynamic]Level,
}

Cmd :: union {
	Cmd_Tiles_Insert,
	Cmd_Tiles_Remove,
	Cmd_Spikes_Insert,
	Cmd_Spikes_Remove,
	Cmd_Enemies_Insert,
	Cmd_Enemies_Remove,
	Cmd_Falling_Logs_Insert,
	Cmd_Falling_Logs_Remove,
	Cmd_Checkpoints_Insert,
	Cmd_Checkpoints_Remove,
	Cmd_Power_Ups_Insert,
	Cmd_Power_Ups_Remove,
	Cmd_Level_Move,
	Cmd_Level_New,
	Cmd_Level_Delete,
	Cmd_Level_Restore,
	Cmd_Level_Resize,
}

Cmd_Tiles_Insert :: struct {
	coords:         []Vec2i,
	spikes_removed: []Spike,
}

Cmd_Tiles_Remove :: struct {
	coords:         []Vec2i,
	spikes_removed: []Spike,
}

Cmd_Spikes_Insert :: struct {
	spikes:        []Spike,
	tiles_removed: []Vec2i,
}

Cmd_Spikes_Remove :: struct {
	spikes:        []Spike,
	tiles_removed: []Vec2i,
}

Cmd_Enemies_Insert :: struct {
	spawns: []Enemy_Spawn,
}

Cmd_Enemies_Remove :: struct {
	spawns: []Enemy_Spawn,
}

Cmd_Falling_Logs_Insert :: struct {
	spawns: []Falling_Log_Spawn,
}

Cmd_Falling_Logs_Remove :: struct {
	spawns: []Falling_Log_Spawn,
}

Cmd_Checkpoints_Insert :: struct {
	checkpoints: []Checkpoint,
}

Cmd_Checkpoints_Remove :: struct {
	checkpoints: []Checkpoint,
}

Cmd_Power_Ups_Insert :: struct {
	power_ups: []Power_Up,
}

Cmd_Power_Ups_Remove :: struct {
	power_ups: []Power_Up,
}

Cmd_Level_Move :: struct {
	level_id: u32,
	old_pos:  Vec2,
	new_pos:  Vec2,
}

Cmd_Level_New :: struct {
	pos:      Vec2,
	size:     Vec2,
	level_id: u32,
}

Cmd_Level_Delete :: struct {
	level_id: u32,
}

Cmd_Level_Restore :: struct {
	level_id: u32,
}

Cmd_Level_Resize :: struct {
	level_id:       u32,
	old_pos:        Vec2,
	old_size:       Vec2,
	new_pos:        Vec2,
	new_size:       Vec2,
	removed_tiles:  []Tile,
	removed_spikes: []Spike,
}

Cmd_Entry :: struct {
	forward: Cmd,
	inverse: Cmd,
}

// Dir8 -> Vec2i mapping
Dir8_Coords := [Dir8]Vec2i {
	.NE = Vec2i{1, -1},
	.SE = Vec2i{1, 1},
	.SW = Vec2i{-1, 1},
	.NW = Vec2i{-1, -1},
	.N  = Vec2i{0, -1},
	.E  = Vec2i{1, 0},
	.S  = Vec2i{0, 1},
	.W  = Vec2i{-1, 0},
}

Tile_Neighbors :: bit_set[Dir8]
TILE_NEIGHBORS_ALL: Tile_Neighbors : {.N, .E, .S, .W, .NE, .SE, .SW, .NW}

Tile_Flip :: enum {
	None,
	X,
	Y,
	Both,
}

Rule_Flags :: enum {
	Match_Exact,
	Terminate,
}

Tileset_Rule :: struct {
	src:           Vec2,
	neighbors:     Tile_Neighbors,
	not_neighbors: Tile_Neighbors,
	flip:          Tile_Flip,
	flags:         bit_set[Rule_Flags],
}

Tileset :: struct {
	texture: rl.Texture2D,
	rules:   []Tileset_Rule,
}

@(private = "file")
es: Editor_State

editor_init :: proc() {
	if err := virtual.arena_init_growing(&es.cmd_arena); err != nil {
		log.panicf("Failed to init editor arena: %s\n", err)
	}
	es.cmd_allocator = virtual.arena_allocator(&es.cmd_arena)
	es.command_history = make([dynamic]Cmd_Entry, es.cmd_allocator)
	es.tileset = make_tileset()
}

calculate_resize :: proc(
	level: ^Level,
	world_pos: Vec2,
	start_pos: Vec2,
	dir: Dir8,
) -> (
	new_pos: Vec2,
	new_size: Vec2,
) {
	min_width := math.ceil(f32(RENDER_WIDTH) / TILE_SIZE) * TILE_SIZE
	min_height := math.ceil(f32(RENDER_HEIGHT) / TILE_SIZE) * TILE_SIZE

	new_pos = level.pos
	new_size = level.size

	delta := world_pos - start_pos
	snapped_delta := linalg.round(delta / TILE_SIZE) * TILE_SIZE

	switch dir {
	case .N:
		height_delta := -snapped_delta.y
		new_size.y = max(level.size.y + height_delta, min_height)
		new_pos.y = level.pos.y - (new_size.y - level.size.y)
	case .S:
		new_size.y = max(level.size.y + snapped_delta.y, min_height)
	case .E:
		new_size.x = max(level.size.x + snapped_delta.x, min_width)
	case .W:
		width_delta := -snapped_delta.x
		new_size.x = max(level.size.x + width_delta, min_width)
		new_pos.x = level.pos.x - (new_size.x - level.size.x)
	case .NE:
		height_delta := -snapped_delta.y
		new_size = {
			max(level.size.x + snapped_delta.x, min_width),
			max(level.size.y + height_delta, min_height),
		}
		new_pos.y = level.pos.y - (new_size.y - level.size.y)
	case .NW:
		height_delta := -snapped_delta.y
		width_delta := -snapped_delta.x
		new_size = {
			max(level.size.x + width_delta, min_width),
			max(level.size.y + height_delta, min_height),
		}
		new_pos = {
			level.pos.x - (new_size.x - level.size.x),
			level.pos.y - (new_size.y - level.size.y),
		}
	case .SE:
		new_size = {
			max(level.size.x + snapped_delta.x, min_width),
			max(level.size.y + snapped_delta.y, min_height),
		}
	case .SW:
		width_delta := -snapped_delta.x
		new_size = {
			max(level.size.x + width_delta, min_width),
			max(level.size.y + snapped_delta.y, min_height),
		}
		new_pos.x = level.pos.x - (new_size.x - level.size.x)
	}

	return new_pos, new_size
}

calculate_resize_rect :: proc(level_rect: Rect, dir: Dir8) -> Rect {
	result: Rect
	thickness :: 12
	half_t :: thickness / 2

	switch dir {
	case .N:
		result = {level_rect.x, level_rect.y - half_t, level_rect.width, thickness}
	case .S:
		result = {
			level_rect.x,
			level_rect.y + level_rect.height - half_t,
			level_rect.width,
			thickness,
		}
	case .E:
		result = {
			level_rect.x + level_rect.width - half_t,
			level_rect.y,
			thickness,
			level_rect.height,
		}
	case .W:
		result = {level_rect.x - half_t, level_rect.y, thickness, level_rect.height}
	case .NW:
		result = {level_rect.x - half_t, level_rect.y - half_t, thickness, thickness}
	case .NE:
		result = {
			level_rect.x + level_rect.width - half_t,
			level_rect.y - half_t,
			thickness,
			thickness,
		}
	case .SE:
		result = {
			level_rect.x + level_rect.width - half_t,
			level_rect.y + level_rect.height - half_t,
			thickness,
			thickness,
		}
	case .SW:
		result = {
			level_rect.x - half_t,
			level_rect.y + level_rect.height - half_t,
			thickness,
			thickness,
		}
	}

	return result
}

editor_update :: proc(gs: ^Game_State, dt: f32) {
	mouse_pos := rl.GetMousePosition()

	if mouse_pos.x < PANEL_WIDTH {
		return
	}

	context.allocator = es.cmd_allocator

	rl.SetMouseCursor(.DEFAULT)

	scroll := rl.GetMouseWheelMove()
	if rl.IsKeyPressed(.LEFT_BRACKET) {
		scroll -= 1
	}
	if rl.IsKeyPressed(.RIGHT_BRACKET) {
		scroll += 1
	}
	if scroll != 0 && es.tool != .Level_Resize {
		mouse_world_pos := rl.GetScreenToWorld2D(mouse_pos, gs.camera)

		gs.camera.zoom = clamp(gs.camera.zoom + scroll * 0.25, 0.25, 8)

		mouse_world_pos_new := rl.GetScreenToWorld2D(mouse_pos, gs.camera)

		gs.camera.target += (mouse_world_pos - mouse_world_pos_new)

		es.resize_rect = {}
	}

	if es.tool == .Level || es.tool == .Level_Resize {
		if gs.camera.zoom >= 1 {
			es.tool = es.previous_tool
		}
	} else {
		if rl.IsKeyPressed(.T) {
			es.tool = .Tile
		}

		if rl.IsKeyPressed(.S) {
			es.tool = .Spike
		}

		if rl.IsKeyPressed(.E) {
			es.tool = .Enemy
		}

		if rl.IsKeyPressed(.L) {
			es.tool = .Falling_Log
		}

		if rl.IsKeyPressed(.C) {
			es.tool = .Checkpoint
		}

		if rl.IsKeyPressed(.P) {
			es.tool = .Power_Up
		}

		if rl.IsKeyPressed(.F) {
			es.spike_orientation += Direction(1)
			if int(es.spike_orientation) > 3 {
				es.spike_orientation = Direction(0)
			}
		}

		if rl.IsKeyPressed(.R) {
			es.enemy_type += Enemy_Type(1)
			if int(es.enemy_type) > int(Enemy_Type.Jumper) {
				es.enemy_type = Enemy_Type(0)
			}
		}

		if rl.IsKeyPressed(.Z) && (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) {
			editor_undo()
		}

		if rl.IsKeyPressed(.Y) && (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) {
			editor_redo()
		}

		es.previous_tool = es.tool
		if gs.camera.zoom < 1 {
			es.tool = .Level
		}
	}

	{
		mouse_delta: Vec2

		if rl.IsKeyDown(.LEFT) {
			mouse_delta.x += 300 * dt
		}

		if rl.IsKeyDown(.RIGHT) {
			mouse_delta.x -= 300 * dt
		}

		if rl.IsKeyDown(.UP) {
			mouse_delta.y += 300 * dt
		}

		if rl.IsKeyDown(.DOWN) {
			mouse_delta.y -= 300 * dt
		}

		if rl.IsMouseButtonDown(.MIDDLE) {
			mouse_delta = rl.GetMouseDelta()
		}

		gs.camera.target -= mouse_delta / gs.camera.zoom
	}

	rel_pos := rl.GetMousePosition() + gs.camera.target * gs.camera.zoom
	rel_pos /= gs.camera.zoom
	coords := coords_from_pos(rel_pos)

	switch es.tool {
	case .None:
	case .Tile:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
		}

		if rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT) {
			es.area_end = coords
		}

		place := rl.IsMouseButtonReleased(.LEFT)
		remove := rl.IsMouseButtonReleased(.RIGHT)

		if place {
			editor_command_dispatch(Cmd_Tiles_Insert)
		} else if remove {
			editor_command_dispatch(Cmd_Tiles_Remove)
		}
	case .Spike:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
			es.area_end = coords
		}

		if rl.IsMouseButtonDown(.LEFT) {
			switch es.spike_orientation {
			case .Up, .Down:
				es.area_end.x = coords.x
			case .Left, .Right:
				es.area_end.y = coords.y
			}
		} else if rl.IsMouseButtonDown(.RIGHT) {
			es.area_end = coords
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			editor_command_dispatch(Cmd_Spikes_Insert)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			editor_command_dispatch(Cmd_Spikes_Remove)
		}

	case .Enemy:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
			es.area_end = coords
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			editor_command_dispatch(Cmd_Enemies_Insert)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			editor_command_dispatch(Cmd_Enemies_Remove)
		}

	case .Falling_Log:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
			es.area_end = coords
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			editor_command_dispatch(Cmd_Falling_Logs_Insert)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			editor_command_dispatch(Cmd_Falling_Logs_Remove)
		}

	case .Checkpoint:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
			es.area_end = coords
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			editor_command_dispatch(Cmd_Checkpoints_Insert)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			editor_command_dispatch(Cmd_Checkpoints_Remove)
		}

	case .Power_Up:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
			es.area_end = coords
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			editor_command_dispatch(Cmd_Power_Ups_Insert)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			editor_command_dispatch(Cmd_Power_Ups_Remove)
		}

	case .Level:
		if es.is_dragging {
			es.drag_end = rl.GetScreenToWorld2D(mouse_pos, gs.camera)
			es.drag_end = linalg.round(es.drag_end / TILE_SIZE) * TILE_SIZE

			if rl.IsMouseButtonReleased(.LEFT) {
				es.is_dragging = false

				start_coords := coords_from_pos(es.drag_start)
				end_coords := coords_from_pos(es.drag_end)

				if start_coords != end_coords {
					editor_command_dispatch(Cmd_Level_Move)
				}
			}
		} else {
			for level in gs.levels {
				level_rect := rect_from_pos_size(level.pos - gs.camera.target, level.size)
				level_rect = rect_scale_all(level_rect, gs.camera.zoom)
				if rl.CheckCollisionPointRec(mouse_pos, level_rect) {
					if rl.IsMouseButtonPressed(.LEFT) {
						level_load(gs, level.id, 0)
					} else if rl.IsMouseButtonDown(.LEFT) {
						es.is_dragging = true
						es.drag_start = rl.GetScreenToWorld2D(mouse_pos, gs.camera)
						es.drag_start = linalg.round(es.drag_start / TILE_SIZE) * TILE_SIZE
					}
				}
			}
		}

		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
		}

		if rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT) {
			es.area_end = coords
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			editor_command_dispatch(Cmd_Level_New)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
			editor_remove_level(gs, rect)
		}

		if rl.IsKeyPressed(.DELETE) {
			if len(gs.levels) > 1 {
				editor_command_dispatch(Cmd_Level_Delete)
			}
		}

		es.resize_rect = {}

		level_rect := rect_from_pos_size(gs.level.pos - gs.camera.target, gs.level.size)
		level_rect = rect_scale_all(level_rect, gs.camera.zoom)

		for dir in Dir8 {
			resize_rect := calculate_resize_rect(level_rect, dir)
			if rl.CheckCollisionPointRec(mouse_pos, resize_rect) {
				rl.SetMouseCursor(Resize_Cursor[dir])
				es.resize_rect = resize_rect

				if rl.IsMouseButtonPressed(.LEFT) {
					es.resize_level_dir = dir
					es.tool = .Level_Resize
					es.area_begin = coords_from_pos(gs.level.pos)
					es.resize_start_pos = rl.GetScreenToWorld2D(mouse_pos, gs.camera)
				}

				break
			}
		}
	case .Level_Resize:
		if rl.IsMouseButtonReleased(.LEFT) {
			editor_command_dispatch(Cmd_Level_Resize)
			es.tool = .Level
		}
	}
}

editor_draw :: proc(gs: ^Game_State) {
	// Draw Editor UI
	rl.DrawTextEx(
		gs.font_48,
		fmt.ctprintf(
			"Tool: %s\nHistory: %d/%d\nOrientation: %v\nCamera.Zoom: %v\nCamera.Target: %v", // changed
			es.tool,
			len(es.command_history) - es.undo_count, // new
			len(es.command_history), // new
			es.spike_orientation, // new
			gs.camera.zoom,
			gs.camera.target,
		),
		{8, 8},
		24,
		0,
		rl.WHITE,
	)

	place := rl.IsMouseButtonDown(.LEFT)
	remove := rl.IsMouseButtonDown(.RIGHT)

	if (place || remove) {
		rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
		rect = rect_pos_add(rect, -gs.camera.target)

		rect = rect_scale_all(rect, gs.camera.zoom)

		if es.tool == .Level || es.tool == .Level_Resize {
			if !es.is_dragging {
				one_screen_rect := rect
				one_screen_rect.width =
					math.ceil(f32(RENDER_WIDTH) / TILE_SIZE) * TILE_SIZE * gs.camera.zoom
				one_screen_rect.height =
					math.ceil(f32(RENDER_HEIGHT) / TILE_SIZE) * TILE_SIZE * gs.camera.zoom
				rl.DrawRectangleLinesEx(one_screen_rect, 1, rl.DARKGRAY)
			}
		} else {
			rl.DrawRectangleLinesEx(rect, 4, place ? rl.WHITE : rl.RED)
		}
	}

	rl.BeginMode2D(gs.camera)

	for l in gs.levels {
		if l.id == gs.level.id do continue

		for tile in l.tiles {
			rl.DrawRectangleV(tile.pos, TILE_SIZE, rl.BROWN)
		}
	}

	if es.is_dragging {
		delta := es.drag_end - es.drag_start
		rl.DrawRectangleLinesEx(
			rect_from_pos_size(gs.level.pos + delta, gs.level.size),
			2,
			rl.GRAY,
		)
	}

	rl.EndMode2D()

	for l in gs.levels {
		level_rect := Rect{l.pos.x, l.pos.y, l.size.x, l.size.y}
		level_rect = rect_pos_add(level_rect, -gs.camera.target)
		level_rect = rect_scale_all(level_rect, gs.camera.zoom)

		color := l.id == gs.level.id ? rl.WHITE : rl.GRAY
		thickness := f32(1)

		if es.tool == .Level {
			thickness = 4
			text := l.name == "" ? fmt.ctprintf("level_%d", l.id) : fmt.ctprintf("%s", l.name)
			text_size := rl.MeasureTextEx(gs.font_48, text, 48, 0)
			text_pos :=
				Vec2{level_rect.x, level_rect.y} +
				({level_rect.width, level_rect.height} - text_size) / 2
			rl.DrawTextEx(gs.font_48, text, text_pos, 48, 0, {255, 255, 255, 128})
		}

		rl.DrawRectangleLinesEx(level_rect, thickness, color)
	}

	if es.tool == .Level_Resize {
		world_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), gs.camera)

		preview_pos, preview_size := calculate_resize(
			gs.level,
			world_pos,
			es.resize_start_pos,
			es.resize_level_dir,
		)

		preview_rect := rect_from_pos_size(preview_pos - gs.camera.target, preview_size)
		preview_rect = rect_scale_all(preview_rect, gs.camera.zoom)

		rl.DrawRectangleLinesEx(preview_rect, 2, rl.WHITE)
	}

	rl.DrawRectangleRec(es.resize_rect, rl.YELLOW)

	coords := coords_from_pos(rl.GetScreenToWorld2D(rl.GetMousePosition(), gs.camera))

	rl.BeginMode2D(gs.camera)

	for dir in Dir8_Coords {
		pos := pos_from_coords(coords + dir)
		if is_tile_at(coords + dir, gs.level) {
			rl.DrawRectangleV(pos, 16, {0, 200, 0, 128})
		} else {
			rl.DrawRectangleV(pos, 16, {200, 0, 0, 128})
		}
	}

	// Draw enemy spawns
	for spawn in gs.level.enemy_spawns {
		rl.DrawRectangleV(spawn.pos, 16, rl.RED)
	}

	// Draw falling log spawns (use runtime logs for accurate rope height)
	for falling_log in gs.falling_logs {
		rl.DrawRectangleRec(falling_log.collider, {139, 90, 43, 180}) // Brown with transparency
		// Draw rope to ceiling
		center_x := falling_log.collider.x + falling_log.collider.width / 2
		rl.DrawLineEx(
			{center_x, falling_log.collider.y},
			{center_x, falling_log.collider.y - falling_log.rope_height},
			2,
			{139, 90, 43, 180},
		)
	}

	// Draw checkpoints
	for checkpoint in gs.level.checkpoints {
		rl.DrawRectangleLinesEx(rect_from_pos_size(checkpoint.pos, 32), 2, rl.ORANGE)
	}

	// Draw powerups
	for pu in gs.level.power_ups {
		rl.DrawCircleV(pu.position, 8, rl.BLUE)
		rl.DrawCircleLinesV(pu.position, 8, rl.WHITE)
	}

	rl.EndMode2D()

	editor_panel(PANEL_WIDTH)

	editor_panel_text(fmt.ctprintf("Level ID: %d", gs.level.id))
	editor_panel_text(fmt.ctprintf("Tool: %s", es.tool))
	editor_panel_text(
		fmt.ctprintf(
			"History: %d/%d",
			len(es.command_history) - es.undo_count,
			len(es.command_history),
		),
	)
	editor_panel_text(fmt.ctprintf("Orientation: %v", es.spike_orientation))
	editor_panel_text(fmt.ctprintf("Enemy Type: %v", es.enemy_type))
	editor_panel_text(fmt.ctprintf("Camera Zoom: %v", gs.camera.zoom))

	level_pos_tiles := coords_from_pos(gs.level.pos)
	editor_panel_text(fmt.ctprintf("Pos: %d, %d", level_pos_tiles.x, level_pos_tiles.y))

	level_size_tiles := coords_from_pos(gs.level.size)
	editor_panel_text(fmt.ctprintf("Size: %d, %d", level_size_tiles.x, level_size_tiles.y))
}

is_tile_at_pos :: proc(pos: Vec2, l: ^Level) -> bool {
	for tile in l.tiles {
		rect := Rect{tile.pos.x, tile.pos.y, TILE_SIZE, TILE_SIZE}
		if rl.CheckCollisionPointRec(pos, rect) {
			return true
		}
	}
	return false
}

is_tile_at_coords :: proc(coords: Vec2i, l: ^Level) -> bool {
	return is_tile_at(pos_from_coords(coords), l)
}

is_spike_at_pos :: proc(pos: Vec2, l: ^Level) -> bool {
	for spike in l.spikes {
		if rl.CheckCollisionPointRec(pos, spike.collider) {
			return true
		}
	}
	return false
}

is_spike_at_coords :: proc(coords: Vec2i, l: ^Level) -> bool {
	return is_spike_at(pos_from_coords(coords), l)
}

is_tile_at :: proc {
	is_tile_at_pos,
	is_tile_at_coords,
}

is_spike_at :: proc {
	is_spike_at_pos,
	is_spike_at_coords,
}

editor_tile_insert :: proc(coords: Vec2i, l: ^Level) {
	if !is_tile_at(coords, l) {
		append(&l.tiles, Tile{pos = pos_from_coords(coords)})
	}
}

editor_tile_index :: proc(coords: Vec2i, l: ^Level) -> (index: int, ok: bool) {
	for tile, i in l.tiles {
		if coords_from_pos(tile.pos) == coords {
			return i, true
		}
	}
	return -1, false
}

editor_tile_remove :: proc(coords: Vec2i, l: ^Level) {
	if index, ok := editor_tile_index(coords, l); ok {
		ordered_remove(&l.tiles, index)
	}
}

editor_spike_insert :: proc(spike: Spike, l: ^Level) {
	append(&l.spikes, spike)
}

editor_spike_index :: proc(coords: Vec2i, l: ^Level) -> (index: int, ok: bool) {
	for spike, i in l.spikes {
		pos := Vec2{spike.collider.x, spike.collider.y}
		if coords_from_pos(pos) == coords {
			return i, true
		}
	}
	return -1, false
}

editor_spike_remove :: proc(spike: Spike, l: ^Level) {
	if index, ok := slice.linear_search(l.spikes[:], spike); ok {
		unordered_remove(&l.spikes, index)
	}
}

editor_enemy_insert :: proc(spawn: Enemy_Spawn, l: ^Level) {
	append(&l.enemy_spawns, spawn)
}

editor_enemy_remove :: proc(spawn: Enemy_Spawn, l: ^Level) {
	for s, i in l.enemy_spawns {
		if s.pos == spawn.pos && s.type == spawn.type {
			unordered_remove(&l.enemy_spawns, i)
			return
		}
	}
}

is_area_tiled :: proc(begin: Vec2i, end: Vec2i, l: ^Level) -> bool {
	for y in 0 ..< end.y - begin.y {
		for x in 0 ..< end.x - begin.x {
			if !is_tile_at(begin + {x, y}, l) {
				return false
			}
		}
	}
	return true
}

editor_remove_level :: proc(gs: ^Game_State, rect: Rect) {
}

rect_from_coords_any_orientation :: proc(a, b: Vec2i) -> Rect {
	top := f32(min(a.y, b.y)) * TILE_SIZE
	left := f32(min(a.x, b.x)) * TILE_SIZE
	bottom := f32(max(a.y, b.y)) * TILE_SIZE
	right := f32(max(a.x, b.x)) * TILE_SIZE

	return Rect{left, top, right - left + TILE_SIZE, bottom - top + TILE_SIZE}
}

get_next_level_id :: proc() -> u32 {
	id := u32(1)
	for l in es.deleted_levels {
		if l.id > id {
			id = l.id
		}
	}

	for l in gs.levels {
		if l.id > id {
			id = l.id
		}
	}

	return id + 1
}

editor_command_construct :: proc(cmd_type: typeid) -> (cmd: Cmd_Entry, ok: bool) {
	switch cmd_type {
	case Cmd_Tiles_Insert:
		area_coords := coords_from_area(es.area_begin, es.area_end)

		// No tiles inside level bounds
		if len(area_coords) == 0 {
			return
		}

		spikes := spikes_from_area(es.area_begin, es.area_end, gs.level)

		forward := Cmd_Tiles_Insert {
			coords         = area_coords,
			spikes_removed = spikes,
		}

		air := make([dynamic]Vec2i)

		for coords in area_coords {
			if !is_tile_at(coords, gs.level) {
				append(&air, coords)
			}
		}

		inverse := Cmd_Tiles_Remove {
			coords         = air[:],
			spikes_removed = spikes,
		}

		return {forward, inverse}, true
	case Cmd_Tiles_Remove:
		area_coords := coords_from_area(es.area_begin, es.area_end)

		forward := Cmd_Tiles_Remove {
			coords = area_coords,
		}

		solid := make([dynamic]Vec2i)

		for coords in area_coords {
			if is_tile_at(coords, gs.level) {
				append(&solid, coords)
			}
		}

		// No tiles removed
		if len(solid) == 0 {
			return
		}

		spikes := spikes_from_area(es.area_begin, es.area_end, gs.level)

		inverse := Cmd_Tiles_Insert {
			coords         = solid[:],
			spikes_removed = spikes,
		}

		return {forward, inverse}, true
	case Cmd_Spikes_Insert:
		rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
		rect = rect_pos_add(rect, -gs.level.pos)
		overlap := rl.GetCollisionRec(rect, rect_from_pos_size(0, gs.level.size))

		// Outside level, do nothing
		if overlap != rect {
			return
		}

		// Overlapping other spikes, do nothing
		for spike in gs.level.spikes {
			if rl.CheckCollisionRecs(spike.collider, rect) {
				return
			}
		}

		spike := Spike {
			collider = rect,
			facing   = es.spike_orientation,
		}

		switch spike.facing {
		case .Up:
			spike.collider.y += SPIKE_DIFF
			spike.collider.height = SPIKE_DEPTH
		case .Right:
			spike.collider.width = SPIKE_DEPTH
		case .Down:
			spike.collider.height = SPIKE_DEPTH
		case .Left:
			spike.collider.width = SPIKE_DEPTH
			spike.collider.x += SPIKE_DIFF
		}

		area_coords := coords_from_area(es.area_begin, es.area_end)

		tiles_removed := make([dynamic]Vec2i)

		for coords in area_coords {
			if is_tile_at(coords, gs.level) {
				append(&tiles_removed, coords)
			}
		}

		spikes := make([]Spike, 1)
		spikes[0] = spike
		forward := Cmd_Spikes_Insert {
			spikes        = spikes,
			tiles_removed = tiles_removed[:],
		}

		inverse := Cmd_Spikes_Remove {
			spikes        = spikes,
			tiles_removed = tiles_removed[:],
		}

		return {forward, inverse}, true
	case Cmd_Spikes_Remove:
		spikes := spikes_from_area(es.area_begin, es.area_end, gs.level)

		if len(spikes) == 0 do return

		forward := Cmd_Spikes_Remove {
			spikes = spikes,
		}

		inverse := Cmd_Spikes_Insert {
			spikes = spikes,
		}

		return {forward, inverse}, true
	case Cmd_Enemies_Insert:
		pos := pos_from_coords(es.area_begin) + gs.level.pos

		// Check if outside level bounds
		if !rl.CheckCollisionPointRec(pos, rect_from_pos_size(gs.level.pos, gs.level.size)) {
			return
		}

		// Check if enemy already exists at this position
		for spawn in gs.level.enemy_spawns {
			if spawn.pos == pos {
				return
			}
		}

		spawns := make([]Enemy_Spawn, 1)
		spawns[0] = Enemy_Spawn{type = es.enemy_type, pos = pos}

		forward := Cmd_Enemies_Insert{spawns = spawns}
		inverse := Cmd_Enemies_Remove{spawns = spawns}

		return {forward, inverse}, true
	case Cmd_Enemies_Remove:
		pos := pos_from_coords(es.area_begin) + gs.level.pos

		// Find enemy at this position
		for spawn in gs.level.enemy_spawns {
			if spawn.pos == pos {
				spawns := make([]Enemy_Spawn, 1)
				spawns[0] = spawn

				forward := Cmd_Enemies_Remove{spawns = spawns}
				inverse := Cmd_Enemies_Insert{spawns = spawns}

				return {forward, inverse}, true
			}
		}

		return
	case Cmd_Falling_Logs_Insert:
		world_pos := pos_from_coords(es.area_begin)
		// Convert to level-relative coordinates
		rel_pos := world_pos - gs.level.pos

		// Check if outside level bounds
		level_rect := rect_from_pos_size(0, gs.level.size)
		spawn_rect := Rect{rel_pos.x, rel_pos.y, FALLING_LOG_WIDTH, FALLING_LOG_HEIGHT}
		if !rl.CheckCollisionRecs(spawn_rect, level_rect) {
			return
		}

		// Check if log already exists at this position
		for spawn in gs.level.falling_log_spawns {
			if spawn.rect.x == spawn_rect.x && spawn.rect.y == spawn_rect.y {
				return
			}
		}

		spawns := make([]Falling_Log_Spawn, 1)
		spawns[0] = Falling_Log_Spawn{rect = spawn_rect}

		forward := Cmd_Falling_Logs_Insert{spawns = spawns}
		inverse := Cmd_Falling_Logs_Remove{spawns = spawns}

		return {forward, inverse}, true
	case Cmd_Falling_Logs_Remove:
		world_pos := pos_from_coords(es.area_begin)
		rel_pos := world_pos - gs.level.pos

		// Find log at this position
		for spawn in gs.level.falling_log_spawns {
			if rl.CheckCollisionPointRec(rel_pos, spawn.rect) {
				spawns := make([]Falling_Log_Spawn, 1)
				spawns[0] = spawn

				forward := Cmd_Falling_Logs_Remove{spawns = spawns}
				inverse := Cmd_Falling_Logs_Insert{spawns = spawns}

				return {forward, inverse}, true
			}
		}

		return
	case Cmd_Checkpoints_Insert:
		// Use world position for checkpoint
		world_pos := pos_from_coords(es.area_begin)

		// Check if outside level bounds
		level_rect := rect_from_pos_size(gs.level.pos, gs.level.size)
		if !rl.CheckCollisionPointRec(world_pos, level_rect) {
			return
		}

		// Check if checkpoint already exists at this position
		for checkpoint in gs.level.checkpoints {
			if checkpoint.pos == world_pos {
				return
			}
		}

		// Generate unique checkpoint ID
		next_id: u32 = 1
		for checkpoint in gs.level.checkpoints {
			if checkpoint.id >= next_id {
				next_id = checkpoint.id + 1
			}
		}

		checkpoints := make([]Checkpoint, 1)
		checkpoints[0] = Checkpoint{id = next_id, pos = world_pos}

		forward := Cmd_Checkpoints_Insert{checkpoints = checkpoints}
		inverse := Cmd_Checkpoints_Remove{checkpoints = checkpoints}

		return {forward, inverse}, true
	case Cmd_Checkpoints_Remove:
		world_pos := pos_from_coords(es.area_begin)

		// Find checkpoint at this position (32x32 area)
		for checkpoint in gs.level.checkpoints {
			rect := rect_from_pos_size(checkpoint.pos, 32)
			if rl.CheckCollisionPointRec(world_pos, rect) {
				checkpoints := make([]Checkpoint, 1)
				checkpoints[0] = checkpoint

				forward := Cmd_Checkpoints_Remove{checkpoints = checkpoints}
				inverse := Cmd_Checkpoints_Insert{checkpoints = checkpoints}

				return {forward, inverse}, true
			}
		}

		return
	case Cmd_Power_Ups_Insert:
		world_pos := pos_from_coords(es.area_begin)

		// Check if outside level bounds
		level_rect := rect_from_pos_size(gs.level.pos, gs.level.size)
		if !rl.CheckCollisionPointRec(world_pos, level_rect) {
			return
		}

		// Check if powerup already exists at this position
		for pu in gs.level.power_ups {
			if pu.position == world_pos {
				return
			}
		}

		power_ups := make([]Power_Up, 1)
		power_ups[0] = Power_Up{position = world_pos, type = .Dash}

		forward := Cmd_Power_Ups_Insert{power_ups = power_ups}
		inverse := Cmd_Power_Ups_Remove{power_ups = power_ups}

		return {forward, inverse}, true
	case Cmd_Power_Ups_Remove:
		world_pos := pos_from_coords(es.area_begin)

		// Find powerup at this position
		for pu in gs.level.power_ups {
			rect := Rect{pu.x - 8, pu.y - 8, 16, 16}
			if rl.CheckCollisionPointRec(world_pos, rect) {
				power_ups := make([]Power_Up, 1)
				power_ups[0] = pu

				forward := Cmd_Power_Ups_Remove{power_ups = power_ups}
				inverse := Cmd_Power_Ups_Insert{power_ups = power_ups}

				return {forward, inverse}, true
			}
		}

		return
	case Cmd_Level_Move:
		forward := Cmd_Level_Move {
			level_id = gs.level.id,
			old_pos  = es.drag_start,
			new_pos  = es.drag_end,
		}

		inverse := Cmd_Level_Move {
			level_id = forward.level_id,
			old_pos  = forward.new_pos,
			new_pos  = forward.old_pos,
		}

		return {forward, inverse}, true
	case Cmd_Level_New:
		mouse_pos := rl.GetMousePosition()
		world_pos := rl.GetScreenToWorld2D(mouse_pos, gs.camera)
		// Round to tile corner
		coords := coords_from_pos(world_pos)
		pos := pos_from_coords(coords)

		// Default level size is one "screen"
		size := linalg.ceil(Vec2{RENDER_WIDTH, RENDER_HEIGHT} / TILE_SIZE) * TILE_SIZE
		rect := rect_from_pos_size(pos, size)

		for l in gs.levels {
			def_rect := rect_from_pos_size(l.pos, l.size)
			if rl.CheckCollisionRecs(rect, def_rect) {
				// Invalid position
				return {}, false
			}
		}

		level_id := get_next_level_id()

		forward := Cmd_Level_New {
			level_id = level_id,
			pos      = pos,
			size     = size,
		}

		inverse := Cmd_Level_Delete {
			level_id = level_id,
		}

		return {forward, inverse}, true
	case Cmd_Level_Delete:
		forward := Cmd_Level_Delete {
			level_id = gs.level.id,
		}

		inverse := Cmd_Level_Restore {
			level_id = gs.level.id,
		}

		return {forward, inverse}, true
	case Cmd_Level_Restore:
		forward := Cmd_Level_Restore {
			level_id = gs.level.id,
		}

		inverse := Cmd_Level_Delete {
			level_id = gs.level.id,
		}

		return {forward, inverse}, true
	case Cmd_Level_Resize:
		mouse_pos := rl.GetMousePosition()
		world_pos := rl.GetScreenToWorld2D(mouse_pos, gs.camera)
		new_pos, new_size := calculate_resize(
			gs.level,
			world_pos,
			es.resize_start_pos,
			es.resize_level_dir,
		)

		removed_tiles := make([dynamic]Tile)
		removed_spikes := make([dynamic]Spike)

		new_rect := rect_from_pos_size(new_pos, new_size)

		for tile in gs.level.tiles {
			// Shrink slightly to account for floating point precision
			rect := Rect{tile.pos.x + 1, tile.pos.y + 1, TILE_SIZE - 2, TILE_SIZE - 2}
			if !rl.CheckCollisionRecs(new_rect, rect) {
				append(&removed_tiles, tile)
			}
		}

		for spike in gs.level.spikes {
			// Shrink slightly to account for floating point precision
			rect := rect_pos_add(spike.collider, 1)
			rect.width -= 2
			rect.height -= 2
			if !rl.CheckCollisionRecs(new_rect, rect) {
				append(&removed_spikes, spike)
			}
		}

		forward := Cmd_Level_Resize {
			level_id       = gs.level.id,
			old_pos        = gs.level.pos,
			old_size       = gs.level.size,
			new_pos        = new_pos,
			new_size       = new_size,
			removed_tiles  = removed_tiles[:],
			removed_spikes = removed_spikes[:],
		}

		inverse := Cmd_Level_Resize {
			level_id       = forward.level_id,
			old_pos        = forward.new_pos,
			old_size       = forward.new_size,
			new_pos        = forward.old_pos,
			new_size       = forward.old_size,
			removed_tiles  = removed_tiles[:],
			removed_spikes = removed_spikes[:],
		}

		return {forward, inverse}, true
	}


	panic("Should not reach this location, check switch statement")
}

editor_command_execute :: proc(cmd: Cmd) {
	switch v in cmd {
	case Cmd_Tiles_Insert:
		for coords in v.coords {
			editor_tile_insert(coords, gs.level)
		}

		for spike in v.spikes_removed {
			editor_spike_remove(spike, gs.level)
		}
	case Cmd_Tiles_Remove:
		for coords in v.coords {
			editor_tile_remove(coords, gs.level)
		}

		for spike in v.spikes_removed {
			editor_spike_insert(spike, gs.level)
		}
	case Cmd_Spikes_Insert:
		for spike in v.spikes {
			editor_spike_insert(spike, gs.level)
		}

		for coords in v.tiles_removed {
			editor_tile_remove(coords, gs.level)
		}
	case Cmd_Spikes_Remove:
		for spike in v.spikes {
			editor_spike_remove(spike, gs.level)
		}

		for coords in v.tiles_removed {
			editor_tile_insert(coords, gs.level)
		}
	case Cmd_Enemies_Insert:
		for spawn in v.spawns {
			editor_enemy_insert(spawn, gs.level)
		}
	case Cmd_Enemies_Remove:
		for spawn in v.spawns {
			editor_enemy_remove(spawn, gs.level)
		}
	case Cmd_Falling_Logs_Insert:
		for spawn in v.spawns {
			append(&gs.level.falling_log_spawns, spawn)
		}
	case Cmd_Falling_Logs_Remove:
		for spawn in v.spawns {
			for s, i in gs.level.falling_log_spawns {
				if s.rect.x == spawn.rect.x && s.rect.y == spawn.rect.y {
					unordered_remove(&gs.level.falling_log_spawns, i)
					break
				}
			}
		}
	case Cmd_Checkpoints_Insert:
		for checkpoint in v.checkpoints {
			append(&gs.level.checkpoints, checkpoint)
		}
	case Cmd_Checkpoints_Remove:
		for checkpoint in v.checkpoints {
			for c, i in gs.level.checkpoints {
				if c.id == checkpoint.id {
					unordered_remove(&gs.level.checkpoints, i)
					break
				}
			}
		}
	case Cmd_Power_Ups_Insert:
		for pu in v.power_ups {
			append(&gs.level.power_ups, pu)
		}
	case Cmd_Power_Ups_Remove:
		for pu in v.power_ups {
			for p, i in gs.level.power_ups {
				if p.position == pu.position && p.type == pu.type {
					unordered_remove(&gs.level.power_ups, i)
					break
				}
			}
		}
	case Cmd_Level_Move:
		level_load(gs, v.level_id, 0)

		delta := v.new_pos - v.old_pos

		gs.level.pos = gs.level.pos + delta

		for &tile in gs.level.tiles {
			tile.pos += delta
		}
	case Cmd_Level_New:
		level: Level
		level.id = v.level_id
		level.name = strings.clone(fmt.tprintf("level_%d", level.id))
		level.pos = v.pos
		level.player_spawn = level.pos
		level.size = v.size
		append(&gs.levels, level)

		level_load(gs, level.id, 0)
	case Cmd_Level_Delete:
		append(&es.deleted_levels, level_from_id(gs.levels[:], v.level_id)^)
		deleted_level_index := level_index_from_id(gs.levels[:], v.level_id)
		unordered_remove(&gs.levels, deleted_level_index)

		for l in gs.levels {
			if l.id != v.level_id {
				level_load(gs, l.id, 0)
			}
		}
	case Cmd_Level_Restore:
		append(&gs.levels, level_from_id(es.deleted_levels[:], v.level_id)^)
		restored_level_index := level_index_from_id(es.deleted_levels[:], v.level_id)
		unordered_remove(&es.deleted_levels, restored_level_index)

		level_load(gs, v.level_id, 0)
	case Cmd_Level_Resize:
		level_load(gs, v.level_id, 0)

		if gs.level.size.x > v.new_size.x || gs.level.size.y > v.new_size.y {
			for tile in v.removed_tiles {
				tile_coords := coords_from_pos(tile.pos)
				#reverse for level_tile, i in gs.level.tiles {
					level_tile_coords := coords_from_pos(level_tile.pos)
					if tile_coords == level_tile_coords {
						ordered_remove(&gs.level.tiles, i)
					}
				}
			}

			for spike in v.removed_spikes {
				spike_coords := coords_from_pos({spike.collider.x, spike.collider.y})
				#reverse for level_spike, i in gs.level.spikes {
					level_spike_coords := coords_from_pos(
						{level_spike.collider.x, level_spike.collider.y},
					)
					if spike_coords == level_spike_coords {
						ordered_remove(&gs.level.spikes, i)
					}
				}
			}
		} else {
			for tile in v.removed_tiles {
				append(&gs.level.tiles, tile)
			}

			for spike in v.removed_spikes {
				append(&gs.level.spikes, spike)
			}
		}

		gs.level.pos = v.new_pos
		gs.level.size = v.new_size
	}

	recreate_colliders(gs.level.pos, &gs.colliders, gs.level.tiles[:])
	autotile_run(gs.level)

	// Respawn falling logs from spawns (with ceiling detection)
	clear(&gs.falling_logs)
	for spawn in gs.level.falling_log_spawns {
		log_collider := rect_pos_add(spawn.rect, gs.level.pos)
		log_center_x := log_collider.x + log_collider.width / 2

		// Find ceiling above the log
		rope_height: f32 = FALLING_LOG_ROPE_HEIGHT
		ceiling_y: f32 = log_collider.y - 1000

		for tile in gs.level.tiles {
			tile_bottom := tile.pos.y + TILE_SIZE
			if tile_bottom <= log_collider.y &&
			   tile.pos.x <= log_center_x &&
			   tile.pos.x + TILE_SIZE >= log_center_x {
				if tile_bottom > ceiling_y {
					ceiling_y = tile_bottom
				}
			}
		}

		if ceiling_y > log_collider.y - 1000 {
			rope_height = log_collider.y - ceiling_y
		}

		append(&gs.falling_logs, Falling_Log {
			collider    = log_collider,
			rope_height = rope_height,
			state       = .Default,
		})
	}

	world_data_save()
}

editor_command_record :: proc(cmd: Cmd_Entry) {
	next_index := len(es.command_history) - es.undo_count
	resize(&es.command_history, next_index + 1)

	es.command_history[next_index] = cmd
	es.undo_count = 0
}

editor_command_dispatch :: proc(cmd_type: typeid) {
	if cmd, ok := editor_command_construct(cmd_type); ok {
		editor_command_execute(cmd.forward)
		editor_command_record(cmd)
	}
}

editor_undo :: proc() {
	commands_exist := len(es.command_history) > 0
	can_undo_more := len(es.command_history) != es.undo_count

	if commands_exist && can_undo_more {
		es.undo_count += 1
		undo_cmd := es.command_history[len(es.command_history) - es.undo_count]
		editor_command_execute(undo_cmd.inverse)
	}
}

editor_redo :: proc() {
	did_undo := es.undo_count > 0
	can_redo_more := len(es.command_history) - es.undo_count >= 0

	if did_undo && can_redo_more {
		redo_cmd := es.command_history[len(es.command_history) - es.undo_count]
		es.undo_count -= 1
		editor_command_execute(redo_cmd.forward)
	}
}

coords_from_area :: proc(begin, end: Vec2i) -> []Vec2i {
	coords := make([dynamic]Vec2i)

	area_min := Vec2i{min(begin.x, end.x), min(begin.y, end.y)}
	area_max := Vec2i{max(begin.x, end.x), max(begin.y, end.y)}

	level_min := coords_from_pos(gs.level.pos)
	level_max := coords_from_pos(gs.level.pos + gs.level.size)

	area_min.x = max(area_min.x, level_min.x)
	area_min.y = max(area_min.y, level_min.y)
	area_max.x = min(area_max.x, level_max.x - 1)
	area_max.y = min(area_max.y, level_max.y - 1)

	for y := area_min.y; y <= area_max.y; y += 1 {
		for x := area_min.x; x <= area_max.x; x += 1 {
			append(&coords, Vec2i{i32(x), i32(y)})
		}
	}

	return coords[:]
}

spikes_from_area :: proc(p, q: Vec2i, l: ^Level) -> []Spike {
	rect := rect_from_coords_any_orientation(p, q)
	rect = rect_pos_add(rect, -l.pos)

	spikes := make([dynamic]Spike)

	for spike in l.spikes {
		if rl.CheckCollisionRecs(rect, spike.collider) {
			append(&spikes, spike)
		}
	}

	return spikes[:]
}

make_tileset :: proc() -> Tileset {
	tileset: Tileset

	rules := make([dynamic]Tileset_Rule)

	// Centre
	append(&rules, Tileset_Rule{src = {48, 48}})

	// NW, NE, SE, SW
	append(&rules, Tileset_Rule{neighbors = {.E, .S}, not_neighbors = {.N}, src = {16, 16}})
	append(&rules, Tileset_Rule{neighbors = {.W, .S}, not_neighbors = {.N}, src = {80, 16}})
	append(&rules, Tileset_Rule{neighbors = {.W, .N}, not_neighbors = {.S}, src = {80, 80}})
	append(&rules, Tileset_Rule{neighbors = {.E, .N}, not_neighbors = {.S}, src = {16, 80}})

	// N, E, S, W
	append(&rules, Tileset_Rule{neighbors = {.E, .W, .S}, not_neighbors = {.N}, src = {48, 16}})
	append(&rules, Tileset_Rule{neighbors = {.W, .SW, .NW}, not_neighbors = {.E}, src = {80, 48}})
	append(&rules, Tileset_Rule{neighbors = {.E, .W, .N}, not_neighbors = {.S}, src = {48, 80}})
	append(&rules, Tileset_Rule{neighbors = {.E, .SE, .NE}, not_neighbors = {.W}, src = {16, 48}})

	// Outcropping E, W
	append(&rules, Tileset_Rule{neighbors = {.W}, not_neighbors = {.N, .E, .S}, src = {16, 320}})
	append(&rules, Tileset_Rule{neighbors = {.W}, not_neighbors = {.N, .S}, src = {16, 320}})
	append(&rules, Tileset_Rule{neighbors = {.E}, not_neighbors = {.N, .W, .S}, src = {16, 320}})
	append(&rules, Tileset_Rule{neighbors = {.E}, not_neighbors = {.N, .S}, src = {16, 320}})

	// Outcropping N, S
	append(&rules, Tileset_Rule{neighbors = {.S}, not_neighbors = {.E, .N, .W}, src = {16, 320}})
	append(&rules, Tileset_Rule{neighbors = {.S}, not_neighbors = {.E, .W}, src = {16, 320}})
	append(&rules, Tileset_Rule{neighbors = {.N}, not_neighbors = {.E, .S, .W}, src = {16, 320}})
	append(&rules, Tileset_Rule{neighbors = {.N}, not_neighbors = {.E, .W}, src = {16, 320}})

	// Outcropping Corners
	append(&rules, Tileset_Rule{neighbors = {.N, .E}, src = {16, 320}, flags = {.Match_Exact}})
	append(&rules, Tileset_Rule{neighbors = {.S, .E}, src = {16, 320}, flags = {.Match_Exact}})
	append(&rules, Tileset_Rule{neighbors = {.S, .W}, src = {16, 320}, flags = {.Match_Exact}})
	append(&rules, Tileset_Rule{neighbors = {.N, .W}, src = {16, 320}, flags = {.Match_Exact}})

	// Outcropping Join
	append(
		&rules,
		Tileset_Rule {
			neighbors = {.N, .E, .S, .SW, .W, .NW},
			src = {80, 48},
			flags = {.Match_Exact},
		},
	)
	append(
		&rules,
		Tileset_Rule {
			neighbors = {.N, .NE, .E, .SE, .S, .W},
			src = {16, 48},
			flags = {.Match_Exact},
		},
	)
	append(
		&rules,
		Tileset_Rule {
			neighbors = {.N, .E, .SE, .S, .SW, .W},
			src = {112, 16},
			flags = {.Match_Exact},
		},
	)
	append(
		&rules,
		Tileset_Rule {
			neighbors = {.N, .E, .NE, .S, .NW, .W},
			src = {48, 80},
			flags = {.Match_Exact},
		},
	)

	// Outcropping Cross
	append(&rules, Tileset_Rule{neighbors = {.E, .S, .W}, src = {16, 320}, flags = {.Match_Exact}})
	append(&rules, Tileset_Rule{neighbors = {.E, .N, .W}, src = {16, 320}, flags = {.Match_Exact}})
	append(&rules, Tileset_Rule{neighbors = {.E, .N, .S}, src = {16, 320}, flags = {.Match_Exact}})
	append(&rules, Tileset_Rule{neighbors = {.W, .N, .S}, src = {16, 320}, flags = {.Match_Exact}})

	tileset.texture = gs.tileset_texture
	tileset.rules = rules[:]

	return tileset
}

autotile_calculate_neighbors :: proc(coords: Vec2i, l: ^Level) -> Tile_Neighbors {
	result: Tile_Neighbors

	if is_tile_at(coords + Dir8_Coords[.N], l) do result += {.N}
	if is_tile_at(coords + Dir8_Coords[.E], l) do result += {.E}
	if is_tile_at(coords + Dir8_Coords[.S], l) do result += {.S}
	if is_tile_at(coords + Dir8_Coords[.W], l) do result += {.W}

	if is_tile_at(coords + Dir8_Coords[.NE], l) do result += {.NE}
	if is_tile_at(coords + Dir8_Coords[.SE], l) do result += {.SE}
	if is_tile_at(coords + Dir8_Coords[.SW], l) do result += {.SW}
	if is_tile_at(coords + Dir8_Coords[.NW], l) do result += {.NW}

	return result
}

autotile_run :: proc(l: ^Level) {
	for &tile in gs.level.tiles {
		tile.src = 0
	}

	for rule in es.tileset.rules {
		for &tile in gs.level.tiles {
			if .Match_Exact in rule.flags {
				if rule.neighbors == tile.neighbors && rule.not_neighbors & tile.neighbors == {} {
					tile.src = rule.src
				}
			} else {
				if rule.neighbors <= tile.neighbors && rule.not_neighbors & tile.neighbors == {} {
					tile.src = rule.src
				}
			}
		}
	}
}
