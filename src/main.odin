#+feature dynamic-literals
package main

import "core:fmt"
import "core:os"
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
Rect :: rl.Rectangle
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
	player_uncontrollable: bool,
	camera:                rl.Camera2D,
	entities:              [dynamic]Entity,
	solid_tiles:           [dynamic]Rect,
	spikes:                map[Entity_Id]Direction,
	debug_shapes:          [dynamic]Debug_Shape,
}

Animation :: struct {
	size:   Vec2,
	offset: Vec2,
	start:  int,
	end:    int,
	row:    int,
	time:   f32,
}

gs: Game_State

spike_on_enter :: proc(self_id, other_id: Entity_Id) {
	self := entity_get(self_id)
	other := entity_get(other_id)

	if other_id == gs.player_id {
		other.x = gs.safe_position.x
		other.y = gs.safe_position.y
		other.vel = 0
		gs.safe_reset_timer = PLAYER_SAFE_RESET_TIME
		gs.player_uncontrollable = true
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

main :: proc() {
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "simple test")
	rl.SetTargetFPS(60)

	{
		player_texture := rl.LoadTexture("assets/textures/player_120x80.png")

		player_anim_idle := Animation {
			size   = {120, 80},
			offset = {52, 42},
			start  = 0,
			end    = 9,
			row    = 0,
			time   = 0.15,
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
						texture = &player_texture,
						animations = {
							"idle" = player_anim_idle,
							"jump" = player_anim_jump,
							"jump_fall_inbetween" = player_anim_jump_fall_inbetween,
							"fall" = player_anim_fall,
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
	}

	gs.camera = rl.Camera2D {
		zoom = ZOOM,
	}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		gs.safe_reset_timer -= dt

		if gs.safe_reset_timer <= 0 {
			gs.player_uncontrollable = false
		}

		player := entity_get(gs.player_id)
		if !gs.player_uncontrollable {
			input_x: f32
			if rl.IsKeyDown(.D) do input_x += 1
			if rl.IsKeyDown(.A) do input_x -= 1

			if rl.IsKeyPressed(.SPACE) && .Grounded in player.flags {
				player.vel.y = -player.jump_force
				player.flags -= {.Grounded}
				player.current_anim_name = "jump"
				player.current_anim_frame = 0
			}

			if player.vel.y >= 0 {
				if .Grounded not_in player.flags {
					player.current_anim_name = "fall"
					player.current_anim_frame = 0
				} else {
					player.current_anim_name = "idle"
					player.current_anim_frame = 0
				}
			}

			player.vel.x = input_x * player.move_speed

			if player.vel.x < 0 {
				player.flags += {.Left}
			} else if player.vel.x > 0 {
				player.flags -= {.Left}
			}
		}

		entity_update(gs.entities[:], dt)
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

				_, hit_entity_right := raycast(pos + {size.x, 0}, RIGHT * TILE_SIZE, targets[:])
				if hit_entity_right do break safety_check

				gs.safe_position = pos
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
		rl.EndDrawing()

		clear(&gs.debug_shapes)
	}
}

