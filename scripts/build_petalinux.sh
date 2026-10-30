#!/usr/bin/env bash
set -euo pipefail

# PetaLinux helper. Runs on the host, or inside the container started by
# build_petalinux_container.sh.
usage="Usage: $0 <config|build|app <recipe>|wic|sdk|fetch-check>"

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

action="${1:-}"
recipe="${2:-}"
repo_root="$SCAM_ROOT"
petalinux_project="${PETALINUX_PROJECT_DIR:-$SCAM_PETALINUX_DIR}"
petalinux_settings="${PETALINUX_SETTINGS:-$PETALINUX_ROOT/settings.sh}"
images_dir="$petalinux_project/images/linux"

if [[ -z "${PETALINUX:-}" ]] || ! command -v petalinux-config >/dev/null 2>&1; then
    if [[ ! -r "$petalinux_settings" ]]; then
        echo "PetaLinux settings not found: $petalinux_settings" >&2
        echo "Set PETALINUX_ROOT to your PetaLinux $PETALINUX_VERSION installation." >&2
        exit 1
    fi
    # The user's interactive bash config puts a standalone GCC 16 toolchain at
    # the front of PATH. That compiler cannot find its matching linker here,
    # which breaks native Yocto recipes. Prefer the host compiler/binutils for
    # BitBake while leaving the user's shell configuration untouched.
    export PATH="/usr/bin:/bin:${PATH}"
    set --
    # shellcheck disable=SC1090
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
        echo "PetaLinux failed. Last 15 lines of ${log#"$repo_root"/}:" >&2
        tail -n 15 "$log" >&2
    else
        echo "PetaLinux failed and its log was not written: ${log#"$repo_root"/}" >&2
        echo "Re-run with the log kept, or check petalinux/build/ inside the container." >&2
    fi
    echo "" >&2
}

