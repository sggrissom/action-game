# iOS port

## Status

The port **builds, boots and renders on the iOS Simulator** (iPhone 17, iOS 27,
Xcode 27 beta). Getting there took three fixes beyond the original port — one for
audio, two for rendering — all described below and all in the tree.

What is verified:

| Thing | Verified how |
| --- | --- |
| The whole game compiles to iOS arm64 | `odin build -target:darwin_arm64 -subtarget:iphone`, device and simulator subtargets |
| raylib builds for iOS and the game links against it | `./ios/build.sh sim`, clean link, no missing symbols |
| The app bundle installs, launches and stays up | `simctl install` + `launch`, several minutes with no crash |
| The game renders correctly, letterboxed | `simctl io booted screenshot` — main menu, correct aspect and position |
| All 8 startup assets load from the bundle | `FILEIO: ... File loaded successfully` for every one |
| Audio initializes | `AUDIO: Device initialized successfully`, Core Audio backend |

What is **still not verified**: touch input, gameplay past the main menu, and whether
sound actually comes out. All three need a Simulator UI to drive, and the Xcode
install used here is a trimmed one that ships no `Simulator.app` — `simctl` runs the
device headlessly, which is enough to install, launch and screenshot but not to tap.
Nothing has run on a physical device.

## Quick start

On your Mac, with Xcode and `brew install cmake`, and `odin` on PATH:

```sh
./ios/build.sh sim
```

That clones raylib, builds it for iOS, compiles the game, assembles `ActionGame.app`,
and launches it in the Simulator with the console attached.

For a physical device you need a signing identity:

```sh
security find-identity -v -p codesigning      # find yours
CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" \
BUNDLE_ID=com.yourteam.actiongame ./ios/build.sh device
```

Useful knobs: `SIM_DEVICE="iPhone 17 Pro"`, `MIN_IOS=13.0`, `BUNDLE_ID=...`. If the
named device is not installed the script falls back to whatever iPhone simulator is,
and says so. Pass `--clean-raylib` as the second argument to force a raylib rebuild.

## How it works

