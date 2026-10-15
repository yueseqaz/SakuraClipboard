import Cocoa
import Carbon.HIToolbox

final class KeyboardShortcut {
    static let shared = KeyboardShortcut()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    private init() {}

    func register(key: Int, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        if handler == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, ptr -> OSStatus in
                    guard let event, let ptr else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID) == noErr,
                          hotKeyID.signature == OSType(0x53434C50) else { return OSStatus(eventNotHandledErr) }
                    let shortcuts = Unmanaged<KeyboardShortcut>.fromOpaque(ptr).takeUnretainedValue()
                    guard let action = shortcuts.actions[hotKeyID.id] else { return OSStatus(eventNotHandledErr) }
                    action()
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &handler
            )
        }

        let id = nextID
        nextID += 1
        let hotKeyID = EventHotKeyID(signature: OSType(0x53434C50), id: id) // 'SCLP'
        var hotKeyRef: EventHotKeyRef?
        let result = RegisterEventHotKey(
            UInt32(key),
            modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if result == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
            actions[id] = action
        }
    }

    func unregister() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        actions.removeAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit {
        unregister()
    }
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