# Board network identity, from config.mk (SCAM_HOSTNAME, SCAM_IP, SCAM_GATEWAY,
# SCAM_DNS).
# The values are written into project-spec/configs/config before every
# configure and build; PetaLinux then puts the host name into /etc/hostname and
# the address into systemd's wired.network.
apply_network_settings() {
    local cfg="$petalinux_project/project-spec/configs/config"
    local eth="CONFIG_SUBSYSTEM_ETHERNET_PSU_ETHERNET_3"
    local hostname="${SCAM_HOSTNAME:-data-yeeter}"
    local ip="${SCAM_IP:-dhcp}"
    local gateway="${SCAM_GATEWAY:-}"
    local dns="${SCAM_DNS:-}"
    local dns_conf="$petalinux_project/project-spec/meta-user/recipes-core/systemd-conf/files/scam-dns.conf"
    local addr="" prefix="" netmask="" octet i bits server
    local ipv4='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$'

    [[ -f "$cfg" ]] || return 0

    # systemd refuses a host name with any other character (an underscore
    # included) and the board then comes up as "localhost".
    if [[ ! "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]]; then
        echo "SCAM_HOSTNAME '$hostname' is not a valid host name." >&2
        echo "Use letters, digits and '-' only, for example data-yeeter." >&2
        exit 1
    fi

    if [[ "$ip" != "dhcp" ]]; then
        addr="${ip%%/*}"
        prefix=24
        [[ "$ip" == */* ]] && prefix="${ip#*/}"
        if [[ ! "$prefix" =~ ^[0-9]{1,2}$ ]] || (( 10#$prefix < 1 || 10#$prefix > 32 )) \
                || [[ ! "$addr" =~ $ipv4 ]]; then
            echo "SCAM_IP '$ip' is not understood." >&2
            echo "Use dhcp, or an address with prefix length such as 192.168.1.50/24." >&2
            exit 1
        fi
        for octet in "${BASH_REMATCH[@]:1}"; do
            if (( 10#$octet > 255 )); then
                echo "SCAM_IP '$ip' is not a valid IPv4 address." >&2
                exit 1
            fi
        done
        prefix=$(( 10#$prefix ))
        if [[ -n "$gateway" && ! "$gateway" =~ $ipv4 ]]; then
            echo "SCAM_GATEWAY '$gateway' is not a valid IPv4 address." >&2
            exit 1
        fi
        # PetaLinux wants the mask in dotted form (255.255.255.0 for /24).
        for i in 0 1 2 3; do
            bits=$(( prefix - 8 * i ))
            (( bits > 8 )) && bits=8
            (( bits < 0 )) && bits=0
            netmask+="${netmask:+.}$(( 256 - (1 << (8 - bits)) ))"
        done
    fi

    # DNS servers go to systemd-resolved through the systemd-conf bbappend in
    # meta-user. Without SCAM_DNS the file stays empty: the DHCP server's DNS
    # is used, and a fixed address has none.
    dns="${dns//,/ }"
    for server in $dns; do
        if [[ ! "$server" =~ $ipv4 ]]; then
            echo "SCAM_DNS '$server' is not a valid IPv4 address." >&2
            exit 1
        fi
    done
    mkdir -p "$(dirname "$dns_conf")"
    if [[ -n "${dns// /}" ]]; then
        printf '[Resolve]\nDNS=%s\n' "$(echo $dns)" > "$dns_conf.new"
    else
        printf '# No DNS servers set (SCAM_DNS in config.mk).\n' > "$dns_conf.new"
    fi
    # Rewrite only on a change, so BitBake does not rebuild systemd-conf.
    if cmp -s "$dns_conf.new" "$dns_conf"; then
        rm -f "$dns_conf.new"
    else
        mv "$dns_conf.new" "$dns_conf"
    fi

    local new="$cfg.scam-new"
    grep -v -E "^(# )?(CONFIG_SUBSYSTEM_HOSTNAME|${eth}_(USE_DHCP|IP_ADDRESS|IP_NETMASK|IP_GATEWAY))[= ]" \
        "$cfg" > "$new" || true
    {
        echo "CONFIG_SUBSYSTEM_HOSTNAME=\"$hostname\""
        if [[ "$ip" == "dhcp" ]]; then
            echo "${eth}_USE_DHCP=y"
        else
            echo "# ${eth}_USE_DHCP is not set"
            echo "${eth}_IP_ADDRESS=\"$addr\""
            echo "${eth}_IP_NETMASK=\"$netmask\""
            echo "${eth}_IP_GATEWAY=\"$gateway\""
        fi
    } >> "$new"
    # PetaLinux moves these lines around, so compare without regard to order.
    if cmp -s <(sort "$cfg") <(sort "$new"); then
        rm -f "$new"
    else
        cat "$new" > "$cfg"
        rm -f "$new"
    fi

    # PetaLinux writes wired.network for a static address but never removes it
    # again, so a return to DHCP would keep the old address.
    if [[ "$ip" == "dhcp" ]]; then
        rm -f "$petalinux_project/project-spec/configs/systemd-conf/wired.network"
        echo "==> Network: host name $hostname, address from DHCP"
    else
        echo "==> Network: host name $hostname, static $addr/$prefix${gateway:+, gateway $gateway}"
    fi
    [[ -n "${dns// /}" ]] && echo "==> DNS: $(echo $dns)"
    return 0
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
        apply_network_settings

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
        apply_network_settings
        echo "==> petalinux-build"
        if ! petalinux-build; then
            show_petalinux_log build
            exit 1
        fi
        # BOOT.BIN = FSBL + PMU firmware + TF-A + U-Boot. No bitstream: the PL
        # is loaded at runtime by fpga-load.service / scam-load.
        echo "==> petalinux-package boot"
        petalinux-package boot --u-boot --force
        ;;
    app)
        if [[ -z "$recipe" ]]; then
            echo "$usage" >&2
            exit 2
        fi
        echo "==> Staging sources into the recipes"
        bash "$repo_root/scripts/stage_assets.sh" sources
        echo "==> Rebuilding only $recipe"
        petalinux-build -c "$recipe" -x do_compile || true
        if ! petalinux-build -c "$recipe"; then
            show_petalinux_log build
            exit 1
        fi
        ;;
    wic)
        for f in BOOT.BIN image.ub boot.scr rootfs.tar.gz; do
            if [[ ! -f "$images_dir/$f" ]]; then
                echo "No built image in ${images_dir#"$repo_root"/} ($f is missing). Run: make petalinux" >&2
                exit 1
            fi
        done
        echo "==> petalinux-package wic"
        # petalinux-package renames the finished image out of build/wic, which
        # fails when build/ is a separate mount (the container). Let it write
        # inside build/ and copy the result out.
        wic_out="$petalinux_project/build/wic-out"
        rm -rf "$wic_out"
        petalinux-package wic --outdir "$wic_out"
        mkdir -p "$(dirname "$SCAM_WIC")"
        cp --sparse=always -f "$wic_out/petalinux-sdimage.wic" "$SCAM_WIC"
        rm -rf "$wic_out"
        # Earlier versions of this script left a copy here.
        rm -f "$images_dir/petalinux-sdimage.wic"
        echo "==> SD card image: ${SCAM_WIC#"$repo_root"/}"
        echo "    Write it to a card with: make flash SD=/dev/sdX"
        ;;
    sdk)
        echo "==> petalinux-build --sdk"
        if ! petalinux-build --sdk; then
            show_petalinux_log build
            exit 1
        fi
        echo "==> SDK installer: ${images_dir#"$repo_root"/}/sdk.sh"
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
            echo "Run: make petalinux-config" >&2
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
            echo "Run: make clean-petalinux, then make petalinux-config" >&2
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
        # Inside the container $proj/downloads is a bind mount; show the host path.
        dl_dir="${SCAM_HOST_DL_DIR:-$proj/downloads}"
        missing="$proj/fetch-missing.txt"
        grep -oE 'https?://[^ ]+\.(tar\.[a-z0-9]+|zip|tgz|tar\.bz2|tar\.xz|git\.tar\.gz)' "$fetch_log" \
            2>/dev/null | sort -u > "$missing" || true

        echo ""
        echo "==> Fetch summary"
        echo "    log:     ${fetch_log#"$repo_root"/}"
        if [[ -s "$missing" ]]; then
            echo "    $(wc -l < "$missing") source(s) could not be downloaded:"
            echo ""
            echo "    Run these to fill the cache by hand:"
            echo ""
            while read -r url; do
                base="${url##*/}"
                echo "      wget -O $dl_dir/$base '$url'"
                echo "      touch $dl_dir/$base.done"
            done < "$missing"
            echo ""
            echo "    Then run 'make fetch-check' again."
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
        echo "$usage" >&2
        exit 2
        ;;
esac

popd > /dev/null
