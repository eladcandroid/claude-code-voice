#!/bin/bash
set -euo pipefail

echo "=== Uninstalling Claude Code Voice ==="
echo ""

# 1. Stop and remove launch agent (check both old and new names)
for name in com.hebrew-voice.server com.hebrew-voice.server; do
  PLIST="$HOME/Library/LaunchAgents/$name.plist"
  if [ -f "$PLIST" ]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "[✓] Removed $name launch agent"
  fi
done

# 2. Kill any running voice server
pkill -f "voice-server" 2>/dev/null || true
pkill -f "hebrew-voice" 2>/dev/null || true
pkill -f "HebrewVoice" 2>/dev/null || true
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
tccutil reset SpeechRecognition com.hebrew-voice.server 2>/dev/null || true
tccutil reset SpeechRecognition com.hebrew-voice.server 2>/dev/null || true
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
