# SakuraClipboard

SakuraClipboard is a lightweight macOS clipboard history app for text and images.

## Features

- Clipboard history for text and images
- Search and filtering by keyword, type, and time
- Favorites/pinning for important items
- Safe clear actions with confirmation dialogs
- SQLite-based persistence for fast lookup and larger history
- Hover preview for images
- Expand/collapse for long text entries
- Chinese/English language switch
- Launch at login support

## Build

```bash
./build.sh
```

Build outputs:

- `SakuraClipboard.app`
- `SakuraClipboard.dmg`

The DMG includes:

- `SakuraClipboard.app`
- `Applications` shortcut link

## Project Structure

- `Sources/ClipboardItem.swift` - item model
- `Sources/ClipboardStore.swift` - SQLite persistence and querying
- `Sources/ClipboardMonitor.swift` - adaptive clipboard polling
- `Sources/UIComponents.swift` - reusable UI components
- `Sources/PopoverController.swift` - main popover UI and interactions
- `Sources/AppDelegate.swift` - app lifecycle and status bar behavior
- `Sources/main.swift` - app entry point

## Author

Sakura
