#!/usr/bin/env bash
set -uo pipefail

# Check that this machine has what the project needs. Read-only.
# Usage: doctor.sh [--full]   (make doctor, make doctor FULL=1)
#
# --full also runs a one-minute Vivado synthesis to prove that a license can
# actually be checked out, not just that the server answers.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

full=0
[[ "${1:-}" == "--full" ]] && full=1

fails=0
warns=0
ok()   { printf '  ok    %s\n' "$1"; }
warn() { printf '  warn  %s\n        -> %s\n' "$1" "$2"; warns=$((warns + 1)); }
fail() { printf '  FAIL  %s\n        -> %s\n' "$1" "$2"; fails=$((fails + 1)); }
have() { command -v "$1" > /dev/null 2>&1; }

# Run a snippet in the same shell environment scripts/run_vivado.sh gives Vivado.
vivado_shell() {
    if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
        [[ -r "$VIVADO_SETTINGS" ]] || return 1
        bash -c 'set +u; source "$1" > /dev/null 2>&1; eval "$2"' _ "$VIVADO_SETTINGS" "$1" 2> /dev/null
    else
        bash -ic "$1" 2> /dev/null
    fi
}

echo "Always needed"
for tool in bash make git tar xz sha256sum; do
    if have "$tool"; then ok "$tool"; else fail "$tool not found" "install it with your package manager"; fi
done
if have make && ! make --version 2> /dev/null | grep -q "GNU Make"; then
    fail "make is not GNU Make" "install GNU Make"
fi
free_gb="$(df -BG --output=avail "$SCAM_ROOT" 2> /dev/null | tail -n 1 | tr -dc '0-9')"
if [[ -z "$free_gb" ]]; then
    warn "could not read free disk space" "make sure there is room: a clean image build needs about 100 GB"
elif (( free_gb < 100 )); then
    warn "${free_gb} GB free on the repository's disk" "a clean image build needs about 100 GB; bitstreams alone need about 10 GB"
else
    ok "${free_gb} GB free disk space"
fi

echo
echo "Bitstreams (make base-xsa, make <app>-bitstream)"
vivado_ok=0
if [[ -n "${VIVADO_SETTINGS:-}" && ! -r "$VIVADO_SETTINGS" ]]; then
    fail "VIVADO_SETTINGS is not readable: $VIVADO_SETTINGS" "point it at Vivado's settings64.sh in config.mk"
else
    version="$(bash "$SCAM_ROOT/scripts/run_vivado.sh" -version 2> /dev/null | grep -oE 'v[0-9]{4}\.[0-9]+' | head -n 1)"
    if [[ -z "$version" ]]; then
        fail "Vivado does not start" "set VIVADO_SETTINGS in config.mk to Vivado's settings64.sh (see config.mk.example)"
    elif [[ "$version" != "v2024.1" ]]; then
        fail "Vivado is $version, the project needs v2024.1" "install Vivado 2024.1 and point VIVADO_SETTINGS at it"
    else
        ok "Vivado $version"
        vivado_ok=1
    fi
fi
if [[ $vivado_ok -eq 1 ]]; then
    xv="$(vivado_shell 'echo "$XILINX_VIVADO"' | tail -n 1)"
    if [[ -z "$xv" || ! -d "$xv" ]]; then
        warn "could not locate the Vivado installation to check board files" "make sure the ZCU102 board files are installed"
    elif compgen -G "$xv/data/boards/board_files/zcu102*" > /dev/null || \
         compgen -G "$xv/data/xhub/boards/XilinxBoardStore/boards/Xilinx/zcu102*" > /dev/null; then
        ok "ZCU102 board files"
    else
        fail "ZCU102 board files not found under $xv" "install them from Vivado: Tools > Vivado Store > Boards"
    fi
fi
# build_hw.sh runs bootgen from the plain environment, or after VIVADO_SETTINGS.
if have bootgen || [[ -n "$(vivado_shell 'command -v bootgen' | tail -n 1)" && -n "${VIVADO_SETTINGS:-}" ]]; then
    ok "bootgen"
else
    fail "bootgen not found" "it ships with Vivado/Vitis: set VIVADO_SETTINGS in config.mk, or put it on PATH"
fi

license="${XILINXD_LICENSE_FILE:-${LM_LICENSE_FILE:-}}"
if [[ -z "$license" && -r "$HOME/.flexlmrc" ]]; then
    license="$(sed -n 's/^XILINXD_LICENSE_FILE=//p' "$HOME/.flexlmrc" | head -n 1)"
fi
if [[ -z "$license" ]]; then
    if compgen -G "$HOME/.Xilinx/*.lic" > /dev/null; then
        ok "license file in ~/.Xilinx"
    else
        warn "no Vivado license source found" "the ZCU102 device needs a license: set XILINXD_LICENSE_FILE, or install a .lic in ~/.Xilinx"
    fi
else
    IFS=':' read -r -a sources <<< "$license"
    for src in "${sources[@]}"; do
        if [[ "$src" == *@* ]]; then
            port="${src%@*}"; host="${src#*@}"
            if timeout 6 bash -c "echo > /dev/tcp/$host/$port" 2> /dev/null; then
                ok "license server $src answers"
            else
                fail "license server $src does not answer" "check the network/VPN to $host, or ask whoever runs the server"
            fi
        elif [[ -r "$src" ]]; then
            ok "license file $src"
        else
            fail "license file $src is not readable" "fix the path in XILINXD_LICENSE_FILE / LM_LICENSE_FILE"
        fi
    done
