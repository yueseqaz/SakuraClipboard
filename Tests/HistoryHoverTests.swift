import Cocoa

private final class InactiveTestWindow: NSWindow {
    var testVisible = true
    private(set) var keyRequests = 0
    override var isVisible: Bool { testVisible }
    override var isKeyWindow: Bool { false }
    override func makeKey() { keyRequests += 1 }
}

private final class Rows: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 6 }

    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        "Row \(row)"
    }
}

private final class RecordingScrollView: NSScrollView {
    private(set) var scrollEvents = 0
    override func scrollWheel(with event: NSEvent) { scrollEvents += 1 }
}

@main
struct HistoryHoverTests {
    static func main() {
        _ = NSApplication.shared
        let window = InactiveTestWindow(
            contentRect: NSRect(x: 100, y: 100, width: 240, height: 120),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        let table = HoverHistoryTableView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let rows = Rows()
        table.dataSource = rows
        table.headerView = nil
        table.rowHeight = 20
        table.intercellSpacing = .zero
        table.addTableColumn(NSTableColumn(identifier: .init("test")))
        window.contentView = table
        table.reloadData()
        table.layoutSubtreeIfNeeded()

        let existingArea = NSTrackingArea(
            rect: table.bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: table
        )
        table.addTrackingArea(existingArea)
        table.updateTrackingAreas()
        precondition(table.trackingAreas.contains { $0 === existingArea }, "Keep AppKit's tracking areas")
        precondition(window.acceptsMouseMovedEvents, "Enable movement events before the first click")
        precondition(table.acceptsFirstMouse(for: nil), "Do not consume the first click for activation")

        func point(for row: Int) -> NSPoint {
            let rect = table.rect(ofRow: row)
            return window.convertPoint(toScreen: table.convert(NSPoint(x: 50, y: rect.midY), to: nil))
        }

        var cursor = point(for: 0)
        var changes: [Int?] = []
        table.onHoverRow = { changes.append($0) }
        table.startHoverTracking(mouseLocation: { cursor })
        precondition(changes.count == 1 && changes[0] == 0, "Recognize the initial row without a click")

        cursor = point(for: 3)
        runLoop(.eventTracking)
        precondition(changes.count == 2 && changes[1] == 3, "Hover must work inside NSMenu's tracking loop")
        runLoop(.eventTracking)
        precondition(changes.count == 2, "Do not restart the same image preview every timer tick")

        cursor = window.convertPoint(toScreen: NSPoint(x: -20, y: -20))
        runLoop(.eventTracking)
        precondition(changes.count == 3 && changes[2] == nil, "Leaving the list must dismiss the preview")

        cursor = point(for: 1)
        runLoop(.default)
        precondition(changes.last! == 1, "Also track outside the nested menu loop")
        window.testVisible = false
        runLoop(.eventTracking)
        precondition(changes.last! == nil, "A hidden menu must not keep its preview")

        window.testVisible = true
        table.stopHoverTracking()
        let countAfterClose = changes.count
        cursor = point(for: 2)
        runLoop(.eventTracking)
        precondition(changes.count == countAfterClose, "Stop tracking when the menu closes")

        table.startHoverTracking(mouseLocation: { cursor })
        precondition(changes.last! == 2, "Reopening must not require a click either")
        table.resetHover()
        runLoop(.eventTracking)
        precondition(changes.last! == 2, "Reloading must refresh a stationary pointer's preview")

        table.resolveHoverRow = { _, _ in 2 }
        cursor = point(for: 4)
        runLoop(.eventTracking)
        precondition(changes.last! == 2, "Preview interaction must override rows behind the panel")
        table.resolveHoverRow = { _, _ in nil }
        runLoop(.eventTracking)
        precondition(changes.last! == nil, "A resolver must be able to dismiss a preview over a row")
        table.resolveHoverRow = nil
        window.contentView = nil
        let countAfterDetach = changes.count
        cursor = point(for: 4)
        runLoop(.eventTracking)
        precondition(changes.count == countAfterDetach, "Detaching the list must stop its timer")

        let controller = HistoryListPopoverController()
        let submenu = NSMenu()
        let contentItem = NSMenuItem()
        contentItem.view = HistoryMenuContentView(historyView: controller.view,
                                                  visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        submenu.addItem(contentItem)
        submenu.delegate = controller
        precondition(controller.view.enclosingMenuItem === contentItem,
                     "The wrapped history must still resolve its submenu for hover tracking and dismissal")
        controller.menuNeedsUpdate(submenu)
        precondition(submenu.items.count == 1 && submenu.items[0] === contentItem,
                     "Submenu updates must not replace the embedded history with a context menu")
        testTextPreview()
        testPreviewInteraction()
        testCombinedMenuLayout()
        testEmbeddedPreview()
        testEmbeddedHoverTracking()
        if let content = contentItem.view as? HistoryMenuContentView {
            content.showPreview(NSView())
            controller.menuTrackingDidEnd()
            precondition(content.displayedPreview == nil, "Closing history must clear its embedded preview")
        }
        withExtendedLifetime(rows) {}
        print("History hover tests passed (inactive window, no mouse or click events)")
    }

    private static func testPreviewInteraction() {
        let interaction = HistoryPreviewInteraction()
        let source = NSRect(x: 400, y: 300, width: 320, height: 28)
        let preview = NSRect(x: 728, y: 150, width: 360, height: 280)
        interaction.show(row: 0, sourceFrame: source, previewFrame: preview)

        _ = interaction.resolve(row: 0, pointer: NSPoint(x: 600, y: 314), now: 0)
        precondition(interaction.resolve(row: 1, pointer: NSPoint(x: 700, y: 290), now: 0.01) == 0,
                     "Crossing another row must not immediately replace the preview")
        precondition(interaction.resolve(row: nil, pointer: NSPoint(x: 724, y: 200), now: 0.1) == 0,
                     "Moving between columns must keep the current preview")
        precondition(interaction.resolve(row: nil, pointer: NSPoint(x: 800, y: 180), now: 10) == 0,
                     "Moving below the history list while inside the preview must keep it open")
        precondition(interaction.resolve(row: 5, pointer: NSPoint(x: 800, y: 180), now: 20) == 0,
                     "Rows underneath the preview must never change its content")
        precondition(interaction.resolve(row: 1, pointer: NSPoint(x: 500, y: 280), now: 21) == 1,
                     "Returning from the preview to history must switch without a fixed dwell")
        precondition(interaction.resolve(row: 2, pointer: NSPoint(x: 500, y: 250), now: 21.001) == 2,
                     "Rapid vertical browsing must not wait 180 milliseconds between rows")

        interaction.show(row: 0, sourceFrame: source, previewFrame: preview)
        let outside = NSPoint(x: 1200, y: 500)
        precondition(interaction.resolve(row: nil, pointer: outside, now: 30) == 0,
                     "Leaving the list must not clear the embedded preview")
        precondition(interaction.resolve(row: nil, pointer: outside, now: 30.2) == 0,
                     "Keep the embedded content readable until another record is hovered")
        precondition(interaction.resolve(row: nil, pointer: outside, now: 100) == 0,
                     "The embedded preview must not disappear on a separate window departure timer")
        interaction.reset()
        precondition(interaction.resolve(row: 3, pointer: outside, now: 31) == 3,
                     "Closing the preview must clear its sticky row")

        let leftPreview = NSRect(x: 32, y: 150, width: 360, height: 280)
        interaction.show(row: 2, sourceFrame: source, previewFrame: leftPreview)
        precondition(interaction.resolve(row: nil, pointer: NSPoint(x: 396, y: 200), now: 40) == 2,
                     "The left preview must keep the current record without a separate window")
        print("Preview interaction tests passed (persistent embedded content, crossing grace and immediate switching)")
    }

    private static func testCombinedMenuLayout() {
        let screens = [NSRect(x: 0, y: 0, width: 2560, height: 1440),
                       NSRect(x: -1440, y: -100, width: 1440, height: 900),
                       NSRect(x: 0, y: 0, width: 640, height: 480)]
        for screen in screens {
            let historyView = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 404))
            let content = HistoryMenuContentView(historyView: historyView, visibleFrame: screen)
            precondition(content.frame.width <= screen.width - 32,
                         "The combined menu must fit the display, leaving room for native menu padding")
            precondition(historyView.frame.minX == content.previewWidth,
                         "Reserve space left of history before native menu placement, not after hovering")
            precondition(historyView.frame.maxX == content.bounds.maxX,
                         "History must occupy the right column of the combined menu")
            let preview = NSImageView()
            content.showPreview(preview)
            let embeddedFrame = content.convert(preview.bounds, from: preview)
            precondition(embeddedFrame.maxX < historyView.frame.minX,
                         "Actual preview content must live inside the left column")
            precondition(content.bounds.contains(embeddedFrame), "Preview must stay within the combined menu")
            precondition(preview.frame.size == content.previewContentSize,
                         "Preview must fill the available column height rather than float beside a row")
            for x in [screen.minX + 8, screen.maxX - 8 - content.frame.width] {
                for y in [screen.minY + 8, screen.maxY - 8 - content.frame.height] {
                    let group = content.bounds.offsetBy(dx: x, dy: y)
                    let frame = embeddedFrame.offsetBy(dx: x, dy: y)
                    precondition(screen.contains(frame) && group.contains(frame),
                                 "The embedded preview must stay inside the menu at every display edge")
                }
            }
            content.clearPreview()
        }
        print("Combined menu layout tests passed (left preview, display edges, narrow and negative-origin displays)")
    }

