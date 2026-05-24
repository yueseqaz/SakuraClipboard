import Cocoa
import Carbon.HIToolbox

final class KeyboardShortcut {
    static let shared = KeyboardShortcut()

    private var registrations: [HotKeyRegistration] = []

    private init() {}

    func register(key: Int, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        let registration = HotKeyRegistration(key: key, modifiers: modifiers, action: action)
        registrations.append(registration)
    }

    func unregisterAll() {
        for reg in registrations {
            reg.unregister()
        }
        registrations.removeAll()
    }

    deinit {
        unregisterAll()
    }
}

private class HotKeyRegistration {
    var hotKeyRef: EventHotKeyRef?
    var handler: EventHandlerRef?
    let action: () -> Void
    let key: Int
    let modifiers: NSEvent.ModifierFlags

    init(key: Int, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.key = key
        self.modifiers = modifiers
        self.action = action
        register()
    }

    private func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let wrapper = Unmanaged.passRetained(HotKeyWrapper(action: action))
        let ptr = wrapper.toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, ptr -> OSStatus in
                guard let ptr else { return OSStatus(eventNotHandledErr) }
                let wrapper = Unmanaged<HotKeyWrapper>.fromOpaque(ptr).takeUnretainedValue()
                wrapper.action()
                return noErr
            },
            1,
            &eventType,
            ptr,
            &handler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x53434C50), id: UInt32(key))
        RegisterEventHotKey(
            UInt32(key),
            modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit {
        unregister()
    }
}

private class HotKeyWrapper {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
}

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}
