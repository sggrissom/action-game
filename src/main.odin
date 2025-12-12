#+feature dynamic-literals
package main

import "core:log"
import "core:slice"
import "core:strings"
import "core:time"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
RENDER_WIDTH :: 640
RENDER_HEIGHT :: 360
ZOOM :: WINDOW_WIDTH / RENDER_WIDTH
BG_COLOR :: rl.Color{50, 44, 67, 255}
TILE_SIZE :: 16
PHYSICS_ITERATIONS :: 8
GRAVITY :: 5
TERMINAL_VELOCITY :: 1200
SPIKE_BREADTH :: 16
SPIKE_DEPTH :: 12
SPIKE_DIFF :: TILE_SIZE - SPIKE_DEPTH
UP :: Vec2{0, -1}
RIGHT :: Vec2{1, 0}
DOWN :: Vec2{0, 1}
LEFT :: Vec2{-1, 0}
JUMP_TIME :: 0.2
COYOTE_TIME :: 0.15
ATTACK_COOLDOWN_DURATION :: 0.3
ATTACK_RECOVERY_DURATION :: 0.2

PLAYER_SAFE_RESET_TIME :: 1
FIRST_LEVEL_ID :: 1

FALLING_LOG_WIDTH :: 48
FALLING_LOG_HEIGHT :: 32
FALLING_LOG_ROPE_HEIGHT :: 64
FALLING_LOG_SPEED :: 600
FALLING_LOG_TRIGGER_RADIUS :: 25

Vec2 :: rl.Vector2
Vec4 :: rl.Vector4
Rect :: rl.Rectangle
Vec2i :: [2]i32
Entity_Id :: distinct int

Entity_Flags :: enum {
	Grounded,
	Dead,
	Kinematic,
	Debug_Draw,
	Left,
	Immortal,
	Frozen,
}

Entity_Behaviors :: enum {
	Walk,
	Flip_At_Wall,
	Flip_At_Edge,
}

Direction :: enum {
	Up,
	Right,
	Down,
	Left,
}

Scene_Type :: enum {
	Main_Menu,
	Game,
}

Tile :: struct {
	pos:       Vec2,
	src:       Vec2,
	neighbors: Tile_Neighbors,
	f:         u8,
}

Spike :: struct {
	collider: Rect,
	facing:   Direction,
}

Enemy_Type :: enum {
	Walker,
	Jumper,
	Charger,
	Orb,
}

Entity_Hit_Response :: enum {
	Stop,
	Knockback,
}

Enemy_Spawn :: struct {
	type: Enemy_Type,
	pos:  Vec2,
}

Falling_Log_Spawn :: struct {
	rect: Rect,
}

Falling_Log_State :: enum {
	Default,
	Falling,
	Settled,
}

Falling_Log :: struct {
	collider:    Rect,
	rope_height: f32,
	state:       Falling_Log_State,
}

Checkpoint :: struct {
	id:  u32,
	pos: Vec2,
}

Power_Up_Spawn :: struct {
	type: Power_Up_Type,
	pos:  Vec2,
}

Power_Up_Type :: enum {
	Dash,
}

Door :: struct {
	rect: Rect,
}

Level :: struct {
	id:                 u32,
	pos:                Vec2,
	size:               Vec2,
	player_spawn:       Maybe(Vec2),
	name:               string,
	enemy_spawns:       [dynamic]Enemy_Spawn,
	falling_log_spawns: [dynamic]Falling_Log_Spawn,
	doors:              [dynamic]Door,
	spikes:             [dynamic]Spike,
	checkpoints:        [dynamic]Checkpoint,
	tiles:              [dynamic]Tile,
	on_enter:           proc(gs: ^Game_State),
}

Entity :: struct {
	using collider:             Rect,
	vel:                        Vec2,
	move_speed:                 f32,
	jump_force:                 f32,
	on_enter, on_stay, on_exit: proc(self_id, other_id: Entity_Id),
	on_death:                   proc(entity: ^Entity, gs: ^Game_State),
	entity_ids:                 map[Entity_Id]time.Time,
	flags:                      bit_set[Entity_Flags],
	debug_color:                rl.Color,
	behaviors:                  bit_set[Entity_Behaviors],
	health:                     int,
	max_health:                 int,
	on_hit_damage:              int,
	texture:                    ^rl.Texture,
	animations:                 map[string]Animation,
	current_anim_name:          string,
	current_anim_frame:         int,
	animation_timer:            f32,
	hit_timer:                  f32,
	hit_duration:               f32,
	hit_response:               Entity_Hit_Response,
}

