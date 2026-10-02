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

.PHONY: all base-xsa tdc ct tdc-bitstream ct-bitstream bitstreams petalinux-config petalinux app-tdc app-ct sdcard flash clean clean-build help

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
	@echo "  clean-build        Remove hardware and PetaLinux build outputs/caches"
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

# Also clears BitBake task state, downloads, shared state, and the external
# work directory configured by petalinux/project-spec/configs/config.
clean-build: clean
	rm -rf petalinux/build petalinux/.petalinux /tmp/scam-petalinux-tmp
	rm -rf .cache/petalinux-2024.1-ubuntu22
	@echo "Cleaned host and container PetaLinux build outputs/caches (project sources/config preserved)."
