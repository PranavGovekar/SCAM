#!/usr/bin/env bash
set -euo pipefail

# Application discovery.
#
# An application is a directory <name>/ holding hw/bd.tcl and/or sw/*.c. They
# are found in:
#   * apps/ in this repository
#   * every directory listed in SCAM_APPS (colon-separated). An entry may be a
#     directory of applications, or a single application directory.
# Directories whose name starts with '_' or '.' are skipped.
#
# Optional <name>/app.conf (plain KEY=value lines, no quotes):
#   BITSTREAM=<name>          bitstream is <BITSTREAM>.bit.bin
#   BINARY=yeet-data-<name>   userspace binary name
#
# Usage: apps.sh list | show | table | dir <app> | get <app> <bitstream|binary|has_hw|has_sw>
#   bitpath <app> | binpath <app>

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

die() { echo "apps.sh: $*" >&2; exit 1; }

has_hw() { [[ -f "$1/hw/bd.tcl" ]]; }
has_sw() { compgen -G "$1/sw/*.c" > /dev/null; }
is_app() { has_hw "$1" || has_sw "$1"; }

declare -A app_dirs=()
app_names=()

add_app() {
    local dir="$1" name
    name="$(basename "$dir")"
    [[ "$name" == _* || "$name" == .* ]] && return 0
    is_app "$dir" || return 0
    [[ "$name" =~ ^[a-z][a-z0-9_-]*$ ]] || \
        die "invalid application name '$name' ($dir): use lowercase letters, digits, '-' and '_'"
    [[ "$name" != base ]] || die "'base' is reserved ($dir)"
    if [[ -n "${app_dirs[$name]:-}" ]]; then
        die "application '$name' exists twice: ${app_dirs[$name]} and $dir"
    fi
    app_dirs[$name]="$dir"
    app_names+=("$name")
}

scan_root() {
    local root="$1" d
    [[ -d "$root" ]] || die "application directory not found: $root"
    root="$(cd "$root" && pwd)"
    if is_app "$root"; then
        add_app "$root"
        return 0
    fi
    for d in "$root"/*/; do
        [[ -d "$d" ]] && add_app "${d%/}"
    done
}

scan_root "$SCAM_ROOT/apps"
IFS=':' read -r -a extra_roots <<< "${SCAM_APPS:-}"
for root in "${extra_roots[@]}"; do
    [[ -n "$root" ]] || continue
    # A missing entry must not block targets such as clean or new-app.
    if [[ ! -d "$root" ]]; then
        echo "apps.sh: warning: SCAM_APPS entry not found, skipped: $root" >&2
        continue
    fi
    scan_root "$root"
done

app_dir() {
    [[ -n "${app_dirs[$1]:-}" ]] || die "unknown application '$1' (known: ${app_names[*]:-none})"
    echo "${app_dirs[$1]}"
}

# Read KEY from app.conf, or print the default.
conf_get() {
    local dir="$1" key="$2" default="$3" value=""
    if [[ -f "$dir/app.conf" ]]; then
        value="$(sed -n "s/^[[:space:]]*$key[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$dir/app.conf" | tail -n 1)"
    fi
    echo "${value:-$default}"
}

app_get() {
    local name="$1" key="$2" dir
    dir="$(app_dir "$name")"
    case "$key" in
        bitstream) conf_get "$dir" BITSTREAM "$name" ;;
        binary)    conf_get "$dir" BINARY "yeet-data-$name" ;;
        has_hw)    if has_hw "$dir"; then echo 1; else echo 0; fi ;;
        has_sw)    if has_sw "$dir"; then echo 1; else echo 0; fi ;;
        *)         die "unknown key '$key'" ;;
    esac
}

cmd="${1:-}"
case "$cmd" in
    list)
        echo "${app_names[*]:-}"
        ;;
    table)
        # One word per application for the Makefile: name|dir|bitstream|binary|hw|sw
        for name in "${app_names[@]}"; do
            echo "$name|${app_dirs[$name]}|$(app_get "$name" bitstream)|$(app_get "$name" binary)|$(app_get "$name" has_hw)|$(app_get "$name" has_sw)"
        done
        ;;
    show)
        for name in "${app_names[@]}"; do
            printf '%-12s %s\n' "$name" "${app_dirs[$name]}"
            [[ "$(app_get "$name" has_hw)" == 1 ]] && \
                printf '             bitstream  %s.bit.bin\n' "$(app_get "$name" bitstream)"
            [[ "$(app_get "$name" has_sw)" == 1 ]] && \
                printf '             binary     %s\n' "$(app_get "$name" binary)"
        done
        exit 0
        ;;
    dir)
        app_dir "${2:?usage: apps.sh dir <app>}"
        ;;
    get)
        app_get "${2:?usage: apps.sh get <app> <key>}" "${3:?usage: apps.sh get <app> <key>}"
        ;;
    bitpath)
        echo "$SCAM_BUILD/apps/${2:?}/$(app_get "$2" bitstream).bit.bin"
        ;;
    binpath)
        echo "$SCAM_BUILD/apps/${2:?}/$(app_get "$2" binary)"
        ;;
    *)
        echo "Usage: $0 list | show | table | dir <app> | get <app> <key> | bitpath <app> | binpath <app>" >&2
        exit 2
        ;;
esac
