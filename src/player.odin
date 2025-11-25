package main

import rl "vendor:raylib"

Player_Movement_State :: enum {
	Uncontrollable,
	Idle,
	Run,
	Jump,
	Fall,
}

player_update :: proc(gs: ^Game_State, dt: f32) {
	player := entity_get(gs.player_id)

	input_x: f32
	if rl.IsKeyDown(.D) do input_x += 1
	if rl.IsKeyDown(.A) do input_x -= 1

	player.vel.x = input_x * player.move_speed
	if player.vel.x < 0 {
		player.flags += {.Left}
	} else if player.vel.x > 0 {
		player.flags -= {.Left}
	}

	switch gs.player_movement_state {
	case .Uncontrollable:
		gs.safe_reset_timer -= dt
		player.vel.x = 0
		player.vel.y = 0
		if gs.safe_reset_timer <= 0 {
			switch_animation(player, "idle")
			gs.player_movement_state = .Idle
		}
	case .Idle:
		try_run(gs, player)
		try_jump(gs, player)
	case .Run:
		if input_x == 0 {
			gs.player_movement_state = .Idle
			switch_animation(player, "idle")
		}
		try_jump(gs, player)
	case .Jump:
		if player.vel.y >= 0 {
			gs.player_movement_state = .Fall
			player.current_anim_name = "fall"
			switch_animation(player, "fall")
		}
	case .Fall:
		if .Grounded in player.flags {
			gs.player_movement_state = .Idle
			switch_animation(player, "idle")
		}
	}
}

try_run :: proc(gs: ^Game_State, player: ^Entity) {
	if player.vel.x != 0 && .Grounded in player.flags {
		switch_animation(player, "run")
		gs.player_movement_state = .Run
	}
}

try_jump :: proc(gs: ^Game_State, player: ^Entity) {
	if rl.IsKeyPressed(.SPACE) && .Grounded in player.flags {
		player.vel.y = -player.jump_force
		player.flags -= {.Grounded}
		switch_animation(player, "jump")
		gs.player_movement_state = .Jump
	}
}

