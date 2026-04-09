#!/bin/bash
set -euo pipefail

# Claude Code Voice (macOS)
# Requirements: Xcode Command Line Tools only.

INSTALL_DIR="$HOME/.local/share/claude-code-voice"

# If running via curl|bash, clone the repo first
if [ ! -f "scripts/server.swift" ]; then
  echo "Downloading claude-code-voice..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 https://github.com/dr-data/claude-code-voice.git "$INSTALL_DIR" 2>/dev/null
  cd "$INSTALL_DIR"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$SCRIPT_DIR/scripts"
APP="$SCRIPTS/VoiceServer.app"

echo "=== Claude Code Voice ==="
echo ""

if ! command -v swiftc &>/dev/null; then
  echo "ERROR: Xcode Command Line Tools required."
  echo "  Install: xcode-select --install"
  exit 1
fi

# 1. Build
echo "[1/3] Building..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/voice-server" "$SCRIPTS/server.swift" \
  -framework Network -framework Speech -framework Foundation -framework AppKit 2>/dev/null

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.claude-code-voice</string>
    <key>CFBundleName</key><string>ClaudeCodeVoice</string>
    <key>CFBundleExecutable</key><string>voice-server</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Voice transcription for Claude Code</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Audio input for speech recognition</string>
</dict></plist>
EOF

codesign --force --sign - --entitlements /dev/stdin "$APP" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.device.audio-input</key><true/>
</dict></plist>
EOF
echo "  Done"

# 2. Grant Speech Recognition permission
echo "[2/3] Requesting Speech Recognition permission..."
echo "  >>> If a dialog appears, click ALLOW <<<"
open -W "$APP" &
OPEN_PID=$!
sleep 10
kill "$OPEN_PID" 2>/dev/null || true
pkill -f voice-server 2>/dev/null || true
sleep 1

# 3. Configure settings + install launch agent
echo "[3/3] Configuring..."

SETTINGS="$HOME/.claude/settings.json"
if [ ! -f "$SETTINGS" ]; then
  mkdir -p "$HOME/.claude"
  echo '{}' > "$SETTINGS"
fi

python3 - << 'PYEOF'
import json, os
path = os.path.expanduser("~/.claude/settings.json")
with open(path) as f:
    s = json.load(f)
s.setdefault("env", {})["VOICE_STREAM_BASE_URL"] = "ws://127.0.0.1:19876"
with open(path, "w") as f:
    json.dump(s, f, indent=2, ensure_ascii=False)
print("  Updated settings.json")
PYEOF

PLIST="$HOME/Library/LaunchAgents/com.claude-code-voice.plist"
launchctl unload "$PLIST" 2>/dev/null || true
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.claude-code-voice</string>
    <key>ProgramArguments</key><array>
        <string>$APP/Contents/MacOS/voice-server</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/claude-code-voice.log</string>
    <key>StandardErrorPath</key><string>/tmp/claude-code-voice.log</string>
</dict></plist>
EOF

launchctl load "$PLIST"
echo "  Voice server started"

echo ""
echo "=== Done ==="
echo "Restart Claude Code, enable /voice, and speak."
echo "Switch language with /config."
echo "Supported /config language codes:"
echo "  en, es, fr, de, ja, ko, pt, it, ru, hi, id, pl, tr, nl, uk, el, cs, da, sv, no, he, ar, zh, zh-hk"
echo "  plus any language supported by Apple SFSpeechRecognizer"
echo ""
echo "Uninstall: curl -fsSL https://raw.githubusercontent.com/dr-data/claude-code-voice/main/uninstall.sh | bash"
