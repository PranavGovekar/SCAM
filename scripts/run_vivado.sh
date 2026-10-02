#!/usr/bin/env bash
set -euo pipefail

# The project workstation defines a vivado() shell function in ~/.bashrc to
# add the Vivado 2024.1 compatibility libraries. Build helpers run in a
# non-interactive shell, so invoke that function through an interactive Bash.
# On hosts without the function, fall back to the vivado executable on PATH.
bash -ic '
    if declare -F vivado >/dev/null 2>&1; then
        vivado "$@"
    else
        command vivado "$@"
    fi
' scam-vivado "$@"
