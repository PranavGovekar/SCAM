#!/usr/bin/env bash
set -euo pipefail

# PetaLinux helper.
# Usage: build_petalinux.sh <config|build|app-tdc|app-ct>

action="${1:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
petalinux_project="${PETALINUX_PROJECT_DIR:-${repo_root}/petalinux}"
petalinux_settings="${PETALINUX_SETTINGS:-${HOME}/petalinux/2024.1/settings.sh}"

if [[ -z "${PETALINUX:-}" ]] || ! command -v petalinux-config >/dev/null 2>&1; then
    if [[ ! -r "$petalinux_settings" ]]; then
        echo "PetaLinux settings not found: $petalinux_settings" >&2
        echo "Set PETALINUX_SETTINGS to your PetaLinux settings.sh path." >&2
        exit 1
    fi
    # shellcheck disable=SC1090
    # The user's interactive bash config puts a standalone GCC 16 toolchain at
    # the front of PATH. That compiler cannot find its matching linker here,
    # which breaks native Yocto recipes. Prefer the host compiler/binutils for
    # BitBake while leaving the user's shell configuration untouched.
    export PATH="/usr/bin:/bin:${PATH}"
    set --
    source "$petalinux_settings"
fi

mkdir -p "$petalinux_project/.petalinux"

# BitBake caches host-tool symlinks under TMPDIR. If that directory was first
# created from a shell with a custom GCC on PATH, refresh the cached compiler
# links so native recipes use the host GCC selected above.
tmpdir=""
if [[ -r "$petalinux_project/project-spec/configs/config" ]]; then
    tmpdir="$(sed -n 's/^CONFIG_TMP_DIR_LOCATION="\([^"]*\)"/\1/p' \
        "$petalinux_project/project-spec/configs/config" | head -n 1)"
fi
if [[ -n "$tmpdir" ]]; then
    for tool in gcc g++; do
        if [[ -L "$tmpdir/hosttools/$tool" ]]; then
            ln -sfn "/usr/bin/$tool" "$tmpdir/hosttools/$tool"
        fi
    done
fi

pushd "$petalinux_project" > /dev/null

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
        sync_src "$repo_root/sw/common" \
            project-spec/meta-user/recipes-apps/yeet-data-common/files
        sync_src "$repo_root/sw/tdc" \
            project-spec/meta-user/recipes-apps/yeet-data-tdc/files
        sync_src "$repo_root/sw/ct" \
            project-spec/meta-user/recipes-apps/yeet-data-ct/files

        # Copy bitstreams if present
        [[ -f "$repo_root/hw/tdc/bitstream/tdc.bit.bin" ]] && \
            cp -f "$repo_root/hw/tdc/bitstream/tdc.bit.bin" \
                  project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/
        [[ -f "$repo_root/hw/ct/bitstream/coincidence.bit.bin" ]] && \
            cp -f "$repo_root/hw/ct/bitstream/coincidence.bit.bin" \
                  project-spec/meta-user/recipes-bsp/fpga-bitstreams/files/

        local_xsa="$repo_root/hw/base/system.xsa"
        if [[ ! -f "$local_xsa" ]]; then
            echo "Base XSA not found: $local_xsa" >&2
            echo "Run 'make base-xsa' first." >&2
            exit 1
        fi

        echo "==> petalinux-config --get-hw-description $local_xsa"
        config_args=(--get-hw-description "$local_xsa" -p "$petalinux_project")
        if [[ ! -t 0 ]]; then
            config_args+=(--silentconfig)
        fi
        petalinux-config "${config_args[@]}"
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
