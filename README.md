# SakuraClipboard

A lightweight macOS menu bar clipboard history app. Keep your text and image clips accessible from the system menu bar.

[![Build](https://github.com/YOUR_USERNAME/SakuraClipboard/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_USERNAME/SakuraClipboard/actions/workflows/build.yml)

## Features

- **Clipboard History** — Automatically saves text and image clips
- **Quick Access** — Opens from menu bar or `Cmd+Shift+C`
- **Search** — `Cmd+Shift+F` opens search panel with Chinese input support
- **Preview** — Click "预览" button to view full text, hover images to preview
- **Favorites** — Right-click to favorite items
- **Auto Cleanup** — Configurable retention (1-30 days or forever)
- **History Limit** — 100 to 5000 items
- **Ignore Apps** — Exclude specific apps from monitoring
- **Launch at Login** — Optional auto-start
- **Chinese/English UI** — Language switching

## Download

Download the latest DMG from [Releases](https://github.com/YOUR_USERNAME/SakuraClipboard/releases):

- `SakuraClipboard-arm64.dmg` — Apple Silicon (M1/M2/M3)
- `SakuraClipboard-x86_64.dmg` — Intel

## Build from Source

```bash
./build.sh
```

Outputs:
- `SakuraClipboard.app`
- `SakuraClipboard.dmg`

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+C` | Open history menu |
| `Cmd+Shift+F` | Open search panel |

## Project Structure

```
Sources/
├── AppDelegate.swift           # App lifecycle, menu bar, settings
├── ClipboardItem.swift         # Data model
├── ClipboardStore.swift        # SQLite storage
├── ClipboardMonitor.swift      # Clipboard polling
├── HistoryListPopoverController.swift  # History list UI
├── SearchPanel.swift           # Search panel UI
├── HUDWindow.swift             # Copy notification
├── KeyboardShortcut.swift      # Global hotkeys
├── ThemeManager.swift          # Dark/light mode
├── Localization.swift          # i18n
└── main.swift                  # Entry point
```

## License

MIT

## Author

Sakura
