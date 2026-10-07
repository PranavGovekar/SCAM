#!/usr/bin/env bash
set -euo pipefail

# Cross-compile one application's userspace binary, without PetaLinux.
# Usage: build_sw.sh <app-name>
#
#   SCAM_SDK  directory where the SCAM/PetaLinux SDK (sdk.sh) was installed.
#             Its environment-setup-* file is sourced. Not needed when the SDK
#             environment is already sourced or CC is set by hand.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

target="${1:-}"
if [[ -z "$target" ]]; then
    echo "Usage: $0 <app-name>" >&2
    exit 2
fi

apps="$SCAM_ROOT/scripts/apps.sh"
app_dir="$(bash "$apps" dir "$target")"
if [[ "$(bash "$apps" get "$target" has_sw)" != 1 ]]; then
    echo "Application '$target' has no software (expected $app_dir/sw/*.c)." >&2
    exit 1
fi
bin_path="$(bash "$apps" binpath "$target")"

if [[ -n "${SCAM_SDK:-}" ]]; then
    sdk_env="$(compgen -G "$SCAM_SDK/environment-setup-*" | head -n 1 || true)"
    if [[ -z "$sdk_env" ]]; then
        echo "No environment-setup-* file in SCAM_SDK=$SCAM_SDK" >&2
        echo "Install the SDK first: sh sdk.sh -d <dir>, then SCAM_SDK=<dir>." >&2
        exit 1
    fi
    set +u
    unset LD_LIBRARY_PATH
    # shellcheck disable=SC1090
    source "$sdk_env"
    set -u
fi

makefile="$app_dir/sw/Makefile"
[[ -f "$makefile" ]] || makefile="$SCAM_ROOT/sw/common/app.mk"

echo "==> Building '$target' userspace binary"
make --no-print-directory -C "$app_dir/sw" -f "$makefile" \
    SCAM_ROOT="$SCAM_ROOT" APP="$target" \
    BINARY="$(basename "$bin_path")" OUT_DIR="$(dirname "$bin_path")"
echo "==> ${bin_path#"$SCAM_ROOT"/}"
