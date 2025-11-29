#+feature dynamic-literals
package main

import "core:fmt"
import "core:os"
import "core:slice"
import "core:time"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
ZOOM :: 2
BG_COLOR :: rl.BLACK
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

PLAYER_SAFE_RESET_TIME :: 1

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
	pos: Vec2,
	src: Vec2,
	f:   u8,
}

Level :: struct {
	id:           u32,
	player_spawn: Maybe(Vec2),
	level_min:    Vec2,
	level_max:    Vec2,
	colliders:    [dynamic]Rect,
	tiles:        [dynamic]Tile,
}

Entity :: struct {
	using collider:             Rect,
	vel:                        Vec2,
	move_speed:                 f32,
	jump_force:                 f32,
	on_enter, on_stay, on_exit: proc(self_id, other_id: Entity_Id),
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
}

Game_State :: struct {
	player_id:             Entity_Id,
	safe_position:         Vec2,
	safe_reset_timer:      f32,
	player_movement_state: Player_Movement_State,
	camera:                rl.Camera2D,
	entities:              [dynamic]Entity,
	solid_tiles:           [dynamic]Rect,
	spikes:                map[Entity_Id]Direction,
	debug_shapes:          [dynamic]Debug_Shape,
	player_texture:        rl.Texture,
	scene:                 Scene_Type,
	font_48:               rl.Font,
	font_64:               rl.Font,
	level_definitions:     map[string]Level,
	level:                 ^Level,
	editor_enabled:        bool,
}

Animation :: struct {
	size:         Vec2,
	offset:       Vec2,
	start:        int,
	end:          int,
	row:          int,
	time:         f32,
	flags:        bit_set[Animation_Flags],
	on_finish:    proc(gs: ^Game_State, entity: ^Entity),
	timed_events: [dynamic]Animation_Event,
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

spike_on_enter :: proc(self_id, other_id: Entity_Id) {
	self := entity_get(self_id)
	other := entity_get(other_id)

	if other_id == gs.player_id {
		other.x = gs.safe_position.x
		other.y = gs.safe_position.y
		other.vel = 0
		gs.safe_reset_timer = PLAYER_SAFE_RESET_TIME
		gs.player_movement_state = .Uncontrollable
		switch_animation(other, "idle")
	}

	dir := gs.spikes[self_id]
	switch dir {
	case .Up:
		if other.vel.y > 0 {
			fmt.println("spikes face Up")
		}
	case .Right:
		if other.vel.x < 0 {
			fmt.println("spikes face Right")
		}
	case .Down:
		if other.vel.y < 0 {
			fmt.println("spikes face Down")
		}
	case .Left:
		if other.vel.x > 0 {
			fmt.println("spikes face Left")
		}
	}
}

player_on_enter :: proc(self_id, other_id: Entity_Id) {
	player := entity_get(self_id)
	other := entity_get(other_id)

	if other.on_hit_damage > 0 {
		player.health -= other.on_hit_damage
	}
}

gs: Game_State

main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "simple test")
	rl.SetTargetFPS(60)

	world_data_save()
	world_data_load()

	gs.font_48 = rl.LoadFontEx("assets/fonts/Gogh-ExtraBold.ttf", 48, nil, 256)
	gs.font_64 = rl.LoadFontEx("assets/fonts/Gogh-ExtraBold.ttf", 64, nil, 256)

	gs.camera = rl.Camera2D {
		zoom = ZOOM,
	}

	for !rl.WindowShouldClose() {
		switch gs.scene {
		case .Main_Menu:
			main_menu_update(&gs)
		case .Game:
			game_update(&gs)
		}
	}
}

