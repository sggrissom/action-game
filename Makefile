.PHONY: all build run clean debug release ios ios-device ios-check

# Project settings
PROJECT_NAME = action-game
SRC_DIR = src
BUILD_DIR = build
BINARY = $(BUILD_DIR)/$(PROJECT_NAME)

# Odin compiler settings
ODIN = odin
ODIN_FLAGS = -collection:src=$(SRC_DIR)

# Default target
all: run

# Build in debug mode
build: debug

# Debug build
debug:
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -debug -out:$(BINARY) $(ODIN_FLAGS)

# Release build (optimized)
release:
	@mkdir -p $(BUILD_DIR)
	$(ODIN) build $(SRC_DIR) -o:speed -out:$(BINARY) $(ODIN_FLAGS)

# Build and run (debug mode)
run: debug
	./$(BINARY)

# Build and run (release mode)
run-release: release
	./$(BINARY)

# iOS: build the .app and launch it in the Simulator (macOS only, see ios/README.md)
ios:
	./ios/build.sh sim

# iOS: build and sign for a physical device (needs CODESIGN_IDENTITY)
ios-device:
	./ios/build.sh device

# Verify the game still cross-compiles to iOS arm64. Works on any host, no Xcode needed.
ios-check:
	@mkdir -p $(BUILD_DIR)/ios-check
	$(ODIN) build $(SRC_DIR) -target:darwin_arm64 -subtarget:iphone \
		-build-mode:obj -no-entry-point $(ODIN_FLAGS) \
		-out:$(BUILD_DIR)/ios-check/game.o
	@echo "iOS arm64 compile OK"

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

# Help target
help:
	@echo "Available targets:"
	@echo "  make build        - Build in debug mode (default)"
	@echo "  make debug        - Build in debug mode"
	@echo "  make release      - Build in release mode (optimized)"
	@echo "  make run          - Build and run in debug mode"
	@echo "  make run-release  - Build and run in release mode"
	@echo "  make ios          - Build and run on the iOS Simulator (macOS)"
	@echo "  make ios-device   - Build and sign for an iOS device (macOS)"
	@echo "  make ios-check    - Verify the iOS arm64 cross-compile (any host)"
	@echo "  make clean        - Remove build artifacts"
	@echo "  make help         - Show this help message"
