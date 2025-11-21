package main

import rl "vendor:raylib"

physics_update :: proc(entities: []Entity, static_colliders: []Rect, dt: f32) {
	for &entity in entities {
		if entity.is_dead do continue

		for _ in 0 ..< PHYSICS_ITERATIONS {
			step := dt / PHYSICS_ITERATIONS
			entity.vel.y += GRAVITY
			if entity.vel.y > TERMINAL_VELOCITY {
				entity.vel.y = TERMINAL_VELOCITY
			}

			entity.y += entity.vel.y * step
			entity.is_grounded = false
			for static in static_colliders {
				if rl.CheckCollisionRecs(entity.collider, static) {
					if entity.vel.y > 0 {
						entity.y = static.y - entity.height
						entity.is_grounded = true
					} else {
						entity.y = static.y + static.height
					}
					entity.vel.y = 0
					break
				}
			}

			entity.x += entity.vel.x * step
			for static in static_colliders {
				if rl.CheckCollisionRecs(entity.collider, static) {
					if entity.vel.x > 0 {
						entity.x = static.x - entity.width
					} else {
						entity.x = static.x + static.width
					}
					entity.vel.x = 0
					break
				}
			}
		}
	}
}
