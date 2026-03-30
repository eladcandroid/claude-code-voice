# Voice Support for Claude Code

Adds native on-device speech-to-text to Claude Code's `/voice` command using Apple's `SFSpeechRecognizer`. Single Swift binary, no external dependencies, survives updates.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/eladcandroid/claude-code-voice/main/setup.sh | bash
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/eladcandroid/claude-code-voice/main/uninstall.sh | bash
```

## Switch language

`/config` → change language → next recording uses it. Default: English. Set to `he` for Hebrew.

## Supported languages

en, he, es, fr, de, ja, ko, pt, it, ru, zh, ar, hi, tr, nl, pl, uk, el, cs, da, sv, no — and any other language Apple's SFSpeechRecognizer supports.