game_init :: proc(gs: ^Game_State) {
	gs.player_texture = rl.LoadTexture("assets/textures/player_120x80.png")

	player_anim_idle := Animation {
		size   = {120, 80},
		offset = {52, 42},
		start  = 0,
		end    = 9,
		row    = 0,
		time   = 0.15,
		flags  = {.Loop},
	}

	player_anim_jump := Animation {
		size   = {120, 80},
		offset = {52, 42},
		start  = 0,
		end    = 2,
		row    = 1,
		time   = 0.15,
	}

	player_anim_jump_fall_inbetween := Animation {
		size   = {120, 80},
		offset = {52, 42},
		start  = 3,
		end    = 4,
		row    = 1,
		time   = 0.15,
	}

	player_anim_fall := Animation {
		size   = {120, 80},
		offset = {52, 42},
		start  = 5,
		end    = 7,
		row    = 1,
		time   = 0.15,
		flags  = {.Loop},
	}

	player_anim_run := Animation {
		size   = {120, 80},
		offset = {52, 42},
		start  = 0,
		end    = 9,
		row    = 2,
		time   = 0.15,
		flags  = {.Loop},
	}

	player_anim_attack := Animation {
		size         = {120, 80},
		offset       = {52, 42},
		start        = 0,
		end          = 3,
		row          = 3,
		time         = 0.15,
		on_finish    = player_on_finish_attack,
		timed_events = {{timer = 0.15, duration = 0.15, callback = player_attack_callback}},
	}

	data, ok := os.read_entire_file_from_filename("data/test.lvl")
	assert(ok, "Failed to load level data")
	x, y: f32
	for v in data {
		if v == '\n' {
			y += TILE_SIZE
			x = 0
			continue
		}
		if v == '#' {
			append(&gs.solid_tiles, rl.Rectangle{x, y, TILE_SIZE, TILE_SIZE})
		}
		if v == 'P' {
			gs.player_id = entity_create(
				{
					x = x,
					y = y,
					width = 16,
					height = 38,
					move_speed = 280,
					jump_force = 650,
					on_enter = player_on_enter,
					health = 5,
					max_health = 5,
					texture = &gs.player_texture,
					animations = {
						"idle" = player_anim_idle,
						"jump" = player_anim_jump,
						"jump_fall_inbetween" = player_anim_jump_fall_inbetween,
						"fall" = player_anim_fall,
						"run" = player_anim_run,
						"attack" = player_anim_attack,
					},
					current_anim_name = "idle",
					animation_timer = 0.15,
				},
			)
		}
		if v == '^' {
			id := entity_create(
				Entity {
					collider = Rect{x, y + SPIKE_DIFF, SPIKE_BREADTH, SPIKE_DEPTH},
					on_enter = spike_on_enter,
					flags = {.Kinematic, .Debug_Draw, .Immortal},
					on_hit_damage = 1,
					debug_color = rl.YELLOW,
				},
			)
			gs.spikes[id] = .Up
		}
		if v == 'v' {
			id := entity_create(
				Entity {
					collider = Rect{x, y, SPIKE_BREADTH, SPIKE_DEPTH},
					on_enter = spike_on_enter,
					flags = {.Kinematic, .Debug_Draw, .Immortal},
					on_hit_damage = 1,
					debug_color = rl.YELLOW,
				},
			)
			gs.spikes[id] = .Down
		}
		if v == '>' {
			id := entity_create(
				Entity {
					collider = Rect{x, y, SPIKE_DEPTH, SPIKE_BREADTH},
					on_enter = spike_on_enter,
					flags = {.Kinematic, .Debug_Draw, .Immortal},
					on_hit_damage = 1,
					debug_color = rl.YELLOW,
				},
			)
			gs.spikes[id] = .Right
		}
		if v == '<' {
			id := entity_create(
				Entity {
					collider = Rect{x + SPIKE_DIFF, y, SPIKE_DEPTH, SPIKE_BREADTH},
					on_enter = spike_on_enter,
					flags = {.Kinematic, .Debug_Draw, .Immortal},
					on_hit_damage = 1,
					debug_color = rl.YELLOW,
				},
			)
			gs.spikes[id] = .Left
		}
		if v == 'e' {
			entity_create(
				Entity {
					collider = Rect{x, y, TILE_SIZE, TILE_SIZE},
					move_speed = 50,
					flags = {.Debug_Draw, .Immortal},
					behaviors = {.Walk, .Flip_At_Wall, .Flip_At_Edge},
					debug_color = rl.RED,
				},
			)
		}
		x += TILE_SIZE
	}

	gs.scene = .Game
}

game_update :: proc(gs: ^Game_State) {
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		if rl.IsKeyPressed(.F5) {
			gs.editor_enabled = !gs.editor_enabled
		}

		player := entity_get(gs.player_id)

		if gs.editor_enabled {
			editor_update(gs)
		} else {

			player_update(gs, dt)
			entity_update(gs, dt)
			physics_update(gs.entities[:], gs.solid_tiles[:], dt)
			behavior_update(gs.entities[:], gs.solid_tiles[:], dt)

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
					_, hit_ground_left := raycast(pos + {0, size.y}, DOWN * 2, gs.solid_tiles[:])
					if !hit_ground_left do break safety_check

					_, hit_ground_right := raycast(pos + size, DOWN * 2, gs.solid_tiles[:])
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

		for rect in gs.solid_tiles {
			rl.DrawRectangleRec(rect, rl.WHITE)
			rl.DrawRectangleLinesEx(rect, 1, rl.GRAY)
		}

		for &e in gs.entities {
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

combine_level_colliders :: proc(solid_tiles: []Rect, l: ^Level) {
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
			big_rect.x += l.level_min.x
			big_rect.y += l.level_min.y
			append(&l.colliders, big_rect)
			big_rect = rect
		}
	}

	big_rect.x += l.level_min.x
	big_rect.y += l.level_min.y
	append(&l.colliders, big_rect)
}

recreate_level_colliders :: proc(l: ^Level) {
	clear(&l.colliders)
	solid_tiles := make([dynamic]Rect, context.temp_allocator)
	for t in l.tiles {
		append(&solid_tiles, Rect{t.pos.x, t.pos.y, TILE_SIZE, TILE_SIZE})
	}
	combine_level_colliders(solid_tiles[:], l)
}
