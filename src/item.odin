package main

item_src :: proc(type: Item_Type) -> Vec2 {
	src: Vec2
	#partial switch type {
	case .Item_A:
		src.x = 0
	case .Item_B:
		src.x = 16
	case .Item_C:
		src.x = 32
	}
	return src
}

item_spawn :: proc(gs: ^Game_State, type: Item_Type, pos: Vec2) {
	src := item_src(type)
	append(&gs.items, Item{type = type, src = src, pos = pos})
}

inventory_add :: proc(gs: ^Game_State, type: Item_Type, count: int) {
	for &slot in gs.inventory {
		if slot.item_type == type {
			slot.count += count
			return
		}
	}

	append(&gs.inventory, Inventory_Slot{item_type = type, count = count})
}
