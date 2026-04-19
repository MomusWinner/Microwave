APP_NAME := sav
SRC_DIR := src
BIN_DIR := bin
DEBUG_BIN := $(BIN_DIR)/debug/$(APP_NAME)
RELEASE_BIN := $(BIN_DIR)/release/$(APP_NAME)

ODIN_FLAGS := -custom-attribute:buffer -collection:lib=./lib/ -define:GLFW_SHARED=false
ODIN_DEBUG_FLAGS := -debug ${ODIN_FLAGS}
ODIN_RELEASE_FLAGS := -o:speed -no-bounds-check -disable-assert ${ODIN_FLAGS}
ODIN := odin

TEST_CSV := svace.csv

.PHONY: all
all: debug release

.PHONY: debug
debug-win:
	@echo "Building debug examples ..."
	@mkdir -p $(BIN_DIR)/debug

	$(ODIN) build $(SRC_DIR) -target:windows_amd64 -out:$(DEBUG_BIN).exe ${ODIN_DEBUG_FLAGS}
	@echo "Built: $(DEBUG_BIN)"

.PHONY: debug
debug:
	@echo "Building debug examples ..."
	@mkdir -p $(BIN_DIR)/debug

	$(ODIN) build $(SRC_DIR) -out:$(DEBUG_BIN) ${ODIN_DEBUG_FLAGS}
	@echo "Built: $(DEBUG_BIN)"

.PHONY: release
release:
	@echo "Building release examples ..."
	@mkdir -p $(BIN_DIR)/release
	$(ODIN) build $(SRC_DIR) -out:$(RELEASE_BIN) ${ODIN_RELEASE_FLAGS}
	@echo "Built: $(RELEASE_BIN)"

.PHONY: release-win
release-win:
	@echo "Building release examples ..."
	@mkdir -p $(BIN_DIR)/release
	$(ODIN) build $(SRC_DIR) -target:windows_amd64 -out:$(RELEASE_BIN).exe ${ODIN_RELEASE_FLAGS}
	@echo "Built: $(RELEASE_BIN)"

.PHONY: run
run: debug
	@echo "🐢 Running examples $(DEBUG_BIN)..."
	@$(DEBUG_BIN) -csv $(TEST_CSV)

.PHONY: run-release
run-release: release
	@echo "🐇 Running example $(RELEASE_BIN)..."
	@$(RELEASE_BIN) -csv $(TEST_CSV)

.PHONY: gen
gen:
	@echo "Generating..."
	odin run ./lib/ve/tools/shadertypegen/ -- \
		-output-glsl-dir:shaders/ \
		-src-dir:./src\
		-ve-import:"ve lib:ve"\

.PHONY: clean
clean:
	rm -rf $(BIN_DIR)
