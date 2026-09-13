#!/usr/bin/env bash
#
# Build the game as an iOS .app. Run this on macOS with Xcode installed.
#
#   ./ios/build.sh sim        build for the Simulator and launch it
#   ./ios/build.sh device     build + sign for a physical device
#   ./ios/build.sh sim --clean-raylib   force a raylib rebuild
#
# Stages are independent and each one prints a banner, so a failure tells you
# exactly which part broke.

set -euo pipefail

RAYLIB_REPO="https://github.com/vsaint1/raylib"
RAYLIB_BRANCH="features/ios-platform"

APP_NAME="ActionGame"
BUNDLE_ID="${BUNDLE_ID:-com.example.actiongame}"
MIN_IOS="${MIN_IOS:-13.0}"
SIM_DEVICE="${SIM_DEVICE:-iPhone 16}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_DIR="$ROOT/ios"
VENDOR="$IOS_DIR/third_party"
OUT="$IOS_DIR/build"

TARGET="${1:-sim}"
CLEAN_RAYLIB="${2:-}"

case "$TARGET" in
  sim)
    SDK="iphonesimulator"
    ODIN_SUBTARGET="iphonesimulator"
    MIN_FLAG="-mios-simulator-version-min=$MIN_IOS"
    ;;
  device)
    SDK="iphoneos"
    ODIN_SUBTARGET="iphone"
    MIN_FLAG="-miphoneos-version-min=$MIN_IOS"
    ;;
  *)
    echo "usage: $0 [sim|device] [--clean-raylib]" >&2
    exit 2
    ;;
esac

banner() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- stage 0
banner "Stage 0: checking prerequisites"

[ "$(uname -s)" = "Darwin" ] || die "This script must run on macOS."
command -v xcrun   >/dev/null || die "Xcode command line tools not found. Run: xcode-select --install"
command -v cmake   >/dev/null || die "cmake not found. Run: brew install cmake"
command -v odin    >/dev/null || die "odin not found. Put the Odin compiler on your PATH."
xcrun --sdk "$SDK" --show-sdk-path >/dev/null 2>&1 || die "SDK '$SDK' unavailable. Open Xcode once to finish installation."

SDK_PATH="$(xcrun --sdk "$SDK" --show-sdk-path)"
echo "odin      : $(odin version)"
echo "sdk       : $SDK_PATH"
echo "target    : $TARGET (arm64)"
echo "bundle id : $BUNDLE_ID"

# ---------------------------------------------------------------- stage 1
banner "Stage 1: raylib with iOS platform support"

mkdir -p "$VENDOR"
if [ ! -d "$VENDOR/raylib/.git" ]; then
  echo "cloning $RAYLIB_REPO ($RAYLIB_BRANCH)..."
  git clone --depth 1 -b "$RAYLIB_BRANCH" "$RAYLIB_REPO" "$VENDOR/raylib"
else
  echo "reusing existing checkout at ios/third_party/raylib"
fi

# raylib bundles miniaudio, which on iOS must be compiled as Objective-C because its
# Core Audio backend talks to AVAudioSession. Upstream still compiles raudio.c as plain
# C, which is why audio is reported as broken on the iOS branches. This patches that.
RAUDIO_MARKER="# action-game: compile raudio as Objective-C for iOS audio"
if ! grep -qF "$RAUDIO_MARKER" "$VENDOR/raylib/src/CMakeLists.txt"; then
  echo "patching raudio.c to build as Objective-C (enables audio)"
  cat >> "$VENDOR/raylib/src/CMakeLists.txt" <<'CMAKE'

# action-game: compile raudio as Objective-C for iOS audio
if (${PLATFORM} STREQUAL "iOS")
    set_source_files_properties(raudio.c PROPERTIES COMPILE_OPTIONS "-x;objective-c")
endif()
CMAKE
fi

RAYLIB_BUILD="$VENDOR/raylib-build-$SDK"
RAYLIB_LIB="$RAYLIB_BUILD/raylib/libraylib.a"

if [ "$CLEAN_RAYLIB" = "--clean-raylib" ]; then
  rm -rf "$RAYLIB_BUILD"
fi

if [ ! -f "$RAYLIB_LIB" ]; then
  cmake -S "$VENDOR/raylib" -B "$RAYLIB_BUILD" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS" \
    -DPLATFORM=iOS \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build "$RAYLIB_BUILD" --config Release -j"$(sysctl -n hw.ncpu)"
