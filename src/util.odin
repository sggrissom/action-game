package main

import "core:math/linalg"

rect_scale_all :: #force_inline proc(r: Rect, s: f32) -> Rect {
	return Rect{r.x * s, r.y * s, r.width * s, r.height * s}
}

coords_from_pos :: #force_inline proc(pos: Vec2) -> Vec2i {
	coordsf := pos / TILE_SIZE
	coordsf = linalg.floor(coordsf)
	return Vec2i{i32(coordsf.x), i32(coordsf.y)}
}

pos_from_coords :: #force_inline proc(coords: Vec2i) -> Vec2 {
	return Vec2{f32(coords.x), f32(coords.y)} * TILE_SIZE
}

rect_center :: #force_inline proc(r: Rect) -> Vec2 {
	return Vec2{r.x, r.y} + Vec2{r.width, r.height} * 0.5
}

rect_from_pos_size :: #force_inline proc(pos, size: Vec2) -> Rect {
	return Rect{pos.x, pos.y, size.x, size.y}
}

rect_pos_add :: #force_inline proc(rect: Rect, v: Vec2) -> Rect {
	return Rect{rect.x + v.x, rect.y + v.y, rect.width, rect.height}
}