**raylib has no official iOS support.** Upstream PR
[#5881](https://github.com/raysan5/raylib/pull/5881) adds `rcore_ios.c`, and that is
what this build uses (`vsaint1/raylib`, branch `features/ios-platform`). It was chosen
over the other community port, [`ghera/raylib-iOS`](https://github.com/ghera/raylib-iOS),
for one decisive reason: it keeps the ordinary `while (!WindowShouldClose())` loop by
running the game on a background dispatch queue, whereas ghera's fork requires
restructuring the game into `ios_ready`/`ios_update`/`ios_destroy` callbacks. Our game
loop survives untouched. The tradeoff is that #5881 is unmerged and based on raylib
master rather than 5.5 — harmless here, because all 77 raylib symbols this game uses
are long-stable core API.

**No Odin binding changes were needed.** The vendored `vendor:raylib` bindings hardcode
the macOS static library and the Cocoa/OpenGL/IOKit frameworks under `ODIN_OS == .Darwin`,
which is also true for iPhone subtargets — so a normal `odin build` would link the wrong
library. Building with `-build-mode:obj` sidesteps this entirely: Odin emits plain Mach-O
objects with raylib as undefined C symbols and records no library paths at all, and
`build.sh` does the linking against the iOS raylib itself.

**The entry point.** iOS requires `main()` to call `UIApplicationMain` on the main thread,
which would collide with Odin's generated `main`. `-no-entry-point` suppresses Odin's
`main`, and `src/platform.odin` exports `raylib_main` in its place, starting and stopping
the Odin runtime explicitly before calling the game's `main`.

**Rendering.** The game's layout math is written against a fixed 1280x720 window. Rather
than rewrite it for phone aspect ratios, `frame_begin`/`frame_end` in `src/platform.odin`
render the frame into a 1280x720 render texture and blit it letterboxed to the device
screen. Touch coordinates are mapped back through the same transform, so all existing
coordinate math stays correct.

That render texture is also what made the first build come up black, and it is worth
knowing why. On desktop, "no render texture bound" means framebuffer 0, which is the
window. On iOS it means nothing at all: raylib presents a CAEAGLLayer-backed
framebuffer it creates in `InitPlatform`, and `presentRenderbuffer:` shows whichever
renderbuffer is bound at the time. `EndTextureMode` binds framebuffer 0, and
`LoadRenderTexture` leaves the renderbuffer binding at 0 as a side effect of creating
its depth buffer — so after the first frame everything was being drawn and presented
into nowhere. `frame_end` calls raylib's own `ios_make_current_context()` after
`EndTextureMode` to put the context, framebuffer, renderbuffer and viewport back.

The same trap applies to any render target used *during* a frame: `EndTextureMode`
returns to the screen, not to the virtual target it was nested inside. `platform.odin`
exports `texture_mode_end` for that case — it re-enters the virtual target, restoring
the framebuffer, viewport and projection together. The save-slot list in `main.odin`
uses it; any new nested render target should too.

**Files.** Assets are read through `asset_path`/`asset_c`, which resolve against
`GetApplicationDirectory()` on iOS (iOS bundles are flat, so resources sit next to the
executable). Saves go to `$HOME/Documents/saves`, since the bundle is read-only.

**Input.** `src/input.odin` replaces the direct key/mouse calls in `player.odin` with
`input_*` procedures. Desktop keeps the original bindings exactly; iOS drives them from
on-screen buttons sampled from the multi-touch points, so run+jump work together.

## Known gaps

1. **Audio initializes, but has not been heard.** Two things were needed. raylib
   bundles miniaudio, which states plainly that "the iOS build needs to be compiled as
   Objective-C" because its Core Audio backend uses `AVAudioSession`; `build.sh`
   patches raylib's CMake to compile `raudio.c` with `-x objective-c` and links
   `AVFoundation`/`AudioToolbox`. On top of that, raylib asks miniaudio for a
   playback-only device but leaves the *context's* iOS session category at miniaudio's
   default, which is `PlayAndRecord`. That opens the microphone, so `AURemoteIO`
   initializes its input side and waits on a permission a game with no
   `NSMicrophoneUsageDescription` can never be granted — `InitAudioDevice` then aborted
   on an RPC timeout, killing the app at startup. `build.sh` patches `InitAudioDevice`
   to pin the category to `Playback`. The device now reports initialized; no sound has
   actually been listened to.

2. **OpenGL ES is deprecated on iOS.** The port renders through GLES3, which Apple
   deprecated in iOS 12. It still runs, but it is not a long-term foundation, and it is
   the reason raysan5 has not merged iOS support.
3. **The level editor is unreachable on iOS.** It is still compiled in, but it is driven
   by TAB, mouse wheel and keyboard, so it is inert. Nothing was removed, so desktop is
   unaffected.
4. **Touch control layout is a first guess.** Positions are in `TOUCH_CONTROLS` in
   `src/input.odin`, in 1280x720 virtual coordinates, and are trivial to move.
5. **The main menu "Quit" item calls `CloseWindow()`**, which is not meaningful on iOS.
6. **No app icon or launch image.** The bundle has an empty `UILaunchScreen`, which is
   enough to get native resolution but gives a black launch.
7. **Unmerged dependency.** `features/ios-platform` is a moving branch on a fork. It is
   cloned with `--depth 1` and reused once present, so your build will not shift under
   you, but it is not a stable base to ship on.

## If it fails

Each stage prints a banner. Match the stage that failed:

- **Stage 1 (raylib)** — the fork's CMake broke or the branch moved. Try
  `./ios/build.sh sim --clean-raylib`.
- **Stage 2 (Odin)** — should not happen; this is the part verified on Linux.
- **Stage 3 (link)** — most likely missing frameworks or a symbol miniaudio needs.
  The error will name the symbol; add the framework to the `clang` invocation.
- **Stage 4 (launch)** — usually a bundle id mismatch. Check
  `xcrun simctl list devices available` for what is actually installed.
