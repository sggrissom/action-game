package main

import "core:time"
import rl "vendor:raylib"

physics_update :: proc(entities: []Entity, static_colliders: []Rect, dt: f32) {
	for &entity, e_id in entities {
		entity_id := Entity_Id(e_id)

		if .Dead in entity.flags do continue

		if .Kinematic not_in entity.flags {
			for _ in 0 ..< PHYSICS_ITERATIONS {
				step := dt / PHYSICS_ITERATIONS
				entity.vel.y += GRAVITY
				if entity.vel.y > TERMINAL_VELOCITY {
					entity.vel.y = TERMINAL_VELOCITY
				}

				// Y axis
				entity.y += entity.vel.y * step
				entity.flags -= {.Grounded}
				for static in static_colliders {
					if rl.CheckCollisionRecs(entity.collider, static) {
						if entity.vel.y > 0 {
							entity.y = static.y - entity.height
							entity.flags += {.Grounded}
						} else {
							entity.y = static.y + static.height
						}
						entity.vel.y = 0
						break
					}
				}

				// X axis
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

		// Collisions
		for &other, o_id in entities {
			other_id := Entity_Id(o_id)
			if entity_id == other_id do continue

			if rl.CheckCollisionRecs(entity, other.collider) {
				if entity_id not_in other.entity_ids {
					other.entity_ids[entity_id] = time.now()

					if other.on_enter != nil {
						other.on_enter(other_id, entity_id)
					}
				} else {
					if other.on_stay != nil {
						other.on_stay(other_id, entity_id)
					}
				}
			} else if entity_id in other.entity_ids {
				if other.on_exit != nil {
					other.on_exit(other_id, entity_id)
				}
				delete_key(&other.entity_ids, entity_id)
			}
		}
	}
}

COLLISION_EPSILON :: 0.01

raycast :: proc(
	start, magnitude: Vec2,
	targets: []Rect,
	allocator := context.temp_allocator,
) -> (
	hits: []Vec2,
	ok: bool,
) {
	hit_store := make([dynamic]Vec2, allocator)

	for t in targets {
		p, q, r, s: Vec2 =
			{t.x, t.y},
			{t.x, t.y + t.height},
			{t.x + t.width, t.y + t.height},
			{t.x + t.width, t.y}
		lines := [4][2]Vec2{{p, q}, {q, r}, {r, s}, {s, p}}
		for line in lines {
			point: Vec2
			if rl.CheckCollisionLines(start, start + magnitude, line[0], line[1], &point) {
				append(&hit_store, point)
			}
		}

		color := len(hit_store) > 0 ? rl.GREEN : rl.YELLOW
		debug_draw_line(start, start + magnitude, 1, color)
	}

	return hit_store[:], len(hit_store) > 0
}

