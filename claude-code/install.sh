#!/bin/bash
# install.sh — Install assistant Claude Code integration
# Installs slash commands, hooks, and updates ~/.claude/settings.json

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "🦞 Installing assistant Claude Code integration..."
echo ""

# Create directories
mkdir -p "$COMMANDS_DIR"
mkdir -p "$HOOKS_DIR"

# Install slash commands
cp "$SCRIPT_DIR/commands/code-assistant.md" "$COMMANDS_DIR/code-assistant.md"
cp "$SCRIPT_DIR/commands/notification.md"   "$COMMANDS_DIR/notification.md"
echo "✅ Slash commands installed:"
echo "   /code-assistant → supervised session startup with Telegram"
echo "   /notification   → alert user before risky actions"

# Install stop hook
cp "$SCRIPT_DIR/hooks/stop_notify.sh" "$HOOKS_DIR/stop_notify.sh"
chmod +x "$HOOKS_DIR/stop_notify.sh"
echo "✅ Stop hook installed: $HOOKS_DIR/stop_notify.sh"

# Install config alongside the hook (if not already present)
HOOK_CONFIG="$HOOKS_DIR/config.sh"
DAEMON_CONFIG="$SCRIPT_DIR/../daemon/config.sh"
if [ ! -f "$HOOK_CONFIG" ]; then
  if [ -f "$DAEMON_CONFIG" ]; then
    cp "$DAEMON_CONFIG" "$HOOK_CONFIG"
    echo "✅ Credentials copied to $HOOK_CONFIG"
  else
    cp "$SCRIPT_DIR/../daemon/config.example.sh" "$HOOK_CONFIG"
    echo "⚠️  No config.sh found — copied template to $HOOK_CONFIG"
    echo "   Edit it and fill in your ASSISTANT_TOKEN and ASSISTANT_CHAT_ID."
  fi
else
  echo "✅ Credentials already at $HOOK_CONFIG (not overwritten)"
fi

# Update settings.json
STOP_HOOK_CMD="$HOOKS_DIR/stop_notify.sh"
NOTIFY_HOOK_CMD="source $HOOK_CONFIG 2>/dev/null; curl -s -X POST \"https://api.telegram.org/bot\${ASSISTANT_TOKEN}/sendMessage\" -d \"chat_id=\${ASSISTANT_CHAT_ID}\" --data-urlencode 'text=🔔 Claude Code is waiting for you — switch back when ready.' > /dev/null"

if [ ! -f "$SETTINGS" ]; then
    echo "Creating new $SETTINGS..."
    cat > "$SETTINGS" << EOF
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'source $HOOK_CONFIG 2>/dev/null; curl -s -X POST \"https://api.telegram.org/bot\${ASSISTANT_TOKEN}/sendMessage\" -d \"chat_id=\${ASSISTANT_CHAT_ID}\" --data-urlencode \"text=🔔 Claude Code is waiting for you — switch back when ready.\" > /dev/null'"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$STOP_HOOK_CMD"
          }
        ]
      }
    ]
  }
}
EOF
    echo "✅ Created $SETTINGS with Notification + Stop hooks"
else
    echo "⚠️  $SETTINGS already exists."
    echo "   Stop hook path: $STOP_HOOK_CMD"
    echo "   Make sure your Stop hook entry points to that path."
fi

echo ""
echo "✅ Done! Restart Claude Code (Code tab) to activate."
echo ""
echo "Available slash commands:"
echo "  /code-assistant  — start a supervised remote session"
echo "  /notification    — alert user before risky actions"
echo ""
echo "Remote loop:"
echo "  Claude finishes task → Telegram notification sent"
echo "  You reply via Telegram → assistant daemon runs: claude --continue \"your message\""
echo ""

read -p "Press Enter to close..."
