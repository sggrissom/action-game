package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

// IOS is true when building with `-subtarget:iphone` or `-subtarget:iphonesimulator`.
IOS :: ODIN_PLATFORM_SUBTARGET_IOS

when IOS {
	// rcore_ios_main.m's own restore routine, exported by raylib's iOS backend. It
	// re-establishes the EAGL context, the framebuffer raylib presents, that
	// framebuffer's colour renderbuffer and the viewport. See frame_end for why the
	// game has to call it.
	foreign import ios_platform "system:raylib"

	@(default_calling_convention = "c")
	foreign ios_platform {
		ios_make_current_context :: proc() ---
	}
}

// The game draws everything in a fixed 1280x720 coordinate space. On desktop that is
// the window itself. On iOS the device screen has a different size and aspect ratio,
// so the frame is rendered into a 1280x720 render texture and blitted letterboxed.
// Keeping the virtual space fixed means none of the existing layout math has to change.
VIRTUAL_WIDTH :: WINDOW_WIDTH
VIRTUAL_HEIGHT :: WINDOW_HEIGHT

Platform_State :: struct {
	virtual_target: rl.RenderTexture2D,
	// True between frame_begin and frame_end, i.e. while virtual_target is the
	// target that a nested texture_mode_end has to restore.
	in_frame:       bool,
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

// texture_mode_end replaces EndTextureMode for render targets drawn *during* a frame.
// EndTextureMode unconditionally returns to framebuffer 0 and to the screen viewport
// and projection, which on iOS drops the rest of the frame on the floor. Re-entering
// the virtual target restores all three.
texture_mode_end :: proc() {
	rl.EndTextureMode()
	when IOS {
		if platform.in_frame {
			rl.BeginTextureMode(platform.virtual_target)
		}
	}
}

// frame_begin/frame_end replace BeginDrawing/EndDrawing. On iOS they redirect the
// frame through the virtual render target and blit it letterboxed to the screen.
frame_begin :: proc() {
	when IOS {
		platform.in_frame = true
		rl.BeginTextureMode(platform.virtual_target)
	} else {
		rl.BeginDrawing()
	}
}

frame_end :: proc() {
	when IOS {
		platform.in_frame = false
		rl.EndTextureMode()
		// On desktop, "no render texture bound" means framebuffer 0, which is the
		// window. On iOS it means nothing at all: raylib presents a CAEAGLLayer-backed
		// framebuffer of its own, and presentRenderbuffer: reads whichever renderbuffer
		// is currently bound -- which LoadRenderTexture left at 0. Without this the
		// blit below lands nowhere and the screen stays black.
		ios_make_current_context()

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
