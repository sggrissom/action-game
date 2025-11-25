package main

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

entity_update :: proc(entities: []Entity, dt: f32) {
	for &e in entities {
		if e.health == 0 && .Immortal not_in e.flags {
			e.flags += {.Dead}
		}

		if len(e.animations) > 0 {
			anim := e.animations[e.current_anim_name]

			e.animation_timer -= dt
			if e.animation_timer <= 0 {
				e.current_anim_frame += 1

				if e.current_anim_frame > anim.end {
					e.current_anim_frame = anim.start
				}

				e.animation_timer = anim.time
			}
		}
	}
}

switch_animation :: proc(entity: ^Entity, name: string) {
	entity.current_anim_name = name
	anim := entity.animations[name]
	entity.animation_timer = anim.time
	entity.current_anim_frame = anim.start
}

