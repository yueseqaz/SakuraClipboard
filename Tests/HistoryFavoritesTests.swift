import Cocoa
import SQLite3

@main
struct HistoryFavoritesTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "com.sakura.clipboard.tests.favorites.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 127, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let imageData = bitmap.representation(using: .png, properties: [:])!
        try testCategoriesAndActions(directory: directory, defaults: defaults, imageData: imageData)
        testRowContainment(directory: directory, defaults: defaults, imageData: imageData)
        try testProtectedFavorites(directory: directory, defaults: defaults, imageData: imageData)
        testClearConfirmation()
        print("History favorites tests passed (four tabs, scoped search, star actions, recopy persistence, safe clearing and automatic retention)")
    }

    private static func testCategoriesAndActions(directory: URL, defaults: UserDefaults, imageData: Data) throws {
        let store = ClipboardStore(storeURL: directory.appendingPathComponent("tabs.sqlite"), defaults: defaults)
        store.addText("favorite search marker")
        let favoriteID = store.items[0].id
        store.updateFavorite(id: favoriteID, isFavorite: true)
        store.addText("ordinary search marker")
        store.addImageData(imageData)
        drainNotifications()

        let controller = HistoryListPopoverController(store: store)
        controller.setMenuEmbeddedStyle(width: 350, height: 470)
        let views = descendants(of: controller.view)
        let tabs = views.compactMap { $0 as? NSSegmentedControl }.first!
        let table = views.compactMap { $0 as? HoverHistoryTableView }.first!
        controller.view.layoutSubtreeIfNeeded()
        precondition(tabs.frame.width > 300 && tabs.frame.height == 25
                     && controller.view.bounds.contains(tabs.convert(tabs.bounds, to: controller.view)),
                     "All four tabs must fit inside the existing history column")
        precondition(tabs.segmentCount == 4, "History must have all, text, image and favorites tabs")
        for mode in HistoryListPopoverController.Mode.allCases {
            precondition(tabs.label(forSegment: mode.rawValue) == mode.title, "Tab labels must match their query modes")
        }
        controller.switchMode(.all)
        precondition(controller.items.count == 3 && tabs.selectedSegment == 0, "All must include text and images")
        controller.switchMode(.text)
        precondition(controller.items.count == 2 && controller.items.allSatisfy { $0.kind == .text }, "Text must exclude images")
        controller.switchMode(.image)
        precondition(controller.items.count == 1 && controller.items[0].kind == .image, "Images must exclude text")
        controller.updateSearch("search marker")
        precondition(controller.items.isEmpty, "Search must stay scoped to the current tab")
        controller.switchMode(.favorites)
        precondition(controller.keyword == "search marker" && controller.items.count == 1 && controller.items[0].id == favoriteID,
                     "Switching tabs must preserve and apply the active search")
        tabs.selectedSegment = HistoryListPopoverController.Mode.text.rawValue
        _ = tabs.sendAction(tabs.action, to: tabs.target)
        precondition(controller.mode == .text && controller.items.count == 2, "Actual tab actions must change the store query")

        controller.switchMode(.favorites)
        let cell = controller.tableView(table, viewFor: table.tableColumns[0], row: 0) as! HistoryRecordCell
        let button = cell.viewWithTag(103) as! NSButton
        precondition(button.toolTip == I18N.t("取消收藏", "Unfavorite"), "A saved record must expose the remove-favorite action")
        var closes = 0
        controller.onRequestClose = { closes += 1 }
        button.performClick(nil)
        drainNotifications()
        precondition(controller.items.isEmpty && closes == 0, "Unfavoriting from the favorites tab must update in place, not copy or close")
        controller.switchMode(.text)
        let ordinaryCell = controller.tableView(table, viewFor: table.tableColumns[0], row: 0) as! HistoryRecordCell
        let saveButton = ordinaryCell.viewWithTag(103) as! NSButton
        precondition(saveButton.toolTip == I18N.t("收藏", "Favorite"), "Ordinary records must offer a save action")
        saveButton.performClick(nil)
        drainNotifications()
        controller.switchMode(.favorites)
        precondition(controller.items.count == 1 && controller.items[0].isFavorite, "Star actions must persist favorites and update the tab")
        controller.updateSearch("")
        controller.switchMode(.image)
        let imageCell = controller.tableView(table, viewFor: table.tableColumns[0], row: 0) as! HistoryRecordCell
        (imageCell.viewWithTag(103) as! NSButton).performClick(nil)
        drainNotifications()
        controller.switchMode(.favorites)
        precondition(controller.items.count == 2 && controller.items.contains { $0.kind == .image }, "Favorites must support images as well as text")

        var staleActions = 0
        imageCell.onToggleFavorite = { staleActions += 1 }
        imageCell.configure(item: ClipboardItem(text: "Reused"), sourceImage: NSImage(size: NSSize(width: 16, height: 16)),
                            thumbnailImage: nil, title: "Reused", isHovering: false)
        (imageCell.viewWithTag(103) as! NSButton).performClick(nil)
        precondition(staleActions == 0, "Cell reuse must clear the previous record's favorite action")
        controller.menuTrackingDidEnd()
    }

    private static func testProtectedFavorites(directory: URL, defaults: UserDefaults, imageData: Data) throws {
        let url = directory.appendingPathComponent("protected.sqlite")
        var store: ClipboardStore? = ClipboardStore(storeURL: url, defaults: defaults)
        let source = ClipboardSource(bundleIdentifier: "com.example.notes", name: "Notes")!
        let newSource = ClipboardSource(bundleIdentifier: "com.example.browser", name: "Browser")!
        store!.addText("Keep this full text", sourceApp: source)
        let textID = store!.items[0].id
        store!.updateFavorite(id: textID, isFavorite: true, folderName: "Writing")
        store!.addImageData(imageData, sourceApp: source)
        let imageID = store!.items.first { $0.kind == .image }!.id
        store!.updateFavorite(id: imageID, isFavorite: true, folderName: "Images")
        store!.addText("Keep this full text", sourceApp: newSource)
        store!.addImageData(imageData, sourceApp: newSource)
        precondition(store!.items.count == 2 && store!.items.allSatisfy { $0.isFavorite && $0.sourceApp == newSource },
                     "Recopying text and images must update their source without losing saved state or duplicating records")
        precondition(store!.items.contains { $0.id == textID && $0.favoriteFolder == "Writing" }
                     && store!.items.contains { $0.id == imageID && $0.favoriteFolder == "Images" },
                     "Recopying must preserve stable IDs and favorite folders")

        store!.setMaxItems(10)
        for index in 0..<15 { store!.addText("Ordinary history \(index)") }
        precondition(store!.items.filter { !$0.isFavorite }.count == 10 && store!.items.filter { $0.isFavorite }.count == 2,
                     "Capacity eviction must only trim ordinary history, never favorites")
        try ageRecords(at: url)
        store!.setRetentionDays(1)
        precondition(store!.items.count == 2 && store!.items.allSatisfy { $0.isFavorite },
                     "Automatic age cleanup must preserve text and image favorites")
        store!.addText("Ordinary history to clear")
        store!.clear()
        precondition(store!.items.count == 2 && store!.fullText(for: textID) == "Keep this full text" && store!.image(for: imageID) != nil,
                     "Default manual cleanup must preserve complete favorite text and image data")
        store!.clear(includingFavorites: false)
        precondition(store!.items.count == 2, "Repeated safe clearing must leave favorites unchanged")
        store = nil
        store = ClipboardStore(storeURL: url, defaults: defaults)
        precondition(store!.items.count == 2 && store!.items.allSatisfy { $0.isFavorite && $0.sourceApp == newSource },
                     "Favorites and source metadata must survive cleanup and app restart")
        store!.clear(includingFavorites: true)
        precondition(store!.items.isEmpty && store!.fullText(for: textID) == nil && store!.image(for: imageID) == nil,
                     "Explicit opt-in must delete both ordinary records and favorites")
        store!.addText("Fresh record after clear", sourceApp: source)
        precondition(store!.items.count == 1 && store!.items[0].sourceApp == source,
                     "Clearing the entire database must leave a usable, migrated store")
        store!.clear()
        precondition(store!.items.isEmpty, "Default cleanup with no favorites must still clear history")
        store = nil
        defaults.removeObject(forKey: "clipboard.maxItems")
        defaults.removeObject(forKey: "clipboard.retentionDays")
    }

    private static func testClearConfirmation() {
        let alert = HistoryClearConfirmation.makeAlert()
        let checkbox = alert.accessoryView as! NSButton
        precondition(!HistoryClearConfirmation.includesFavorites(in: alert), "Every new cleanup confirmation must protect favorites by default")
        checkbox.state = .on
        precondition(HistoryClearConfirmation.includesFavorites(in: alert), "The explicit checkbox must include favorites")
        precondition(!HistoryClearConfirmation.includesFavorites(in: HistoryClearConfirmation.makeAlert()),
                     "A previous destructive choice must not carry over to the next cleanup")
    }

    private static func testRowContainment(directory: URL, defaults: UserDefaults, imageData: Data) {
        let store = ClipboardStore(storeURL: directory.appendingPathComponent("row-layout.sqlite"), defaults: defaults)
        let title = String(repeating: "很长的历史记录 https://example.com/a/long/path/ ", count: 10)
        store.addText(title)
        store.updateFavorite(id: store.items[0].id, isFavorite: true)
        store.addImageData(imageData)
        for index in 0..<20 { store.addText("\(title) \(index)") }
        drainNotifications()

        for screenWidth: CGFloat in [1440, 640, 560] {
            let controller = HistoryListPopoverController(store: store)
            controller.setMenuEmbeddedStyle(width: 350, height: 470)
            let content = HistoryMenuContentView(historyView: controller.view,
                                                 visibleFrame: NSRect(x: 0, y: 0, width: screenWidth, height: 900))
            let window = NSWindow(contentRect: content.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = content
            let table = descendants(of: controller.view).compactMap { $0 as? HoverHistoryTableView }.first!
            let scroll = table.enclosingScrollView!
            for scrollerStyle: NSScroller.Style in [.legacy, .overlay] {
                scroll.scrollerStyle = scrollerStyle
                for mode in [HistoryListPopoverController.Mode.all, .text, .image, .favorites] {
                    controller.switchMode(mode)
                    content.layoutSubtreeIfNeeded()
                    drainNotifications()
                    for row in 0..<controller.items.count {
                        let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as! HistoryRecordCell
                        cell.layoutSubtreeIfNeeded()
                        let button = cell.viewWithTag(103) as! NSButton
                        let time = cell.viewWithTag(102) as! NSTextField
                        let label = cell.viewWithTag(101) as! NSTextField
                        let clip = scroll.contentView
                        for control in [button as NSView, time] {
                            let frame = control.convert(control.bounds, to: clip)
                            precondition(frame.minX >= clip.bounds.minX - 0.5 && frame.maxX <= clip.bounds.maxX + 0.5,
                                         "Time and favorite actions must remain visible inside the actual viewport, including narrow panels and always-visible scrollbars")
                        }
                        precondition(label.frame.maxX <= time.frame.minX + 0.5,
                                     "Long text must truncate before the fixed time and favorite controls")
                        precondition(!cell.hasAmbiguousLayout, "History row constraints must remain unambiguous")
                    }
                    precondition(table.frame.width <= scroll.contentView.bounds.width + 0.5,
                                 "The table must never be wider than its visible history column")
                }
            }
            controller.menuTrackingDidEnd()
            window.contentView = nil
        }
        print("History row layout tests passed (long text, images, favorites, narrow panels and both scrollbar styles)")
    }

    private static func ageRecords(at url: URL) throws {
        var db: OpaquePointer?
        precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let date = Date().addingTimeInterval(-40 * 86_400).timeIntervalSince1970
        precondition(sqlite3_exec(db, "UPDATE clipboard_items SET created_at = \(date);", nil, nil, nil) == SQLITE_OK)
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private static func drainNotifications() {
        let deadline = Date(timeIntervalSinceNow: 0.05)
        while Date() < deadline { _ = RunLoop.main.run(mode: .default, before: deadline) }
    }
}
