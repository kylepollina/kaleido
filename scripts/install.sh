#!/bin/bash
# Builds Kaleido and installs it to /Applications (quitting and relaunching a running copy).
set -euo pipefail
exec "$(dirname "$0")/build.sh" --install
