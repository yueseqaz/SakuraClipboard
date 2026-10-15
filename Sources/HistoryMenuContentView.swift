import Cocoa

final class HistoryMenuContentView: NSView {
    let previewWidth: CGFloat
    private let previewHost = NSView()
    private let hint = NSTextField(labelWithString: I18N.t("移到记录上预览", "Hover over a record to preview"))
    private var scrollMonitor: Any?
    private(set) var displayedPreview: NSView?

    var previewContentSize: NSSize { previewHost.bounds.size }

    var previewScreenFrame: NSRect? {
        guard let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return nil }
        return window.convertToScreen(convert(NSRect(x: 0, y: 0, width: previewWidth, height: bounds.height), to: nil))
    }

    init(historyView: NSView, visibleFrame: NSRect) {
        // AppKit positions both columns as one menu, including at the display edges.
        let availableWidth = max(0, visibleFrame.width - 32)
        let historyWidth = min(historyView.frame.width, availableWidth / 2)
        previewWidth = min(360, availableWidth - historyWidth)
        let height = min(historyView.frame.height, max(0, visibleFrame.height - 32))
        super.init(frame: NSRect(x: 0, y: 0, width: previewWidth + historyWidth, height: height))

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: previewWidth, height: height))
        background.material = .menu
        background.blendingMode = .withinWindow
        background.state = .active
        addSubview(background)

        let header = NSTextField(labelWithString: I18N.t("预览", "Preview"))
        header.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.frame = NSRect(x: 10, y: height - 24, width: max(0, previewWidth - 20), height: 16)
        background.addSubview(header)

        previewHost.frame = NSRect(x: 8, y: 8, width: max(0, previewWidth - 16), height: max(0, height - 38))
        previewHost.wantsLayer = true
        previewHost.layer?.cornerRadius = 6
        previewHost.layer?.masksToBounds = true
        background.addSubview(previewHost)

        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false
        previewHost.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: previewHost.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: previewHost.centerYAnchor),
            hint.widthAnchor.constraint(lessThanOrEqualTo: previewHost.widthAnchor, constant: -16)
        ])

        let divider = NSBox(frame: NSRect(x: previewWidth - 1, y: 0, width: 1, height: height))
        divider.boxType = .separator
        addSubview(divider)

        historyView.frame = NSRect(x: previewWidth, y: 0, width: historyWidth, height: height)
        addSubview(historyView)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func showPreview(_ content: NSView) {
        if displayedPreview !== content {
            displayedPreview?.removeFromSuperview()
            content.frame = previewHost.bounds
            content.autoresizingMask = [.width, .height]
            previewHost.addSubview(content)
            displayedPreview = content
        }
        hint.isHidden = true
        guard scrollMonitor == nil else { return }
        // NSMenu's tracking loop can consume wheel events before its custom views see them.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.forwardPreviewScroll(event, at: NSEvent.mouseLocation) == true ? nil : event
        }
    }

    @discardableResult
    func forwardPreviewScroll(_ event: NSEvent, at screenPoint: NSPoint) -> Bool {
        guard let frame = previewScreenFrame, frame.contains(screenPoint),
              let scrollView = displayedPreview as? NSScrollView else { return false }
        scrollView.scrollWheel(with: event)
        return true
    }

    func clearPreview() {
        displayedPreview?.removeFromSuperview()
        displayedPreview = nil
        hint.isHidden = false
        removeScrollMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clearPreview() }
    }

    private func removeScrollMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeScrollMonitor()
    }
}
