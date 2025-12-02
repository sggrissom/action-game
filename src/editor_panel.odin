package main

import "core:strings"

import rl "vendor:raylib"

Editor_Panel :: struct {
	pos:         Vec2, // Position the next element will be drawn
	line_height: f32,
	padding:     f32,
	width:       f32,
}

@(private = "file")
panel: Editor_Panel

editor_panel :: proc(w: f32, padding: f32 = 8, line_height: f32 = 20, bg := rl.BLACK) {
	rl.DrawRectangleV(0, {w, WINDOW_HEIGHT}, bg)
	panel.width = w
	panel.padding = padding
	panel.line_height = line_height
	panel.pos = {padding, padding}
}

editor_panel_row_increment :: proc() {
	panel.pos += {0, panel.line_height}
}

editor_panel_text :: proc(text: cstring) {
	rl.DrawTextEx(gs.font_18, text, panel.pos, 18, 0, rl.WHITE)
	editor_panel_row_increment()
}

editor_panel_button :: proc(
	text: cstring,
	bg := rl.GRAY,
	hover_overlay := rl.Color{0, 255, 255, 80},
) -> bool {
	is_pressed := false
	is_hovered := false

	size := Vec2{panel.width - 16, 20}
	rect := rect_from_pos_size(panel.pos, size)

	mouse_pos := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(mouse_pos, rect) {
		is_hovered = true
		if rl.IsMouseButtonPressed(.LEFT) {
			is_pressed = true
		}
	}

	text_pos := panel.pos + {8, 1}

	rl.DrawRectangleRounded(rect, 0.2, 5, bg)

	if is_hovered {
		rl.DrawRectangleRounded(rect, 0.2, 5, hover_overlay)
	}

	rl.DrawTextEx(gs.font_18, text, text_pos, 18, 0, rl.BLACK)

	editor_panel_row_increment()

	return is_pressed
}

// This element was being used during development before I switched
// to a series of buttons for on_enter.
// I left it in here to show how a simple text box may be made
editor_panel_textbox :: proc(sb: ^strings.Builder) -> bool {
	size := Vec2{panel.width - 16, 20}
	rect := rect_from_pos_size(panel.pos, size)

	text := strings.to_cstring(sb)

	rl.DrawRectangleRec(rect, rl.GRAY)
	rl.DrawTextEx(gs.font_18, text, panel.pos, 18, 0, rl.BLACK)

	key := rl.GetKeyPressed()

	if key == .KEY_NULL {
		return false
	}

	if key == .BACKSPACE {
		strings.pop_byte(sb)
		return false
	}

	if key == .ENTER {
		return true
	}

	char := rl.GetCharPressed()

	strings.write_rune(sb, char)

	editor_panel_row_increment()

	return false
}
