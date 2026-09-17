# SCAM top-level orchestration
# See docs/build-guide.md for prerequisites.

SHELL := /bin/bash

# Paths
BASE_XSA_DIR  := petalinux/project-spec/hw-description
BASE_XSA      := $(BASE_XSA_DIR)/system.xsa
TDC_BIT       := hw/tdc/bitstream/tdc.bit.bin
CT_BIT        := hw/ct/bitstream/coincidence.bit.bin
OUT_DIR       := out

# SD card device for 'make flash' -- override with: make flash SD=/dev/sdX
SD ?= /dev/sdX

.PHONY: all base-xsa tdc ct bitstreams petalinux-config petalinux app-tdc app-ct sdcard flash clean help

help:
	@echo "Targets:"
	@echo "  base-xsa           Generate base system.xsa into PetaLinux hw-description"
	@echo "  tdc                Build TDC bitstream (.bit.bin)"
	@echo "  ct                 Build CT bitstream (.bit.bin)"
	@echo "  bitstreams         Build both bitstreams"
	@echo "  petalinux-config   Point PetaLinux at base XSA (once)"
	@echo "  petalinux          Build the Linux image"
	@echo "  app-tdc            Build only the TDC userspace binary"
	@echo "  app-ct             Build only the CT userspace binary"
	@echo "  sdcard             Assemble ./out/ for SD card"
	@echo "  flash              Write ./out/ to SD card (SD=/dev/sdX)"
	@echo "  all                Full pipeline"
	@echo "  clean              Remove build outputs"

all: base-xsa bitstreams petalinux sdcard
	@echo "All done. Artifacts in $(OUT_DIR)/"

base-xsa:
	bash scripts/build_hw.sh base

tdc:
	bash scripts/build_hw.sh tdc

ct:
	bash scripts/build_hw.sh ct

bitstreams: tdc ct

petalinux-config:
	bash scripts/build_petalinux.sh config

petalinux:
	bash scripts/build_petalinux.sh build

app-tdc:
	bash scripts/build_petalinux.sh app-tdc

app-ct:
	bash scripts/build_petalinux.sh app-ct

sdcard:
	bash scripts/package_sd.sh

flash:
	bash scripts/flash_sd.sh $(SD)

clean:
	rm -rf hw/base/build hw/tdc/build hw/ct/build $(OUT_DIR)
	rm -f hw/tdc/bitstream/*.bit hw/tdc/bitstream/*.bit.bin
	rm -f hw/ct/bitstream/*.bit hw/ct/bitstream/*.bit.bin
	@echo "Cleaned build outputs (source files preserved)."
