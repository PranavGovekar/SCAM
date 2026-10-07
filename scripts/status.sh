#!/usr/bin/env bash
set -uo pipefail

# Show what has been built, when, what is out of date, and what to run next.
# Read-only: builds and changes nothing.
# Usage: status.sh   (make status)

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
cd "$SCAM_ROOT"

apps="$SCAM_ROOT/scripts/apps.sh"
env_name="${PETALINUX_ENV:-host}"
img="$SCAM_IMAGES_DIR"
next=()

rel() { echo "${1#"$SCAM_ROOT"/}"; }
when() { date -r "$1" '+%m-%d %H:%M'; }
row() { printf '  %-22s %-10s %-12s %s\n' "$1" "$2" "$3" "${4:-}"; }
need() {
    local c
    for c in "${next[@]:-}"; do [[ "$c" == "$1" ]] && return 0; done
    next+=("$1")
}

# Ask Make whether a file target it tracks is up to date.
make_fresh() {
    env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS make --no-print-directory -q "$1" > /dev/null 2>&1
}

# First of the given files/directories holding something newer than $1.
newer_than() {
    local target="$1"; shift
    find "$@" -type f -newer "$target" -print -quit 2>/dev/null
}

# report <label> <file> <stale-reason-or-empty> <command>
# Prints the row and queues the command when missing or stale. Returns 0 when current.
report() {
    local label="$1" file="$2" reason="$3" cmd="$4"
    if [[ ! -e "$file" ]]; then
        row "$label" missing "" ""
        [[ -n "$cmd" ]] && need "$cmd"
        return 1
    fi
    if [[ -n "$reason" ]]; then
        row "$label" stale "$(when "$file")" "$reason"
        [[ -n "$cmd" ]] && need "$cmd"
        return 1
    fi
    row "$label" built "$(when "$file")" ""
    return 0
}

echo "Hardware"
xsa="$SCAM_ROOT/hw/base/system.xsa"
reason=""
if [[ -e "$xsa" ]] && ! make_fresh hw/base/system.xsa; then
    reason="$(rel "$(newer_than "$xsa" hw/base/build_base_xsa.tcl hw/base/src hw/base/constraints)") is newer"
fi
report "Base XSA" "$xsa" "$reason" "make base-xsa"

bits_recipe="$SCAM_RECIPES/recipes-bsp/fpga-bitstreams/fpga-bitstreams.bb"
image_inputs_stale=""
while IFS='|' read -r name dir bitname binary has_hw has_sw; do
    [[ -n "$name" ]] || continue
    if [[ "$has_hw" == 1 ]]; then
        bit="$SCAM_BUILD/apps/$name/$bitname.bit.bin"
        reason=""
        if [[ -e "$bit" ]] && ! make_fresh "build/apps/$name/$bitname.bit.bin"; then
            n="$(newer_than "$bit" "$dir/hw" hw/base/scam_app.tcl "$xsa")"
            reason="$(rel "${n:-a source}") is newer"
        fi
        if ! report "$name bitstream" "$bit" "$reason" "make $name-bitstream"; then
            grep -q "file://$bitname.bit.bin\b" "$bits_recipe" 2>/dev/null && \
                image_inputs_stale="$name bitstream is not current"
        fi
    fi
done < <(bash "$apps" table)

echo
echo "Programs (standalone SDK builds; the image builds its own copies)"
while IFS='|' read -r name dir bitname binary has_hw has_sw; do
    [[ "$has_sw" == 1 ]] || continue
    bin="$SCAM_BUILD/apps/$name/$binary"
    if [[ ! -e "$bin" ]]; then
        row "$name program" "not built" "" "optional: make app-$name SCAM_SDK=<installed sdk>"
        continue
    fi
    n="$(newer_than "$bin" "$dir/sw" sw/common)"
    if [[ -n "$n" ]]; then
        if [[ -n "${SCAM_SDK:-}" ]]; then
            row "$name program" stale "$(when "$bin")" "$(rel "$n") is newer"
            need "make app-$name"
        else
            row "$name program" stale "$(when "$bin")" "$(rel "$n") is newer (optional: make app-$name SCAM_SDK=<installed sdk>)"
        fi
    else
        row "$name program" built "$(when "$bin")"
    fi
done < <(bash "$apps" table)

echo
echo "Linux image (PETALINUX_ENV=$env_name)"
stamp="$SCAM_BUILD/.petalinux-config.$env_name.stamp"
config="$SCAM_PETALINUX_DIR/project-spec/configs/config"
if [[ ! -e "$config" || ! -e "$stamp" ]]; then
    row "PetaLinux config" missing "" "done by make petalinux"
    image_inputs_stale="${image_inputs_stale:-PetaLinux is not configured}"
