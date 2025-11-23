package main

import rl "vendor:raylib"

Debug_Line :: struct {
	start, end: Vec2,
	thickness:  f32,
	color:      rl.Color,
}

Debug_Rect :: struct {
	pos, size: Vec2,
	thickness: f32,
	color:     rl.Color,
}

Debug_Circle :: struct {
	pos:    Vec2,
	radius: f32,
	color:  rl.Color,
}

Debug_Shape :: union {
	Debug_Line,
	Debug_Rect,
	Debug_Circle,
}

debug_draw_line :: proc(start, end: Vec2, thickness: f32, color: rl.Color) {
	append(&gs.debug_shapes, Debug_Line{start, end, thickness, color})
}

debug_draw_rect :: proc(pos, size: Vec2, thickness: f32, color: rl.Color) {
	append(&gs.debug_shapes, Debug_Rect{pos, size, thickness, color})
}

debug_draw_circle :: proc(pos: Vec2, radius: f32, color: rl.Color) {
	append(&gs.debug_shapes, Debug_Circle{pos, radius, color})
}

