import Cocoa

final class KeyboardShortcut {
    static let shared = KeyboardShortcut()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var actions: [String: () -> Void] = [:]

    private init() {}

    func register(key: String, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        let identifier = "\(key)-\(modifiers.rawValue)"
        actions[identifier] = action

        // Re-register monitors
        unregisterMonitors()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }
    }

    private func handleEvent(_ event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers ?? ""
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        let identifier = "\(key)-\(modifiers.rawValue)"
        if let action = actions[identifier] {
            action()
            return true
        }
        return false
    }

    private func unregisterMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    func unregisterAll() {
        unregisterMonitors()
        actions.removeAll()
    }

    deinit {
        unregisterAll()
    }
}
