#!/bin/bash
# Double-click to launch kloa daemon in a new Terminal window.
# Sources config.sh first so credentials are loaded.
cd "$(dirname "$0")"
source config.sh
python3 kloa_daemon.py
