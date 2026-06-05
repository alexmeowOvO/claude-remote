#!/usr/bin/env python3
"""
assistant_daemon.py — Telegram remote control for your Mac (+ optional Claude Code)
Polls the assistant Telegram bot for incoming messages and executes them.

Credentials are read from environment variables:
  ASSISTANT_TOKEN      — Telegram bot token (from @BotFather)
  ASSISTANT_CHAT_ID    — your numeric Telegram chat ID
  ASSISTANT_SECRET     — (optional) shared secret required to run shell commands
  ASSISTANT_CLAUDE_MODE — set to "1" to forward unrecognised messages to Claude Code

Built-in commands (type exactly):
  screenshot          — take a screenshot and send it back
  open <app>          — open an application
  say <text>          — speak text aloud (macOS TTS)
  run <shell cmd>     — run a shell command (requires secret if set)
  remind <text>       — add a reminder via AppleScript
  volume <0-100>      — set system volume
  usage               — check Claude 5-hour limit and get notified on reset
  status              — show daemon uptime and stats
  help                — show available commands

Start:  python3 daemon/assistant_daemon.py
Stop:   Ctrl+C  (or kill the process)
"""

import subprocess
import json
import time
import os
import sys
import signal
import logging
import urllib.request
import urllib.parse
import tempfile
import threading
import shlex
import sqlite3
import base64
from datetime import datetime, timezone

# ── Logging ────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("/tmp/assistant_daemon.log"),
    ],
)
log = logging.getLogger("assistant")

# ── Configuration ──────────────────────────────────────────────────────────

TOKEN = os.environ.get("ASSISTANT_TOKEN", "").strip()
CHAT_ID_STR = os.environ.get("ASSISTANT_CHAT_ID", "").strip()
SECRET = os.environ.get("ASSISTANT_SECRET", "").strip()
CLAUDE_MODE = os.environ.get("ASSISTANT_CLAUDE_MODE", "0").strip() == "1"

if not TOKEN or not CHAT_ID_STR:
    log.error("ASSISTANT_TOKEN and ASSISTANT_CHAT_ID must be set.")
    log.error("Source config.sh or export them yourself.")
    sys.exit(1)

try:
    CHAT_ID = int(CHAT_ID_STR)
except ValueError:
    log.error("ASSISTANT_CHAT_ID must be an integer (got: %s)", CHAT_ID_STR)
    sys.exit(1)

if not SECRET:
    log.warning("⚠️  ASSISTANT_SECRET is not set. The `run` command will be disabled.")
    log.warning("   Set ASSISTANT_SECRET in config.sh to enable remote shell execution.")

API = f"https://api.telegram.org/bot{TOKEN}"
STATE_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".assistant_state.json")

# ── Approval registry ──────────────────────────────────────────────────────
# Maps approval_id -> threading.Event so ask() callers can wait for a reply.
# Replies must be "YES <id>" or "NO <id>" to be routed here.
_pending_approvals: dict = {}
_approvals_lock = threading.Lock()

def ask(question: str, timeout: int = 120) -> bool:
    """
    Send a YES/NO question via Telegram and block until answered or timed out.
    Uses a unique approval ID so replies cannot be confused with normal commands.
    Returns True if approved, False if denied or timed out.
    """
    import secrets as _secrets
    approval_id = _secrets.token_hex(3)  # e.g. "a1b2c3"
    event = threading.Event()
    result = {"approved": False}

    with _approvals_lock:
        _pending_approvals[approval_id] = (event, result)

    send(
        f"❓ {question}\n\n"
        f"Reply `YES {approval_id}` to approve or `NO {approval_id}` to cancel "
        f"({timeout}s timeout)."
    )

    approved = event.wait(timeout=timeout)
    with _approvals_lock:
        _pending_approvals.pop(approval_id, None)

    if not approved:
        send(f"⏰ Approval `{approval_id}` timed out — cancelled.")
    return approved and result["approved"]

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
        log.warning("State save error: %s", e)

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
        log.error("Send error: %s", e)

def send_photo(path):
    """Send a photo to Telegram via multipart upload."""
    try:
        import mimetypes
        boundary = "----assistant_boundary"
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
        send("⚠️ Claude Code not found. Install it or disable ASSISTANT_CLAUDE_MODE.")
    except subprocess.TimeoutExpired:
        send("⏰ Claude Code timed out (5 min)")
    except Exception as e:
        send(f"❌ Claude Code error: {e}")

# ── Claude usage helpers ───────────────────────────────────────────────────

