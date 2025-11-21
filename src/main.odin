package main

import "core:os"
import rl "vendor:raylib"

WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720
ZOOM :: 2
BG_COLOR :: rl.BLACK
TILE_SIZE :: 16
PHYSICS_ITERATIONS :: 8
GRAVITY :: 5
TERMINAL_VELOCITY :: 1200

Vec2 :: rl.Vector2
Rect :: rl.Rectangle

Entity :: struct {
  using collider: Rect,
  vel:            Vec2,
  move_speed:     f32,
  jump_force:     f32,
  is_grounded:    bool,
  is_dead:        bool,
}

Game_State :: struct {
  camera:      rl.Camera2D,
  entities:    [dynamic]Entity,
  solid_tiles: [dynamic]rl.Rectangle,
}

gs: Game_State

main :: proc() {
  player_id: int
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
      x += TILE_SIZE
    }
  }

  rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "simple test")
  rl.SetTargetFPS(60)

  gs.camera = rl.Camera2D{
    zoom = ZOOM,
  }

  for !rl.WindowShouldClose() {
    dt := rl.GetFrameTime()

    player := entity_get(player_id)
    input_x: f32
    if rl.IsKeyDown(.D) do input_x += 1
    if rl.IsKeyDown(.A) do input_x -= 1

    if rl.IsKeyPressed(.SPACE) && player.is_grounded {
      player.vel.y = -player.jump_force
      player.is_grounded = false
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

    rl.DrawRectangleLinesEx(player.collider, 1, rl.GREEN)

    rl.EndMode2D()
    rl.EndDrawing()
  }
}
