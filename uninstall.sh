#!/bin/bash
set -euo pipefail

echo "=== Uninstalling Claude Code Voice ==="
echo ""

# Detect GitHub username from the installed repo before we remove it
_INSTALL_DIR="$HOME/.local/share/claude-code-voice"
_REMOTE_URL=$(git -C "$_INSTALL_DIR" remote get-url origin 2>/dev/null || echo "")
_GITHUB_USER=$(echo "$_REMOTE_URL" | sed -E 's|.*github\.com[:/]([^/]+)/.*|\1|')
_GITHUB_USER="${_GITHUB_USER:-dr-data}"

# 1. Stop and remove launch agents (current + legacy names)
for name in com.claude-code-voice com.claude-code-voice.server com.hebrew-voice.server; do
  PLIST="$HOME/Library/LaunchAgents/$name.plist"
  if [ -f "$PLIST" ]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "[✓] Removed $name"
  fi
done

# 2. Kill any running voice server
pkill -f "voice-server" 2>/dev/null || true
echo "[✓] Stopped voice server"

# 3. Remove VOICE_STREAM_BASE_URL from settings.json
SETTINGS="$HOME/.claude/settings.json"
if [ -f "$SETTINGS" ] && grep -q VOICE_STREAM_BASE_URL "$SETTINGS"; then
  python3 - << 'PYEOF'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
with open(path) as f:
    s = json.load(f)
s.get("env", {}).pop("VOICE_STREAM_BASE_URL", None)
with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
PYEOF
  echo "[✓] Removed VOICE_STREAM_BASE_URL from settings.json"
else
  echo "[–] settings.json already clean"
fi

# 4. Reset Speech Recognition permission
for bid in com.claude-code-voice com.claude-code-voice.server com.hebrew-voice.server; do
  tccutil reset SpeechRecognition "$bid" 2>/dev/null || true
done
echo "[✓] Reset Speech Recognition permission"

# 5. Remove install directories
for dir in "$HOME/.local/share/claude-code-voice" "$HOME/.local/share/hebrew-voice"; do
  if [ -d "$dir" ]; then
    rm -rf "$dir"
    echo "[✓] Removed $dir"
  fi
done

echo ""
echo "=== Uninstall complete ==="
echo "Restart Claude Code for changes to take effect."
echo "Reinstall: curl -fsSL https://raw.githubusercontent.com/$_GITHUB_USER/claude-code-voice/main/setup.sh | bash"
