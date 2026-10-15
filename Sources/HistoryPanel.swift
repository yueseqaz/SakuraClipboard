import Cocoa

class HistoryPanelWindow: NSPanel {
    var onFocusSearch: (() -> Void)?
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "f" {
            onFocusSearch?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class HistoryPanel: NSObject, NSWindowDelegate {
    static let shared = HistoryPanel()
    private(set) var panel: HistoryPanelWindow?
    private(set) var controller: HistoryListPopoverController?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var appSwitchObserver: NSObjectProtocol?
    private let store: ClipboardStore
    private let makeWindow: (NSRect) -> HistoryPanelWindow

    init(store: ClipboardStore = .shared, makeWindow: @escaping (NSRect) -> HistoryPanelWindow = {
        HistoryPanelWindow(contentRect: $0, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
    }) {
        self.store = store
        self.makeWindow = makeWindow
        super.init()
    }

    func show(relativeTo button: NSStatusBarButton?, focusSearch: Bool) {
        if let panel, panel.isVisible, let controller {
            panel.makeKeyAndOrderFront(nil)
            if focusSearch { controller.focusSearch() }
            return
        }
        let screen = button?.window?.screen ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let controller = HistoryListPopoverController(store: store)
        controller.setMenuEmbeddedStyle(width: 350, height: 470)
        controller.switchMode(.all)
        let content = HistoryMenuContentView(historyView: controller.view, visibleFrame: screenFrame)
        let anchor = button.flatMap { button in
            button.window?.convertToScreen(button.convert(button.bounds, to: nil))
        } ?? NSRect(x: screenFrame.midX, y: screenFrame.maxY, width: 0, height: 0)
        let frame = Self.frame(size: content.frame.size, anchor: anchor, screen: screenFrame)
        let panel = makeWindow(frame)
        panel.contentView = content
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.delegate = self
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        content.layer?.masksToBounds = true
        self.controller = controller
        self.panel = panel
        controller.onRequestClose = { [weak self] in self?.hide() }
        panel.onFocusSearch = { [weak controller] in controller?.focusSearch() }
        panel.onCancel = { [weak controller] in controller?.cancelSearchOrClose() }
        panel.makeKeyAndOrderFront(nil)
        controller.beginBrowsing(focusSearch: focusSearch)
        installDismissalMonitors()
    }

    func hide() {
        removeDismissalMonitors()
        controller?.menuTrackingDidEnd()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        controller = nil
    }

    static func frame(size: NSSize, anchor: NSRect, screen: NSRect) -> NSRect {
        let area = screen.insetBy(dx: 8, dy: 8)
        let size = NSSize(width: min(size.width, area.width), height: min(size.height, area.height))
        let x = max(area.minX, min(anchor.maxX - size.width, area.maxX - size.width))
        let y = max(area.minY, min(anchor.minY - size.height - 4, area.maxY - size.height))
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func installDismissalMonitors() {
        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.hide()
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hide()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel && (event.window?.level.rawValue ?? 0) < NSWindow.Level.popUpMenu.rawValue {
                self.hide()
            }
            return event
        }
    }

    private func removeDismissalMonitors() {
        for monitor in [outsideClickMonitor, localClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        outsideClickMonitor = nil
        localClickMonitor = nil
        if let appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(appSwitchObserver)
            self.appSwitchObserver = nil
        }
    }

    deinit {
        removeDismissalMonitors()
    }
}
