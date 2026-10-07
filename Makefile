# SCAM top-level orchestration
# See docs/build-guide.md for prerequisites, docs/adding-an-app.md for adding
# your own hardware and software.

SHELL := /bin/bash

# Per-machine settings (tool paths, PETALINUX_ENV, SCAM_APPS). See config.mk.example.
-include config.mk

PETALINUX_ENV ?= host
# SD card device for 'make flash' -- override with: make flash SD=/dev/sdX
SD ?= /dev/sdX

export PETALINUX_ENV PETALINUX_ROOT VIVADO VIVADO_SETTINGS SCAM_APPS SCAM_SDK SCAM_JOBS

# Paths
# The base XSA has exactly one home: hw/base/system.xsa. It must NOT live in
# petalinux/project-spec/hw-description/, because petalinux-config empties that
# directory before copying the XSA in.
BASE_XSA     := hw/base/system.xsa
BUILD_DIR    := build
OUT_DIR      := out
RECIPES      := petalinux/project-spec/meta-user
CONFIG_STAMP := $(BUILD_DIR)/.petalinux-config.$(PETALINUX_ENV).stamp

# Container cache. Keep in step with scripts/lib/common.sh.
CACHE_DIR    := .cache/petalinux-2024.1-ubuntu22

# Applications: apps/<name>/ plus anything in SCAM_APPS. One word per
# application: name|dir|bitstream|binary|has_hw|has_sw
APP_TABLE := $(shell bash scripts/apps.sh table || echo '!error')
ifneq ($(filter !error,$(APP_TABLE)),)
  # 'make doctor' has to run on a broken setup too.
  ifeq ($(filter doctor,$(MAKECMDGOALS)),)
    $(error Application discovery failed, see the message above)
  endif
  APP_TABLE :=
endif
app_field = $(word $(1),$(subst |, ,$(2)))
APPS      := $(foreach t,$(APP_TABLE),$(call app_field,1,$(t)))
HW_APPS   := $(foreach t,$(APP_TABLE),$(if $(filter 1,$(call app_field,5,$(t))),$(call app_field,1,$(t))))
SW_APPS   := $(foreach t,$(APP_TABLE),$(if $(filter 1,$(call app_field,6,$(t))),$(call app_field,1,$(t))))

.DEFAULT_GOAL := help

# Vivado and BitBake parallelise internally, and the application builds all
# clone the same base project.
.NOTPARALLEL:

.PHONY: help
help: ## Show this help
	@echo "Applications: $(APPS)"
	@echo
	@echo "Targets:"
	@grep -hE '^[a-zA-Z%<>_-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/^([^:]+):.*## (.*)/  \1|\2/' | column -t -s '|'
	@echo
	@echo "Per application (<app> is one of: $(APPS)):"
	@echo "  <app>-bitstream         Build build/apps/<app>/<bitstream>.bit.bin (Vivado)"
	@echo "  app-<app>               Cross-compile the userspace binary (SCAM_SDK=<installed sdk>)"
	@echo "  petalinux-app-<app>     Rebuild only that application's recipe inside PetaLinux"
	@echo
	@echo "Settings go on the command line or in config.mk (see config.mk.example)."

.PHONY: status
status: ## Show what is built, when, what is out of date, and what to run next
	@bash scripts/status.sh

.PHONY: doctor
doctor: ## Check that this machine can build the project (FULL=1 also tests a license checkout)
	@bash scripts/doctor.sh $(if $(FULL),--full)

.PHONY: list-apps
list-apps: ## List the discovered applications
	@bash scripts/apps.sh show

.PHONY: new-app
new-app: ## Create an application from the template (NAME=<name> [DEST=<dir>])
	@bash scripts/new_app.sh "$(NAME)" $(DEST)

# ---------------------------------------------------------------------------
# Hardware
# ---------------------------------------------------------------------------

.PHONY: base-xsa
base-xsa: $(BASE_XSA) ## Generate the base XSA at hw/base/system.xsa