elif [[ "$xsa" -nt "$stamp" ]]; then
    row "PetaLinux config" stale "$(when "$stamp")" "base XSA is newer"
    image_inputs_stale="${image_inputs_stale:-PetaLinux configuration is not current}"
else
    row "PetaLinux config" built "$(when "$stamp")"
fi

rootfs="$img/rootfs.tar.gz"
reason="$image_inputs_stale"
if [[ -z "$reason" && -e "$rootfs" ]]; then
    # Sources of every application that has a recipe, plus the layer itself.
    # (conf/ is left out: PetaLinux rewrites files there on every build.)
    inputs=(sw/common "$SCAM_RECIPES"/recipes-*)
    while IFS='|' read -r name dir bitname binary has_hw has_sw; do
        [[ -d "$SCAM_RECIPES/recipes-apps/$binary" && "$has_sw" == 1 ]] && inputs+=("$dir/sw")
    done < <(bash "$apps" table)
    n="$(find "${inputs[@]}" -type f \( -name '*.c' -o -name '*.h' -o -name '*.bb' -o -name '*.bbappend' \
            -o -name '*.dtsi' -o -name '*.conf' -o -name '*.cfg' -o -name '*.service' \) \
            -newer "$rootfs" -print -quit 2>/dev/null)"
    [[ -n "$n" ]] && reason="$(rel "$n") is newer"
    for t in config.template rootfs_config.template; do
        [[ -z "$reason" && "$SCAM_PETALINUX_DIR/project-spec/configs/$t" -nt "$rootfs" ]] && \
            reason="$t is newer (make clean-petalinux-config first)"
    done
fi
image_ok=1
report "Kernel + rootfs" "$rootfs" "$reason" "make petalinux" || image_ok=0

reason=""
[[ $image_ok -eq 0 ]] && reason="image is not current"
[[ -z "$reason" && -e "$img/BOOT.BIN" && "$img/u-boot.elf" -nt "$img/BOOT.BIN" ]] && reason="boot components are newer"
boot_ok=1
report "BOOT.BIN" "$img/BOOT.BIN" "$reason" "make sdcard" || boot_ok=0

reason=""
[[ $image_ok -eq 0 || $boot_ok -eq 0 ]] && reason="image is not current"
[[ -z "$reason" && -e "$img/petalinux-sdimage.wic" && "$rootfs" -nt "$img/petalinux-sdimage.wic" ]] && reason="rootfs is newer"
report "SD image (.wic)" "$img/petalinux-sdimage.wic" "$reason" "make sdcard" || boot_ok=0

report "SDK installer" "$img/sdk.sh" "" "make sdk" || true

echo
echo "Outputs"
reason=""
[[ $image_ok -eq 0 || $boot_ok -eq 0 ]] && reason="image is not current"
if [[ -z "$reason" && -e "$SCAM_OUT/rootfs.tar.gz" ]]; then
    for f in BOOT.BIN image.ub boot.scr rootfs.tar.gz; do
        [[ "$img/$f" -nt "$SCAM_OUT/$f" ]] && reason="$f in the image directory is newer"
    done
fi
out_ok=1
report "SD card files (out/)" "$SCAM_OUT/rootfs.tar.gz" "$reason" "make sdcard" || out_ok=0

sums="$SCAM_OUT/release/SHA256SUMS"
reason=""
[[ $out_ok -eq 0 ]] && reason="SD card files are not current"
[[ -z "$reason" && -e "$sums" && "$SCAM_OUT/rootfs.tar.gz" -nt "$sums" ]] && reason="SD card files are newer"
[[ -z "$reason" && -e "$sums" && "$img/sdk.sh" -nt "$sums" ]] && reason="SDK installer is newer"
report "Release (out/release/)" "$sums" "$reason" "make release" || true

echo
if [[ ${#next[@]} -eq 0 ]]; then
    echo "Everything is up to date."
else
    echo "Next, in this order:"
    # Hardware first, then the image chain in its fixed order.
    for c in "${next[@]}"; do
        case "$c" in make\ base-xsa) echo "  $c" ;; esac
    done
    for c in "${next[@]}"; do
        case "$c" in make\ *-bitstream|make\ app-*) echo "  $c" ;; esac
    done
    for want in "make petalinux" "make sdcard" "make sdk" "make release"; do
        for c in "${next[@]}"; do [[ "$c" == "$want" ]] && echo "  $c"; done
    done
fi
