#!/bin/bash
# launchd-install.sh — Install the assistant daemon as a macOS login item
# Generates the plist using the actual repo path at install time.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_LABEL="com.alex.assistant"
PLIST_DEST="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
LAUNCHD_SH="$SCRIPT_DIR/assistant_launchd.sh"

cat > "$PLIST_DEST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${LAUNCHD_SH}</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/assistant_daemon.log</string>

    <key>StandardErrorPath</key>
    <string>/tmp/assistant_daemon.err</string>
</dict>
</plist>
EOF

echo "✅ Plist written to $PLIST_DEST"

# Load (or reload) the agent
launchctl unload "$PLIST_DEST" 2>/dev/null || true
launchctl load "$PLIST_DEST"
echo "✅ Plist loaded — checking daemon started..."

# Give the daemon a moment to write its PID file, then verify it is alive
HEARTBEAT_FILE="/tmp/claude-remote-$(id -u)/daemon.heartbeat"
MAX_WAIT=15
for i in $(seq 1 $MAX_WAIT); do
  sleep 1
  if [ -f "$HEARTBEAT_FILE" ]; then
    AGE=$(python3 -c "
import time
try:
    ts = float(open('$HEARTBEAT_FILE').read())
    print(int(time.time() - ts))
except Exception:
    print(9999)
")
    if [ "$AGE" -lt 30 ]; then
      echo "✅ Daemon is alive (heartbeat age: ${AGE}s)."
      echo "   Logs: /tmp/assistant_daemon.log"
      echo "   Stop: launchctl unload $PLIST_DEST"
      exit 0
    fi
  fi
done

echo "⚠️  Daemon did not produce a heartbeat within ${MAX_WAIT}s."
echo "   It may have exited immediately — check for missing config.sh or errors:"
echo "   cat /tmp/assistant_daemon.log"
echo "   cat /tmp/assistant_daemon.err"
