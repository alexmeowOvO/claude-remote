#!/bin/bash
set -euo pipefail
# push_to_github.command
# Double-click to commit everything and push claude-remote to GitHub.
# Before running: create an empty repo at https://github.com/new

cd "$(dirname "$0")"

echo "🦞 claude-remote — GitHub push"
echo ""

# Only remove index.lock (safe) — never touch MERGE_HEAD (would corrupt in-progress merges)
rm -f .git/index.lock 2>/dev/null

# Init if needed
if [ ! -d ".git" ]; then
  git init
  git branch -m main
fi

# Show status and require explicit confirmation before staging anything
echo "Current git status:"
git status --short
echo ""

if git status --short | grep -q .; then
  read -p "Stage and commit all changes above? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborted — nothing staged or pushed."
    exit 0
  fi
else
  echo "(No uncommitted changes — will still push existing commits.)"
fi

git add -A
git status

echo ""
echo "Step 1: Create an empty repo at https://github.com/new"
echo "  - Name: claude-remote  (or anything you like)"
echo "  - Keep it Public or Private"
echo "  - Do NOT add README, .gitignore, or license (we already have them)"
echo ""
read -p "Paste your GitHub repo URL (e.g. https://github.com/yourname/claude-remote): " REPO_URL

if [ -z "$REPO_URL" ]; then
  echo "❌ No URL provided. Exiting."
  exit 1
fi

# Commit
git -c user.email="wpengnan@gmail.com" -c user.name="alex" \
  commit -m "Initial commit: claude-remote Telegram daemon and Claude Code integration" \
  2>/dev/null || echo "(nothing new to commit)"

echo ""
echo "Pushing to $REPO_URL ..."

# Set or update remote
if git remote get-url origin &>/dev/null; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

if git push -u origin main; then
  echo ""
  echo "✅ Done! Your repo is live at $REPO_URL"
else
  echo ""
  echo "❌ Push failed — check output above."
  read -p "Press Enter to close..."
  exit 1
fi
echo ""
echo "✅ Done! Your repo is live at $REPO_URL"
echo ""
read -p "Press Enter to close..."
