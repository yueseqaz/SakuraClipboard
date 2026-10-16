import Cocoa
import SQLite3

@main
struct ClipboardSourceTests {
    static func main() throws {
        _ = NSApplication.shared
        testPasteboardSources()
        try testStorageMigration()
        testSourceIconsAndCells()
        print("Clipboard source tests passed (capture, restore, database migration, persistence and row reuse)")
    }

    private static func testPasteboardSources() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let fallback = ClipboardSource(bundleIdentifier: "com.example.browser", name: "Browser")!
        let original = ClipboardSource(bundleIdentifier: "com.example.editor", name: "Editor")!
        pasteboard.setString("Clipboard source test", forType: .string)
        precondition(ClipboardSource.capture(from: pasteboard, fallback: fallback) == fallback,
                     "Use the frontmost app when the clipboard provides no explicit source")
        pasteboard.setString(original.bundleIdentifier!, forType: NSPasteboard.PasteboardType("org.nspasteboard.source"))
        precondition(ClipboardSource.capture(from: pasteboard, fallback: fallback)?.bundleIdentifier == original.bundleIdentifier,
                     "Explicit clipboard source must win over a different frontmost app")
        ClipboardSource.writeOriginal(original, to: pasteboard)
        precondition(ClipboardSource.capture(from: pasteboard, fallback: fallback) == original,
                     "Restoring history must preserve the original app and display name")
        ClipboardSource.writeOriginal(nil, to: pasteboard)
        precondition(ClipboardSource.capture(from: pasteboard, fallback: fallback) == nil,
                     "Restoring an old item must not invent a source from the current frontmost app")
        pasteboard.clearContents()
        pasteboard.setData(Data("invalid metadata".utf8),
                           forType: NSPasteboard.PasteboardType("com.sakura.clipboard.original-source"))
        precondition(ClipboardSource.capture(from: pasteboard, fallback: fallback) == fallback,
                     "Malformed optional metadata must not prevent capturing clipboard content")
        precondition(ClipboardSource(bundleIdentifier: " ", name: "\n") == nil,
                     "Empty metadata must represent an unknown source")
        precondition(ClipboardSource(bundleIdentifier: " com.example.editor ", name: " Editor\n") == original,
                     "Trim optional source metadata before storing it")
    }

    private static func testStorageMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.sqlite")
        var db: OpaquePointer?
        precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        let schema = """
        CREATE TABLE clipboard_items (
            id TEXT PRIMARY KEY, type INTEGER NOT NULL, text TEXT, image_data BLOB,
            data_hash TEXT, created_at REAL NOT NULL, is_favorite INTEGER NOT NULL DEFAULT 0, favorite_folder TEXT
        );
        INSERT INTO clipboard_items (id, type, text, created_at, is_favorite, favorite_folder)
        VALUES ('legacy', 0, 'Legacy saved text', \(Date().timeIntervalSince1970), 1, 'Keep');
        """
        precondition(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let editor = ClipboardSource(bundleIdentifier: "com.example.editor", name: "Editor")!
        let browser = ClipboardSource(bundleIdentifier: "com.example.browser", name: "Browser")!
        let query = ClipboardStore.Query(keyword: "", filterType: .all, favoritesOnly: false, favoriteFolder: nil)
        var store: ClipboardStore? = ClipboardStore(storeURL: url)
        precondition(store!.storageLocationDescription() == url.path, "Database tests must use only their temporary store")
        let legacy = store!.items.first!
        precondition(legacy.id == "legacy" && legacy.text == "Legacy saved text" && legacy.sourceApp == nil,
                     "Migration must preserve old records without fabricating provenance")
        precondition(legacy.isFavorite && legacy.favoriteFolder == "Keep", "Migration must preserve favorites and folders")

        let text = String(repeating: "Complete source metadata test. ", count: 40) + "End."
        store!.addText(text, sourceApp: editor)
        let textItem = store!.filteredItems(query: query, limit: 10, offset: 0).first { $0.kind == .text && $0.id != "legacy" }!
        precondition(textItem.hasMoreText && textItem.sourceApp == editor,
                     "Paginated text-prefix queries must include source metadata")
        precondition(store!.fullText(for: textItem.id) == text, "Source metadata must not alter the full text")
        store!.addText(text, sourceApp: browser)
        precondition(store!.items.filter { $0.id != "legacy" }.count == 1 && store!.items.first!.sourceApp == browser,
                     "Recopying identical text from another app must update its source without duplicates")

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let imageData = bitmap.representation(using: .png, properties: [:])!
        store!.addImageData(imageData, sourceApp: editor)
        store!.addImageData(imageData, sourceApp: browser)
        let imageItems = store!.items.filter { $0.kind == .image }
        precondition(imageItems.count == 1 && imageItems[0].sourceApp == browser,
                     "Image metadata must persist through deduplication and lightweight image rows")
        store!.updateFavorite(id: imageItems[0].id, isFavorite: true, folderName: "Images")
        precondition(store!.items.first { $0.id == imageItems[0].id }?.sourceApp == browser,
                     "Changing favorites must not discard the source app")
        store = nil

        let reopened = ClipboardStore(storeURL: url)
        let fetched = reopened.filteredItems(query: query)
        precondition(fetched.count == 3 && fetched.filter { $0.id != "legacy" }.allSatisfy { $0.sourceApp == browser },
                     "Source app metadata must survive closing and reopening the database")
        precondition(reopened.filteredCount(query: query) == 3, "Source columns must not break count queries")
        precondition(reopened.items.first { $0.id == "legacy" }?.sourceApp == nil,
                     "Repeated migration must leave unknown legacy sources unknown")
        let freshURL = directory.appendingPathComponent("fresh.sqlite")
        let fresh = ClipboardStore(storeURL: freshURL)
        precondition(fresh.storageLocationDescription() == freshURL.path, "Never write test records to the user's history")
        fresh.addText("Fresh source record", sourceApp: editor)
        precondition(fresh.items.first?.sourceApp == editor, "New databases must create source columns immediately")
    }

    private static func testSourceIconsAndCells() {
        let provider = ClipboardSourceIconProvider()
        let finder = ClipboardSource(bundleIdentifier: "com.apple.finder", name: "Finder")!
        let finderIcon = provider.icon(for: finder)
        precondition(!finderIcon.isTemplate && finderIcon.size == NSSize(width: 16, height: 16),
                     "Installed apps must use their real full-color icon")
        precondition(provider.icon(for: finder) === finderIcon, "Reuse cached icons while browsing history")
        let missing = ClipboardSource(bundleIdentifier: "com.example.sakura.source-tests-missing", name: "Missing App")!
        let unknownIcon = provider.icon(for: nil)
        precondition(provider.icon(for: missing) === unknownIcon, "Unavailable apps must fall back to a generic icon")

        let cell = HistoryRecordCell(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        let text = ClipboardItem(text: "Text from Finder", sourceApp: finder)
        cell.configure(item: text, sourceImage: finderIcon, thumbnailImage: nil, title: "Text from Finder", isHovering: false)
        cell.layoutSubtreeIfNeeded()
        let icons = cell.subviews.compactMap { $0 as? NSImageView }
        precondition(cell.subviews.compactMap { $0 as? NSButton }.allSatisfy { $0.tag == 103 },
                     "Only the favorite action may be a button; the old preview button must not return")
        precondition(icons[0].image === finderIcon && icons[0].toolTip?.contains("Finder") == true,
                     "The leading icon and tooltip must identify the source app")
        precondition(icons[1].isHidden && icons[1].frame.width == 0,
                     "Text rows must reclaim the old preview-button and image-thumbnail space")
        let label = cell.viewWithTag(101) as! NSTextField
        precondition(label.frame.minX <= 30, "Text must start directly beside its source icon")

        let image = ClipboardItem(id: "image", imageDate: Date(), isFavorite: false, sourceApp: missing)
        cell.configure(item: image, sourceImage: unknownIcon, thumbnailImage: finderIcon, title: "[Image]", isHovering: true)
        cell.layoutSubtreeIfNeeded()
        precondition(!icons[1].isHidden && icons[1].frame.width == 16 && icons[0].toolTip?.contains("Missing App") == true,
                     "Reused image rows must show their thumbnail alongside the source icon")
        cell.configure(item: ClipboardItem(text: "Legacy text"), sourceImage: unknownIcon,
                       thumbnailImage: nil, title: "Legacy text", isHovering: false)
        precondition(icons[0].image === unknownIcon && icons[1].isHidden && icons[1].image == nil,
                     "Reused legacy text rows must clear stale icons and thumbnails")
        precondition(icons[0].toolTip?.contains("Missing App") == false && label.stringValue == "Legacy text",
                     "Reusing a row must not leak the previous app name or record title")
    }
}
