#!/usr/bin/env bash
# segmentation-model.sh - Add, change or remove a segmentation model server: stack.ps1 viking-segmentation model.
# Runs scripts/segmentation-model.ps1 (which runs stack.ps1 from this checkout) with the same arguments. Works through a
# symlink, so `ln -s .../scripts/segmentation-model.sh ~/bin/segmentation-model` gives a plain `segmentation-model` command.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec pwsh -NoLogo -NoProfile -File "$here/segmentation-model.ps1" "$@"
