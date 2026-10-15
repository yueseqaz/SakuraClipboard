import Cocoa

final class HistoryPreviewInteraction {
    private var sourceRow: Int?
    private var sourceFrame = NSRect.zero
    private var previewFrame = NSRect.zero
    private var lastPointer: NSPoint?
    private var crossingSince: TimeInterval?

    func show(row: Int, sourceFrame: NSRect, previewFrame: NSRect) {
        self.sourceRow = row
        self.sourceFrame = sourceFrame
        self.previewFrame = previewFrame
        lastPointer = nil
        clearTransition()
    }

    func reset() {
        sourceRow = nil
        lastPointer = nil
        clearTransition()
    }

    func resolve(row: Int?, pointer: NSPoint, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int? {
        defer { lastPointer = pointer }
        guard let sourceRow else { return row }

        // Empty space and the embedded preview keep the current record selected.
        if row == nil || previewFrame.contains(pointer) || row == sourceRow {
            clearTransition()
            return sourceRow
        }

        if let row {
            if let previous = lastPointer {
                let dx = pointer.x - previous.x
                let dy = pointer.y - previous.y
                let direction: CGFloat = previewFrame.midX < sourceFrame.midX ? -1 : 1
                let towardPreview = dx * direction > 0.5 && abs(dx) > abs(dy) * 0.6
                if towardPreview {
                    if crossingSince == nil { crossingSince = now }
                } else if abs(dx) + abs(dy) > 0.5 {
                    crossingSince = nil
                }
            }
            // Only a lateral move toward the preview gets grace; vertical browsing is immediate.
            if let crossingSince, now - crossingSince < 0.12 { return sourceRow }
            return row
        }

        return sourceRow
    }

    private func clearTransition() {
        crossingSince = nil
    }
}
