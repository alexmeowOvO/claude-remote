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
echo "✅ Daemon loaded — will start now and on every login."
echo "   Logs: /tmp/assistant_daemon.log"
echo "   Stop: launchctl unload $PLIST_DEST"
