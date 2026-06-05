#!/bin/bash
# Double-click to launch assistant daemon in a new Terminal window.
# Sources config.sh first so credentials are loaded.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f config.sh ]; then
  echo "❌ config.sh not found in $(pwd)." >&2
  echo "   Copy daemon/config.example.sh to daemon/config.sh and fill in your credentials." >&2
  read -p "Press Enter to close..."
  exit 1
fi
source config.sh
python3 assistant_daemon.py
