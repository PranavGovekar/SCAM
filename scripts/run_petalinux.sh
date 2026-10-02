#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment="${PETALINUX_ENV:-host}"

case "$environment" in
    host)
        exec bash "$repo_root/scripts/build_petalinux.sh" "$action"
        ;;
    container|docker)
        exec bash "$repo_root/scripts/build_petalinux_container.sh" "$action"
        ;;
    *)
        echo "Unknown PETALINUX_ENV '$environment' (expected host or container)." >&2
        exit 2
        ;;
esac

