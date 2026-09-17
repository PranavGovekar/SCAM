#!/usr/bin/env bash
set -euo pipefail

# PetaLinux helper.
# Usage: build_petalinux.sh <config|build|app-tdc|app-ct>

action="${1:-}"
pushd petalinux > /dev/null

case "${action}" in
    config)
        echo "==> Copying config templates"
        [[ -f project-spec/configs/config ]] || \
            cp project-spec/configs/config.template project-spec/configs/config
        [[ -f project-spec/configs/rootfs_config ]] || \
            cp project-spec/configs/rootfs_config.template project-spec/configs/rootfs_config

        echo "==> Syncing shared C sources into recipes"
        sync_src() {
            local src_dir="$1"
            local dst_dir="$2"
            cp -f "${src_dir}"/*.h "${dst_dir}/" 2>/dev/null || true
            cp -f "${src_dir}"/*.c "${dst_dir}/" 2>/dev/null || true
        }
        sync_src ../sw/common \
            project-spec/meta-user/recipes-apps/yeet-data-common/files
        sync_src ../sw/tdc \
            project-spec/meta-user/recipes-apps/yeet-data-tdc/files
        sync_src ../sw/ct \
            project-spec/meta-user/recipes-apps/yeet-data-ct/files

        # Copy bitstreams if present
        [[ -f ../hw/tdc/bitstream/tdc.bit.bin ]] && \
            cp -f ../hw/tdc/bitstream/tdc.bit.bin \
                  project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/
        [[ -f ../hw/ct/bitstream/coincidence.bit.bin ]] && \
            cp -f ../hw/ct/bitstream/coincidence.bit.bin \
                  project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/

        echo "==> petalinux-config --get-hw-description"
        petalinux-config --get-hw-description project-spec/hw-description/ -p .
        ;;
    build)
        echo "==> petalinux-build"
        petalinux-build
        ;;
    app-tdc)
        echo "==> Rebuilding only yeet-data-tdc"
        petalinux-build -c yeet-data-tdc -x do_compile
        petalinux-build -c yeet-data-tdc
        ;;
    app-ct)
        echo "==> Rebuilding only yeet-data-ct"
        petalinux-build -c yeet-data-ct -x do_compile
        petalinux-build -c yeet-data-ct
        ;;
    *)
        echo "Usage: $0 <config|build|app-tdc|app-ct>"
        exit 1
        ;;
esac

popd > /dev/null
