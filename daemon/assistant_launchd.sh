#!/bin/bash
# Wrapper called by launchd. Source config and run the daemon.
# The plist calls this script from wherever assistant-remote is checked out.
# No hardcoded paths — we derive our location at runtime.

set -euo pipefail
cd "$(dirname "$0")" || exit 1
source config.sh
exec /usr/bin/python3 -u assistant_daemon.py
