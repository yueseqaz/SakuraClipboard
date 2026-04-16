import Cocoa

// MARK: - FlippedView (scroll content starts from top)
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let monitor = ClipboardMonitor()
    let controller = PopoverController()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let btn = statusItem.button {
            btn.title = ""
            if let appIcon = (NSApp.applicationIconImage?.copy() as? NSImage) ?? NSApp.applicationIconImage {
                appIcon.size = NSSize(width: 18, height: 18)
                appIcon.isTemplate = false
                btn.image = appIcon
            }
            btn.imagePosition = .imageOnly
            btn.action = #selector(toggle)
            btn.target = self
        }

        popover.contentViewController = controller
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 338, height: 540)
        popover.appearance = NSAppearance(named: .aqua)

        installOutsideClickClose()
        monitor.start()
    }

    deinit {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
    }

    private func installOutsideClickClose() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            guard self.popover.isShown else { return event }
            if self.isEventInsidePopoverOrStatus(event) {
                return event
            }
            self.popover.performClose(nil)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self else { return }
            guard self.popover.isShown else { return }
            if self.isCurrentMouseInsidePopoverOrStatusButton() {
                return
            }
            DispatchQueue.main.async {
                self.popover.performClose(nil)
            }
        }
    }

    private func isEventInsidePopoverOrStatus(_ event: NSEvent) -> Bool {
        if event.window == popover.contentViewController?.view.window {
            return true
        }
        if event.window == statusItem.button?.window {
            return true
        }
        return false
    }

    private func isCurrentMouseInsidePopoverOrStatusButton() -> Bool {
        let mousePoint = NSEvent.mouseLocation
        if let popoverWindow = popover.contentViewController?.view.window,
           popoverWindow.frame.contains(mousePoint) {
            return true
        }
        if let btn = statusItem.button, let win = btn.window {
            let inWindow = btn.convert(btn.bounds, to: nil)
            let onScreen = win.convertToScreen(inWindow)
            if onScreen.contains(mousePoint) {
                return true
            }
        }
        return false
    }

    @objc func toggle() {
        guard let btn = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        }
    }
}
