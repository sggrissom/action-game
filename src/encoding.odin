package main

import "core:bytes"
import "core:mem"
import "core:os"

import "base:runtime"

World_Data_Header :: struct {
	magic:         u32,
	version_major: u32,
	version_minor: u32,
	version_patch: u32,
	level_count:   u32,
	tileset_count: u32,
}

World_Data_Tileset_Header :: struct {}

World_Data_Level_Header :: struct {
	magic:  u32,
	id:     u32,
	x:      i32,
	y:      i32,
	width:  u32,
	height: u32,
}

LEVEL_MAGIC :: 0xBEBAFECA
HEADER_MAGIC :: 0x57475650

world_data_save :: proc() {
	b := bytes.Buffer {
		buf = make([dynamic]u8, context.temp_allocator),
	}

	header := World_Data_Header {
		magic         = HEADER_MAGIC,
		version_major = 0,
		version_minor = 5,
		version_patch = 0,
		level_count   = u32(len(gs.levels)),
		tileset_count = 0,
	}

	bytes.buffer_write_ptr(&b, &header, size_of(World_Data_Header))

	for level in gs.levels {
		size_in_tiles := coords_from_pos(level.size)
		pos_in_tiles := coords_from_pos(level.pos)
		level_header := World_Data_Level_Header {
			magic  = LEVEL_MAGIC,
			id     = level.id,
			x      = i32(pos_in_tiles.x),
			y      = i32(pos_in_tiles.y),
			width  = u32(size_in_tiles.x),
			height = u32(size_in_tiles.y),
		}

		bytes.buffer_write_ptr(&b, &level_header, size_of(level_header))

		tiles := make([]u8, level_header.width * level_header.height, context.temp_allocator)

		for tile in level.tiles {
			coords := coords_from_pos(tile.pos - level.pos)
			tiles[u32(coords.y) * level_header.width + u32(coords.x)] = 1
		}

		bytes.buffer_write(&b, tiles)

		// Write enemy spawns
		enemy_count := u32(len(level.enemy_spawns))
		bytes.buffer_write_ptr(&b, &enemy_count, size_of(u32))

		for spawn in level.enemy_spawns {
			enemy_type := u8(spawn.type)
			bytes.buffer_write_ptr(&b, &enemy_type, size_of(u8))
			x := spawn.pos.x
			y := spawn.pos.y
			bytes.buffer_write_ptr(&b, &x, size_of(f32))
			bytes.buffer_write_ptr(&b, &y, size_of(f32))
		}

		// Write spikes
		spike_count := u32(len(level.spikes))
		bytes.buffer_write_ptr(&b, &spike_count, size_of(u32))

		for spike in level.spikes {
			facing := u8(spike.facing)
			bytes.buffer_write_ptr(&b, &facing, size_of(u8))
			x := spike.collider.x
			y := spike.collider.y
			w := spike.collider.width
			h := spike.collider.height
			bytes.buffer_write_ptr(&b, &x, size_of(f32))
			bytes.buffer_write_ptr(&b, &y, size_of(f32))
			bytes.buffer_write_ptr(&b, &w, size_of(f32))
			bytes.buffer_write_ptr(&b, &h, size_of(f32))
		}

		// Write falling log spawns
		log_count := u32(len(level.falling_log_spawns))
		bytes.buffer_write_ptr(&b, &log_count, size_of(u32))

		for spawn in level.falling_log_spawns {
			x := spawn.rect.x
			y := spawn.rect.y
			w := spawn.rect.width
			h := spawn.rect.height
			bytes.buffer_write_ptr(&b, &x, size_of(f32))
			bytes.buffer_write_ptr(&b, &y, size_of(f32))
			bytes.buffer_write_ptr(&b, &w, size_of(f32))
			bytes.buffer_write_ptr(&b, &h, size_of(f32))
		}

		// Write checkpoints
		checkpoint_count := u32(len(level.checkpoints))
		bytes.buffer_write_ptr(&b, &checkpoint_count, size_of(u32))

		for checkpoint in level.checkpoints {
			id := checkpoint.id
			x := checkpoint.pos.x
			y := checkpoint.pos.y
			bytes.buffer_write_ptr(&b, &id, size_of(u32))
			bytes.buffer_write_ptr(&b, &x, size_of(f32))
			bytes.buffer_write_ptr(&b, &y, size_of(f32))
		}
	}

	if !os.write_entire_file("data/world.dat", bytes.buffer_to_bytes(&b)) {
		panic("Failed to write world file")
	}
}

