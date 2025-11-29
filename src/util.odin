package main

import "core:math/linalg"

rect_scale_all :: #force_inline proc(r: Rect, s: f32) -> Rect {
	return Rect{r.x * s, r.y * s, r.width * s, r.height * s}
}

coords_from_pos :: proc(pos: Vec2) -> Vec2i {
	coordsf := linalg.floor(pos) / TILE_SIZE
	return Vec2i{i32(coordsf.x), i32(coordsf.y)}
}

pos_from_coords :: proc(coords: Vec2i) -> Vec2 {
	return Vec2{f32(coords.x), f32(coords.y)} * TILE_SIZE
}
