#!/bin/bash
# check.sh — Validate all project files before committing
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0; FAIL=0

ok()   { echo "  ✅ $*"; PASS=$((PASS+1)); }
fail() { echo "  ❌ $*"; FAIL=$((FAIL+1)); }

echo "🔍 claude-remote integrity check"
echo ""

# Python syntax
echo "── Python ──"
for f in "$REPO"/daemon/*.py; do
  if python3 -m py_compile "$f" 2>/dev/null; then
    ok "$(basename "$f")"
  else
    fail "$(basename "$f") — syntax error"
  fi
done

# Bash syntax
echo "── Bash ──"
for f in "$REPO"/daemon/*.sh "$REPO"/claude-code/**/*.sh "$REPO"/scripts/*.sh; do
  [ -f "$f" ] || continue
  if bash -n "$f" 2>/dev/null; then
    ok "$(basename "$f")"
  else
    fail "$(basename "$f") — syntax error"
  fi
done

# Plist lint (both .plist and .plist.template)
echo "── Plist ──"
for f in "$REPO"/daemon/*.plist; do
  [ -f "$f" ] || continue
  if plutil -lint "$f" > /dev/null 2>&1; then
    ok "$(basename "$f")"
  else
    fail "$(basename "$f") — invalid plist"
  fi
done
for f in "$REPO"/daemon/*.plist.template; do
  [ -f "$f" ] || continue
  # Substitute placeholder with a dummy path and lint the result
  tmp=$(mktemp /tmp/check_plist_XXXXXX.plist)
  sed 's|/REPLACE_WITH_REPO_PATH|/tmp/dummy|g' "$f" > "$tmp"
  if plutil -lint "$tmp" > /dev/null 2>&1; then
    ok "$(basename "$f")"
  else
    fail "$(basename "$f") — invalid plist"
  fi
  rm -f "$tmp"
done

# Shellcheck (optional)
echo "── Shellcheck (optional) ──"
if command -v shellcheck &>/dev/null; then
  for f in "$REPO"/daemon/*.sh "$REPO"/claude-code/hooks/*.sh; do
    [ -f "$f" ] || continue
    if shellcheck "$f" 2>/dev/null; then
      ok "$(basename "$f")"
    else
      fail "$(basename "$f") — shellcheck warnings"
    fi
  done
else
  echo "  ⚠️  shellcheck not installed (brew install shellcheck)"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
