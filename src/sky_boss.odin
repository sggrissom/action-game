package main

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

// Boss state machine
Boss_State :: enum {
	Searching,
	Hovering,
	Swooping,
	Breath_Attack,
	Retreating,
}

// File-private state variables
@(private = "file")
boss_state: Boss_State = .Searching

@(private = "file")
state_timer: f32 = 0

@(private = "file")
attack_timer: f32 = 0

@(private = "file")
arena_bounds: Rect

@(private = "file")
swoop_target: Vec2

@(private = "file")
orbs_fired: int = 0

// Constants
BOSS_HOVER_SPEED :: 120
BOSS_SWOOP_SPEED :: 400
BOSS_RETREAT_SPEED :: 200
BOSS_HOVER_HEIGHT :: 48 // Distance from ceiling
BOSS_SEARCH_DURATION :: 2.0
BOSS_HOVER_DURATION :: 0.5
BOSS_BREATH_DURATION :: 2.0
BOSS_ORB_INTERVAL :: 0.4
BOSS_ORBS_PER_ATTACK :: 5

sky_boss_update :: proc(self: ^Entity, gs: ^Game_State, dt: f32) {
	player := entity_get(gs.player_id)
	if player == nil || .Dead in player.flags {
		return
	}

	boss_center := Vec2{self.x + self.width / 2, self.y + self.height / 2}
	player_center := Vec2{player.x + player.width / 2, player.y + player.height / 2}

	// Update facing direction based on player position
	if player_center.x < boss_center.x {
		self.flags += {.Left}
	} else {
		self.flags -= {.Left}
	}

	switch boss_state {
	case .Searching:
		// Hover at ceiling, track player horizontally
		target_y := arena_bounds.y + BOSS_HOVER_HEIGHT
		target_x := clamp(
			player_center.x - self.width / 2,
			arena_bounds.x,
			arena_bounds.x + arena_bounds.width - self.width,
		)

		// Move toward target position
		diff := Vec2{target_x, target_y} - Vec2{self.x, self.y}
		if linalg.length(diff) > 1 {
			self.vel = linalg.normalize(diff) * BOSS_HOVER_SPEED
		} else {
			self.vel = 0
		}

		// Add hovering bob motion
		self.vel.y += math.sin(state_timer * 4) * 20

		state_timer += dt
		if state_timer >= BOSS_SEARCH_DURATION {
			// Pick attack type
			if rand.float32() < 0.5 {
				// Swoop attack
				boss_state = .Swooping
				swoop_target = player_center
			} else {
				// Breath attack
				boss_state = .Breath_Attack
				orbs_fired = 0
				attack_timer = 0
			}
			state_timer = 0
		}

	case .Swooping:
		// Dive toward player position
		diff := swoop_target - boss_center
		if linalg.length(diff) > 20 {
			self.vel = linalg.normalize(diff) * BOSS_SWOOP_SPEED
		} else {
			// Reached target, start retreating
			boss_state = .Retreating
			state_timer = 0
		}

		// Safety check - retreat if taking too long
		state_timer += dt
		if state_timer > 2.0 {
			boss_state = .Retreating
			state_timer = 0
		}

	case .Breath_Attack:
		// Hover in place while firing orbs
		target_y := arena_bounds.y + BOSS_HOVER_HEIGHT
		diff_y := target_y - self.y
		self.vel.x = 0
		self.vel.y = diff_y * 2 + math.sin(state_timer * 4) * 15

		attack_timer += dt
		state_timer += dt

		// Fire orbs at intervals
		if attack_timer >= BOSS_ORB_INTERVAL && orbs_fired < BOSS_ORBS_PER_ATTACK {
			// Spawn projectile aimed at player
			spawn_pos := boss_center + Vec2{0, self.height / 4}
			spawn_projectile(spawn_pos, player_center, 250, 12, 2, rl.PURPLE)
			orbs_fired += 1
			attack_timer = 0
		}

		if state_timer >= BOSS_BREATH_DURATION {
			boss_state = .Retreating
			state_timer = 0
		}

	case .Retreating:
		// Fly back up to ceiling
		target_y := arena_bounds.y + BOSS_HOVER_HEIGHT
		target_x := arena_bounds.x + arena_bounds.width / 2 - self.width / 2

		diff := Vec2{target_x, target_y} - Vec2{self.x, self.y}
		if linalg.length(diff) > 10 {
			self.vel = linalg.normalize(diff) * BOSS_RETREAT_SPEED
		} else {
			// Reached ceiling, hover briefly
			boss_state = .Hovering
			state_timer = 0
		}

	case .Hovering:
		// Brief pause at ceiling
		self.vel = Vec2{0, math.sin(state_timer * 4) * 15}

		state_timer += dt
		if state_timer >= BOSS_HOVER_DURATION {
			boss_state = .Searching
			state_timer = 0
		}
	}

	// Apply velocity to position (since Kinematic skips normal physics)
	self.x += self.vel.x * dt
	self.y += self.vel.y * dt

	// Keep boss within arena bounds
	self.x = clamp(self.x, arena_bounds.x, arena_bounds.x + arena_bounds.width - self.width)
	self.y = clamp(self.y, arena_bounds.y, arena_bounds.y + arena_bounds.height - self.height)
}

sky_boss_init :: proc(gs: ^Game_State, bounds: Rect) {
	arena_bounds = bounds
	boss_state = .Searching
	state_timer = 0
	attack_timer = 0
	orbs_fired = 0
}

boss_arena_on_enter :: proc(gs: ^Game_State) {
	sky_boss_init(gs, rect_from_pos_size(gs.level.pos, gs.level.size))
}
