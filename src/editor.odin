package main

import "core:fmt"
import "core:math/linalg"
import "core:slice"
import rl "vendor:raylib"

Editor_Tool :: enum {
	None,
	Tile,
}

Editor_State :: struct {
	tool:       Editor_Tool,
	area_begin: Vec2i,
	area_end:   Vec2i,
}

@(private = "file")
es: Editor_State

editor_update :: proc(gs: ^Game_State) {
	if rl.IsKeyPressed(.T) {
		es.tool = .Tile
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
	}
}

editor_draw :: proc(gs: ^Game_State) {
	rl.DrawTextEx(gs.font_48, "EDITOR MODE", {8, 8}, 48, 0, rl.WHITE)
	rl.DrawTextEx(gs.font_48, fmt.ctprintf("Tool: %s", es.tool), {8, 48}, 48, 0, rl.WHITE)

	place := rl.IsMouseButtonDown(.LEFT)
	remove := rl.IsMouseButtonDown(.RIGHT)

	if place || remove {
		rect := rect_from_coords_any_orientation(es.area_begin, es.area_end)
		rect.x -= gs.camera.target.x
		rect.y -= gs.camera.target.y

		rect = rect_scale_all(rect, gs.camera.zoom)
		rl.DrawRectangleLinesEx(rect, 4, place ? rl.WHITE : rl.RED)
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
