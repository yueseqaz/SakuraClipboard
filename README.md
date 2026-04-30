# SakuraClipboard

SakuraClipboard is a lightweight macOS menu bar clipboard history app. It keeps recent text and image clips locally, opens from the system menu bar, and avoids a separate main window.

## Features

- Automatic clipboard history for text and images
- Native menu bar interface with no main panel
- Current clipboard summary in the menu
- Fixed-height History menu with scrolling and incremental loading
- Click any history item to copy it back to the clipboard
- Image preview on hover in the History menu
- Automatic cleanup by age
- Adjustable history limit: 100, 200, 350, 500, 1000, 2000, or 5000 items
- SQLite-based local storage
- Chinese/English interface switching
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

## Usage Notes

- Access the app from the macOS menu bar.
- Open History to browse recent clipboard items.
- Scroll inside History to load more items.
- Hover over an image item to preview it.
- Choose Auto Clean to set retention time.
- Choose History Limit to set the maximum number of saved items.

## Project Structure

- `Sources/ClipboardItem.swift` - item model
- `Sources/ClipboardStore.swift` - SQLite persistence and history querying
- `Sources/ClipboardMonitor.swift` - clipboard monitoring
- `Sources/HistoryListPopoverController.swift` - embedded menu history list
- `Sources/AppDelegate.swift` - app lifecycle and status bar behavior
- `Sources/main.swift` - app entry point

## Author

Sakura
