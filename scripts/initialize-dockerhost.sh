#!/usr/bin/env bash
# initialize-dockerhost.sh - Create the host layout and copy the stack templates (Initialize-DockerHost.ps1 of this checkout).
# Runs scripts/initialize-dockerhost.ps1 (which runs Initialize-DockerHost.ps1 from this checkout) with the same arguments. Works through a
# symlink, so `ln -s .../scripts/initialize-dockerhost.sh ~/bin/initialize-dockerhost` gives a plain `initialize-dockerhost` command.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
exec pwsh -NoLogo -NoProfile -File "$here/initialize-dockerhost.ps1" "$@"
