# SCAM top-level orchestration
# See docs/build-guide.md for prerequisites.

SHELL := /bin/bash

# Paths
BASE_XSA_DIR  := petalinux/project-spec/hw-description
BASE_XSA      := $(BASE_XSA_DIR)/system.xsa
TDC_BIT       := hw/tdc/bitstream/tdc.bit.bin
CT_BIT        := hw/ct/bitstream/coincidence.bit.bin
OUT_DIR       := out
PETALINUX_ENV ?= host

# SD card device for 'make flash' -- override with: make flash SD=/dev/sdX
SD ?= /dev/sdX

.PHONY: all base-xsa tdc ct tdc-bitstream ct-bitstream bitstreams petalinux-config petalinux app-tdc app-ct sdcard flash clean clean-build clean-hw clean-staged clean-petalinux-config clean-petalinux-build clean-container-state clean-container-image clean-downloads-cache help

help:
	@echo "Targets:"
	@echo "  base-xsa           Generate base system.xsa into PetaLinux hw-description"
	@echo "  tdc-bitstream      Build TDC bitstream (.bit.bin)"
	@echo "  ct-bitstream       Build CT bitstream (.bit.bin)"
	@echo "  bitstreams         Build both bitstreams"
	@echo "  petalinux-config   Point PetaLinux at base XSA (once)"
	@echo "  petalinux          Build the Linux image (PETALINUX_ENV=host|container)"
	@echo "  app-tdc            Build only the TDC userspace binary"
	@echo "  app-ct             Build only the CT userspace binary"
	@echo "  sdcard             Assemble ./out/ for SD card"
	@echo "  flash              Write ./out/ to SD card (SD=/dev/sdX)"
	@echo "  all                Full pipeline"
	@echo "  clean              Remove hardware products and ./out/"
	@echo "  clean-build        Full clean (hardware + staged + config + build + container state)"
	@echo "  clean-hw           Remove hardware outputs only (hw/*/build, system.xsa, .bit, .bit.bin, .bif, ./out)"
	@echo "  clean-staged       Remove files staged into recipes (C/H synced from sw/, .bit.bin copies)"
	@echo "  clean-petalinux-config  Remove generated config state under project-spec/configs/ (keeps templates)"
	@echo "  clean-petalinux-build   Remove host PetaLinux build state (petalinux/build, .petalinux, /tmp/scam-petalinux-tmp)"
	@echo "  clean-container-state   Remove container cache build/components/tmp/home (keeps downloads and sstate)"
	@echo "  clean-container-image   Remove the Docker image scam-petalinux:2024.1-ubuntu22"
	@echo "  clean-downloads-cache   Remove only downloads and sstate caches"
	@echo "  Container example: PETALINUX_ENV=container make petalinux"

all: base-xsa bitstreams petalinux sdcard
	@echo "All done. Artifacts in $(OUT_DIR)/"

base-xsa:
	bash scripts/build_hw.sh base

tdc tdc-bitstream:
	bash scripts/build_hw.sh tdc

ct ct-bitstream:
	bash scripts/build_hw.sh ct

bitstreams: tdc ct

petalinux-config:
	PETALINUX_ENV=$(PETALINUX_ENV) bash scripts/run_petalinux.sh config

petalinux:
	PETALINUX_ENV=$(PETALINUX_ENV) bash scripts/run_petalinux.sh build

app-tdc:
	PETALINUX_ENV=$(PETALINUX_ENV) bash scripts/run_petalinux.sh app-tdc

app-ct:
	PETALINUX_ENV=$(PETALINUX_ENV) bash scripts/run_petalinux.sh app-ct

sdcard:
	bash scripts/package_sd.sh

flash:
	bash scripts/flash_sd.sh $(SD)

