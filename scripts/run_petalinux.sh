#!/usr/bin/env bash
set -euo pipefail

# Dispatch a PetaLinux action to the host or the container.
# Usage: PETALINUX_ENV=<host|container> run_petalinux.sh <action> [args]

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
environment="${PETALINUX_ENV:-host}"

case "$environment" in
    host)
        exec bash "$repo_root/scripts/build_petalinux.sh" "$@"
        ;;
    container|docker)
        exec bash "$repo_root/scripts/build_petalinux_container.sh" "$@"
        ;;
    *)
        echo "Unknown PETALINUX_ENV '$environment' (expected host or container)." >&2
        exit 2
        ;;
esac

