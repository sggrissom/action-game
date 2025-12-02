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
	tileset:           Tileset,
}

Cmd :: union {
	Cmd_Tiles_Insert,
	Cmd_Tiles_Remove,
	Cmd_Spikes_Insert,
	Cmd_Spikes_Remove,
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

		if rl.IsKeyPressed(.F) {
			es.spike_orientation += Direction(1)
			if int(es.spike_orientation) > 3 {
				es.spike_orientation = Direction(0)
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
	case .Level:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
		}

		if rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT) {
			es.area_end = coords
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
			editor_place_level(gs, rect)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
			editor_remove_level(gs, rect)
		}

		for level in gs.levels {
			level_rect := rect_from_pos_size(level.pos - gs.camera.target, level.size)
			level_rect = rect_scale_all(level_rect, gs.camera.zoom)
			if rl.CheckCollisionPointRec(mouse_pos, level_rect) {
				if rl.IsMouseButtonPressed(.LEFT) {
					level_load(gs, level.id, 0)
				}
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
			world_pos := rl.GetScreenToWorld2D(mouse_pos, gs.camera)

			gs.level.pos, gs.level.size = calculate_resize(
				gs.level,
				world_pos,
				es.resize_start_pos,
				es.resize_level_dir,
			)

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
			one_screen_rect := rect
			one_screen_rect.width =
				math.ceil(f32(RENDER_WIDTH) / TILE_SIZE) * TILE_SIZE * gs.camera.zoom
			one_screen_rect.height =
				math.ceil(f32(RENDER_HEIGHT) / TILE_SIZE) * TILE_SIZE * gs.camera.zoom
			rl.DrawRectangleLinesEx(one_screen_rect, 1, rl.DARKGRAY)
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

	rl.EndMode2D()

	if es.tool == .Level {
		editor_panel(PANEL_WIDTH)

		editor_panel_text(fmt.ctprintf("Level ID: %d", gs.level.id))

		level_pos_tiles := coords_from_pos(gs.level.pos)
		editor_panel_text(fmt.ctprintf("Pos: %d, %d", level_pos_tiles.x, level_pos_tiles.y))

		level_size_tiles := coords_from_pos(gs.level.size)
		editor_panel_text(fmt.ctprintf("Size: %d, %d", level_size_tiles.x, level_size_tiles.y))
	}
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

editor_place_level :: proc(gs: ^Game_State, rect: Rect) {
	// 1. Increase size to minimum level size
	rect := rect
	rect.width = max(rect.width, math.ceil(f32(RENDER_WIDTH) / TILE_SIZE) * TILE_SIZE)
	rect.height = max(rect.height, math.ceil(f32(RENDER_HEIGHT) / TILE_SIZE) * TILE_SIZE)

	// 2. Determine whether the level is in a valid spot
	// - Overlapping other levels is not valid

	is_valid_placement := true

	for l in gs.levels {
		def_rect := rect_from_pos_size(l.pos, l.size)
		if rl.CheckCollisionRecs(rect, def_rect) {
			is_valid_placement = false
			break
		}
	}

	if is_valid_placement {
		level: Level
		level.id = get_next_level_id(gs.levels[:])
		level.name = strings.clone(fmt.tprintf("level_%d", level.id))
		level.pos = {rect.x, rect.y}
		level.player_spawn = level.pos
		level.size = {rect.width, rect.height}
		append(&gs.levels, level)
		gs.level = level_from_id(gs.levels[:], level.id)
	}
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

get_next_level_id :: proc(levels: []Level) -> u32 {
	id := u32(0)
	for level in levels {
		if level.id > id {
			id = level.id
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
	}

	recreate_colliders(gs.level.pos, &gs.colliders, gs.level.tiles[:])
	autotile_run(gs.level)
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
