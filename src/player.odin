package main

import "core:math/linalg"
import rl "vendor:raylib"

Player_Movement_State :: enum {
	Uncontrollable,
	Attacking,
	Attack_Cooldown,
	Idle,
	Run,
	Jump,
	Fall,
	Dash,
}

player_update :: proc(gs: ^Game_State, dt: f32) {
	player := entity_get(gs.player_id)

	if player.health <= 0 {
		player_on_death(player, gs)
		return
	}

	// Pause player input while menu is open
	if gs.game_menu_state.menu_type != .None {
		return
	}

	input_x: f32
	if rl.IsKeyDown(.D) do input_x += 1
	if rl.IsKeyDown(.A) do input_x -= 1

	if gs.player_movement_state != .Dash {
		player.vel.x = input_x * player.move_speed
		if player.vel.x > 0 do player.flags -= {.Left}
		if player.vel.x < 0 do player.flags += {.Left}
	}

	if gs.attack_recovery_timer > 0 {
		gs.attack_recovery_timer -= dt
		player.vel *= 0.5
	}

	gs.jump_timer -= dt
	gs.coyote_timer -= dt
	if gs.dash_cooldown_timer > 0 do gs.dash_cooldown_timer -= dt

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
	case .Attack_Cooldown:
		gs.attack_cooldown_timer -= dt
		if gs.attack_cooldown_timer <= 0 {
			gs.player_movement_state = .Idle
		}
		try_run(gs, player)
	case .Idle:
		try_run(gs, player)
		try_jump(gs, player)
		try_attack(gs, player)
		try_activate_checkpoint(gs, player)
		try_dash(gs, player)
	case .Run:
		if input_x == 0 {
			gs.player_movement_state = .Idle
			switch_animation(player, "idle")
		}
		try_jump(gs, player)
		try_attack(gs, player)
		try_dash(gs, player)
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
		try_dash(gs, player)
	case .Fall:
		if .Grounded in player.flags {
			gs.player_movement_state = .Idle
			switch_animation(player, "idle")
		}
		try_attack(gs, player)
		try_dash(gs, player)
	case .Dash:
		gs.dash_timer -= dt
		if gs.dash_timer <= 0 {
			gs.dash_cooldown_timer = DASH_COOLDOWN
			player.flags -= {.Dashing}
			gs.player_movement_state = .Fall
			switch_animation(player, "fall")
		}
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

	// Powerup collection
	for pu, i in gs.level.power_ups {
		rect := Rect{pu.x - 8, pu.y - 8, 16, 16}
		if rl.CheckCollisionRecs(player.collider, rect) {
			gs.collected_power_ups += {pu.type}
			ordered_remove(&gs.level.power_ups, i)
			break
		}
	}

	// Item collection (16-unit radius = 256 squared distance)
	player_center := rect_center(player.collider)
	#reverse for item, i in gs.items {
		if linalg.length2(player_center - item.pos) < 256 {
			inventory_add(gs, item.type, 1)
			ordered_remove(&gs.items, i)
		}
	}

	// Trigger falling logs when player is near rope
	for &falling_log in gs.falling_logs {
		if falling_log.state != .Default do continue

		log_center_x := falling_log.collider.x + falling_log.collider.width / 2
		rope_rect := Rect {
			log_center_x - 1,
			falling_log.collider.y - falling_log.rope_height,
			2,
			falling_log.rope_height,
		}

		if rl.CheckCollisionCircleRec(player_center, FALLING_LOG_TRIGGER_RADIUS, rope_rect) {
			falling_log.state = .Falling
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
		rl.PlaySound(gs.player_jump_sound)
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
		gs.attack_cooldown_timer = ATTACK_COOLDOWN_DURATION
	}
}

try_activate_checkpoint :: proc(gs: ^Game_State, player: ^Entity) {
	if rl.IsKeyPressed(.W) {
		for checkpoint in gs.level.checkpoints {
			rect := rect_from_pos_size(checkpoint.pos, 32)

			if rl.CheckCollisionRecs(rect, player.collider) {
				gs.checkpoint_level_id = gs.level.id
				gs.checkpoint_id = checkpoint.id

				// Auto-save on checkpoint activation
				gs.save_data.level_id = gs.level.id
				gs.save_data.checkpoint_id = checkpoint.id
				gs.save_data.collected_power_ups = gs.collected_power_ups
				save_data_update(gs)
				savefile_save(gs.save_data)

				break
			}
		}
	}
}

try_dash :: proc(gs: ^Game_State, player: ^Entity) {
	if .Dash not_in gs.collected_power_ups do return
	if gs.dash_cooldown_timer > 0 do return
	if !rl.IsMouseButtonPressed(.RIGHT) do return

	input_dir: Vec2
	if rl.IsKeyDown(.W) do input_dir.y -= 1
	if rl.IsKeyDown(.S) do input_dir.y += 1
	if rl.IsKeyDown(.A) do input_dir.x -= 1
	if rl.IsKeyDown(.D) do input_dir.x += 1

	if input_dir == {0, 0} {
		input_dir.x = .Left in player.flags ? -1 : 1
	}

	if input_dir.x != 0 && input_dir.y != 0 {
		input_dir = linalg.normalize(input_dir)
	}

	player.vel = input_dir * DASH_VELOCITY
	player.flags += {.Dashing}
	gs.dash_timer = DASH_DURATION
	gs.player_movement_state = .Dash
	switch_animation(player, "dash")
}

player_on_finish_attack :: proc(gs: ^Game_State, player: ^Entity) {
	switch_animation(player, "idle")
	gs.player_movement_state = .Attack_Cooldown
}

player_attack_sfx :: proc(gs: ^Game_State, player: ^Entity) {
	// Alternate between two swing sounds
	if int(gs.camera.target.x) % 2 == 0 {
		rl.PlaySound(gs.sword_swoosh_sound)
	} else {
		rl.PlaySound(gs.sword_swoosh_sound_2)
	}
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
			a := rect_center(player.collider)
			b := rect_center(e.collider)
			dir := linalg.normalize0(b - a)

			player.vel.x = -dir.x * 500
			player.vel.y = -dir.y * 200 - 100

			gs.attack_recovery_timer = ATTACK_RECOVERY_DURATION

			entity_hit(Entity_Id(i), dir * 500)
			rl.PlaySound(gs.sword_hit_medium_sound)
		}
	}
}

player_on_death :: proc(player: ^Entity, gs: ^Game_State) {
	player := player
	spawn_point := gs.original_spawn_point

	if gs.checkpoint_level_id != 0 && gs.checkpoint_id != 0 {
		if gs.checkpoint_level_id != gs.level.id {
			level_load(gs, gs.checkpoint_level_id, 0)
		}

		for checkpoint in gs.level.checkpoints {
			if checkpoint.id == gs.checkpoint_id {
				spawn_point.x = checkpoint.pos.x
				spawn_point.y = checkpoint.pos.y
				break
			}
		}
	} else {
		level_load(gs, FIRST_LEVEL_ID, 0)
	}

	player = entity_get(gs.player_id)
	player.health = player.max_health
	player.flags -= {.Dead}
	player.x = spawn_point.x
	player.y = spawn_point.y
}
