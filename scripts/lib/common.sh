#!/usr/bin/env bash
# Shared paths and helpers for the SCAM build scripts. Source this file.

SCAM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAM_BUILD="${SCAM_BUILD:-$SCAM_ROOT/build}"
SCAM_OUT="$SCAM_ROOT/out"

PETALINUX_VERSION="2024.1"
PETALINUX_ROOT="${PETALINUX_ROOT:-$HOME/petalinux/$PETALINUX_VERSION}"
SCAM_PETALINUX_DIR="$SCAM_ROOT/petalinux"
SCAM_RECIPES="$SCAM_PETALINUX_DIR/project-spec/meta-user"
# petalinuxbsp.conf points PLNX_DEPLOY_DIR here for host and container builds.
SCAM_IMAGES_DIR="$SCAM_PETALINUX_DIR/images/linux"

# Container build state. PetaLinux believes its eSDK is already set up as soon
# as components/yocto/environment-setup-* exists, so components/ must be
# removed whole or not at all -- never in part.
SCAM_PETALINUX_CACHE="${SCAM_PETALINUX_CACHE:-$SCAM_ROOT/.cache/petalinux-$PETALINUX_VERSION-ubuntu22}"
SCAM_CONTAINER_IMAGE="scam-petalinux:$PETALINUX_VERSION-ubuntu22"

# Copy only when the destination is missing or its content differs. This keeps
# mtimes stable so BitBake does not recompile unchanged recipes.
copy_if_changed() {
    local src="$1" dst="$2"
    [[ -f "$src" ]] || return 0
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        return 0
    fi
    cp -f "$src" "$dst"
    echo "    staged $(basename "$dst")"
}
