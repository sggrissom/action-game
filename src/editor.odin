package main

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:slice"
import rl "vendor:raylib"

Editor_Tool :: enum {
	None,
	Tile,
	Spike,
	Level,
}

Editor_State :: struct {
	tool:          Editor_Tool,
	previous_tool: Editor_Tool,
	area_begin:    Vec2i,
	area_end:      Vec2i,
}

@(private = "file")
es: Editor_State

editor_update :: proc(gs: ^Game_State) {
	scroll := rl.GetMouseWheelMove()
	if rl.IsKeyPressed(.LEFT_BRACKET) {
		scroll -= 1
	}
	if rl.IsKeyPressed(.RIGHT_BRACKET) {
		scroll += 1
	}
	if scroll != 0 {
		mouse_pos := rl.GetMousePosition()

		mouse_world_pos := rl.GetScreenToWorld2D(mouse_pos, gs.camera)

		gs.camera.zoom = clamp(gs.camera.zoom + scroll * 0.25, 0.25, 8)

		mouse_world_pos_new := rl.GetScreenToWorld2D(mouse_pos, gs.camera)

		gs.camera.target += (mouse_world_pos - mouse_world_pos_new)
	}

	if es.tool == .Level {
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

	pos := rl.GetMousePosition() + gs.camera.target * gs.camera.zoom
	pos /= gs.camera.zoom
	coords := coords_from_pos(pos)

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
			size := linalg.abs(diff)
			diff_f32 := Vec2{f32(diff.x), f32(diff.y)}
			sign := Vec2i{i32(linalg.sign(diff_f32.x)), i32(linalg.sign(diff_f32.y))}

			for y in 0 ..= size.y {
				for x in 0 ..= size.x {
					if place {
						editor_place_tile(es.area_begin + {i32(x), i32(y)} * sign, gs.level)
					} else {
						editor_remove_tile(es.area_begin + {i32(x), i32(y)} * sign, gs.level)
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
			rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
			editor_place_spikes(rect, gs.level)
		}

		if rl.IsMouseButtonReleased(.RIGHT) {
			rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
			editor_remove_spikes(rect, gs.level)
		}
	case .Level:
		if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
			es.area_begin = coords
		}

		if rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT) {
			es.area_end = coords
		}
	}
}

editor_draw :: proc(gs: ^Game_State) {
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

	if place || remove {
		rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
		rect.x -= gs.camera.target.x
		rect.y -= gs.camera.target.y

		rect = rect_scale_all(rect, gs.camera.zoom)
		rl.DrawRectangleLinesEx(rect, 4, place ? rl.WHITE : rl.RED)
		if es.tool == .Level {
			one_screen_rect := rect
			one_screen_rect.width =
				math.ceil(f32(RENDER_WIDTH) / TILE_SIZE) * TILE_SIZE * gs.camera.zoom
			one_screen_rect.height =
				math.ceil(f32(RENDER_HEIGHT) / TILE_SIZE) * TILE_SIZE * gs.camera.zoom
			rl.DrawRectangleLinesEx(one_screen_rect, 1, rl.DARKGRAY)
		}
	}

	for &ld in gs.levels {
		level_min := ld.pos - gs.camera.target
		level_size := ld.size
		level_rect := Rect{level_min.x, level_min.y, level_size.x, level_size.y}
		level_rect = rect_scale_all(level_rect, gs.camera.zoom)

		color := ld.id == gs.level.id ? rl.WHITE : rl.GRAY
		thickness := f32(1)

		if es.tool == .Level {
			thickness = 4
			text := fmt.ctprintf("level_%d", ld.id)
			text_size := rl.MeasureTextEx(gs.font_48, text, 48, 0)
			text_pos :=
				Vec2{level_rect.x, level_rect.y} +
				({level_rect.width, level_rect.height} - text_size) / 2
			rl.DrawTextEx(gs.font_48, text, text_pos, 48, 0, {255, 255, 255, 128})
		}

		rl.DrawRectangleLinesEx(level_rect, thickness, color)
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

is_tile_at :: proc {
	is_tile_at_pos,
	is_tile_at_coords,
}

editor_place_tile :: proc(coords: Vec2i, l: ^Level) {
	if !is_tile_at(coords, l) {
		append(&l.tiles, Tile{pos = pos_from_coords(coords)})
		slice.sort_by(l.tiles[:], proc(a, b: Tile) -> bool {
			if a.pos.y != b.pos.y do return a.pos.y < b.pos.y
			return a.pos.x < b.pos.x
		})

		pos := pos_from_coords(coords)
		rect := Rect{pos.x, pos.y, TILE_SIZE, TILE_SIZE}
		editor_remove_spikes(rect, l)

		recreate_level_colliders(l)
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

		recreate_level_colliders(l)
	}
}

rect_from_coords_any_orientation :: proc(a, b: Vec2i) -> Rect {
	top := f32(min(a.y, b.y)) * TILE_SIZE
	left := f32(min(a.x, b.x)) * TILE_SIZE
	bottom := f32(max(a.y, b.y)) * TILE_SIZE
	right := f32(max(a.x, b.x)) * TILE_SIZE

	return Rect{left, top, right - left + TILE_SIZE, bottom - top + TILE_SIZE}
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

is_area_tiled :: proc(begin: Vec2i, end: Vec2i, l: ^Level) -> bool {
	for y in begin.y ..< end.y {
		for x in begin.x ..< end.x {
			if !is_tile_at(Vec2i{x, y}, l) {
				return false
			}
		}
	}
	return true
}
