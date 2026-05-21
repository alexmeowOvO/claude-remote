# kloa-remote

Telegram-based remote control daemon for macOS. Zero dependencies beyond Python stdlib.

Control your Mac from anywhere by sending messages to a Telegram bot — screenshots, open apps, run shell commands, set volume, speak text, add reminders, and optionally pipe natural language to Claude Code.

## Quick start

```bash
git clone https://github.com/alexmeowOvO/kloa-remote.git
cd kloa-remote

# Create your config (never commit this file)
cp daemon/config.example.sh daemon/config.sh
# Edit config.sh with your bot token and chat ID
nano daemon/config.sh

# Start the daemon
cd daemon
source config.sh
python3 kloa_daemon.py
```

## Setup

### 1. Create a Telegram bot
Message [@BotFather](https://t.me/BotFather) on Telegram:
- Send `/newbot` and follow the prompts
- Copy the token (looks like `1234567890:ABCdef...`)

### 2. Get your chat ID
Message [@userinfobot](https://t.me/userinfobot) to get your numeric chat ID.

### 3. Configure
```bash
cp daemon/config.example.sh daemon/config.sh
```
Edit `daemon/config.sh` and fill in:
```bash
export KLOA_TOKEN="1234567890:ABCdef..."
export KLOA_CHAT_ID="6981350701"
```

### 4. (Recommended) Set a shared secret
```bash
export KLOA_SECRET="pick-a-random-phrase"
```
Without this, anyone who can message your bot can run shell commands on your Mac.

### 5. (Optional) Enable Claude Code forwarding
```bash
export KLOA_CLAUDE_MODE="1"
```
Unrecognised messages are forwarded as `claude --continue --print "<message>"`.

## Commands (send from Telegram)

| Command | Description |
|---------|-------------|
| `screenshot` | Take a screenshot and send it back |
| `open Safari` | Open an application |
| `say hello world` | Speak text aloud (macOS TTS) |
| `run ls -la` | Run a shell command (requires secret if set) |
| `volume 50` | Set system volume (0-100) |
| `remind buy milk` | Add a reminder to Reminders.app |
| `status` | Show daemon uptime and stats |
| `help` | Show all commands |

### With secret enabled
Prefix `run` commands with your secret:
```
run my-secret-phrase df -h
```

### Shell scripts
```bash
# Send a message without the daemon
./daemon/kloa_send.sh "Backup complete"

# Send a yes/no question and block for a reply (120s timeout)
./daemon/kloa_ask.sh "Deploy to production?" 120
```

## Running persistently

### Launch at startup (macOS launchd)
```bash
# Copy and edit the plist, then:
cp daemon/com.alex.kloa.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.alex.kloa.plist
```

### Double-click
Double-click `daemon/start_kloa.command` to launch in a Terminal window.

## Architecture

- **Zero dependencies** — Python stdlib only (urllib, subprocess, threading, json, tempfile)
- **Long polling** via Telegram `getUpdates` API
- **State persistence** — update offset saved to `.kloa_state.json` (gitignored)
- **Threaded commands** — `run` executes in background threads, daemon stays responsive
- **Shared secret auth** — shell commands gated behind KLOA_SECRET
- **No shell injection** — uses `shlex.split()` + subprocess list args
- **No AppleScript injection** — scripts piped via stdin to `osascript`

## Security

- `config.sh` is gitignored — credentials never leave your machine
- Copy `config.example.sh` as your template
- All `run` commands require KLOA_SECRET when set
- Shell commands use subprocess with argument lists (no `shell=True`)
- AppleScript uses stdin piping (no string interpolation)
- Chat ID filtering — only your Telegram account controls the bot

## File overview

```
kloa-remote/
├── LICENSE
├── README.md
├── .gitignore
└── daemon/
    ├── config.example.sh      # Template — copy to config.sh
    ├── config.sh              # Your credentials (gitignored)
    ├── kloa_daemon.py         # Main daemon
    ├── kloa_send.sh           # Send messages from shell
    ├── kloa_ask.sh            # Yes/no approval gating
    └── start_kloa.command     # Double-click launcher
```
