# SakuraClipboard

SakuraClipboard is a lightweight macOS clipboard history app focused on fast access, clean organization, and dependable local storage for both text and images.

## Features

- Automatic clipboard history for text and images
- Keyword search for text content
- Filters by type, time range, and favorite state/folder
- Favorite any item and organize favorites into folders inline
- Image preview and expand/collapse support for long text entries
- SQLite-based persistence for larger history and fast lookup
- Adjustable history limit with storage usage visibility
- Open storage location in Finder for quick inspection
- Safe clear actions with confirmation dialogs
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
- Click an item to copy it back to the clipboard.
- Use the star action to add an item to favorites, then assign or change its folder directly in the list.
- Use the favorites filter to view all items, only unfavorited items, or a specific favorite folder.

## Project Structure

- `Sources/ClipboardItem.swift` - item model
- `Sources/ClipboardStore.swift` - SQLite persistence, favorite folders, and querying
- `Sources/ClipboardMonitor.swift` - adaptive clipboard polling
- `Sources/UIComponents.swift` - reusable UI components
- `Sources/PopoverController.swift` - main popover UI, filters, and inline favorite interactions
- `Sources/AppDelegate.swift` - app lifecycle and status bar behavior
- `Sources/main.swift` - app entry point

## Author

Sakura
