# receptor-fryer 🍟🧠

Plays a local video while **Claude Code is thinking** and pauses it the moment Claude
stops — resuming exactly where it left off. Each series remembers its own episode and
timestamp. Built for Windows with `mpv` + PowerShell, plus a small control panel.

> This tool only plays whatever local file you point it at via `config.json`. It does
> not download anything and does not care where your files come from.

## How it works

Claude Code fires hooks around each turn:

| Event | Claude Code hook | Action |
|-------|------------------|--------|
| You send a message → Claude starts working | `UserPromptSubmit` | bring video to front + play |
| Claude finishes → your turn | `Stop` | pause + save position |

Playback uses **mpv**, kept alive as a single instance and driven over its JSON IPC
pipe, so pausing keeps the exact frame. Position is also persisted to `config.json`
per series.

## Features

- ▶️ Auto play/pause tied to Claude Code's thinking state
- ⏱️ Per-series resume memory (which episode + which second)
- 📁 Single source folder, auto-grouped into "animes" by filename
- 🎛️ WinForms control panel: master on/off, series picker, episode list, speed
- ⚡ Default **1.25×** playback speed, adjustable live from the panel
- 🌐 Works in every Claude Code session (global hooks) or just one folder (project hooks)

## Requirements

- Windows
- [Claude Code](https://claude.com/claude-code)
- [mpv](https://mpv.io/installation/) — e.g. `winget install shinchiro.mpv`

## Setup

1. Install mpv and note the path to `mpv.exe`.
2. Copy `config.example.json` to `config.json` and edit:
   - `mpvPath` — full path to `mpv.exe`
   - `sourceRoot` — folder that holds your video files
3. Enable the hooks (see below).
4. Open the panel: double-click `receptor-fryer.cmd`.

## Enabling the hooks

**Every session (any folder)** — add to your global `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command",
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/path/to/receptor-fryer/scripts/fryer.ps1\" play" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command",
        "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"C:/path/to/receptor-fryer/scripts/fryer.ps1\" pause" } ] }
    ]
  }
}
```

**One folder only** — put the same `hooks` block in that project's `.claude/settings.json`.

Hooks load at session start, so start a new Claude Code session after editing settings.

## Control panel

`receptor-fryer.cmd` (or `scripts/gui.ps1`) opens a panel to:

- Toggle the whole system **on/off** (`enabled`)
- Pick the **active series** (auto-detected from `sourceRoot`)
- Pick the **active episode** (each series remembers its own)
- Set **playback speed**
- Play / pause manually and watch the live position

## Manual test (without Claude Code)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fryer.ps1 play
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\fryer.ps1 pause
```

## Files

| File | Purpose |
|------|---------|
| `scripts/fryer.ps1` | Core: play/pause, position memory, speed (hooks call this) |
| `scripts/gui.ps1` | WinForms control panel |
| `scripts/common.ps1` | Groups the source folder into series |
| `config.json` | Your config (git-ignored; copy from `config.example.json`) |
| `receptor-fryer.cmd` | Launches the panel |

## Notes

- The master **off** switch in the panel disables playback across all sessions.
- Number formatting for speed is culture-invariant, so non-US locales won't break mpv/JSON.
