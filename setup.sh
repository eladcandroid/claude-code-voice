#!/bin/bash
set -euo pipefail

# Claude Code Voice (macOS)
# Requirements: Xcode Command Line Tools only.

INSTALL_DIR="$HOME/.local/share/claude-code-voice"

# If running via curl|bash, clone the repo first
if [ ! -f "scripts/server.swift" ]; then
  echo "Downloading claude-code-voice..."
  rm -rf "$INSTALL_DIR"
  git clone --depth 1 https://github.com/eladcandroid/claude-code-voice.git "$INSTALL_DIR" 2>/dev/null
  cd "$INSTALL_DIR"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$SCRIPT_DIR/scripts"
APP="$SCRIPTS/HebrewVoice.app"

echo "=== Claude Code Voice ==="
echo ""

# Check Swift is available
if ! command -v swiftc &>/dev/null; then
  echo "ERROR: Xcode Command Line Tools required."
  echo "  Install: xcode-select --install"
  exit 1
fi

# 1. Build the app
echo "[1/2] Building..."
mkdir -p "$APP/Contents/MacOS"

swiftc -O -o "$APP/Contents/MacOS/voice-server" "$SCRIPTS/server.swift" \
  -framework Network -framework Speech -framework Foundation -framework AppKit 2>/dev/null

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.hebrew-voice.server</string>
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

echo "  Built HebrewVoice.app"

# 2. Configure settings + install launch agent
echo "[2/2] Configuring..."

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

# Install launch agent
PLIST="$HOME/Library/LaunchAgents/com.hebrew-voice.server.plist"
launchctl unload "$PLIST" 2>/dev/null || true
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.hebrew-voice.server</string>
    <key>ProgramArguments</key><array>
        <string>$APP/Contents/MacOS/voice-server</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/tmp/hebrew-voice.log</string>
    <key>StandardErrorPath</key><string>/tmp/hebrew-voice.log</string>
</dict></plist>
EOF

launchctl load "$PLIST"
echo "  Voice server installed and started"

echo ""
echo "=== Done ==="
echo ""
echo "Restart Claude Code, enable /voice, and speak."
echo "Switch language with /config. Native languages → Anthropic, others → Apple STT."
echo ""
echo "First run: macOS will ask for Speech Recognition permission — click Allow."
echo ""
echo "Uninstall: curl -fsSL https://raw.githubusercontent.com/eladcandroid/claude-code-voice/main/uninstall.sh | bash"
