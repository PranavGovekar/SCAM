#!/usr/bin/env bash
set -euo pipefail

# Run build_petalinux.sh inside the Ubuntu 22.04 prerequisite container.
# Arguments are passed through unchanged.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

action="${1:-}"
repo_root="$SCAM_ROOT"
petalinux_root="$PETALINUX_ROOT"
settings_path="${petalinux_root}/settings.sh"
cache_root="$SCAM_PETALINUX_CACHE"
image="$SCAM_CONTAINER_IMAGE"

if [[ -z "$action" ]]; then
    echo "Usage: $0 <config|build|app <recipe>|package|sdk|fetch-check>" >&2
    exit 2
fi
if [[ ! -r "$settings_path" ]]; then
    echo "PetaLinux settings not found: $settings_path" >&2
    echo "Set PETALINUX_ROOT to your PetaLinux $PETALINUX_VERSION installation." >&2
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
# PetaLinux treats the eSDK as "already set up" as soon as the environment-setup-*
# marker exists. If layers/ or sysroots/ is missing while that marker survives,
# every build dies at oe-init-build-env with an empty [ERROR]. Refuse early.
if compgen -G "$cache_root/components/yocto/environment-setup-*" > /dev/null; then
    if [[ ! -e "$cache_root/components/yocto/layers/poky/oe-init-build-env" ]]; then
        cat >&2 <<'MSG'
PetaLinux's saved build files are incomplete. Run:
make clean-container-state, then make petalinux-config
MSG
        exit 1
    fi
fi
# Applications outside the repository must be visible at the same path.
IFS=':' read -r -a extra_roots <<< "${SCAM_APPS:-}"
for root in ${extra_roots[@]+"${extra_roots[@]}"}; do
    [[ -d "$root" ]] || continue
    root="$(cd "$root" && pwd)"
    docker_args+=(--mount "type=bind,src=$root,dst=$root,readonly")
done
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
    --env "SCAM_APPS=${SCAM_APPS:-}" \
    --env "SCAM_HOST_DL_DIR=$cache_root/build/downloads" \
    --workdir /workspace \
    "$image" \
    bash scripts/build_petalinux.sh "$@"
