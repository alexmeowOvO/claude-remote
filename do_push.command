#!/bin/bash
cd "$(dirname "$0")"

echo "=== Removing git lock ==="
rm -f .git/index.lock .git/MERGE_HEAD 2>/dev/null

echo "=== Staging all files ==="
git add -A
git status

echo "=== Committing ==="
git -c user.email="wpengnan@gmail.com" -c user.name="alex" \
  commit -m "Rename: kloa → assistant throughout (files, env vars, comments)" 2>/dev/null \
  || echo "(already committed or nothing new)"

echo "=== Setting remote ==="
git remote remove origin 2>/dev/null
git remote add origin https://github.com/alexmeowOvO/claude-remote.git

echo "=== Pushing ==="
git push -u origin main

echo ""
echo "✅ Done!"
read -p "Press Enter to close..."
