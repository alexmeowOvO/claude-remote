#!/bin/bash
# Wrapper called by launchd. Source config and run the daemon.
# The plist calls this script from wherever claude-remote is checked out.
# No hardcoded paths — we derive our location at runtime.

set -euo pipefail
cd "$(dirname "$0")" || exit 1
if [ ! -f config.sh ]; then
  echo "❌ config.sh not found in $(pwd)." >&2
  echo "   Copy daemon/config.example.sh to daemon/config.sh and fill in your credentials." >&2
  exit 1
fi
source config.sh
exec /usr/bin/python3 -u assistant_daemon.py
