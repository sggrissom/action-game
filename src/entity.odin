package main

import "core:math/rand"

entity_create :: proc(entity: Entity) -> Entity_Id {
	for &e, i in gs.entities {
		if .Dead in e.flags {
			e = entity
			e.flags -= {.Dead}
			return Entity_Id(i)
		}
	}

	index := len(gs.entities)
	append(&gs.entities, entity)

	return Entity_Id(index)
}

entity_get :: proc(id: Entity_Id) -> ^Entity {
	if int(id) >= len(gs.entities) {
		return nil
	}
	return &gs.entities[int(id)]
}

entity_update :: proc(gs: ^Game_State, dt: f32) {
	for &e in gs.entities {
		if e.health <= 0 && .Immortal not_in e.flags && .Dead not_in e.flags {
			e.flags += {.Dead}

			if e.on_death != nil {
				e.on_death(&e, gs)
			}

			if e.definition != nil {
				for drop in e.definition.drops {
					if rand.float32() <= drop.chance {
						count := rand.int_max(drop.range[1] + 1 - drop.range[0]) + drop.range[0]
						for _ in 0 ..< count {
							spawn_pos := Vec2{e.x + e.width / 2, e.y + e.height - 8}
							item_spawn(gs, drop.type, spawn_pos)
						}
					}
				}
			}
		}

		if len(e.animations) > 0 {
			anim := e.animations[e.current_anim_name]

			if e.hit_timer > 0 {
				e.hit_timer -= dt
				if e.hit_timer <= 0 {
					#partial switch e.hit_response {
					case .Stop:
						e.behaviors += {.Walk}
						e.flags -= {.Frozen}
					}
				}
			}

			if .Frozen not_in e.flags {
				e.animation_timer -= dt
			}
			if e.animation_timer <= 0 {
				e.current_anim_frame += 1
				e.animation_timer = anim.time

				if .Loop in anim.flags {
					if e.current_anim_frame > anim.end {
						e.current_anim_frame = anim.start
					}
				} else {
					if e.current_anim_frame > anim.end {
						e.current_anim_frame -= 1
						if anim.on_finish != nil {
							anim.on_finish(gs, &e)
						}
					}
				}
			}

			for &event in anim.timed_events {
				if event.timer > 0 {
					event.timer -= dt
					if event.timer <= 0 {
						event.callback(gs, &e)
					}
				}
			}
		}
	}
}

switch_animation :: proc(entity: ^Entity, name: string) {
	entity.current_anim_name = name
	anim := &entity.animations[name]
	entity.animation_timer = anim.time
	entity.current_anim_frame = anim.start

	for &event in anim.timed_events {
		event.timer = event.duration
	}
}

entity_damage :: proc(id: Entity_Id, amount: int) {
	entity := entity_get(id)
	entity.health -= amount
}

entity_hit :: proc(id: Entity_Id, hit_force := Vec2{}) {
	entity := entity_get(id)
	entity.hit_timer = entity.hit_duration

	switch entity.hit_response {
	case .Stop:
		entity.behaviors -= {.Walk}
		entity.flags += {.Frozen}
		entity.vel = 0
	case .Knockback:
		entity.vel += hit_force
	}
}
