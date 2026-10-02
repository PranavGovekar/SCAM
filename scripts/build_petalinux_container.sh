#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
petalinux_root="${PETALINUX_ROOT:-${HOME}/petalinux/2024.1}"
settings_path="${petalinux_root}/settings.sh"
cache_root="${SCAM_PETALINUX_CACHE:-${repo_root}/.cache/petalinux-2024.1-ubuntu22}"
image="scam-petalinux:2024.1-ubuntu22"

if [[ -z "$action" ]]; then
    echo "Usage: $0 <config|build|app-tdc|app-ct>" >&2
    exit 2
fi
if [[ ! -r "$settings_path" ]]; then
    echo "PetaLinux settings not found: $settings_path" >&2
    echo "Set PETALINUX_ROOT to your PetaLinux 2024.1 installation." >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "Docker is required for PETALINUX_ENV=container." >&2
    exit 1
fi

mkdir -p "$cache_root"/{build,components,tmp,home,sdk-statistics}
# PetaLinux reads the installed SDK's per-architecture checksums and may update
# them. Seed a writable overlay with those files so the SDK mount can stay
# read-only without hiding its metadata.
cp -a --no-clobber "$petalinux_root/components/yocto/.statistics/." \
    "$cache_root/sdk-statistics/"

echo "==> Building the Ubuntu 22.04 PetaLinux prerequisite image"
docker build \
    --build-arg "SCAM_UID=$(id -u)" \
    --build-arg "SCAM_GID=$(id -g)" \
    -f "$repo_root/Dockerfile.petalinux" \
    -t "$image" \
    "$repo_root"

echo "==> Running PetaLinux action '$action' in Ubuntu 22.04"
docker_args=(run --rm --init)
# PetaLinux's first-time hardware configuration may need Kconfig choices that
# have no default. Preserve a real terminal so those prompts can be answered.
# Build and app actions remain suitable for non-interactive automation.
if [[ "$action" == "config" && -t 0 && -t 1 ]]; then
    docker_args+=(--interactive --tty)
fi
docker "${docker_args[@]}" \
    --hostname scam-petalinux \
    --mount "type=bind,src=$repo_root,dst=/workspace" \
    --mount "type=bind,src=$cache_root/build,dst=/workspace/petalinux/build" \
    --mount "type=bind,src=$cache_root/components,dst=/workspace/petalinux/components" \
    --mount "type=bind,src=$cache_root/tmp,dst=/tmp/scam-petalinux-tmp" \
    --mount "type=bind,src=$cache_root/home,dst=/home/scam" \
    --mount "type=bind,src=$petalinux_root,dst=$petalinux_root,readonly" \
    --mount "type=bind,src=$cache_root/sdk-statistics,dst=$petalinux_root/components/yocto/.statistics" \
    --env "HOME=/home/scam" \
    --env "PETALINUX_SETTINGS=$settings_path" \
    --env "PETALINUX_PROJECT_DIR=/workspace/petalinux" \
    --env "KCONFIG_OVERWRITECONFIG=1" \
    --workdir /workspace \
    "$image" \
    bash scripts/build_petalinux.sh "$action"