    private static func testEmbeddedPreview() {
        let history = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 404))
        let content = HistoryMenuContentView(historyView: history,
                                             visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let window = InactiveTestWindow(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: content.frame.size),
                                        styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = content
        let windowsBeforePreview = NSApp.windows.count
        let scroll = RecordingScrollView(frame: .zero)
        content.showPreview(scroll)
        precondition(scroll.window === history.window && scroll.window === window,
                     "Preview and history must be actual subviews of the same native menu window")
        precondition(content.displayedPreview === scroll, "The preview must replace the placeholder")
        precondition(content.acceptsFirstMouse(for: nil), "The embedded panel must not require an activation click")
        guard let frame = content.previewScreenFrame,
              let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [],
                                             timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                             subtype: 0, data1: 0, data2: 0) else {
            fatalError("Unable to create the embedded scroll forwarding fixture")
        }
        let previewPoint = NSPoint(x: frame.midX, y: frame.midY)
        precondition(content.forwardPreviewScroll(event, at: previewPoint) && scroll.scrollEvents == 1,
                     "Forward wheel events into preview without clicking or focusing a separate window")
        let historyPoint = window.convertToScreen(content.convert(history.frame, to: nil)).origin
        precondition(!content.forwardPreviewScroll(event, at: NSPoint(x: historyPoint.x + 30, y: historyPoint.y + 30)),
                     "Scrolling history must not scroll the preview")
        precondition(window.keyRequests == 0, "Embedded preview scrolling must not change window focus")
        content.showPreview(scroll)
        precondition(scroll.window === window, "Showing the same cached text must preserve its attachment")
        let image = NSImageView()
        content.showPreview(image)
        precondition(scroll.superview == nil && image.window === window,
                     "Switching to an image must replace the text inside the same column")
        precondition(!content.forwardPreviewScroll(event, at: previewPoint),
                     "Switching to an image must stop forwarding events to the previous text")
        content.showPreview(scroll)
        window.testVisible = false
        precondition(!content.forwardPreviewScroll(event, at: previewPoint),
                     "Hidden menus must not consume scroll events from other apps")
        window.testVisible = true
        content.clearPreview()
        precondition(scroll.superview == nil && content.displayedPreview == nil,
                     "Closing the menu must detach its preview content")
        precondition(!content.forwardPreviewScroll(event, at: previewPoint),
                     "Clearing the preview must stop scroll interception")
        content.showPreview(image)
        window.contentView = nil
        precondition(content.displayedPreview == nil && image.window == nil,
                     "Removing the menu from its window must clean up embedded content")
        precondition(NSApp.windows.count == windowsBeforePreview, "Displaying previews must never create another window")
        print("Embedded preview tests passed (one window, text/image replacement, no-click wheel routing and cleanup)")
    }

    private static func testTextPreview() {
        let size = NSSize(width: 360, height: 280)
        let longText = String(repeating: "Full preview text \u{4e2d}\u{6587}, with preserved line breaks.\n", count: 100)
        for text in ["Short text", "First line\nSecond line", longText, String(repeating: "x", count: 5000)] {
            let scroll = HistoryListPopoverController.makeTextPreviewView(text: text, size: size)
            guard let textView = scroll.documentView as? NSTextView else {
                fatalError("Text preview must contain a text view")
            }
            precondition(textView.string == text, "Preview must not truncate text to the list's 600-character prefix")
            precondition(!textView.isEditable && textView.isSelectable, "Preview must be read-only and selectable")
            precondition(!textView.isHorizontallyResizable && !scroll.hasHorizontalScroller, "Long lines must wrap")
            precondition(textView.frame.width > 0 && textView.frame.width <= size.width, "Text needs a bounded layout width")
            if text.count > 600 {
                precondition(textView.frame.height > size.height, "Long previews must lay out all content vertically")
            }
        }
        print("Text preview tests passed (short, multiline, Unicode and long text)")
    }

    private static func testEmbeddedHoverTracking() {
        let table = HoverHistoryTableView(frame: NSRect(x: 0, y: 0, width: 350, height: 404))
        let rows = Rows()
        table.dataSource = rows
        table.headerView = nil
        table.rowHeight = 28
        table.addTableColumn(NSTableColumn(identifier: .init("embedded")))
        let content = HistoryMenuContentView(historyView: table,
                                             visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let window = InactiveTestWindow(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: content.frame.size),
                                        styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = content
        table.reloadData()
        table.layoutSubtreeIfNeeded()
        let interaction = HistoryPreviewInteraction()
        var hovered: [Int] = []
        table.resolveHoverRow = { row, point in interaction.resolve(row: row, pointer: point) }
        table.onHoverRow = { [weak table, weak content] row in
            guard let row, let table, let content, let frame = content.previewScreenFrame else { return }
            hovered.append(row)
            let source = window.convertToScreen(table.convert(table.rect(ofRow: row), to: nil))
            interaction.show(row: row, sourceFrame: source, previewFrame: frame)
            content.showPreview(NSView())
        }
        func point(for row: Int) -> NSPoint {
            window.convertPoint(toScreen: table.convert(NSPoint(x: 100, y: table.rect(ofRow: row).midY), to: nil))
        }
        var cursor = point(for: 0)
        table.startHoverTracking(mouseLocation: { cursor })
        precondition(hovered == [0], "Hovering the history must populate the embedded preview without clicking")
        let firstPreview = content.displayedPreview
        let frame = content.previewScreenFrame!
        cursor = NSPoint(x: frame.midX, y: frame.minY + 30)
        runLoop(.eventTracking)
        precondition(hovered == [0] && content.displayedPreview === firstPreview,
                     "Moving into a different height in the left column must keep the current preview")
        cursor = point(for: 3)
        runLoop(.eventTracking)
        precondition(hovered == [0, 3] && content.displayedPreview !== firstPreview,
                     "Returning to another history row must update the same embedded column")
        cursor = point(for: 4)
        runLoop(.eventTracking)
        precondition(hovered == [0, 3, 4], "Vertical browsing must remain responsive without a dwell")
        precondition(window.keyRequests == 0, "Hover previews must not activate another window")
        table.stopHoverTracking()
        content.clearPreview()
        withExtendedLifetime(rows) {}
        print("Embedded hover integration tests passed (no-click population, stable left-column reading and row switching)")
    }

    private static func runLoop(_ mode: RunLoop.Mode) {
        let deadline = Date(timeIntervalSinceNow: 0.1)
        while Date() < deadline {
            _ = RunLoop.main.run(mode: mode, before: deadline)
        }
    }
}
