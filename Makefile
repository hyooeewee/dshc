# dshc.app release orchestration over the Python pipeline scripts.
#
# Targets can be run individually or as a whole `all` release:
#
#   make save                  download + export image tarballs (TAG, default latest)
#   make check                 run `ug check` only
#   make prepack TAG=0.1.2-alpha.3
#                              stamp versions + `ug check`, no pack
#   make pack BUILD=103        `ug pack` only (run make prepack first, or make all)
#   make all BUILD=103 TAG=0.1.2-alpha.3
#                              download, prepack, pack in one go
#   make help                  show usage and per-target arguments
#
# Shared variables: BUILD (ug pack build id), TAG (release tag),
# PLATFORM (save platforms, default linux/amd64,linux/arm64).

PY := python3
APP_DIR := apps/dshc.upk
SCRIPTS := $(APP_DIR)/scripts
SAVE := $(SCRIPTS)/save-docker-images.py
PACK := $(SCRIPTS)/pack-upk.py

BUILD ?=
TAG ?=
PLATFORM ?= linux/amd64,linux/arm64

.PHONY: help save check prepack pack all

help: ## :: Show this help
	@echo "Usage: make <target> [VAR=value ...]"
	@echo "Variables: TAG=<release tag, e.g. 0.1.2-alpha.3>  BUILD=<ug pack build id, e.g. 103>  PLATFORM=<platforms, default linux/amd64,linux/arm64>"
	@echo ""
	@printf "  %-10s %-30s %s\n" "TARGET" "ARGS" "DESCRIPTION"
	@grep -hE '^[a-zA-Z0-9._-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk -F':.*?## ' '{ split($$2, a, "::"); gsub(/^ +| +$$/, "", a[1]); gsub(/^ +| +$$/, "", a[2]); printf "  %-10s %-30s %s\n", $$1, a[1], a[2] }'

save: ## TAG=<tag> (default latest) :: Download + export per-arch image tarballs (PLATFORM optional), self-verifying
	$(PY) $(SAVE) --tag $(if $(TAG),$(TAG),latest) --platform $(PLATFORM) --pull

check: ## :: Run `ug check` only
	$(PY) $(PACK) --check-only

prepack: ## TAG=<tag> :: Stamp compose image + project version, then `ug check`
	@test -n "$(TAG)" || { echo "error: TAG missing, use: make prepack TAG=0.1.2-alpha.3"; exit 1; }
	$(PY) $(PACK) --prepack --tag $(TAG)

pack: ## BUILD=<id> :: `ug pack --arch all --build <id>` (after prepack)
	@test -n "$(BUILD)" || { echo "error: BUILD missing, use: make pack BUILD=103"; exit 1; }
	$(PY) $(PACK) --pack-only --build $(BUILD)

all: ## TAG=<tag>, BUILD=<id> :: save + prepack + pack in one go
	@test -n "$(BUILD)" || { echo "error: BUILD missing, use: make all BUILD=103 TAG=0.1.2-alpha.3"; exit 1; }
	@test -n "$(TAG)" || { echo "error: TAG missing, use: make all BUILD=103 TAG=0.1.2-alpha.3"; exit 1; }
	$(PY) $(SAVE) --tag $(TAG) --platform $(PLATFORM) --pull
	$(PY) $(PACK) --prepack --tag $(TAG)
	$(PY) $(PACK) --pack-only --build $(BUILD)
