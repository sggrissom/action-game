# iOS port

## Status

The port is **structurally complete and builds for iOS, but has never been run on a
device or simulator** — this machine is Linux, so everything from `clang` linking
onwards is unverified. Treat stage 3+ of the build as the part most likely to need
fixing.

What is actually verified:

| Thing | Verified how |
| --- | --- |
| The whole game compiles to iOS arm64 | `odin build -target:darwin_arm64 -subtarget:iphone` on Linux, both device and simulator subtargets, debug and `-o:speed` |
| Odin emits no macOS-only link hints | Objects contain zero `LC_LINKER_OPTION` and no Cocoa/IOKit references, so they link cleanly against an iOS raylib |
| The iOS entry point matches raylib's | Odin exports `_raylib_main`; raylib's `rcore_ios_main.m` declares `extern int raylib_main(int, char**)` |
| Desktop build is unchanged | Builds and runs, 17/17 assets load, zero warnings |

What is **not** verified: the raylib iOS build, the link step, the app bundle,
whether it boots, whether audio works, and whether the touch controls feel right.

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

Useful knobs: `SIM_DEVICE="iPhone 16 Pro"`, `MIN_IOS=13.0`, `BUNDLE_ID=...`.
Pass `--clean-raylib` as the second argument to force a raylib rebuild.

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

**Files.** Assets are read through `asset_path`/`asset_c`, which resolve against
`GetApplicationDirectory()` on iOS (iOS bundles are flat, so resources sit next to the
executable). Saves go to `$HOME/Documents/saves`, since the bundle is read-only.

**Input.** `src/input.odin` replaces the direct key/mouse calls in `player.odin` with
`input_*` procedures. Desktop keeps the original bindings exactly; iOS drives them from
on-screen buttons sampled from the multi-touch points, so run+jump work together.

## Known gaps

1. **Audio is the weakest point.** raylib bundles miniaudio, which states plainly that
   "the iOS build needs to be compiled as Objective-C" because its Core Audio backend
   uses `AVAudioSession`. Upstream compiles `raudio.c` as plain C, which is why the iOS
   branches report audio as broken. `build.sh` patches raylib's CMake to compile
   `raudio.c` with `-x objective-c` and links `AVFoundation`/`AudioToolbox`. This is the
   documented fix but I could not test it. If the app crashes on `InitAudioDevice`, build
   raylib with `-DSUPPORT_MODULE_RAUDIO=OFF` to confirm everything else works, then treat
   audio as a separate problem.
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
- **Stage 4 (launch)** — usually a bundle id or Simulator device name mismatch. Check
  `xcrun simctl list devices available`.
