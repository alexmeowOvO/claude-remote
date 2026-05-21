#!/bin/bash
# Double-click to launch assistant daemon in a new Terminal window.
# Sources config.sh first so credentials are loaded.
cd "$(dirname "$0")"
source config.sh
python3 assistant_daemon.py
