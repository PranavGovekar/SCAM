#!/usr/bin/env bash
set -euo pipefail

# Run Vivado with the given arguments.
#
#   VIVADO_SETTINGS  path to Vivado's settings64.sh; sourced first when set
#   VIVADO           Vivado executable to run (default: vivado)
#
# With neither set, an interactive Bash is used so that a vivado() shell
# function from ~/.bashrc is honoured (some hosts wrap Vivado that way to add
# compatibility libraries). Without such a function this falls back to the
# vivado executable on PATH.

if [[ -n "${VIVADO_SETTINGS:-}" ]]; then
    if [[ ! -r "$VIVADO_SETTINGS" ]]; then
        echo "VIVADO_SETTINGS is not readable: $VIVADO_SETTINGS" >&2
        exit 1
    fi
    set +u
    # shellcheck disable=SC1090
    source "$VIVADO_SETTINGS"
    set -u
    exec "${VIVADO:-vivado}" "$@"
fi
if [[ -n "${VIVADO:-}" ]]; then
    exec "$VIVADO" "$@"
fi

bash -ic '
    if declare -F vivado >/dev/null 2>&1; then
        vivado "$@"
    elif command -v vivado >/dev/null 2>&1; then
        command vivado "$@"
    else
        echo "Vivado not found. Set VIVADO_SETTINGS to settings64.sh (see config.mk.example)." >&2
        exit 127
    fi
' scam-vivado "$@"