Game_State :: struct {
	player_id:             Entity_Id,
	safe_position:         Vec2,
	safe_reset_timer:      f32,
	player_movement_state: Player_Movement_State,
	camera:                rl.Camera2D,
	entities:              [dynamic]Entity,
	falling_logs:          [dynamic]Falling_Log,
	debug_shapes:          [dynamic]Debug_Shape,
	colliders:             [dynamic]Rect,
	player_texture:        rl.Texture,
	item_texture:          rl.Texture,
	tileset_texture:       rl.Texture,
	scene:                 Scene_Type,
	font_18:               rl.Font,
	font_48:               rl.Font,
	font_64:               rl.Font,
	level:                 ^Level,
	levels:                [dynamic]Level,
	checkpoint_level_id:   u32,
	checkpoint_id:         u32,
	editor_enabled:        bool,
	jump_timer:            f32,
	coyote_timer:          f32,
	enemy_definitions:     map[Enemy_Type]Enemy_Def,
	debug_draw_enabled:    bool,
	attack_cooldown_timer: f32,
	attack_recovery_timer: f32,
}

Save_Data :: struct {
	level_id:          u32,
	checkpoint_id:     u32,
	visited_level_ids: [dynamic]u32,
}

Animation :: struct {
	size:           Vec2,
	offset:         Vec2,
	offset_flipped: Vec2,
	start:          int,
	end:            int,
	row:            int,
	time:           f32,
	flags:          bit_set[Animation_Flags],
	on_finish:      proc(gs: ^Game_State, entity: ^Entity),
	timed_events:   [dynamic]Animation_Event,
}

Animation_Flags :: enum {
	Loop,
	Ping_Pong,
}

Animation_Event :: struct {
	timer:    f32,
	duration: f32,
	callback: proc(gs: ^Game_State, entity: ^Entity),
}

Enemy_Def :: struct {
	collider_size:       Vec2,
	move_speed:          f32,
	behaviors:           bit_set[Entity_Behaviors],
	health:              int,
	on_hit_damage:       int,
	texture:             rl.Texture2D,
	animations:          map[string]Animation,
	initial_animation:   string,
	hit_response:        Entity_Hit_Response,
	hit_duration:        f32,
	hit_knockback_force: f32,
}

player_on_enter :: proc(self_id, other_id: Entity_Id) {
	player := entity_get(self_id)
	other := entity_get(other_id)

	if other.on_hit_damage > 0 {
		player.health -= other.on_hit_damage
	}
}

level_load :: proc(gs: ^Game_State, id: u32, player_spawn: Vec2) {
	level := level_from_id(gs.levels[:], id)
	if level == nil {
		log.fatalf("Level with id `%d` could not be found.", id)
	}
	gs.level = level

	player := entity_get(gs.player_id)
	player_anim_name: string
	player_health: int
	player_vel: Vec2

	if player != nil {
		player_anim_name = strings.clone(player.current_anim_name, context.temp_allocator)
		player_health = player.health
		player_vel = player.vel
	}

	clear(&gs.entities)

	spawn_player(gs, player_spawn)
	spawn_enemies(gs)

	// Spawn falling logs from level spawns
	clear(&gs.falling_logs)
	for spawn in gs.level.falling_log_spawns {
		log_collider := rect_pos_add(spawn.rect, level.pos)
		log_center_x := log_collider.x + log_collider.width / 2

		// Find ceiling above the log by checking tiles
		rope_height: f32 = FALLING_LOG_ROPE_HEIGHT
		ceiling_y: f32 = log_collider.y - 1000 // Default far above

		for tile in level.tiles {
			tile_bottom := tile.pos.y + TILE_SIZE
			// Check if tile is above log and horizontally aligned
			if tile_bottom <= log_collider.y &&
			   tile.pos.x <= log_center_x &&
			   tile.pos.x + TILE_SIZE >= log_center_x {
				// Find the lowest ceiling (closest to the log)
				if tile_bottom > ceiling_y {
					ceiling_y = tile_bottom
				}
			}
		}

		// Calculate rope height from ceiling to log top
		if ceiling_y > log_collider.y - 1000 {
			rope_height = log_collider.y - ceiling_y
		}

		append(&gs.falling_logs, Falling_Log {
			collider    = log_collider,
			rope_height = rope_height,
			state       = .Default,
		})
	}

	if player_anim_name != "" {
		player = entity_get(gs.player_id)
		player.health = player_health
		for k in player.animations {
			if k == player_anim_name {
				player.current_anim_name = k
			}
		}
		player.vel = player_vel
	}

	recreate_colliders(level.pos, &gs.colliders, level.tiles[:])
	autotile_run(level)

	if level.on_enter != nil {
		level.on_enter(gs)
	}

}