_CLAUDE_COOKIES_DB = os.path.expanduser(
    "~/Library/Application Support/Claude/Cookies"
)

def _get_keychain_key():
    """Read the Claude Safe Storage key from macOS Keychain."""
    for service in ("Claude Safe Storage", "Electron Safe Storage"):
        r = subprocess.run(
            ["security", "find-generic-password", "-s", service, "-w"],
            capture_output=True, text=True,
        )
        if r.returncode == 0:
            return r.stdout.strip()
    return None

def _decrypt_electron_cookie(encrypted_value, keychain_password):
    """
    Decrypt a v10 Electron/Chrome cookie (macOS).
    Format: b'v10' + 16-byte unknown + 16-byte IV + AES-128-CBC ciphertext
    Key: PBKDF2-SHA1(password, salt='saltysalt', iterations=1003, length=16)
    """
    try:
        from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        from cryptography.hazmat.backends import default_backend
    except ImportError:
        return None

    raw = bytes(encrypted_value)
    if raw[:3] != b"v10" or len(raw) < 35:
        return None

    password = keychain_password.encode("utf-8")
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA1(), length=16, salt=b"saltysalt",
        iterations=1003, backend=default_backend(),
    )
    key = kdf.derive(password)

    iv = raw[19:35]
    ciphertext = raw[35:]
    cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
    dec = cipher.decryptor()
    plaintext = dec.update(ciphertext) + dec.finalize()
    pad = plaintext[-1]
    return plaintext[:-pad].decode("utf-8", errors="replace")

def _read_claude_cookies():
    """Return a dict of decrypted Claude cookies, or {} on failure."""
    password = _get_keychain_key()
    if not password:
        return {}
    try:
        import shutil
        with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as tmp:
            tmp_path = tmp.name
        shutil.copy2(_CLAUDE_COOKIES_DB, tmp_path)
        conn = sqlite3.connect(tmp_path)
        rows = conn.execute(
            "SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%claude%'"
        ).fetchall()
        conn.close()
        os.remove(tmp_path)
        return {
            name: _decrypt_electron_cookie(ev, password)
            for name, ev in rows
            if _decrypt_electron_cookie(ev, password)
        }
    except Exception as e:
        log.error("Cookie read error: %s", e)
        return {}

