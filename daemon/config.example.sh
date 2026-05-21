#!/bin/bash
# kloa config — COPY THIS FILE to config.sh and fill in your values.
# config.sh is gitignored and should NEVER be committed.
#
# Generate a bot token via @BotFather on Telegram.
# Get your chat ID by messaging @userinfobot.

# ── Telegram Bot (REQUIRED) ─────────────────────
export KLOA_TOKEN="YOUR_BOT_TOKEN_HERE"
export KLOA_CHAT_ID="YOUR_CHAT_ID_HERE"

# ── Authentication (RECOMMENDED) ────────────────
# Shared secret required to run shell commands remotely.
# Any `run <cmd>` message must be prefixed with this secret.
# Leave empty to disable (NOT recommended).
export KLOA_SECRET=""

# ── Feature flags (OPTIONAL) ────────────────────
# Set to "1" to forward unrecognised messages to Claude Code.
export KLOA_CLAUDE_MODE="0"
