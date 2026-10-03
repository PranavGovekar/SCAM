#!/usr/bin/env bash
set -euo pipefail

# PetaLinux helper.
# Usage: build_petalinux.sh <config|build|app-tdc|app-ct|fetch-check>

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

# PetaLinux often fails with a bare "[ERROR]" and no explanation, because the
# real message is only in its own log. Show the tail of the relevant log so the
# cause is visible without hunting for the file.
show_petalinux_log() {
    local kind="$1" log=""
    case "$kind" in
        config) log="$petalinux_project/build/config.log" ;;
        *)      log="$petalinux_project/build/build.log" ;;
    esac
    echo "" >&2
    if [[ -r "$log" ]]; then
        echo "PetaLinux failed. Last 15 lines of ${log#$repo_root/}:" >&2
        tail -n 15 "$log" >&2
    else
        echo "PetaLinux failed and its log was not written: ${log#$repo_root/}" >&2
        echo "Re-run with the log kept, or check petalinux/build/ inside the container." >&2
    fi
    echo "" >&2
}

pushd "$petalinux_project" > /dev/null

case "${action}" in
    config)
        local_xsa="$repo_root/hw/base/system.xsa"
        if [[ ! -f "$local_xsa" ]]; then
            echo "The base hardware description (XSA) is missing." >&2
            echo "Run: make base-xsa" >&2
            exit 1
        fi

        echo "==> Copying config templates"
        [[ -f project-spec/configs/config ]] || \
            cp project-spec/configs/config.template project-spec/configs/config
        [[ -f project-spec/configs/rootfs_config ]] || \
            cp project-spec/configs/rootfs_config.template project-spec/configs/rootfs_config

        echo "==> Staging sources and bitstreams into the recipes"
        bash "$repo_root/scripts/stage_assets.sh" both

        echo "==> petalinux-config --get-hw-description $local_xsa"
        config_args=(--get-hw-description "$local_xsa" -p "$petalinux_project")
        if [[ ! -t 0 ]]; then
            config_args+=(--silentconfig)
        fi
        if ! petalinux-config "${config_args[@]}"; then
            show_petalinux_log config
            exit 1
        fi
        ;;
    build)
        echo "==> Staging sources and bitstreams into the recipes"
        bash "$repo_root/scripts/stage_assets.sh" both --require-bitstreams
        echo "==> petalinux-build"
        if ! petalinux-build; then
            show_petalinux_log build
            exit 1
        fi
        echo "==> Done. Next: make sdcard, then make flash SD=/dev/sdX"
        ;;
    app-tdc)
        echo "==> Staging sources into the recipes"
        bash "$repo_root/scripts/stage_assets.sh" sources
        echo "==> Rebuilding only yeet-data-tdc"
        petalinux-build -c yeet-data-tdc -x do_compile || true
        if ! petalinux-build -c yeet-data-tdc; then
            show_petalinux_log build
            exit 1
        fi
        ;;
    app-ct)
        echo "==> Staging sources into the recipes"
        bash "$repo_root/scripts/stage_assets.sh" sources
        echo "==> Rebuilding only yeet-data-ct"
        petalinux-build -c yeet-data-ct -x do_compile || true
        if ! petalinux-build -c yeet-data-ct; then
            show_petalinux_log build
            exit 1
        fi
        ;;
    fetch-check)
        # Download-only pass over everything the image needs. Runs inside the
        # container so it uses the same mounts and the same PetaLinux eSDK that
        # a real build would. Nothing is compiled and nothing is installed.
        #
        # petalinux-build maps component "project" to the image target
        # petalinux-image-minimal (see MapBuildComp in the petalinux-build
        # script), so that is what a plain petalinux-build fetches for.
        image_target="petalinux-image-minimal"
        proj="$petalinux_project/build"

        if [[ ! -f "$petalinux_project/project-spec/configs/config" ]]; then
            echo "PetaLinux is not configured yet, so there is nothing to fetch for." >&2
            echo "Run: make PETALINUX_ENV=container petalinux-config" >&2
            exit 1
        fi
        # Same three files a build sources, in the same order.
        setup_env="$petalinux_project/components/yocto/environment-setup-cortexa72-cortexa53-xilinx-linux"
        # The SDK env file sits next to the petalinux-build we are already
        # using, so derive it from PATH rather than guessing at a path.
        sdk_bin="$(command -v petalinux-build || true)"
        sdk_env=""
        if [[ -n "$sdk_bin" ]]; then
            sdk_env="$(cd "$(dirname "$sdk_bin")/.." && pwd)/.environment-setup-x86_64-petalinux-linux"
        fi
        oe_init="$petalinux_project/components/yocto/layers/poky/oe-init-build-env"

        if [[ ! -f "$oe_init" ]]; then
            echo "Cannot find the PetaLinux eSDK: $oe_init is missing." >&2
            echo "Run: make clean-container-state, then make PETALINUX_ENV=container petalinux-config" >&2
            exit 1
        fi

        echo "==> Fetching sources for $image_target (downloads only)"
        # -k keeps going after a failure so we see every missing file at once.
        # --runall=fetch re-runs do_fetch even for already-fetched recipes.
        fetch_log="$proj/fetch-check.log"
        (
            # BitBake's environment scripts read unset variables, so -u must go.
            set +eu
            unset LD_LIBRARY_PATH
            # shellcheck disable=SC1090
            source "$setup_env" > /dev/null 2>&1
            [[ -f "$sdk_env" ]] && source "$sdk_env" > /dev/null 2>&1
            # shellcheck disable=SC1090
            source "$oe_init" "$proj" > /dev/null 2>&1
            bitbake -k --runall=fetch "$image_target"
        ) 2>&1 | tee "$fetch_log"
        fetch_rc="${PIPESTATUS[0]}"

        # Collect every URL bitbake reported as unfetchable.
        dl_dir="$proj/downloads"
        missing="$proj/fetch-missing.txt"
        grep -oE 'https?://[^ ]+\.(tar\.[a-z0-9]+|zip|tgz|tar\.bz2|tar\.xz|git\.tar\.gz)' "$fetch_log" \
            2>/dev/null | sort -u > "$missing" || true

        echo ""
        echo "==> Fetch summary"
        echo "    log:     ${fetch_log#$repo_root/}"
        if [[ -s "$missing" ]]; then
            echo "    $(wc -l < "$missing") source(s) could not be downloaded:"
            echo ""
            echo "    Run these from the repository root to fill the cache by hand:"
            echo ""
            while read -r url; do
                base="${url##*/}"
                echo "      wget -O .cache/petalinux-2024.1-ubuntu22/build/downloads/$base '$url'"
                echo "      touch .cache/petalinux-2024.1-ubuntu22/build/downloads/$base.done"
            done < "$missing"
            echo ""
            echo "    Then run 'make PETALINUX_ENV=container fetch-check' again."
            exit 1
        fi
        if [[ $fetch_rc -ne 0 ]]; then
            echo "    Fetch returned status $fetch_rc but named no URLs."
            echo "    Check the log above for the failing task."
            exit 1
        fi
        echo "    All sources for $image_target are present in the cache."
        exit 0
        ;;
    *)
        echo "Usage: $0 <config|build|app-tdc|app-ct>"
        exit 1
        ;;
esac

popd > /dev/null
