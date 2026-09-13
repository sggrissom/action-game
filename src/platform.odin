package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// IOS is true when building with `-subtarget:iphone` or `-subtarget:iphonesimulator`.
IOS :: ODIN_PLATFORM_SUBTARGET_IOS

// The game draws everything in a fixed 1280x720 coordinate space. On desktop that is
// the window itself. On iOS the device screen has a different size and aspect ratio,
// so the frame is rendered into a 1280x720 render texture and blitted letterboxed.
// Keeping the virtual space fixed means none of the existing layout math has to change.
VIRTUAL_WIDTH :: WINDOW_WIDTH
VIRTUAL_HEIGHT :: WINDOW_HEIGHT

Platform_State :: struct {
	virtual_target: rl.RenderTexture2D,
	// Letterbox mapping from device pixels back into virtual coordinates.
	view_scale:     f32,
	view_offset:    Vec2,
	asset_base:     string,
	save_base:      string,
}

platform: Platform_State

// platform_init must run after InitWindow, since it queries the real screen size
// and (on iOS) allocates the virtual render target.
platform_init :: proc() {
	when IOS {
		// GetApplicationDirectory keeps its trailing slash; drop it so joins stay clean.
		platform.asset_base = strings.trim_right(string(rl.GetApplicationDirectory()), "/")
		// On iOS the app sandbox container is HOME; Documents is the writable,
		// backed-up location. The app bundle itself is read-only.
		home := os.get_env("HOME", context.allocator)
		platform.save_base = fmt.aprintf("%s/Documents/saves", home)
		platform.virtual_target = rl.LoadRenderTexture(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
	} else {
		platform.asset_base = ""
		platform.save_base = "saves"
	}

	platform_update_view()
}

platform_update_view :: proc() {
	when IOS {
		sw := f32(rl.GetScreenWidth())
		sh := f32(rl.GetScreenHeight())
		platform.view_scale = min(sw / VIRTUAL_WIDTH, sh / VIRTUAL_HEIGHT)
		platform.view_offset = {
			(sw - VIRTUAL_WIDTH * platform.view_scale) / 2,
			(sh - VIRTUAL_HEIGHT * platform.view_scale) / 2,
		}
	} else {
		platform.view_scale = 1
		platform.view_offset = {0, 0}
	}
}

// asset_path resolves a repo-relative asset path for reading.
asset_path :: proc(rel: string) -> string {
	when IOS {
		// iOS app bundles are flat: resources sit next to the executable.
		return fmt.tprintf("%s/%s", platform.asset_base, rel)
	} else {
		return rel
	}
}

// asset_c is asset_path as a cstring, for the raylib Load* calls.
asset_c :: proc(rel: string) -> cstring {
	when IOS {
		return strings.clone_to_cstring(asset_path(rel), context.temp_allocator)
	} else {
		return strings.clone_to_cstring(rel, context.temp_allocator)
	}
}

// save_dir is the writable directory holding save slots.
save_dir :: proc() -> string {
	return platform.save_base
}

save_path :: proc(slot: int) -> string {
	return fmt.tprintf("%s/%d.json", save_dir(), slot)
}

// mouse_pos returns the pointer position in virtual (1280x720) coordinates.
// raylib reports touches through the mouse API, so this covers both platforms.
mouse_pos :: proc() -> Vec2 {
	when IOS {
		return (rl.GetMousePosition() - platform.view_offset) / platform.view_scale
	} else {
		return rl.GetMousePosition()
	}
}

// frame_begin/frame_end replace BeginDrawing/EndDrawing. On iOS they redirect the
// frame through the virtual render target and blit it letterboxed to the screen.
frame_begin :: proc() {
	when IOS {
		rl.BeginTextureMode(platform.virtual_target)
	} else {
		rl.BeginDrawing()
	}
}

frame_end :: proc() {
	when IOS {
		rl.EndTextureMode()

		platform_update_view()

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		// Render textures are stored bottom-up, hence the negative source height.
		src := Rect{0, 0, VIRTUAL_WIDTH, -VIRTUAL_HEIGHT}
		dest := Rect {
			platform.view_offset.x,
			platform.view_offset.y,
			VIRTUAL_WIDTH * platform.view_scale,
			VIRTUAL_HEIGHT * platform.view_scale,
		}
		rl.DrawTexturePro(platform.virtual_target.texture, src, dest, {0, 0}, 0, rl.WHITE)
		rl.EndDrawing()
	} else {
		rl.EndDrawing()
	}
}

when IOS {
	// raylib's iOS platform layer owns main(): rcore_ios_main.m starts UIApplicationMain
	// on the main thread and then calls raylib_main on a dedicated game thread.
	// The Odin build uses -no-entry-point so that no competing C `main` is emitted,
	// which means the runtime has to be started and torn down explicitly here.
	@(export, link_name = "raylib_main")
	ios_entry :: proc "c" (argc: i32, argv: [^]cstring) -> i32 {
		context = runtime.default_context()
		#force_no_inline runtime._startup_runtime()
		main()
		#force_no_inline runtime._cleanup_runtime()
		return 0
	}
}
