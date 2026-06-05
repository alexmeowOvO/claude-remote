#!/bin/bash
# install.sh — Install claude-remote Claude Code integration
# Installs slash commands, hooks, and MERGES into ~/.claude/settings.json

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"

echo "🦞 Installing claude-remote Claude Code integration..."
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

# Install hooks
cp "$SCRIPT_DIR/hooks/stop_notify.sh" "$HOOKS_DIR/stop_notify.sh"
chmod +x "$HOOKS_DIR/stop_notify.sh"
cp "$SCRIPT_DIR/hooks/notify_hook.sh" "$HOOKS_DIR/notify_hook.sh"
chmod +x "$HOOKS_DIR/notify_hook.sh"
echo "✅ Hooks installed:"
echo "   $HOOKS_DIR/stop_notify.sh  (Stop hook)"
echo "   $HOOKS_DIR/notify_hook.sh  (Notification hook)"

# Install config alongside the hooks
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

# Merge hooks into settings.json using Python (preserves existing config)
STOP_HOOK_CMD="$HOOKS_DIR/stop_notify.sh"
NOTIFY_HOOK_CMD="$HOOKS_DIR/notify_hook.sh"

python3 - "$SETTINGS" "$STOP_HOOK_CMD" "$NOTIFY_HOOK_CMD" << 'PYEOF'
import json, sys, os

settings_path, stop_cmd, notify_cmd = sys.argv[1], sys.argv[2], sys.argv[3]

# Load existing settings or start fresh
if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
    print(f"   Merging into existing {settings_path}")
else:
    settings = {}
    print(f"   Creating new {settings_path}")

hooks = settings.setdefault("hooks", {})

def upsert_hook(hook_type, command):
    """Add or update our hook entry, leaving other hooks untouched."""
    entries = hooks.setdefault(hook_type, [])
    # Find existing claude-remote entry by command path substring
    marker = "stop_notify.sh" if "stop_notify" in command else "notify_hook.sh"
    for entry in entries:
        for h in entry.get("hooks", []):
            if marker in h.get("command", ""):
                h["command"] = command
                return
    # Not found — append a new entry
    entries.append({
        "matcher": "",
        "hooks": [{"type": "command", "command": command}]
    })

upsert_hook("Stop", stop_cmd)
upsert_hook("Notification", notify_cmd)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")

print(f"✅ settings.json updated")
PYEOF

echo ""
echo "✅ Done! Restart Claude Code (Code tab) to activate."
echo ""
echo "Available slash commands:"
echo "  /code-assistant  — start a supervised remote session"
echo "  /notification    — alert user before risky actions"
echo ""
