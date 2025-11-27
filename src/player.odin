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

