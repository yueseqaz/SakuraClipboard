import Cocoa

private final class SearchTestWindow: NSWindow {
    override var isVisible: Bool { true }
    override var canBecomeKey: Bool { true }
}

private final class ComposingTextView: NSTextView {
    override func hasMarkedText() -> Bool { true }
}

private final class SharedPanelTestWindow: HistoryPanelWindow {
    private var shown = false
    override var isVisible: Bool { shown }
    override func makeKeyAndOrderFront(_ sender: Any?) { shown = true }
    override func orderOut(_ sender: Any?) { shown = false }
    override func close() { shown = false }
}

@main
struct HistorySearchTests {
    static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ClipboardStore(storeURL: directory.appendingPathComponent("search.sqlite"))
        let source = ClipboardSource(bundleIdentifier: "com.apple.finder", name: "Finder")!
        for number in 0..<35 { store.addText("matching record \(number)", sourceApp: source) }
        let fullText = String(repeating: "Content before the searchable suffix. ", count: 30) + "独特关键词"
        store.addText(fullText, sourceApp: source)
        store.addText("Different entry")
        // Deliver fixture-ingestion notifications before the UI starts observing updates.
        for _ in 0..<5 { runLoop() }
        let controller = HistoryListPopoverController(store: store)
        controller.setMenuEmbeddedStyle(width: 350, height: 470)
        let content = HistoryMenuContentView(historyView: controller.view,
                                             visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let window = SearchTestWindow(contentRect: NSRect(origin: .zero, size: content.frame.size),
                                       styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = content
        controller.view.layoutSubtreeIfNeeded()
        let views = descendants(of: controller.view)
        let search = views.compactMap { $0 as? NSSearchField }.first!
        let table = views.compactMap { $0 as? HoverHistoryTableView }.first!
        let scroll = table.enclosingScrollView!
        controller.switchMode(.all)
        precondition(!controller.items.isEmpty && controller.keyword.isEmpty,
                     "The shared panel must open with history, not an empty search-only screen")

        content.showPreview(NSView())
        controller.updateSearch(" 独特关键词 \n")
        precondition(controller.keyword == "独特关键词" && controller.items.count == 1,
                     "Search must match full stored text, including Chinese beyond the list prefix")
        precondition(controller.items[0].sourceApp == source && controller.items[0].hasMoreText,
                     "Search must reuse history rows, source icons and full-text preview metadata")
        precondition(content.displayedPreview == nil, "Changing queries must clear the previous record's preview")
        precondition(scroll.contentView.bounds.origin.y == 0 && table.selectedRow == -1,
                     "New queries must reset scrolling and stale selection")
        let editor = NSTextView()
        precondition(controller.control(search, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))),
                     "Arrow keys in search must navigate the same history table")
        precondition(table.selectedRow == 0, "Down from the search field must select its first result")
        for _ in 0..<5 { runLoop() }
        let preview = content.displayedPreview as? NSScrollView
        precondition((preview?.documentView as? NSTextView)?.string == fullText,
                     "Selecting a search result must populate the existing left preview with full text")
        precondition(preview?.window === table.window, "Search results must not create a separate preview window")

        controller.updateSearch("matching")
        precondition(controller.items.count >= 15 && controller.items.count < 35,
                     "Search must retain paginated loading rather than fetch all records upfront")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, table.frame.height - scroll.contentSize.height)))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        precondition(controller.items.count >= 30 && controller.items.allSatisfy { $0.text?.contains("matching") == true },
                     "Scrolling must load the next page using the current query and offset")

        controller.updateSearch("no-record-can-match-this")
        precondition(controller.items.isEmpty && content.displayedPreview == nil,
                     "No matches must clear old results and previews")
        precondition(views.compactMap { $0 as? NSTextField }.contains { !$0.isHidden && $0.stringValue == I18N.t("没有匹配的记录", "No matching records") },
                     "No matches must show an explicit empty state")

        var closes = 0
        controller.onRequestClose = { closes += 1 }
        controller.cancelSearchOrClose()
        precondition(controller.keyword.isEmpty && !controller.items.isEmpty && closes == 0,
                     "First Escape must clear search and restore history in the same panel")
        controller.cancelSearchOrClose()
        precondition(closes == 1, "Escape with an empty query must close the panel")

        search.stringValue = "Different"
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        precondition(controller.items.count == 1 && controller.items[0].text == "Different entry",
                     "Typing must filter immediately without a submit button")
        search.stringValue = ""
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: search))
        precondition(controller.keyword.isEmpty && !controller.items.isEmpty,
                     "The native search clear button must restore history")
        let markedEditor = ComposingTextView()
        precondition(!controller.control(search, textView: markedEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))),
                     "Return during Chinese composition must confirm the candidate, not copy a record")
        precondition(!controller.control(search, textView: markedEditor, doCommandBy: #selector(NSResponder.moveDown(_:))),
                     "Arrow keys during composition must stay with the input method")

        controller.updateSearch("matching")
        store.addText("matching newly copied content", sourceApp: source)
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
        precondition(controller.keyword == "matching" && controller.items.first?.text == "matching newly copied content",
                     "Live clipboard updates must preserve the current query")
        controller.menuTrackingDidEnd()
        precondition(content.displayedPreview == nil, "Closing the shared panel must clean up preview and hover state")
        window.contentView = nil
        testPanelPlacement()
        testSharedPanelReuse(store: store)
        print("Unified history search tests passed (inline filtering, full text, pagination, keyboard preview, IME and empty states)")
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    private static func runLoop() {
        let deadline = Date(timeIntervalSinceNow: 0.02)
        _ = RunLoop.main.run(mode: .default, before: deadline)
    }

    private static func testPanelPlacement() {
        for screen in [NSRect(x: 0, y: 0, width: 1440, height: 900),
                       NSRect(x: -1440, y: -100, width: 1440, height: 900),
                       NSRect(x: 0, y: 0, width: 640, height: 480)] {
            for x in [screen.minX, screen.maxX - 20] {
                let anchor = NSRect(x: x, y: screen.maxY, width: 20, height: 22)
                let frame = HistoryPanel.frame(size: NSSize(width: 710, height: 470), anchor: anchor, screen: screen)
                precondition(screen.insetBy(dx: 8, dy: 8).contains(frame),
                             "The unified search/history panel must remain inside every display edge")
            }
        }
    }

    private static func testSharedPanelReuse(store: ClipboardStore) {
        var createdWindows = 0
        let manager = HistoryPanel(store: store) { frame in
            createdWindows += 1
            return SharedPanelTestWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered, defer: false)
        }
        manager.show(relativeTo: nil, focusSearch: false)
        let panel = manager.panel!
        let controller = manager.controller!
        controller.updateSearch("matching")
        manager.show(relativeTo: nil, focusSearch: true)
        precondition(createdWindows == 1 && manager.panel === panel && manager.controller === controller,
                     "The search shortcut must reuse the visible history window, not open another panel")
        precondition(controller.keyword == "matching", "Focusing search must preserve query, results and reading position")
        panel.onCancel?()
        precondition(controller.keyword.isEmpty && manager.panel === panel,
                     "Escape with a query must return to history without closing or replacing its window")
        panel.onCancel?()
        precondition(manager.panel == nil && manager.controller == nil,
                     "The next Escape must close the one shared window and release its controller")
        manager.show(relativeTo: nil, focusSearch: true)
        precondition(createdWindows == 2 && manager.controller?.keyword == "",
                     "Reopening after dismissal must start with a fresh history/search session")
        manager.hide()
    }
}
