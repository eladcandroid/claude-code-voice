# Claude Code Voice (macOS)

Adds native on-device speech-to-text to Claude Code's `/voice` command using Apple's `SFSpeechRecognizer`. Natively supported languages proxy to Anthropic's server; unsupported languages (Hebrew, Arabic, etc.) transcribe locally via Apple STT. No API keys, no binary patching — survives Claude Code updates.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/eladcandroid/claude-code-voice/main/setup.sh | bash
```

## Requirements

- macOS (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`)
- Claude Code with `/voice` support

## Usage

After install, restart Claude Code:

1. `/voice` to enable voice mode
2. Hold **Space** to record
3. Speak
4. Release — transcript appears

> **First run:** macOS will prompt for Speech Recognition permission — click **Allow**.

## Switching languages

Type `/config` in Claude Code to change the language. The voice server picks it up immediately — no restart needed.

### Supported languages

| Language | `/config` value | Backend |
|----------|----------------|---------|
| English | `en` (default) | Anthropic |
| Spanish | `es` | Anthropic |
| French | `fr` | Anthropic |
| German | `de` | Anthropic |
| Japanese | `ja` | Anthropic |
| Korean | `ko` | Anthropic |
| Portuguese | `pt` | Anthropic |
| Italian | `it` | Anthropic |
| Russian | `ru` | Anthropic |
| Hindi | `hi` | Anthropic |
| Indonesian | `id` | Anthropic |
| Polish | `pl` | Anthropic |
| Turkish | `tr` | Anthropic |
| Dutch | `nl` | Anthropic |
| Ukrainian | `uk` | Anthropic |
| Greek | `el` | Anthropic |
| Czech | `cs` | Anthropic |
| Danish | `da` | Anthropic |
| Swedish | `sv` | Anthropic |
| Norwegian | `no` | Anthropic |
| **Hebrew** | `he` | Apple STT |
| **Arabic** | `ar` | Apple STT |
| **Chinese** | `zh` | Apple STT |

Any language supported by Apple's `SFSpeechRecognizer` works — the 20 natively supported languages are proxied to Anthropic's server for best quality.

## How it works

Claude Code has an undocumented `VOICE_STREAM_BASE_URL` env var that redirects its voice WebSocket. This project runs a native macOS app on `localhost:19876` that acts as a smart router:

- **Native languages** (20) → proxied to Anthropic's voice server with OAuth token from Keychain
- **Other languages** → transcribed locally via Apple's on-device `SFSpeechRecognizer`

```
                          ┌─ native lang ──▶ Anthropic server
┌─────────────┐   audio   │                  (streaming STT)
│ Claude Code  │──chunks──▶│ voice-server
│ /voice + ␣   │◀──text───│
└─────────────┘           └─ other lang ──▶ Apple STT
                                             (on-device)
```

Everything is a single Swift binary — WebSocket server, proxy, and speech recognition combined. No external runtimes needed.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/eladcandroid/claude-code-voice/main/uninstall.sh | bash
```

## Project structure

```
├── setup.sh              # One-command install
├── uninstall.sh           # Full uninstall
└── scripts/
    └── server.swift       # WebSocket server + proxy + Apple STT (single file)
```
