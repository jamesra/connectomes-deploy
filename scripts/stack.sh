#!/usr/bin/env bash
# stack.sh - One command for every Nornir/Viking container stack (stack.ps1 of this checkout).
# Runs scripts/stack.ps1 (which runs stack.ps1 from this checkout) with the same arguments. Works through a
# symlink, so `ln -s .../scripts/stack.sh ~/bin/stack` gives a plain `stack` command.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec pwsh -NoLogo -NoProfile -File "$here/stack.ps1" "$@"
