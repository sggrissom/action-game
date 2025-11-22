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

Vec2 :: rl.Vector2
Rect :: rl.Rectangle
Entity_Id :: distinct int

Entity_Flags :: enum {
	Grounded,
	Dead,
	Kinematic,
	Debug_Draw,
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
}

Game_State :: struct {
	camera:      rl.Camera2D,
	entities:    [dynamic]Entity,
	solid_tiles: [dynamic]Rect,
	spikes:      map[Entity_Id]Direction,
}

Direction :: enum {
	Up,
	Right,
	Down,
	Left,
}

gs: Game_State

spike_on_enter :: proc(self_id, other_id: Entity_Id) {
	self := entity_get(self_id)
	other := entity_get(other_id)

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

main :: proc() {
	player_id: Entity_Id
	{
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
				player_id = entity_create(
					{x = x, y = y, width = 16, height = 38, move_speed = 280, jump_force = 650},
				)
			}
			if v == '^' {
				id := entity_create(
					Entity {
						collider = Rect{x, y + SPIKE_DIFF, SPIKE_BREADTH, SPIKE_DEPTH},
						on_enter = spike_on_enter,
						flags = {.Kinematic, .Debug_Draw},
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
						flags = {.Kinematic, .Debug_Draw},
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
						flags = {.Kinematic, .Debug_Draw},
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
						flags = {.Kinematic, .Debug_Draw},
						debug_color = rl.YELLOW,
					},
				)
				gs.spikes[id] = .Left
			}
			x += TILE_SIZE
		}
	}

	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "simple test")
	rl.SetTargetFPS(60)

	gs.camera = rl.Camera2D {
		zoom = ZOOM,
	}

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		player := entity_get(player_id)
		input_x: f32
		if rl.IsKeyDown(.D) do input_x += 1
		if rl.IsKeyDown(.A) do input_x -= 1

		if rl.IsKeyPressed(.SPACE) && .Grounded in player.flags {
			player.vel.y = -player.jump_force
			player.flags -= {.Grounded}
		}

		player.vel.x = input_x * player.move_speed
		physics_update(gs.entities[:], gs.solid_tiles[:], dt)


		rl.BeginDrawing()
		rl.BeginMode2D(gs.camera)
		rl.ClearBackground(BG_COLOR)

		for rect in gs.solid_tiles {
			rl.DrawRectangleRec(rect, rl.WHITE)
			rl.DrawRectangleLinesEx(rect, 1, rl.GRAY)
		}

		for e in gs.entities {
			if .Debug_Draw in e.flags {
				rl.DrawRectangleLinesEx(e.collider, 1, e.debug_color)
			}
		}

		rl.DrawRectangleLinesEx(player.collider, 1, rl.GREEN)

		rl.EndMode2D()
		rl.EndDrawing()
	}
}