else
  echo "reusing $RAYLIB_LIB"
fi

[ -f "$RAYLIB_LIB" ] || die "raylib build finished but $RAYLIB_LIB is missing."
echo "raylib: $RAYLIB_LIB"

# ---------------------------------------------------------------- stage 2
banner "Stage 2: compiling the Odin game to iOS objects"

OBJ_DIR="$OUT/obj-$SDK"
rm -rf "$OBJ_DIR"; mkdir -p "$OBJ_DIR"

# -build-mode:obj keeps Odin out of the linking step, so we control which libraries
# and frameworks get used. -no-entry-point suppresses Odin's C `main`, because
# raylib's rcore_ios_main.m owns main() and calls our exported raylib_main instead.
odin build "$ROOT/src" \
  -target:darwin_arm64 \
  -subtarget:"$ODIN_SUBTARGET" \
  -build-mode:obj \
  -no-entry-point \
  -minimum-os-version:"$MIN_IOS" \
  -o:speed \
  -collection:src="$ROOT/src" \
  -out:"$OBJ_DIR/game.o"

OBJ_COUNT=$(ls "$OBJ_DIR"/*.o 2>/dev/null | wc -l | tr -d ' ')
[ "$OBJ_COUNT" -gt 0 ] || die "Odin produced no object files."
echo "$OBJ_COUNT object files"

# ---------------------------------------------------------------- stage 3
banner "Stage 3: linking and assembling $APP_NAME.app"

APP="$OUT/$APP_NAME.app"
rm -rf "$APP"; mkdir -p "$APP"

clang \
  -arch arm64 \
  -isysroot "$SDK_PATH" \
  $MIN_FLAG \
  "$OBJ_DIR"/*.o \
  "$RAYLIB_LIB" \
  -framework UIKit \
  -framework OpenGLES \
  -framework QuartzCore \
  -framework CoreGraphics \
  -framework Foundation \
  -framework AVFoundation \
  -framework AudioToolbox \
  -framework CoreMotion \
  -o "$APP/$APP_NAME"

# iOS bundles are flat: resources live next to the executable, which is what
# raylib's GetApplicationDirectory() returns and what asset_path() builds on.
cp -R "$ROOT/assets" "$APP/assets"
cp -R "$ROOT/data"   "$APP/data"

sed -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" -e "s|__MIN_IOS__|$MIN_IOS|g" \
  "$IOS_DIR/Info.plist" > "$APP/Info.plist"

echo "bundle: $APP"

# ---------------------------------------------------------------- stage 4
if [ "$TARGET" = "device" ]; then
  banner "Stage 4: code signing"
  if [ -z "${CODESIGN_IDENTITY:-}" ]; then
    cat <<'MSG'
Skipping signing: CODESIGN_IDENTITY is not set.

A device build must be signed before it will install. List your identities with:
    security find-identity -v -p codesigning

Then re-run with, for example:
    CODESIGN_IDENTITY="Apple Development: you@example.com (XXXXXXXXXX)" \
    BUNDLE_ID=com.yourteam.actiongame ./ios/build.sh device

You also need a provisioning profile whose App ID matches BUNDLE_ID. The simplest
path is to let Xcode generate one once for that bundle id, then reuse it here.
MSG
    exit 0
  fi
  codesign --force --sign "$CODESIGN_IDENTITY" --timestamp=none \
    ${PROVISIONING_PROFILE:+--entitlements "$PROVISIONING_PROFILE"} "$APP"
  echo "signed with: $CODESIGN_IDENTITY"
  echo "install with: xcrun devicectl device install app --device <UDID> \"$APP\""
  exit 0
fi

banner "Stage 4: launching on the Simulator"

open -a Simulator || true
DEVICE_ID="$(xcrun simctl list devices available | awk -v d="$SIM_DEVICE" '
  $0 ~ d { if (match($0, /[0-9A-F-]{36}/)) { print substr($0, RSTART, RLENGTH); exit } }')"
[ -n "$DEVICE_ID" ] || die "Simulator device '$SIM_DEVICE' not found. List them with: xcrun simctl list devices available"

xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl install "$DEVICE_ID" "$APP"
echo
echo "Launching (Ctrl-C to detach from the log):"
xcrun simctl launch --console "$DEVICE_ID" "$BUNDLE_ID"
