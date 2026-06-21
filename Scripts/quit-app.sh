#!/bin/zsh
set -euo pipefail

pkill -f "/Claude Island.app/Contents/MacOS/Claude Island" 2>/dev/null || true