fi
if [[ $full -eq 1 && $vivado_ok -eq 1 ]]; then
    work="$(mktemp -d)"
    cat > "$work/t.vhd" <<'VHD'
library ieee; use ieee.std_logic_1164.all;
entity t is port (a, b : in std_logic; y : out std_logic); end;
architecture r of t is begin y <= a and b; end;
VHD
    cat > "$work/t.tcl" <<'TCL'
read_vhdl t.vhd
if {[catch {synth_design -top t -part xczu9eg-ffvb1156-2-e -mode out_of_context} msg]} { puts "DOCTOR-LICENSE-FAIL" } else { puts "DOCTOR-LICENSE-OK" }
TCL
    out="$(cd "$work" && bash "$SCAM_ROOT/scripts/run_vivado.sh" -mode batch -nolog -nojournal -source t.tcl 2>&1)"
    rm -rf "$work"
    if grep -q "^DOCTOR-LICENSE-OK" <<< "$out"; then
        ok "synthesis license for xczu9eg checked out"
    else
        fail "Vivado could not get a synthesis license for xczu9eg" \
             "$(grep -m 1 -oE 'Explanation: [^.]*\.' <<< "$out" || echo 'see the Vivado License Manager')"
    fi
elif [[ $vivado_ok -eq 1 ]]; then
    echo "        (a real license checkout is tested by: make doctor FULL=1)"
fi

echo
env_name="${PETALINUX_ENV:-host}"
echo "Linux image (make petalinux, sdcard, sdk; PETALINUX_ENV=$env_name)"
settings="${PETALINUX_SETTINGS:-$PETALINUX_ROOT/settings.sh}"
if [[ ! -r "$settings" ]]; then
    fail "PetaLinux not found at $PETALINUX_ROOT" "install PetaLinux $PETALINUX_VERSION and set PETALINUX_ROOT in config.mk"
else
    pver="$(sed -n 's/^export PETALINUX_VER=//p' "$settings" | head -n 1)"
    if [[ "$pver" == "$PETALINUX_VERSION" ]]; then
        ok "PetaLinux $pver"
    else
        fail "PetaLinux is '${pver:-unknown}', the project needs $PETALINUX_VERSION" "install PetaLinux $PETALINUX_VERSION and set PETALINUX_ROOT"
    fi
fi
case "$env_name" in
    container|docker)
        if ! have docker; then
            fail "docker not found" "install Docker, or use PETALINUX_ENV=host on an AMD-supported distribution"
        elif ! docker info > /dev/null 2>&1; then
            fail "docker is installed but this user cannot use it" "start the Docker service and add yourself to the 'docker' group"
        else
            ok "Docker $(docker info --format '{{.ServerVersion}}' 2> /dev/null)"
        fi
        ;;
    host)
        distro="$(. /etc/os-release 2> /dev/null && echo "$PRETTY_NAME")"
        warn "host build on ${distro:-this system}" "PetaLinux $PETALINUX_VERSION only builds on AMD-supported distributions; otherwise set PETALINUX_ENV := container in config.mk"
        ;;
    *)
        fail "PETALINUX_ENV is '$env_name'" "use host or container"
        ;;
esac

echo
echo "C programs without PetaLinux (make app-<app>)"
if [[ -n "${SCAM_SDK:-}" ]]; then
    if compgen -G "$SCAM_SDK/environment-setup-*" > /dev/null; then
        ok "SDK at $SCAM_SDK"
    else
        fail "SCAM_SDK=$SCAM_SDK has no environment-setup file" "install the SDK there: sh <sdk>.sh -d $SCAM_SDK"
    fi
elif [[ "${CC:-}" == aarch64-* ]]; then
    ok "cross compiler from the environment: ${CC%% *}"
else
    warn "no SDK configured" "only needed for 'make app-<app>': install the SDK (sh <sdk>.sh -d <dir>) and set SCAM_SDK in config.mk"
fi

echo
echo "SD card and board (make flash, make deploy)"
for tool in parted mkfs.vfat mkfs.ext4 ssh scp; do
    if have "$tool" || [[ -x "/usr/sbin/$tool" || -x "/sbin/$tool" ]]; then
        ok "$tool"
    else
        warn "$tool not found" "needed for 'make flash' (parted, mkfs.*) or 'make deploy' (ssh, scp)"
    fi
done

echo
echo "Host collector (sw/host/collect_data.py)"
if ! have python3; then
    warn "python3 not found" "install Python 3.9 or newer"
else
    ok "python3 $(python3 -c 'import platform; print(platform.python_version())')"
    if python3 -c 'import paramiko' > /dev/null 2>&1; then
        ok "paramiko"
    else
        warn "Python module paramiko is missing" "pip install -r sw/host/requirements.txt (not needed with --no-ssh)"
    fi
fi

echo
if (( fails > 0 )); then
    echo "$fails problem(s) must be fixed, $warns warning(s)."
    exit 1
fi
echo "Ready to build. $warns warning(s)."
