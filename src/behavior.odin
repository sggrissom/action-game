package main

import "core:math"
import "core:math/rand"

behavior_update :: proc(entities: []Entity, static_colliders: []Rect, dt: f32) {
	for &e in entities {
		if .Dead in e.flags do continue

		if .Walk in e.behaviors {
			if .Left in e.flags {
				e.vel.x = -e.move_speed
			} else {
				e.vel.x = e.move_speed
			}
		}

		if .Flip_At_Wall in e.behaviors {
			if .Left in e.flags {
				if _, ok := raycast(
					{e.x + e.width / 2, e.y + e.height / 2},
					{-e.width / 2 - COLLISION_EPSILON, 0},
					static_colliders,
				); ok {
					e.flags -= {.Left}
					e.vel.x = 0
				}
			} else {
				if _, ok := raycast(
					{e.x + e.width / 2, e.y + e.height / 2},
					{e.width / 2 + COLLISION_EPSILON, 0},
					static_colliders,
				); ok {
					e.flags += {.Left}
					e.vel.x = 0
				}
			}
		}

		if .Flip_At_Edge in e.behaviors && .Grounded in e.flags {
			if .Left in e.flags {
				start := Vec2{e.x, e.y + e.height / 2}
				magnitude := Vec2{0, e.height / 2 + COLLISION_EPSILON}
				if _, ok := raycast(start, magnitude, static_colliders); !ok {
					e.flags -= {.Left}
					e.vel.x = 0
				}
			} else {
				start := Vec2{e.x + e.width, e.y + e.height / 2}
				magnitude := Vec2{0, e.height / 2 + COLLISION_EPSILON}
				if _, ok := raycast(start, magnitude, static_colliders); !ok {
					e.flags += {.Left}
					e.vel.x = 0
				}

			}
		}

		if .Hop in e.behaviors {
			e.hop_timer -= dt

			if e.hop_timer <= 0 && .Grounded in e.flags {
				// Hop in facing direction
				direction: f32 = .Left in e.flags ? -1.0 : 1.0
				e.vel.x = direction * HOP_HORIZONTAL_SPEED
				e.vel.y = UP.y * HOP_FORCE

				// Reset timer with random interval
				e.hop_timer = rand.float32_range(HOP_INTERVAL_MIN, HOP_INTERVAL_MAX)
			}
		}

		if .Charge_At_Player in e.behaviors {
			if e.is_charging {
				e.charge_timer -= dt
				if e.charge_timer <= 0 {
					e.is_charging = false
					e.charge_cooldown_timer = CHARGE_COOLDOWN
				}
			} else {
				e.charge_cooldown_timer -= dt

				// Check if player in range
				if e.charge_cooldown_timer <= 0 {
					player := entity_get(gs.player_id)
					if player != nil {
						player_center := Vec2{player.x + player.width / 2, player.y + player.height / 2}
						enemy_center := Vec2{e.x + e.width / 2, e.y + e.height / 2}
						dx := player_center.x - enemy_center.x
						dy := player_center.y - enemy_center.y
						dist := math.sqrt(dx * dx + dy * dy)

						if dist < CHARGE_DETECTION_RANGE {
							e.is_charging = true
							e.charge_timer = CHARGE_DURATION
							// Face toward player
							if dx < 0 {
								e.flags += {.Left}
							} else {
								e.flags -= {.Left}
							}
						}
					}
				}
			}

			// Override walk speed when charging
			if e.is_charging {
				if .Left in e.flags {
					e.vel.x = -CHARGE_SPEED
				} else {
					e.vel.x = CHARGE_SPEED
				}
			}
		}
	}
}
