#!/usr/bin/env python3
"""
kloa_daemon.py — Telegram remote control for your Mac (+ optional Claude Code)
Polls the kloa Telegram bot for incoming messages and executes them.

Credentials are read from environment variables:
  KLOA_TOKEN      — Telegram bot token (from @BotFather)
  KLOA_CHAT_ID    — your numeric Telegram chat ID
  KLOA_SECRET     — (optional) shared secret required to run shell commands
  KLOA_CLAUDE_MODE — set to "1" to forward unrecognised messages to Claude Code

Built-in commands (type exactly):
  screenshot          — take a screenshot and send it back
  open <app>          — open an application
  say <text>          — speak text aloud (macOS TTS)
  run <shell cmd>     — run a shell command (requires secret if set)
  remind <text>       — add a reminder via AppleScript
  volume <0-100>      — set system volume
  status              — show daemon uptime and stats
  help                — show available commands

Start:  python3 daemon/kloa_daemon.py
Stop:   Ctrl+C  (or kill the process)
"""

import subprocess
import json
import time
import os
import sys
import urllib.request
import urllib.parse
import tempfile
import threading
import shlex

# ── Configuration ──────────────────────────────────────────────────────────

TOKEN = os.environ.get("KLOA_TOKEN", "").strip()
CHAT_ID_STR = os.environ.get("KLOA_CHAT_ID", "").strip()
SECRET = os.environ.get("KLOA_SECRET", "").strip()
CLAUDE_MODE = os.environ.get("KLOA_CLAUDE_MODE", "0").strip() == "1"

if not TOKEN or not CHAT_ID_STR:
    print("❌ KLOA_TOKEN and KLOA_CHAT_ID must be set.")
    print("   Source daemon/config.sh or export them yourself.")
    sys.exit(1)

try:
    CHAT_ID = int(CHAT_ID_STR)
except ValueError:
    print(f"❌ KLOA_CHAT_ID must be an integer (got: {CHAT_ID_STR})")
    sys.exit(1)

API = f"https://api.telegram.org/bot{TOKEN}"
STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".kloa_state.json")

# ── State persistence ──────────────────────────────────────────────────────

def load_state():
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"offset": 0}

def save_state(state):
    try:
        with open(STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception as e:
        print(f"[state save error] {e}")

# ── Telegram API helpers ───────────────────────────────────────────────────

TELEGRAM_MAX_LEN = 4096
TRUNCATED_SUFFIX = "\n⋯(truncated)"

def api_call(method, params=None):
    url = f"{API}/{method}"
    if params:
        data = urllib.parse.urlencode(params).encode()
        req = urllib.request.Request(url, data=data)
    else:
        req = urllib.request.Request(url)
    with urllib.request.urlopen(req, timeout=35) as resp:
        return json.loads(resp.read())

def send(text):
    """Send a text message to Telegram, truncating if necessary."""
    try:
        max_body = TELEGRAM_MAX_LEN - len(TRUNCATED_SUFFIX)
        if len(text) > max_body:
            text = text[:max_body] + TRUNCATED_SUFFIX
        api_call("sendMessage", {"chat_id": CHAT_ID, "text": text})
    except Exception as e:
        print(f"[send error] {e}")

def send_photo(path):
    """Send a photo to Telegram via multipart upload."""
    try:
        import mimetypes
        boundary = "----kloa_boundary"
        with open(path, "rb") as f:
            photo_data = f.read()

        filename = os.path.basename(path)
        body = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="chat_id"\r\n\r\n'
            f"{CHAT_ID}\r\n"
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="photo"; filename="{filename}"\r\n'
            f"Content-Type: image/png\r\n\r\n"
        ).encode() + photo_data + f"\r\n--{boundary}--\r\n".encode()

        req = urllib.request.Request(
            f"{API}/sendPhoto",
            data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())
    except Exception as e:
        send(f"[photo error] {e}")

# ── Shell helpers ──────────────────────────────────────────────────────────

