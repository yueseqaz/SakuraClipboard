# SakuraClipboard

A lightweight macOS menu bar clipboard history app. Keep your text and image clips accessible from the system menu bar.

[![Build](https://github.com/yueseqaz/SakuraClipboard/actions/workflows/build.yml/badge.svg)](https://github.com/yueseqaz/SakuraClipboard/actions/workflows/build.yml)

## Features

- **Clipboard History** — Automatically saves text and image clips
- **Quick Access** — Opens from menu bar or `Cmd+Shift+C`
- **Search** — `Cmd+Shift+F` opens search panel with Chinese input support
- **Preview** — Hover text or images to preview; text also keeps its "预览" button
- **Interactive Previews** — Text and images appear in the history menu's built-in left column; read or scroll without opening or activating another window
- **Favorites** — Right-click to favorite items
- **Auto Cleanup** — Configurable retention (1-30 days or forever)
- **History Limit** — 100 to 5000 items
- **Ignore Apps** — Exclude specific apps from monitoring
- **Launch at Login** — Optional auto-start
- **Chinese/English UI** — Language switching

## Download

Download the latest DMG from [Releases](https://github.com/yueseqaz/SakuraClipboard/releases):

- `SakuraClipboard-arm64.dmg` — Apple Silicon (M1/M2/M3)
- `SakuraClipboard-x86_64.dmg` — Intel

## Homebrew

Install via [Homebrew](https://brew.sh):

```bash
brew tap yueseqaz/sakura-clipboard https://github.com/yueseqaz/SakuraClipboard
brew trust yueseqaz/sakura-clipboard
brew install --cask sakura-clipboard
```

To upgrade later:

```bash
brew upgrade --cask sakura-clipboard
```

## Build from Source

```bash
./build.sh
```

The default build includes both Apple Silicon and Intel. To build for Apple Silicon only:

```bash
ARCHS=arm64 ./build.sh
```

Run UI regression tests (menu bar icons at 1x/2x and history hover without clicking):

```bash
bash Tests/run.sh
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

## Architecture

### Layer Diagram

![Architecture](docs/diagrams/architecture.svg)

### Data Flow

![Data Flow](docs/diagrams/dataflow.svg)

## License

MIT

## Author

Sakura