def _get_claude_usage():
    """
    Fetch the Claude 5-hour usage window from claude.ai.
    Returns (resets_at: datetime | None, message: str).
    Requires curl_cffi (pip install curl_cffi) for Chrome TLS impersonation.
    """
    try:
        from curl_cffi import requests as cffi_requests
    except ImportError:
        return None, "curl_cffi not installed. Run: pip install curl_cffi"

    cookies = _read_claude_cookies()
    org_id = cookies.get("lastActiveOrg", "").strip()
    if not org_id or not cookies.get("sessionKey"):
        return None, "Could not read Claude session cookies."

    try:
        resp = cffi_requests.get(
            f"https://claude.ai/api/organizations/{org_id}/usage",
            cookies=cookies,
            impersonate="chrome131",
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        return None, f"API request failed: {e}"

    five = data.get("five_hour")
    if not five:
        return None, "No five_hour usage data in API response."

    utilization = five.get("utilization")
    resets_at_str = five.get("resets_at")
    pct = f"{round(utilization)}%" if utilization is not None else "unknown"

    if resets_at_str:
        resets_at = datetime.fromisoformat(resets_at_str.replace("Z", "+00:00"))
        now = datetime.now(timezone.utc)
        secs_left = max(0, int((resets_at - now).total_seconds()))
        h, rem = divmod(secs_left, 3600)
        m = rem // 60
        time_str = f"{h}h {m}m" if h else f"{m}m"
    else:
        resets_at = None
        time_str = "unknown"

    return resets_at, f"⏳ 5-hour limit: {pct} used · resets in {time_str}"

def _schedule_usage_notification(resets_at):
    """Sleep until resets_at then send a Telegram notification."""
    def _notify():
        secs = max(0, (resets_at - datetime.now(timezone.utc)).total_seconds())
        time.sleep(secs)
        send("✅ 5-hour limit has reset — you're good to go!")
    threading.Thread(target=_notify, daemon=True).start()

# ── Command handlers ───────────────────────────────────────────────────────

# Private 0700 directory — avoids world-writable /tmp races
_ASK_RESULT_DIR = os.path.join(tempfile.gettempdir(), f"claude-remote-{os.getuid()}")

def _init_approval_dir(path: str) -> None:
    """Create or verify the private approval directory. Abort if unsafe."""
    os.makedirs(path, mode=0o700, exist_ok=True)
    st = os.stat(path)
    import stat as _stat
    if st.st_uid != os.getuid():
        raise RuntimeError(
            f"Approval directory {path} is owned by UID {st.st_uid}, "
            f"expected {os.getuid()}. Possible pre-creation attack. Aborting."
        )
    mode = _stat.S_IMODE(st.st_mode)
    if mode != 0o700:
        raise RuntimeError(
            f"Approval directory {path} has mode {oct(mode)}, expected 0700. "
            f"Fix with: chmod 700 {path}"
        )

_init_approval_dir(_ASK_RESULT_DIR)

# PID file — written at startup, removed on clean shutdown.
# assistant_ask.sh uses this to verify the daemon that owns the approval dir is running.
_PID_FILE = os.path.join(_ASK_RESULT_DIR, "daemon.pid")

# Heartbeat file — updated every poll cycle so assistant_ask.sh can detect PID reuse.
# A crashed daemon will leave a stale heartbeat; a reused PID won't update it.
_HEARTBEAT_FILE = os.path.join(_ASK_RESULT_DIR, "daemon.heartbeat")
_HEARTBEAT_INTERVAL = 30   # seconds between heartbeat writes
_HEARTBEAT_MAX_AGE  = 120  # seconds before assistant_ask.sh treats daemon as dead
                            # Must be > HEARTBEAT_INTERVAL + worst-case write delay

_heartbeat_error_logged = False

def _update_heartbeat() -> None:
    global _heartbeat_error_logged
    try:
        fd = os.open(_HEARTBEAT_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(str(time.time()))
        _heartbeat_error_logged = False  # reset if it recovers
    except Exception as e:
        if not _heartbeat_error_logged:
            log.error("Heartbeat write failed — assistant_ask.sh will reject approvals: %s", e)
            _heartbeat_error_logged = True

def _start_heartbeat_thread() -> None:
    """Write heartbeat on a fixed interval, independent of handle() blocking."""
    def _loop():
        while True:
            _update_heartbeat()
            time.sleep(_HEARTBEAT_INTERVAL)
    t = threading.Thread(target=_loop, daemon=True, name="heartbeat")
    t.start()

def _ask_result_path(approval_id: str) -> str:
    return os.path.join(_ASK_RESULT_DIR, f"ask_{approval_id}")

def _try_route_approval(text: str) -> bool:
    """
    Check if text is a YES/NO <id> approval reply.

    Handles two cases:
    - In-process: daemon's ask() registered the ID in _pending_approvals → signal the event.
    - Shell: assistant_ask.sh registered the ID via a sentinel file → write result to file.

    Returns True if consumed, False if the ID is unknown (forward normally).
    """
    parts = text.strip().split()
    if len(parts) != 2:
        return False
    verdict, approval_id = parts[0].upper(), parts[1].lower()
    if verdict not in ("YES", "NO"):
        return False

    approved = (verdict == "YES")

    # Case 1: in-process approval (daemon's ask() is waiting)
    with _approvals_lock:
        entry = _pending_approvals.get(approval_id)
    if entry:
        event, result = entry
        result["approved"] = approved
        event.set()
        send("✅ Approved." if approved else "❌ Denied — cancelled.")
        return True

    # Case 2: shell approval (assistant_ask.sh created a sentinel file)
    sentinel = _ask_result_path(approval_id)
    if os.path.exists(sentinel):
        result_file = sentinel + ".result"
        fd = os.open(result_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write("YES" if approved else "NO")
        send("✅ Approved." if approved else "❌ Denied — cancelled.")
        return True

    # Unknown ID — don't consume, let normal handling deal with it
    return False

def handle(text):
    text = text.strip()
    lower = text.lower()

    if _try_route_approval(text):
        return

    if lower == "help":
        help_text = (
            "🤖 *assistant commands:*\n"
            "• `screenshot` — send a screenshot\n"
            "• `open <app>` — open an app\n"
            "• `say <text>` — speak aloud\n"
            "• `run <cmd>` — run shell command" +
            (" (requires secret)" if SECRET else "") + "\n"
            "• `volume <0-100>` — set volume\n"
            "• `remind <text>` — add a reminder\n"
            "• `usage` — check Claude 5-hour limit & get notified on reset\n"
            "• `status` — daemon uptime and stats\n"
            "• `help` — this message"
        )
        if CLAUDE_MODE:
            help_text += "\n\nAnything else → forwarded to Claude Code 🚀"
        send(help_text)

    elif lower == "usage":
        send("🔍 Checking Claude usage...")
        resets_at, msg = _get_claude_usage()
        if resets_at:
            send(msg + "\n\n📬 I'll notify you when it resets.")
            _schedule_usage_notification(resets_at)
        else:
            send(msg)

    elif lower == "status":
        uptime = time.time() - start_time
        h, m = divmod(int(uptime), 3600)
        m, s = divmod(m, 60)
        send(
            f"🟢 assistant daemon is running\n"
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
        if not SECRET:
            send("🔒 `run` is disabled — set ASSISTANT_SECRET in config.sh to enable remote shell execution.")
            return
        cmd = text[4:].strip()
        secret_prefix = SECRET + " "
        if not cmd.startswith(secret_prefix):
            send("🔒 Wrong secret. Format: `run <secret> <command>`")
            return
        cmd = cmd[len(secret_prefix):]
        if not cmd:
            send("❌ No command after secret.")
            return
        send(f"💻 Running: `{cmd[:80]}{'...' if len(cmd) > 80 else ''}`")
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
        # Pass reminder text as an AppleScript argument — no string interpolation
        script = 'on run argv\ntell application "Reminders"\nmake new reminder with properties {name:item 1 of argv}\nend tell\nend run'
        try:
            result = subprocess.run(
                ["osascript", "-e", script, reminder],
                capture_output=True, text=True, timeout=15,
            )
            if result.returncode == 0:
                send(f"🔔 Reminder added: {reminder}")
            else:
                send(f"❌ Reminder error: {(result.stdout + result.stderr).strip()}")
        except Exception as e:
            send(f"❌ Reminder error: {e}")

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

    # Write PID file so assistant_ask.sh can verify this daemon instance is running
    try:
        fd = os.open(_PID_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(str(os.getpid()))
    except Exception as e:
        log.warning("Could not write PID file: %s", e)

    # Heartbeat runs in a background thread — independent of handle() blocking
    _start_heartbeat_thread()

    log.info("assistant daemon starting...")
    log.info("Claude mode: %s", "on" if CLAUDE_MODE else "off")
    log.info("Secret: %s", "required" if SECRET else "disabled (insecure)")
    log.info("State file: %s", STATE_FILE)

    # Send startup notification (survive failure gracefully)
    try:
        send(
            f"🟢 assistant daemon is online.\n"
            f"Send `help` for commands." +
            ("\nAnything else → Claude Code 🚀" if CLAUDE_MODE else "")
        )
    except Exception as e:
        log.warning("Could not send startup message: %s", e)

    # If no saved offset, fast-forward past old messages
    if offset == 0:
        try:
            data = api_call("getUpdates", {"limit": 1, "offset": -1})
            if data.get("result"):
                offset = data["result"][-1]["update_id"] + 1
        except Exception:
            pass

    log.info("Listening for messages (offset=%d)...", offset)

    error_backoff = 5  # seconds, doubles on repeated errors up to 60s
    while True:
        try:
            data = api_call("getUpdates", {"offset": offset, "timeout": 30})
            error_backoff = 5  # reset on success
            for update in data.get("result", []):
                msg = update.get("message", {})
                chat_id = msg.get("chat", {}).get("id")
                text = msg.get("text", "").strip()

                # Skip non-target chats & empty messages (advance past them)
                if chat_id != CHAT_ID or not text:
                    offset = update["update_id"] + 1
                    state["offset"] = offset
                    save_state(state)
                    continue

                stats["commands"] += 1
                log.info("Received: %s", text)
                handle(text)

                # Advance offset AFTER successful handle — prevents silent loss on crash
                offset = update["update_id"] + 1
                state["offset"] = offset
                save_state(state)

        except KeyboardInterrupt:
            try:
                send("🔴 assistant daemon stopped.")
            except Exception:
                pass
            try:
                os.remove(_PID_FILE)
            except OSError:
                pass
            log.info("Stopped (KeyboardInterrupt).")
            sys.exit(0)
        except Exception as e:
            log.error("Poll error (retry in %ds): %s", error_backoff, e)
            time.sleep(error_backoff)
            error_backoff = min(error_backoff * 2, 60)  # exponential backoff, cap 60s

def _shutdown(signum, frame):
    """Handle SIGTERM gracefully (sent by launchd on stop)."""
    try:
        send("🔴 assistant daemon stopped.")
    except Exception:
        pass
    try:
        os.remove(_PID_FILE)
    except OSError:
        pass
    log.info("Stopped (SIGTERM).")
    sys.exit(0)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _shutdown)
    main()