spawn_player :: proc(gs: ^Game_State, player_spawn: Vec2) {
	player_anim_idle := Animation {
		size           = {120, 80},
		offset         = {52, 42},
		offset_flipped = {52, 42},
		start          = 0,
		end            = 9,
		row            = 0,
		time           = 0.075,
		flags          = {.Loop},
	}

	player_anim_jump := Animation {
		size           = {120, 80},
		offset         = {52, 42},
		offset_flipped = {52, 42},
		start          = 0,
		end            = 2,
		row            = 1,
		time           = 0.075,
	}

	player_anim_jump_fall_inbetween := Animation {
		size           = {120, 80},
		offset         = {52, 42},
		offset_flipped = {52, 42},
		start          = 3,
		end            = 4,
		row            = 1,
		time           = 0.075,
	}

	player_anim_fall := Animation {
		size           = {120, 80},
		offset         = {52, 42},
		offset_flipped = {52, 42},
		start          = 5,
		end            = 7,
		row            = 1,
		time           = 0.075,
		flags          = {.Loop},
	}

	player_anim_run := Animation {
		size           = {120, 80},
		offset         = {52, 42},
		offset_flipped = {52, 42},
		start          = 0,
		end            = 9,
		row            = 2,
		time           = 0.075,
		flags          = {.Loop},
	}

	player_anim_attack := Animation {
		size           = {120, 80},
		offset         = {52, 42},
		offset_flipped = {52, 42},
		start          = 0,
		end            = 3,
		row            = 3,
		time           = 0.05,
		on_finish      = player_on_finish_attack,
		timed_events   = {{timer = 0.05, duration = 0.05, callback = player_attack_callback}},
	}

	player_anim_dash := Animation {
		size           = {120, 80},
		offset         = {52, 42},
		offset_flipped = {52, 42},
		start          = 4,
		end            = 5,
		row            = 3,
		time           = 0.075,
	}

	gs.player_id = entity_create(
		{
			x = player_spawn.x,
			y = player_spawn.y,
			width = 16,
			height = 38,
			move_speed = 220,
			jump_force = 650,
			on_enter = player_on_enter,
			health = 7,
			max_health = 7,
			debug_color = rl.GREEN,
			texture = &gs.player_texture,
			animations = {
				"idle" = player_anim_idle,
				"jump" = player_anim_jump,
				"jump_fall_inbetween" = player_anim_jump_fall_inbetween,
				"fall" = player_anim_fall,
				"run" = player_anim_run,
				"attack" = player_anim_attack,
				"dash" = player_anim_dash,
			},
			current_anim_name = "idle",
		},
	)

}

spawn_enemies :: proc(gs: ^Game_State) {
	for spawn in gs.level.enemy_spawns {
		def := &gs.enemy_definitions[spawn.type]

		enemy := Entity {
			collider          = {
				spawn.pos.x,
				spawn.pos.y,
				def.collider_size.x,
				def.collider_size.y,
			},
			move_speed        = def.move_speed,
			behaviors         = def.behaviors,
			health            = def.health,
			on_hit_damage     = def.on_hit_damage,
			texture           = &def.texture,
			animations        = def.animations,
			current_anim_name = def.initial_animation,
			debug_color       = rl.RED,
			flags             = {.Debug_Draw},
			hit_response      = def.hit_response,
			hit_duration      = def.hit_duration,
		}

		entity_create(enemy)
	}
}

