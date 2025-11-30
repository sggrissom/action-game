package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

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
	tool:             Editor_Tool,
	previous_tool:    Editor_Tool,
	area_begin:       Vec2i,
	area_end:         Vec2i,
	resize_level_dir: Dir8,
	resize_rect:      Rect,
	resize_start_pos: Vec2,
}

@(private = "file")
es: Editor_State

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

editor_update :: proc(gs: ^Game_State) {
	mouse_pos := rl.GetMousePosition()

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

		es.previous_tool = es.tool
		if gs.camera.zoom < 1 {
			es.tool = .Level
		}
	}

	if rl.IsMouseButtonDown(.MIDDLE) {
		mouse_delta := rl.GetMouseDelta()
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

		if place || remove {
			es.area_end = coords
			diff := es.area_end - es.area_begin
			area := linalg.abs(diff)
			diff_f32 := Vec2{f32(diff.x), f32(diff.y)}
			sign := Vec2i{i32(linalg.sign(diff_f32.x)), i32(linalg.sign(diff_f32.y))}

			for y in 0 ..= area.y {
				for x in 0 ..= area.x {
					rel_coords := es.area_begin + {i32(x), i32(y)} * sign
					rel_coords -= coords_from_pos(gs.level.pos)

					if place {
						editor_place_tile(rel_coords, gs.level)
					} else {
						editor_remove_tile(rel_coords, gs.level)
					}
				}
			}
		}
	case .Spike:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
			es.area_end = coords
		}

		if rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT) {
			rect := rect_from_coords_any_orientation(es.area_begin, coords)
			if rect.width > rect.height {
				es.area_end.x = coords.x
				es.area_end.y = es.area_begin.y
			}
			if rect.height > rect.width {
				es.area_end.x = es.area_begin.x
				es.area_end.y = coords.y
			}
		}

		if rl.IsMouseButtonReleased(.LEFT) {
			begin := es.area_begin - coords_from_pos(gs.level.pos)
			end := es.area_end - coords_from_pos(gs.level.pos)
			rect := rect_from_coords_any_orientation(begin, end)
			editor_place_spikes(rect, gs.level)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			begin := es.area_begin - coords_from_pos(gs.level.pos)
			end := es.area_end - coords_from_pos(gs.level.pos)
			rect := rect_from_coords_any_orientation(begin, end)
			editor_remove_spikes(rect, gs.level)
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
					level_load(gs, level.id)
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
			"Tool: %s\nCamera.Zoom: %v\nCamera.Target: %v",
			es.tool,
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

editor_place_tile :: proc(coords: Vec2i, l: ^Level) {
	if !is_tile_at(coords, l) {
		append(&l.tiles, Tile{pos = pos_from_coords(coords)})
		slice.sort_by(l.tiles[:], proc(a, b: Tile) -> bool {
			if a.pos.y != b.pos.y do return a.pos.y < b.pos.y
			return a.pos.x < b.pos.x
		})

		rect := rect_from_pos_size(pos_from_coords(coords) - l.pos, TILE_SIZE)
		editor_remove_spikes(rect, l)

		recreate_colliders(l.pos, &gs.colliders, l.tiles[:])
	}
}

try_remove_tile_at :: proc(coords: Vec2i, l: ^Level) -> bool {
	for tile, index in l.tiles {
		if coords_from_pos(tile.pos) == coords {
			ordered_remove(&l.tiles, index)
			return true
		}
	}
	return false
}

editor_remove_tile :: proc(coords: Vec2i, l: ^Level) {
	if try_remove_tile_at(coords, l) {
		slice.sort_by(l.tiles[:], proc(a, b: Tile) -> bool {
			if a.pos.y != b.pos.y do return a.pos.y < b.pos.y
			return a.pos.x < b.pos.x
		})

		recreate_colliders(l.pos, &gs.colliders, l.tiles[:])
	}
}

editor_place_spikes :: proc(rect: Rect, l: ^Level) {
	coords := coords_from_pos({rect.x, rect.y})
	cols := int(rect.width) / TILE_SIZE
	rows := int(rect.height) / TILE_SIZE

	for y in 0 ..< rows {
		for x in 0 ..< cols {
			editor_remove_tile(coords + {i32(x), i32(y)}, l)
		}
	}

	editor_remove_spikes(rect, l)

	spike: Spike
	spike.collider = rect
	if facing, ok := determine_spike_facing(rect, l); ok {
		spike.facing = facing
		switch facing {
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
		append(&l.spikes, spike)
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

determine_spike_facing :: proc(rect: Rect, l: ^Level) -> (facing: Direction, ok: bool) {
	begin_coords := coords_from_pos({rect.x, rect.y})
	end_coords := coords_from_pos({rect.x + rect.width, rect.y + rect.height})

	// Check Below, Facing Up
	if is_area_tiled(begin_coords + {0, 1}, end_coords + {0, 1}, l) {
		return .Up, true
	}

	// Check Above, Facing Down
	if is_area_tiled(begin_coords + {0, -1}, end_coords + {0, -1}, l) {
		return .Down, true
	}
	// Check Right, Facing Left
	if is_area_tiled(begin_coords + {1, 0}, end_coords + {1, 0}, l) {
		return .Left, true
	}

	// Check Left, Facing Right
	if is_area_tiled(begin_coords + {-1, 0}, end_coords + {-1, 0}, l) {
		return .Right, true
	}

	return .Up, false
}

editor_remove_spikes :: proc(rect: Rect, l: ^Level) {
	#reverse for spike, i in l.spikes {
		if rl.CheckCollisionRecs(rect, spike.collider) {
			ordered_remove(&l.spikes, i)
		}
	}
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
