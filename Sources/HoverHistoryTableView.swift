import Cocoa

final class HoverHistoryTableView: NSTableView {
    var onHoverRow: ((Int?) -> Void)?
    var resolveHoverRow: ((Int?, NSPoint) -> Int?)?

    private var hoverTrackingArea: NSTrackingArea?
    private var hoverTimer: Timer?
    private var hoveredRow: Int?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseMoved,
                      .mouseEnteredAndExited, .enabledDuringMouseDrag],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        return super.menu(for: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if window == nil {
            stopHoverTracking()
        }
    }

    func startHoverTracking(mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        stopHoverTracking()
        window?.acceptsMouseMovedEvents = true

        // Native menus may consume mouseMoved before forwarding it to embedded views.
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.updateHoveredRow(at: mouseLocation())
        }
        hoverTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
        RunLoop.main.add(timer, forMode: .default)
        updateHoveredRow(at: mouseLocation())
    }

    func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
        resetHover()
    }

    func resetHover() {
        setHoveredRow(nil)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoveredRow(at: NSEvent.mouseLocation)
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredRow(at: NSEvent.mouseLocation)
        super.mouseMoved(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateHoveredRow(at: NSEvent.mouseLocation)
        super.mouseDragged(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateHoveredRow(at: NSEvent.mouseLocation)
        super.mouseExited(with: event)
    }

    func rowUnderPointer(at screenPoint: NSPoint) -> Int? {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else {
            return nil
        }
        let point = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let row = visibleRect.contains(point) ? self.row(at: point) : -1
        return row >= 0 ? row : nil
    }

    private func updateHoveredRow(at screenPoint: NSPoint) {
        let rawRow = rowUnderPointer(at: screenPoint)
        if let resolveHoverRow {
            setHoveredRow(resolveHoverRow(rawRow, screenPoint))
        } else {
            setHoveredRow(rawRow)
        }
    }

    private func setHoveredRow(_ row: Int?) {
        guard row != hoveredRow else { return }
        hoveredRow = row
        onHoverRow?(row)
    }

    deinit {
        hoverTimer?.invalidate()
    }
}