level_from_id :: proc(levels: []Level, id: u32) -> ^Level {
	for &l in levels {
		if l.id == id {
			return &l
		}
	}
	return nil
}

gs: ^Game_State

game_init :: proc(gs: ^Game_State) {
	gs.player_texture = rl.LoadTexture("assets/textures/player_120x80.png")
	gs.item_texture = rl.LoadTexture("assets/textures/items_16x16.png")
	gs.scene = .Game
}

game_update :: proc(gs: ^Game_State) {
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		if rl.IsKeyPressed(.TAB) {
			gs.editor_enabled = !gs.editor_enabled
			gs.camera.zoom = ZOOM
		}

		player := entity_get(gs.player_id)

		if gs.editor_enabled {
			editor_update(gs, dt)
		} else {

			player_update(gs, dt)
			entity_update(gs, dt)
			physics_update(gs.entities[:], gs.colliders[:], dt)
			behavior_update(gs.entities[:], gs.colliders[:], dt)

			// Update falling logs
			for &falling_log in gs.falling_logs {
				if falling_log.state == .Falling {
					falling_log.collider.y += dt * FALLING_LOG_SPEED

					// Check collision with ground
					for collider in gs.colliders {
						if rl.CheckCollisionRecs(collider, falling_log.collider) {
							falling_log.state = .Settled
							recreate_colliders(gs.level.pos, &gs.colliders, gs.level.tiles[:])
							break
						}
					}

					// Check collision with player (instant kill)
					if rl.CheckCollisionRecs(player.collider, falling_log.collider) {
						player.health = 0
					}
				}
			}

			{
				render_half_size := Vec2{RENDER_WIDTH, RENDER_HEIGHT} / 2

				gs.camera.target = {player.x, player.y} - render_half_size

				if gs.camera.target.x < gs.level.pos.x {
					gs.camera.target.x = gs.level.pos.x
				}

				if gs.camera.target.y < gs.level.pos.y {
					gs.camera.target.y = gs.level.pos.y
				}

				if gs.camera.target.x + RENDER_WIDTH > gs.level.pos.x + gs.level.size.x {
					gs.camera.target.x = gs.level.pos.x + gs.level.size.x - RENDER_WIDTH
				}

				if gs.camera.target.y + RENDER_HEIGHT > gs.level.pos.y + gs.level.size.y {
					gs.camera.target.y = gs.level.pos.y + gs.level.size.y - RENDER_HEIGHT
				}
			}


			if .Grounded in player.flags {
				pos := Vec2{player.x, player.y}
				size := Vec2{player.width, player.height}

				targets := make([dynamic]Rect, context.temp_allocator)
				for e, i in gs.entities {
					if Entity_Id(i) == gs.player_id do continue
					if .Dead not_in e.flags {
						append(&targets, e.collider)
					}
				}

				safety_check: {
					for spike in gs.level.spikes {
						if rl.CheckCollisionRecs(
							rect_pos_add(spike.collider, gs.level.pos),
							player.collider,
						) {
							break safety_check
						}
					}

					_, hit_ground_left := raycast(pos + {0, size.y}, DOWN * 2, gs.colliders[:])
					if !hit_ground_left do break safety_check

					_, hit_ground_right := raycast(pos + size, DOWN * 2, gs.colliders[:])
					if !hit_ground_right do break safety_check

					_, hit_entity_left := raycast(pos, LEFT * TILE_SIZE, targets[:])
					if hit_entity_left do break safety_check

					_, hit_entity_right := raycast(
						pos + {size.x, 0},
						RIGHT * TILE_SIZE,
						targets[:],
					)
					if hit_entity_right do break safety_check

					gs.safe_position = pos
				}
			}
		}

		rl.BeginDrawing()
		rl.BeginMode2D(gs.camera)
		rl.ClearBackground(BG_COLOR)

		for tile in gs.level.tiles {
			width: f32 = TILE_SIZE
			height: f32 = TILE_SIZE

			if tile.f == 1 || tile.f == 3 {
				width = -TILE_SIZE
			} else if tile.f == 2 || tile.f == 3 {
				height = -TILE_SIZE
			}
			rl.DrawTextureRec(
				gs.tileset_texture,
				{tile.src.x, tile.src.y, width, height},
				tile.pos,
				rl.WHITE,
			)
		}

		for spike in gs.level.spikes {
			rl.DrawRectangleLinesEx(rect_pos_add(spike.collider, gs.level.pos), 1, rl.YELLOW)
		}

		// Draw falling logs
		for falling_log in gs.falling_logs {
			// Draw rope if not settled
			if falling_log.state != .Settled {
				log_center_x := falling_log.collider.x + falling_log.collider.width / 2
				rope_start := Vec2{log_center_x, falling_log.collider.y}
				rope_end := Vec2{log_center_x, falling_log.collider.y - falling_log.rope_height}
				rl.DrawLineV(rope_start, rope_end, rl.BROWN)
			}
			// Draw log
			rl.DrawRectangleRec(falling_log.collider, rl.BROWN)
		}

		for &e in gs.entities {
			if .Dead in e.flags do continue
			if e.texture != nil && len(e.animations) > 0 {
				anim := e.animations[e.current_anim_name]

				source := Rect {
					f32(e.current_anim_frame) * anim.size.x,
					f32(anim.row) * anim.size.y,
					anim.size.x,
					anim.size.y,
				}
				if .Left in e.flags {
					source.width = -source.width
				}
				rl.DrawTextureRec(e.texture^, source, {e.x, e.y} - anim.offset, rl.WHITE)
			}

			if .Debug_Draw in e.flags && .Dead not_in e.flags {
				rl.DrawRectangleLinesEx(e.collider, 1, e.debug_color)
			}
		}

		debug_draw_rect(gs.safe_position, {player.width, player.height}, 1, rl.BLUE)
		debug_draw_circle(
			{player.collider.x, player.collider.y} +
			{.Left in player.flags ? -30 + player.collider.width : 30, 20},
			25,
			rl.GREEN,
		)

		rl.DrawRectangleLinesEx(player.collider, 1, rl.GREEN)

		if gs.debug_draw_enabled {
			for s in gs.debug_shapes {
				switch v in s {
				case Debug_Line:
					rl.DrawLineEx(v.start, v.end, v.thickness, v.color)
				case Debug_Rect:
					rl.DrawRectangleLinesEx(
						{v.pos.x, v.pos.y, v.size.x, v.size.y},
						v.thickness,
						v.color,
					)
				case Debug_Circle:
					rl.DrawCircleLinesV(v.pos, v.radius, v.color)
				}
			}
		}

		rl.EndMode2D()
		rl.DrawFPS(10, 10)

		if gs.editor_enabled {
			editor_draw(gs)
		}

		rl.EndDrawing()

		clear(&gs.debug_shapes)
	}
}

