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
