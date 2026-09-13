package main

import rl "vendor:raylib"

// Input abstraction. On desktop these map to the original keyboard/mouse bindings and
// behave exactly as before. On iOS they are driven by on-screen buttons sampled from
// the multi-touch points, so more than one control can be held at once (e.g. run+jump).

Touch_Button :: enum {
	Left,
	Right,
	Jump,
	Attack,
	Dash,
	Interact,
}

Touch_Control :: struct {
	center: Vec2,
	radius: f32,
	label:  cstring,
}

// Laid out in the fixed 1280x720 virtual space, thumbs at the bottom corners.
TOUCH_CONTROLS := [Touch_Button]Touch_Control {
	.Left     = {{120, 570}, 66, "<"},
	.Right    = {{280, 570}, 66, ">"},
	.Jump     = {{1160, 560}, 76, "A"},
	.Attack   = {{1000, 610}, 62, "B"},
	.Dash     = {{1090, 420}, 54, "D"},
	.Interact = {{200, 405}, 54, "^"},
}

touch_input: struct {
	down: [Touch_Button]bool,
	prev: [Touch_Button]bool,
}

// input_update samples the touch points once per frame. Call before game logic.
input_update :: proc() {
	when IOS {
		touch_input.prev = touch_input.down
		touch_input.down = {}

		count := rl.GetTouchPointCount()
		for i in 0 ..< count {
			// Touch points come back in device pixels; fold them into virtual space.
			p := (rl.GetTouchPosition(i) - platform.view_offset) / platform.view_scale

			for control, button in TOUCH_CONTROLS {
				if rl.CheckCollisionPointCircle(p, control.center, control.radius) {
					touch_input.down[button] = true
				}
			}
		}
	}
}

@(private = "file")
touch_down :: proc(button: Touch_Button) -> bool {
	return touch_input.down[button]
}

@(private = "file")
touch_pressed :: proc(button: Touch_Button) -> bool {
	return touch_input.down[button] && !touch_input.prev[button]
}

@(private = "file")
touch_released :: proc(button: Touch_Button) -> bool {
	return !touch_input.down[button] && touch_input.prev[button]
}

input_move_x :: proc() -> f32 {
	x: f32
	when IOS {
		if touch_down(.Right) do x += 1
		if touch_down(.Left) do x -= 1
	} else {
		if rl.IsKeyDown(.D) do x += 1
		if rl.IsKeyDown(.A) do x -= 1
	}
	return x
}

input_jump_pressed :: proc() -> bool {
	when IOS {
		return touch_pressed(.Jump)
	} else {
		return rl.IsKeyPressed(.SPACE)
	}
}

input_jump_released :: proc() -> bool {
	when IOS {
		return touch_released(.Jump)
	} else {
		return rl.IsKeyReleased(.SPACE)
	}
}

input_attack_pressed :: proc() -> bool {
	when IOS {
		return touch_pressed(.Attack)
	} else {
		return rl.IsMouseButtonPressed(.LEFT)
	}
}

input_dash_pressed :: proc() -> bool {
	when IOS {
		return touch_pressed(.Dash)
	} else {
		return rl.IsMouseButtonPressed(.RIGHT)
	}
}

input_interact_pressed :: proc() -> bool {
	when IOS {
		return touch_pressed(.Interact)
	} else {
		return rl.IsKeyPressed(.W)
	}
}

// input_dash_dir is the held aim direction for a dash; {0,0} means "use facing".
input_dash_dir :: proc() -> Vec2 {
	dir: Vec2
	when IOS {
		if touch_down(.Interact) do dir.y -= 1
		if touch_down(.Right) do dir.x += 1
		if touch_down(.Left) do dir.x -= 1
	} else {
		if rl.IsKeyDown(.W) do dir.y -= 1
		if rl.IsKeyDown(.S) do dir.y += 1
		if rl.IsKeyDown(.A) do dir.x -= 1
		if rl.IsKeyDown(.D) do dir.x += 1
	}
	return dir
}

// touch_controls_draw renders the on-screen buttons. No-op off iOS.
touch_controls_draw :: proc() {
	when IOS {
		for control, button in TOUCH_CONTROLS {
			fill := rl.Color{255, 255, 255, touch_input.down[button] ? 90 : 40}
			rl.DrawCircleV(control.center, control.radius, fill)
			rl.DrawCircleLinesV(control.center, control.radius, {255, 255, 255, 140})

			size := rl.MeasureTextEx(gs.font_48, control.label, 48, 0)
			rl.DrawTextEx(
				gs.font_48,
				control.label,
				control.center - size / 2,
				48,
				0,
				{255, 255, 255, 200},
			)
		}
	}
}
