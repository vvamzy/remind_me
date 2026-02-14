# Todo Timer (Windows)

Futuristic, minimal Windows todo app with per-task countdowns and a green→red progression as time runs out. Light, Dark, and Auto themes included.

## Features
- Per-task countdown with live updates (4× per second)
- Progress bar color shifts from green to red as time elapses
- Light / Dark / Auto theme with neon accents
- Mark complete, delete, and filter by All / Active / Done
- Local persistence of tasks and theme

## Run Locally
PowerShell 7+ on Windows:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\src\app.ps1
```

## Logging
- File-based logging writes to `%LOCALAPPDATA%\TodoTimer\logs\todotimer.log`.
- Default level is `INFO`. Set `TODO_TIMER_LOG_LEVEL` to `DEBUG`, `INFO`, `WARN`, or `ERROR`.
- The log auto-rotates at ~2 MB.

## Build (GitHub Actions)
On every push and PR, a Windows workflow:
- Generates an icon from `assets/icon.svg`
- Compiles the script into `dist/TodoTimer.exe` using PS2EXE
- Builds a Windows installer `dist/TodoTimer-Setup.exe` using Inno Setup
- Uploads artifacts

See [.github/workflows/build.yml](file:///c:/Users/Miriyala/Documents/trae_projects/todo_list_win/.github/workflows/build.yml).

## Installer Script
Inno Setup configuration lives at [installer.iss](file:///c:/Users/Miriyala/Documents/trae_projects/todo_list_win/assets/installer.iss). It bundles the compiled EXE and adds Start Menu and optional desktop shortcuts.

## Source Layout
- `src/app.ps1` — main WPF desktop app
- `assets/icon.svg` — app icon (converted to `.ico` during CI)
- `assets/installer.iss` — Inno Setup script
- `dist/` — build outputs (CI)
- `data/` — local state during development

## License
MIT — see [LICENSE](file:///c:/Users/Miriyala/Documents/trae_projects/todo_list_win/LICENSE).