# An existing template project in hw/base/build is reused so that changes made
# in the Vivado GUI survive. SCAM_REBUILD_TEMPLATE=1 recreates it from the TCL.
$(BASE_XSA): hw/base/build_base_xsa.tcl $(wildcard hw/base/src/* hw/base/constraints/*)
	bash scripts/build_hw.sh base

# Bitstreams that the image installs (listed in fpga-bitstreams.bb).
IMAGE_BIT_NAMES := $(patsubst file://%,%,$(shell grep -o 'file://[^ ]*\.bit\.bin' $(RECIPES)/recipes-bsp/fpga-bitstreams/fpga-bitstreams.bb))

# $(1)=name $(2)=dir $(3)=bitstream $(4)=binary
define HW_APP_RULES
$(BUILD_DIR)/apps/$(1)/$(3).bit.bin: $(BASE_XSA) hw/base/scam_app.tcl $$(shell find $(2)/hw -type f)
	bash scripts/build_hw.sh $(1)
.PHONY: $(1)-bitstream
$(1)-bitstream: $(BUILD_DIR)/apps/$(1)/$(3).bit.bin
ALL_BITSTREAMS += $(BUILD_DIR)/apps/$(1)/$(3).bit.bin
IMAGE_BITSTREAMS += $$(if $$(filter $(3).bit.bin,$$(IMAGE_BIT_NAMES)),$(BUILD_DIR)/apps/$(1)/$(3).bit.bin)
endef

define SW_APP_RULES
.PHONY: app-$(1) petalinux-app-$(1)
app-$(1):
	bash scripts/build_sw.sh $(1)
petalinux-app-$(1): $(CONFIG_STAMP)
	bash scripts/run_petalinux.sh app $(4)
endef

$(foreach t,$(APP_TABLE),\
    $(if $(filter 1,$(call app_field,5,$(t))),$(eval $(call HW_APP_RULES,$(call app_field,1,$(t)),$(call app_field,2,$(t)),$(call app_field,3,$(t)),$(call app_field,4,$(t)))))\
    $(if $(filter 1,$(call app_field,6,$(t))),$(eval $(call SW_APP_RULES,$(call app_field,1,$(t)),$(call app_field,2,$(t)),$(call app_field,3,$(t)),$(call app_field,4,$(t))))))

.PHONY: bitstreams
bitstreams: $(ALL_BITSTREAMS) ## Build every application's bitstream

.PHONY: apps
apps: $(addprefix app-,$(SW_APPS)) ## Cross-compile every application's binary (needs the SDK)

.PHONY: deploy
deploy: ## Copy an application to a running board (APP=<name> TARGET=<user@host>)
	bash scripts/deploy.sh "$(APP)" "$(TARGET)"

# ---------------------------------------------------------------------------
# PetaLinux image (only needed to produce or change the Linux image)
# ---------------------------------------------------------------------------

.PHONY: petalinux-config
petalinux-config: $(BASE_XSA) ## Configure PetaLinux from the base XSA
	bash scripts/run_petalinux.sh config
	@mkdir -p $(BUILD_DIR) && touch $(CONFIG_STAMP)

# Re-run the configuration only when the XSA changed since the last one.
$(CONFIG_STAMP): $(BASE_XSA)
	bash scripts/run_petalinux.sh config
	@mkdir -p $(BUILD_DIR) && touch $@

.PHONY: petalinux
petalinux: $(CONFIG_STAMP) $(IMAGE_BITSTREAMS) ## Build the Linux image (PETALINUX_ENV=host or container)
	bash scripts/run_petalinux.sh build

# Downloads every source the image needs, without compiling anything. Run this
# before a long build to find missing sources early.
.PHONY: fetch-check
fetch-check: ## Download every source the image needs (no compiling)
	bash scripts/run_petalinux.sh fetch-check

.PHONY: sdcard
sdcard: ## Create BOOT.BIN + SD image, assemble ./out/ (after 'make petalinux')
	bash scripts/run_petalinux.sh package
	bash scripts/package_sd.sh

.PHONY: flash
flash: ## Write ./out/ to an SD card (SD=/dev/sdX)
	bash scripts/flash_sd.sh $(SD)

.PHONY: sdk
sdk: $(CONFIG_STAMP) ## Build the SDK installer (cross toolchain for applications)
	bash scripts/run_petalinux.sh sdk

.PHONY: release
release: ## Collect the SD image, boot tarball and SDK into out/release/ (after sdcard, sdk)
	bash scripts/make_release.sh

.PHONY: all
all: bitstreams petalinux ## Full pipeline: XSA, bitstreams, image, SD card files
	$(MAKE) sdcard
	@echo "All done. Artifacts in $(OUT_DIR)/"

# ---------------------------------------------------------------------------
# Cleaning
# ---------------------------------------------------------------------------

.PHONY: clean
clean: clean-hw clean-staged ## Remove hardware products, application binaries and ./out/
	@echo "Cleaned build outputs (source files preserved)."

.PHONY: clean-hw
clean-hw: ## Remove hardware outputs (base project + XSA, build/apps, ./out)
	rm -rf hw/base/build $(BUILD_DIR)/apps $(OUT_DIR)
	rm -f $(BASE_XSA) petalinux/project-spec/hw-description/system.xsa
	@echo "Cleaned hardware outputs (sources preserved)."

.PHONY: clean-staged
clean-staged: ## Remove files staged into recipes (C/H synced from sw/ and apps/, .bit.bin copies)
	rm -f $(RECIPES)/recipes-apps/*/files/*.[ch]
	rm -f $(RECIPES)/recipes-bsp/fpga-bitstreams/files/*.bit.bin
	@echo "Cleaned staged source files (recipes preserved)."

.PHONY: clean-petalinux-config
clean-petalinux-config: ## Remove generated config state under project-spec/configs/ (keeps templates)
	rm -f $(BUILD_DIR)/.petalinux-config.*.stamp
	rm -f petalinux/project-spec/configs/config
	rm -f petalinux/project-spec/configs/config.old
	rm -f petalinux/project-spec/configs/rootfs_config
	rm -f petalinux/project-spec/configs/rootfs_config.old
	rm -f petalinux/project-spec/configs/plnx_syshw_data
	rm -f petalinux/project-spec/configs/flash_parts.txt
	rm -f petalinux/project-spec/configs/gen-machineconf.log
	rm -f petalinux/project-spec/configs/gen-machineconf.log.old
	rm -rf petalinux/project-spec/configs/.Xil
	rm -rf petalinux/project-spec/configs/busybox
	rm -rf petalinux/project-spec/configs/configs
	rm -rf petalinux/project-spec/configs/init-ifupdown
	rm -rf petalinux/project-spec/configs/rootfsconfigs
	rm -rf petalinux/project-spec/configs/systemd-conf
	rm -rf petalinux/project-spec/configs/.statistics
	rm -f petalinux/project-spec/hw-description/psu_init.c
	rm -f petalinux/project-spec/hw-description/psu_init.h
	rm -f petalinux/project-spec/hw-description/psu_init.html
	rm -f petalinux/project-spec/hw-description/psu_init.tcl
	rm -f petalinux/project-spec/hw-description/psu_init_gpl.c
	rm -f petalinux/project-spec/hw-description/psu_init_gpl.h
	@echo "Cleaned generated config state (templates preserved)."

.PHONY: clean-petalinux-build
clean-petalinux-build: ## Remove PetaLinux images and host build state
	rm -rf petalinux/images /tmp/scam-petalinux-tmp
	@# petalinux/build is a mount point while a container is running; empty it instead.
	rm -rf petalinux/build petalinux/.petalinux 2>/dev/null || true
	@echo "Cleaned PetaLinux images and host build state."

# Removes the whole components/ and build/ caches, keeping only the two
# directories that are expensive to recreate:
#   build/downloads     <- the real DL_DIR  (DL_DIR = ${TOPDIR}/downloads)
#   build/sstate-cache  <- the real SSTATE_DIR
#   components/yocto/downloads is NOT the DL_DIR; it only holds uninative.
# Partial removal of components/yocto/ breaks every later build, because the
# environment-setup-* marker survives while layers/ and sysroots/ do not.
.PHONY: clean-container-state
clean-container-state: ## Remove the container's components/ and build/ state (keeps downloads, sstate)
	rm -f $(BUILD_DIR)/.petalinux-config.container.stamp
	@if [ -d "$(CACHE_DIR)/components" ]; then \
	    find "$(CACHE_DIR)/components" -mindepth 1 -maxdepth 1 \
	        ! -name yocto -exec rm -rf {} +; \
	    find "$(CACHE_DIR)/components/yocto" -mindepth 1 -maxdepth 1 \
	        ! -name downloads -exec rm -rf {} +; \
	fi
	@if [ -d "$(CACHE_DIR)/build" ]; then \
	    find "$(CACHE_DIR)/build" -mindepth 1 -maxdepth 1 \
	        ! -name downloads ! -name sstate-cache -exec rm -rf {} +; \
	fi
	rm -rf $(CACHE_DIR)/tmp $(CACHE_DIR)/home
	@echo "Cleaned container state. Kept: build/downloads, build/sstate-cache."
	@echo "The next container build re-creates the PetaLinux eSDK from scratch."

.PHONY: clean-container-image
clean-container-image: ## Remove the Docker image scam-petalinux:2024.1-ubuntu22
	docker rmi scam-petalinux:2024.1-ubuntu22 2>/dev/null || true
	@echo "Removed container image."

.PHONY: clean-downloads-cache
clean-downloads-cache: ## Remove only the download and sstate caches
	rm -rf $(CACHE_DIR)/build/downloads
	rm -rf $(CACHE_DIR)/build/sstate-cache
	rm -rf $(CACHE_DIR)/components/yocto/downloads
	@echo "Cleaned the download and sstate caches. The next build re-downloads sources."

# Full clean: hardware + staged files + config state + build state + container state.
# The downloads/sstate caches are kept; use clean-downloads-cache for those.
.PHONY: clean-build
clean-build: clean-hw clean-staged clean-petalinux-config clean-petalinux-build clean-container-state ## Full clean (keeps downloads/sstate caches)
	rm -rf $(BUILD_DIR)
	@echo "Cleaned hardware, staged files, config, build state, and container state (downloads/sstate preserved)."