def run_shell(cmd, timeout=15):
    """Run a shell command safely (no shell=True — args are split)."""
    try:
        # Use shlex to split, then subprocess with a list (no shell injection)
        args = shlex.split(cmd)
        result = subprocess.run(
            args, capture_output=True, text=True, timeout=timeout
        )
        out = (result.stdout + result.stderr).strip()
        return out[:3000] if out else "(no output)"
    except subprocess.TimeoutExpired:
        return "⏰ Command timed out"
    except Exception as e:
        return f"Error: {e}"

def run_applescript(script):
    """Run AppleScript with proper quoting via stdin (avoids injection)."""
    try:
        result = subprocess.run(
            ["osascript", "-"],
            input=script,
            capture_output=True,
            text=True,
            timeout=15,
        )
        out = (result.stdout + result.stderr).strip()
        return out[:2000] if out else "(no output)"
    except subprocess.TimeoutExpired:
        return "⏰ AppleScript timed out"
    except Exception as e:
        return f"Error: {e}"

# ── Claude Code forwarding ─────────────────────────────────────────────────

def forward_to_claude(text):
    """Forward natural language message to Claude Code."""
    if not CLAUDE_MODE:
        send(f"❓ Unknown command: `{text}`\nSend `help` to see available commands.")
        return

    send("🤖 Sending to Claude Code...")

    # Build PATH to find claude binary
    env = os.environ.copy()
    for prefix in [os.path.expanduser("~/.local/bin"), "/usr/local/bin", "/opt/homebrew/bin"]:
        if prefix not in env.get("PATH", ""):
            env["PATH"] = f"{prefix}:{env.get('PATH', '')}"

    try:
        result = subprocess.run(
            ["claude", "--continue", "--print", text],
            capture_output=True,
            text=True,
            timeout=300,
            env=env,
        )
        out = (result.stdout + result.stderr).strip()
        if not out:
            send("⚠️ No response from Claude Code. Is it installed and has a recent session?")
        else:
            send(f"💬 Claude Code:\n\n{out}")
    except FileNotFoundError:
        send("⚠️ Claude Code not found. Install it or disable KLOA_CLAUDE_MODE.")
    except subprocess.TimeoutExpired:
        send("⏰ Claude Code timed out (5 min)")
    except Exception as e:
        send(f"❌ Claude Code error: {e}")

# ── Command handlers ───────────────────────────────────────────────────────

def handle(text):
    text = text.strip()
    lower = text.lower()

    if lower == "help":
        help_text = (
            "🤖 *kloa commands:*\n"
            "• `screenshot` — send a screenshot\n"
            "• `open <app>` — open an app\n"
            "• `say <text>` — speak aloud\n"
            "• `run <cmd>` — run shell command" +
            (" (requires secret)" if SECRET else "") + "\n"
            "• `volume <0-100>` — set volume\n"
            "• `remind <text>` — add a reminder\n"
            "• `status` — daemon uptime and stats\n"
            "• `help` — this message"
        )
        if CLAUDE_MODE:
            help_text += "\n\nAnything else → forwarded to Claude Code 🚀"
        send(help_text)

    elif lower == "status":
        uptime = time.time() - start_time
        h, m = divmod(int(uptime), 3600)
        m, s = divmod(m, 60)
        send(
            f"🟢 kloa daemon is running\n"
            f"Uptime: {h}h {m}m {s}s\n"
            f"Commands processed: {stats['commands']}\n"
            f"Claude mode: {'on' if CLAUDE_MODE else 'off'}\n"
            f"Secret required: {'yes' if SECRET else 'no'}"
        )

    elif lower == "screenshot":
        send("📸 Taking screenshot...")
        # Use NamedTemporaryFile (not deprecated mktemp)
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            tmp_path = tmp.name
        result = subprocess.run(["screencapture", "-x", tmp_path], capture_output=True)
        if os.path.exists(tmp_path) and os.path.getsize(tmp_path) > 0:
            send_photo(tmp_path)
        else:
            send("❌ Screenshot failed")
        try:
            os.remove(tmp_path)
        except OSError:
            pass

    elif lower.startswith("open "):
        app = text[5:].strip()
        out = run_shell(f"open -a {shlex.quote(app)}", timeout=10)
        send(f"🔓 Opened {app}" if out == "(no output)" else f"❌ {out}")

    elif lower.startswith("say "):
        phrase = text[4:].strip()
        subprocess.run(["say", phrase], capture_output=True, timeout=60)
        send(f"🔊 Said: {phrase}")

    elif lower.startswith("run "):
        cmd = text[4:].strip()
        # Check shared secret if configured
        if SECRET:
            if not cmd.startswith(SECRET):
                send("🔒 Secret required. Prefix your command with the shared secret.")
                return
            cmd = cmd[len(SECRET):].strip()
            if not cmd:
                send("❌ No command after secret.")
                return
        send(f"💻 Running: `{cmd[:80]}{'...' if len(cmd) > 80 else ''}`")
        # Run in background thread so daemon stays responsive
        t = threading.Thread(target=_run_and_report, args=(cmd,), daemon=True)
        t.start()

    elif lower.startswith("volume "):
        vol = text[7:].strip()
        try:
            v = int(vol)
            if 0 <= v <= 100:
                run_applescript(f"set volume output volume {v}")
                send(f"🔉 Volume set to {v}%")
            else:
                send("❌ Volume must be 0-100")
        except ValueError:
            send("❌ Invalid volume value")

    elif lower.startswith("remind "):
        reminder = text[7:].strip()
        # AppleScript with proper heredoc — no injection
        script = (
            'tell application "Reminders"\n'
            f'    make new reminder with properties {{name:"{reminder}"}}\n'
            "end tell"
        )
        err = run_applescript(script)
        if err == "(no output)":
            send(f"🔔 Reminder added: {reminder}")
        else:
            send(f"❌ Reminder error: {err}")

    else:
        forward_to_claude(text)

