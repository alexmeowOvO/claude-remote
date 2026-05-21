#!/bin/bash
# push_to_github.command
# Double-click to commit everything and push assistant-remote to GitHub.
# Before running: create an empty repo at https://github.com/new

cd "$(dirname "$0")"

echo "🦞 assistant-remote — GitHub push"
echo ""

# Clean up any stale git lock files
rm -f .git/index.lock .git/MERGE_HEAD 2>/dev/null

# Init if needed, otherwise just stage everything
if [ ! -d ".git" ]; then
  git init
  git branch -m main
fi

git add -A
git status

echo ""
echo "Step 1: Create an empty repo at https://github.com/new"
echo "  - Name: assistant-remote  (or anything you like)"
echo "  - Keep it Public or Private"
echo "  - Do NOT add README, .gitignore, or license (we already have them)"
echo ""
read -p "Paste your GitHub repo URL (e.g. https://github.com/yourname/assistant-remote): " REPO_URL

if [ -z "$REPO_URL" ]; then
  echo "❌ No URL provided. Exiting."
  exit 1
fi

# Commit
git -c user.email="wpengnan@gmail.com" -c user.name="alex" \
  commit -m "Add claude-code integration + security improvements

- claude-code/: Stop hook, slash commands, install.sh
  - stop_notify.sh sources creds from config.sh (no hardcoded tokens)
  - /code-assistant: supervised session startup with Telegram
  - /notification: alert before risky actions
- daemon/: security rewrite
  - No shell=True; shlex.split() throughout
  - AppleScript via stdin (no injection)
  - Credentials from env vars only
  - Offset persistence via .assistant_state.json
  - Background threading for run commands
  - status command, [ASK] prefix skip" 2>/dev/null || echo "(nothing new to commit)"

echo ""
echo "Pushing to $REPO_URL ..."

# Set or update remote
if git remote get-url origin &>/dev/null; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

git push -u origin main

echo ""
echo "✅ Done! Your repo is live at $REPO_URL"
echo ""
read -p "Press Enter to close..."