main_menu_update :: proc(gs: ^Game_State) {
	for !rl.WindowShouldClose() {
		center := Vec2{WINDOW_WIDTH, WINDOW_HEIGHT} / 2
		title_text: cstring = "Action Game Thing"
		title_text_size := rl.MeasureTextEx(gs.font_64, title_text, 64, 4)

		rl.BeginDrawing()
		rl.ClearBackground({0, 0, 28, 255})

		rl.DrawTextEx(
			gs.font_64,
			title_text,
			{center.x - title_text_size.x / 2, center.y / 2},
			64,
			4,
			rl.WHITE,
		)

		if main_menu_item_draw("Continue", center, rl.DARKGRAY, rl.DARKGRAY) {
			// TODO
		}

		if main_menu_item_draw("New Game", center + {0, 60}) {
			game_init(gs)
			level_load(gs, FIRST_LEVEL_ID, 0)
			return
		}

		if main_menu_item_draw("Quit", center + {0, 120}) {
			rl.CloseWindow()
			return
		}

		rl.EndDrawing()
	}
}

main_menu_item_draw :: proc(
	text: cstring,
	pos: Vec2,
	color := rl.WHITE,
	hover_color := rl.YELLOW,
) -> (
	pressed: bool,
) {
	pos := pos
	text_size := rl.MeasureTextEx(gs.font_48, text, 48, 0)
	pos.x -= text_size.x / 2
	rect := Rect{pos.x, pos.y, text_size.x, text_size.y}

	if rl.CheckCollisionPointRec(rl.GetMousePosition(), rect) {
		rl.DrawTextEx(gs.font_48, text, pos, 48, 0, hover_color)
		if rl.IsMouseButtonPressed(.LEFT) {
			pressed = true
		}
	} else {
		rl.DrawTextEx(gs.font_48, text, pos, 48, 0, color)
	}

	return
}