world_data_load :: proc() {
	data, ok := os.read_entire_file("data/world.dat", context.temp_allocator)
	if !ok {
		panic("Failed to read world file")
	}

	header: World_Data_Header

	r: bytes.Reader
	bytes.reader_init(&r, data)

	n_header, err_header := bytes.reader_read(&r, mem.any_to_bytes(header))
	assert(n_header == size_of(World_Data_Header) && err_header == nil)

	assert(header.magic == HEADER_MAGIC)

	for _ in 0 ..< header.level_count {
		level: Level
		level_header: World_Data_Level_Header
		n, err := bytes.reader_read(&r, mem.any_to_bytes(level_header))

		assert(err == nil)
		assert(n == size_of(World_Data_Level_Header))
		assert(level_header.magic == LEVEL_MAGIC)

		level.id = level_header.id
		level.pos = pos_from_coords({level_header.x, level_header.y})
		level.size = pos_from_coords({i32(level_header.width), i32(level_header.height)})

		for y in 0 ..< level_header.height {
			for x in 0 ..< level_header.width {
				tile_type_index: u8
				bytes.reader_read(&r, mem.any_to_bytes(tile_type_index))
				if tile_type_index > 0 {
					pos := level.pos + pos_from_coords({i32(x), i32(y)})
					append(&level.tiles, Tile{pos = pos})
				}
			}
		}

		for &tile in level.tiles {
			tile.neighbors = autotile_calculate_neighbors(coords_from_pos(tile.pos), &level)
		}

		// Read enemy spawns (version 0.2+)
		if header.version_minor >= 2 {
			enemy_count: u32
			bytes.reader_read(&r, mem.any_to_bytes(enemy_count))

			for _ in 0 ..< enemy_count {
				enemy_type: u8
				x, y: f32
				bytes.reader_read(&r, mem.any_to_bytes(enemy_type))
				bytes.reader_read(&r, mem.any_to_bytes(x))
				bytes.reader_read(&r, mem.any_to_bytes(y))

				append(
					&level.enemy_spawns,
					Enemy_Spawn{type = Enemy_Type(enemy_type), pos = Vec2{x, y}},
				)
			}
		}

		// Read spikes (version 0.3+)
		if header.version_minor >= 3 {
			spike_count: u32
			bytes.reader_read(&r, mem.any_to_bytes(spike_count))

			for _ in 0 ..< spike_count {
				facing: u8
				x, y, w, h: f32
				bytes.reader_read(&r, mem.any_to_bytes(facing))
				bytes.reader_read(&r, mem.any_to_bytes(x))
				bytes.reader_read(&r, mem.any_to_bytes(y))
				bytes.reader_read(&r, mem.any_to_bytes(w))
				bytes.reader_read(&r, mem.any_to_bytes(h))

				append(&level.spikes, Spike{collider = {x, y, w, h}, facing = Direction(facing)})
			}
		}

		// Read falling log spawns (version 0.4+)
		if header.version_minor >= 4 {
			log_count: u32
			bytes.reader_read(&r, mem.any_to_bytes(log_count))

			for _ in 0 ..< log_count {
				x, y, w, h: f32
				bytes.reader_read(&r, mem.any_to_bytes(x))
				bytes.reader_read(&r, mem.any_to_bytes(y))
				bytes.reader_read(&r, mem.any_to_bytes(w))
				bytes.reader_read(&r, mem.any_to_bytes(h))

				append(&level.falling_log_spawns, Falling_Log_Spawn{rect = {x, y, w, h}})
			}
		}

		// Read checkpoints (version 0.5+)
		if header.version_minor >= 5 {
			checkpoint_count: u32
			bytes.reader_read(&r, mem.any_to_bytes(checkpoint_count))

			for _ in 0 ..< checkpoint_count {
				id: u32
				x, y: f32
				bytes.reader_read(&r, mem.any_to_bytes(id))
				bytes.reader_read(&r, mem.any_to_bytes(x))
				bytes.reader_read(&r, mem.any_to_bytes(y))

				append(&level.checkpoints, Checkpoint{id = id, pos = {x, y}})
			}
		}

		recreate_colliders(level.pos, &gs.colliders, level.tiles[:])

		level.player_spawn = Vec2{100, 100}
		append(&gs.levels, level)
	}
}
