#!/usr/bin/env bash
set -euo pipefail

# Copy one application's bitstream and binary onto a running board.
# Usage: deploy.sh <app-name> <user@host>
#
# Installs <bitstream>.bit.bin into /lib/firmware/ and the binary into
# /usr/bin/ (through sudo on the board). Whatever has been built is copied.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

app="${1:-}"
target="${2:-}"
if [[ -z "$app" || -z "$target" ]]; then
    echo "Usage: $0 <app-name> <user@host>   (make deploy APP=<name> TARGET=<user@host>)" >&2
    exit 2
fi

apps="$SCAM_ROOT/scripts/apps.sh"
bit="$(bash "$apps" bitpath "$app")"
bin="$(bash "$apps" binpath "$app")"

files=()
remote=""
if [[ -f "$bit" ]]; then
    files+=("$bit")
    remote+="sudo install -m 0644 /tmp/$(basename "$bit") /lib/firmware/ && "
fi
if [[ -f "$bin" ]]; then
    files+=("$bin")
    remote+="sudo install -m 0755 /tmp/$(basename "$bin") /usr/bin/ && "
fi
if [[ ${#files[@]} -eq 0 ]]; then
    echo "Nothing built for '$app'. Run: make $app-bitstream app-$app" >&2
    exit 1
fi
remote+="rm -f"
for f in "${files[@]}"; do
    remote+=" /tmp/$(basename "$f")"
done

echo "==> Copying to $target: ${files[*]##*/}"
scp "${files[@]}" "$target:/tmp/"
ssh -t "$target" "$remote"

bitname="$(basename "$bit" .bit.bin)"
echo "==> Deployed. On the board:"
[[ -f "$bit" ]] && echo "      sudo fpgautil -b /lib/firmware/$bitname.bit.bin"
[[ -f "$bin" ]] && echo "      sudo $(basename "$bin") <host-ip>"
exit 0
