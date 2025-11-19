.PHONY: all build run clean debug release

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
	@echo "  make clean        - Remove build artifacts"
	@echo "  make help         - Show this help message"