recreate_colliders :: proc(world_pos: Vec2, colliders: ^[dynamic]Rect, tiles: []Tile) {
	clear(colliders)
	slice.sort_by(tiles, proc(a, b: Tile) -> bool {
		if a.pos.y != b.pos.y do return a.pos.y < b.pos.y
		return a.pos.x < b.pos.x
	})

	solid_tiles := make([dynamic]Rect, context.temp_allocator)
	for t in tiles {
		append(
			&solid_tiles,
			Rect{t.pos.x - world_pos.x, t.pos.y - world_pos.y, TILE_SIZE, TILE_SIZE}, // Fix: subtract world_pos from collider position
		)
	}

	if len(solid_tiles) > 0 {
		combine_colliders(world_pos, solid_tiles[:], colliders)
	}

	// Add settled falling logs as colliders
	for falling_log in gs.falling_logs {
		if falling_log.state == .Settled {
			append(colliders, falling_log.collider)
		}
	}
}

combine_colliders :: proc(world_pos: Vec2, solid_tiles: []Rect, colliders: ^[dynamic]Rect) {
	wide_rect := solid_tiles[0]
	wide_rects := make([dynamic]Rect, context.temp_allocator)

	for i in 1 ..< len(solid_tiles) {
		rect := solid_tiles[i]

		if rect.x == wide_rect.x + wide_rect.width && rect.y == wide_rect.y {
			wide_rect.width += TILE_SIZE
		} else {
			append(&wide_rects, wide_rect)
			wide_rect = rect
		}
	}

	append(&wide_rects, wide_rect)

	slice.sort_by(wide_rects[:], proc(a, b: Rect) -> bool {
		if a.x != b.x do return a.x < b.x
		return a.y < b.y
	})

	big_rect := wide_rects[0]

	for i in 1 ..< len(wide_rects) {
		rect := wide_rects[i]

		if rect.x == big_rect.x &&
		   big_rect.width == rect.width &&
		   big_rect.y + big_rect.height == rect.y {
			big_rect.height += TILE_SIZE
		} else {
			big_rect.x += world_pos.x
			big_rect.y += world_pos.y
			append(colliders, big_rect)
			big_rect = rect
		}
	}

	big_rect.x += world_pos.x
	big_rect.y += world_pos.y
	append(colliders, big_rect)
}

main :: proc() {
	gs = new(Game_State)

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "simple test")

	gs.tileset_texture = rl.LoadTexture("assets/textures/tileset.png")
	gs.enemy_definitions[.Walker] = Enemy_Def {
		collider_size = {36, 18},
		move_speed = 35,
		health = 3,
		behaviors = {.Walk, .Flip_At_Wall, .Flip_At_Edge},
		on_hit_damage = 1,
		texture = rl.LoadTexture("assets/textures/opossum_36x28.png"),
		animations = {
			"walk" = Animation {
				size = {36, 28},
				offset = {0, 10},
				start = 0,
				end = 5,
				time = 0.15,
				flags = {.Loop},
			},
		},
		initial_animation = "walk",
		hit_response = .Stop,
		hit_duration = 0.25,
	}

	editor_init()
	rl.SetTargetFPS(60)

	world_data_load()

	gs.font_18 = rl.LoadFontEx("assets/fonts/Gogh-ExtraBold.ttf", 18, nil, 256)
	gs.font_48 = rl.LoadFontEx("assets/fonts/Gogh-ExtraBold.ttf", 48, nil, 256)
	gs.font_64 = rl.LoadFontEx("assets/fonts/Gogh-ExtraBold.ttf", 64, nil, 256)

	gs.camera = rl.Camera2D {
		zoom = ZOOM,
	}

	for !rl.WindowShouldClose() {
		switch gs.scene {
		case .Main_Menu:
			main_menu_update(gs)
		case .Game:
			game_update(gs)
		}
	}
}
