#!/usr/bin/env bash
set -euo pipefail

# Create a new application from apps/_template.
# Usage: new_app.sh <name> [destination-dir]   (default destination: apps/)

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

name="${1:-}"
dest="${2:-$SCAM_ROOT/apps}"
if [[ ! "$name" =~ ^[a-z][a-z0-9_-]*$ || "$name" == base ]]; then
    echo "Usage: $0 <name> [destination-dir]" >&2
    echo "The name must use lowercase letters, digits, '-' and '_'." >&2
    exit 2
fi
if [[ -e "$dest/$name" ]]; then
    echo "$dest/$name already exists." >&2
    exit 1
fi

mkdir -p "$dest"
cp -r "$SCAM_ROOT/apps/_template" "$dest/$name"
dest="$(cd "$dest" && pwd)"
mv "$dest/$name/sw/yeet-data-template.c" "$dest/$name/sw/yeet-data-$name.c"
sed -i "s/@APP@/$name/g" "$dest/$name/README.md" "$dest/$name/sw/Makefile" \
    "$dest/$name/sw/yeet-data-$name.c" "$dest/$name/hw/bd.tcl" "$dest/$name/app.conf"

echo "Created $dest/$name"
if [[ "$dest" != "$SCAM_ROOT/apps" ]]; then
    echo "It is outside the repository: add SCAM_APPS=$dest to config.mk or the make command line."
fi
echo "Next: edit hw/bd.tcl and sw/, then: make $name-bitstream app-$name"
