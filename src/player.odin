package main

import rl "vendor:raylib"

Player_Movement_State :: enum {
	Uncontrollable,
	Attacking,
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

	gs.jump_timer -= dt
	gs.coyote_timer -= dt

	switch gs.player_movement_state {
	case .Uncontrollable:
		gs.safe_reset_timer -= dt
		player.vel.x = 0
		player.vel.y = 0
		if gs.safe_reset_timer <= 0 {
			switch_animation(player, "idle")
			gs.player_movement_state = .Idle
		}
	case .Attacking:
		if .Grounded in player.flags {
			player.vel.x = 0
		}
	case .Idle:
		try_run(gs, player)
		try_jump(gs, player)
		try_attack(gs, player)
	case .Run:
		if input_x == 0 {
			gs.player_movement_state = .Idle
			switch_animation(player, "idle")
		}
		try_jump(gs, player)
		try_attack(gs, player)
	case .Jump:
		if rl.IsKeyReleased(.SPACE) {
			player.vel.y *= 0.5
		}

		if player.vel.y >= 0 {
			gs.player_movement_state = .Fall
			player.current_anim_name = "fall"
			switch_animation(player, "fall")
		}
		try_attack(gs, player)
	case .Fall:
		if .Grounded in player.flags {
			gs.player_movement_state = .Idle
			switch_animation(player, "idle")
		}
		try_attack(gs, player)
	}

	// Spike collision - reset to safe position
	for spike in gs.level.spikes {
		if rl.CheckCollisionRecs(rect_pos_add(spike.collider, gs.level.pos), player.collider) {
			player.x = gs.safe_position.x
			player.y = gs.safe_position.y
			player.vel = 0
			gs.safe_reset_timer = PLAYER_SAFE_RESET_TIME
			gs.player_movement_state = .Uncontrollable
			switch_animation(player, "idle")
			break
		}
	}

	{
		overlap := rl.GetCollisionRec(
			player.collider,
			rect_from_pos_size(gs.level.pos, gs.level.size),
		)
		if overlap.width == 0 && overlap.height == 0 {
			for l in gs.levels {
				if rl.CheckCollisionRecs(player.collider, rect_from_pos_size(l.pos, l.size)) {
					overlap = rl.GetCollisionRec(
						player.collider,
						rect_from_pos_size(l.pos, l.size),
					)
					level_load(gs, l.id, Vec2{overlap.x, overlap.y})
					break
				}
			}
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
	if rl.IsKeyPressed(.SPACE) {
		gs.jump_timer = JUMP_TIME
	}

	if .Grounded in player.flags {
		gs.coyote_timer = COYOTE_TIME
	}

	if gs.player_movement_state != .Fall && gs.coyote_timer > 0 && gs.jump_timer > 0 {
		player.vel.y = -player.jump_force
		player.flags -= {.Grounded}
		switch_animation(player, "jump")
		gs.player_movement_state = .Jump
	}
}

try_attack :: proc(gs: ^Game_State, player: ^Entity) {
	if rl.IsMouseButtonPressed(.LEFT) {
		switch_animation(player, "attack")
		gs.player_movement_state = .Attacking
	}
}

player_on_finish_attack :: proc(gs: ^Game_State, player: ^Entity) {
	switch_animation(player, "idle")
	gs.player_movement_state = .Fall
}

player_attack_callback :: proc(gs: ^Game_State, player: ^Entity) {
	center := Vec2{player.x, player.y}
	center += {.Left in player.flags ? -30 + player.collider.width : 30, 20}

	for &e, i in gs.entities {
		id := Entity_Id(i)
		if id == gs.player_id do continue
		if .Dead in e.flags do continue
		if .Immortal in e.flags do continue

		if rl.CheckCollisionCircleRec(center, 25, e.collider) {
			entity_damage(Entity_Id(i), 1)
		}
	}
}