clean:
	rm -rf hw/base/build hw/tdc/build hw/ct/build $(OUT_DIR)
	rm -f hw/base/system.xsa petalinux/project-spec/hw-description/system.xsa
	rm -f hw/tdc/bitstream/*.bit hw/tdc/bitstream/*.bit.bin hw/tdc/tdc.bif
	rm -f hw/ct/bitstream/*.bit hw/ct/bitstream/*.bit.bin hw/ct/ct.bif
	rm -f petalinux/project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/*.bit.bin
	@echo "Cleaned build outputs (source files preserved)."

clean-hw:
	rm -rf hw/base/build hw/tdc/build hw/ct/build $(OUT_DIR)
	rm -f hw/base/system.xsa petalinux/project-spec/hw-description/system.xsa
	rm -f hw/tdc/bitstream/tdc.bit hw/tdc/bitstream/tdc.bit.bin hw/tdc/tdc.bif
	rm -f hw/ct/bitstream/coincidence.bit hw/ct/bitstream/coincidence.bit.bin hw/ct/ct.bif
	@echo "Cleaned hardware outputs (sources preserved)."

clean-staged:
	rm -f petalinux/project-spec/meta-user/recipes-apps/yeet-data-common/files/*.h
	rm -f petalinux/project-spec/meta-user/recipes-apps/yeet-data-common/files/*.c
	rm -f petalinux/project-spec/meta-user/recipes-apps/yeet-data-tdc/files/*.h
	rm -f petalinux/project-spec/meta-user/recipes-apps/yeet-data-tdc/files/*.c
	rm -f petalinux/project-spec/meta-user/recipes-apps/yeet-data-ct/files/*.h
	rm -f petalinux/project-spec/meta-user/recipes-apps/yeet-data-ct/files/*.c
	rm -f petalinux/project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/tdc.bit.bin
	rm -f petalinux/project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/coincidence.bit.bin
	@echo "Cleaned staged source files (recipes preserved)."

clean-petalinux-config:
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
	rm -f petalinux/project-spec/configs/.statistics
	rm -f petalinux/project-spec/hw-description/psu_init.c
	rm -f petalinux/project-spec/hw-description/psu_init.h
	rm -f petalinux/project-spec/hw-description/psu_init.html
	rm -f petalinux/project-spec/hw-description/psu_init.tcl
	rm -f petalinux/project-spec/hw-description/psu_init_gpl.c
	rm -f petalinux/project-spec/hw-description/psu_init_gpl.h
	@echo "Cleaned generated config state (templates preserved)."

clean-petalinux-build:
	rm -rf petalinux/build petalinux/.petalinux /tmp/scam-petalinux-tmp
	@echo "Cleaned host PetaLinux build state."

clean-container-state:
	rm -rf .cache/petalinux-2024.1-ubuntu22/build
	rm -rf .cache/petalinux-2024.1-ubuntu22/components/yocto/layers
	rm -rf .cache/petalinux-2024.1-ubuntu22/components/yocto/sysroots
	rm -rf .cache/petalinux-2024.1-ubuntu22/components/yocto/cache
	rm -rf .cache/petalinux-2024.1-ubuntu22/tmp
	rm -rf .cache/petalinux-2024.1-ubuntu22/home
	@echo "Cleaned container build state (downloads and sstate preserved)."

clean-container-image:
	docker rmi scam-petalinux:2024.1-ubuntu22 2>/dev/null || true
	@echo "Removed container image."

clean-downloads-cache:
	rm -rf .cache/petalinux-2024.1-ubuntu22/components/yocto/downloads
	rm -rf .cache/petalinux-2024.1-ubuntu22/components/yocto/sstate-cache
	@echo "Cleaned downloads and sstate caches."

# Full clean: hardware + staged files + config state + host build state + container state.
# NOTE: This no longer deletes the downloads/sstate caches (previously it deleted
# the entire .cache/petalinux-2024.1-ubuntu22 directory). Use clean-downloads-cache
# to remove those separately.
clean-build: clean-hw clean-staged clean-petalinux-config clean-petalinux-build clean-container-state
	@echo "Cleaned hardware, staged files, config, host build state, and container state (downloads/sstate preserved)."
