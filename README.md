# claude-remote

Remote supervision for Claude Code via Telegram. Get notified when tasks finish or need input — reply in natural language to continue the session from your phone.

## What's in here

**Slash commands** (drop into `~/.claude/commands/`):

| Command | What it does |
|---------|-------------|
| `/code-assistant` | Start a supervised session — sends a Telegram startup alert and keeps you in the loop |
| `/notification` | Alert yourself before Claude takes a risky action and wait for approval |

**Hooks** (auto-fire on Claude Code events):

| Hook | Trigger | What it sends |
|------|---------|--------------|
| `stop_notify.sh` | Task finishes | "✅ Claude Code finished! Reply with your next instruction." |
| Notification hook | Claude is waiting | "🔔 Claude Code is waiting for you — switch back when ready." |

**Telegram daemon** (`daemon/assistant_daemon.py`):

Polls your Telegram bot for incoming messages and forwards them to Claude Code as `claude --continue --print "<your message>"`. This closes the loop — you reply on your phone, Claude keeps working.

## How it works

```
Claude Code finishes a task
        ↓
Stop hook fires → Telegram: "✅ Done! Reply with next instruction."
        ↓
You reply from your phone
        ↓
Daemon receives message → runs: claude --continue --print "your message"
        ↓
Claude Code continues working
```

## Quick start

### 1. Create a Telegram bot
Message [@BotFather](https://t.me/BotFather):
- Send `/newbot` and follow the prompts
- Copy the token (looks like `1234567890:ABCdef...`)

Get your chat ID by messaging [@userinfobot](https://t.me/userinfobot).

### 2. Configure
```bash
cp daemon/config.example.sh daemon/config.sh
```
Edit `daemon/config.sh`:
```bash
export ASSISTANT_TOKEN="1234567890:ABCdef..."
export ASSISTANT_CHAT_ID="your-numeric-chat-id"
export ASSISTANT_SECRET="pick-a-random-phrase"  # gates shell commands
export ASSISTANT_CLAUDE_MODE="1"                 # enable claude --continue forwarding
```

### 3. Install Claude Code hooks and slash commands
```bash
bash claude-code/install.sh
```
This copies the slash commands to `~/.claude/commands/` and installs the Stop and Notification hooks into `~/.claude/settings.json`.

### 4. Start the daemon
```bash
cd daemon
source config.sh
python3 assistant_daemon.py
```

Or double-click `daemon/start_assistant.command` to launch in a Terminal window.

**To start automatically at login:**
```bash
cp daemon/com.alex.assistant.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.alex.assistant.plist
```

## Telegram bot commands

| Command | Description |
|---------|-------------|
| `screenshot` | Take a screenshot and send it back |
| `open Safari` | Open an application |
| `say hello world` | Speak text aloud (macOS TTS) |
| `run <cmd>` | Run a shell command (requires secret if set) |
| `volume 50` | Set system volume (0–100) |
| `remind buy milk` | Add a reminder to Reminders.app |
| `status` | Show daemon uptime and stats |
| `help` | Show all commands |

**Note:** `run` uses `shlex.split()` — no pipes, redirects, or globs. For shell syntax:
```
run <secret> sh -c 'df -h | grep /dev'
```

## File overview

```
claude-remote/
├── claude-code/
│   ├── commands/
│   │   ├── code-assistant.md      # /code-assistant slash command
│   │   └── notification.md        # /notification slash command
│   ├── hooks/
│   │   └── stop_notify.sh         # Stop hook — Telegram alert on task finish
│   └── install.sh                 # One-command setup for hooks + commands
└── daemon/
    ├── config.example.sh          # Template — copy to config.sh
    ├── assistant_daemon.py        # Telegram polling daemon
    ├── assistant_launchd.sh       # Wrapper for launchd
    ├── assistant_send.sh          # Send a message from shell
    ├── assistant_ask.sh           # Yes/no approval gating
    └── start_assistant.command    # Double-click launcher
```

## Architecture

- **Zero dependencies** — Python stdlib only (`urllib`, `subprocess`, `threading`, `json`)
- **Long polling** via Telegram `getUpdates` API
- **State persistence** — update offset saved to `.assistant_state.json` (gitignored)
- **Threaded commands** — `run` executes in background threads, daemon stays responsive

## Security

- `config.sh` is gitignored — credentials never leave your machine
- Shell commands require `ASSISTANT_SECRET` when set
- No `shell=True` — uses `shlex.split()` + subprocess list args throughout
- AppleScript sent via stdin (no injection via `-e`)
- Chat ID filtering — only your Telegram account controls the bot