def _run_and_report(cmd):
    """Run a shell command in a background thread and report results."""
    out = run_shell(cmd, timeout=30)
    send(f"💻 Output:\n```\n{out}\n```")

# ── Main loop ──────────────────────────────────────────────────────────────

stats = {"commands": 0}
start_time = time.time()

def main():
    global start_time
    start_time = time.time()

    state = load_state()
    offset = state.get("offset", 0)

    print(f"🤖 kloa daemon starting...")
    print(f"   Claude mode: {'on' if CLAUDE_MODE else 'off'}")
    print(f"   Secret: {'required' if SECRET else 'disabled (⚠️  insecure)'}")
    print(f"   State file: {STATE_FILE}")

    # Send startup notification (survive failure gracefully)
    try:
        send(
            f"🟢 kloa daemon is online.\n"
            f"Send `help` for commands." +
            ("\nAnything else → Claude Code 🚀" if CLAUDE_MODE else "")
        )
    except Exception as e:
        print(f"⚠️  Could not send startup message: {e}")

    # If no saved offset, fast-forward past old messages
    if offset == 0:
        try:
            data = api_call("getUpdates", {"limit": 1, "offset": -1})
            if data.get("result"):
                offset = data["result"][-1]["update_id"] + 1
        except Exception:
            pass

    print(f"Listening for messages (offset={offset})...")

    while True:
        try:
            data = api_call("getUpdates", {"offset": offset, "timeout": 30})
            for update in data.get("result", []):
                offset = update["update_id"] + 1
                # Persist offset immediately so crashes don't lose messages
                state["offset"] = offset
                save_state(state)

                msg = update.get("message", {})
                chat_id = msg.get("chat", {}).get("id")
                text = msg.get("text", "").strip()

                # Only respond to your own chat
                if chat_id != CHAT_ID:
                    continue
                if not text:
                    continue

                # Skip [ASK] prefixed messages — those belong to kloa_ask.sh
                if text.startswith("[ASK]"):
                    continue

                stats["commands"] += 1
                print(f"[{time.strftime('%H:%M:%S')}] Received: {text}")
                handle(text)

        except KeyboardInterrupt:
            try:
                send("🔴 kloa daemon stopped.")
            except Exception:
                pass
            print("\nStopped.")
            sys.exit(0)
        except Exception as e:
            print(f"[error] {e}")
            time.sleep(5)

if __name__ == "__main__":
    main()
