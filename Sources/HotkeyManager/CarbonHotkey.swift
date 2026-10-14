import Carbon
import os

private let logger = Logger(subsystem: "com.tray.app", category: "CarbonHotkey")

/// Global Carbon hotkey registration for ⌘⇧V.
/// Carbon's RegisterEventHotKey is the most reliable approach for global hotkeys on macOS.
final class CarbonHotkey {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?

    /// Unique hotkey ID
    private let hotkeyID = EventHotKeyID(signature: fourCharCode("TRAY"), id: 1)

    func register(handler: @escaping () -> Void) {
        self.callback = handler
        unregister()

        // Install Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        guard status == noErr else {
            logger.error("Failed to install event handler: \(status)")
            return
        }

        // Register ⌘⇧V: V key = 0x09, modifiers = cmdKey + shiftKey
        let keyID = hotkeyID
        let regStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            keyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if regStatus == noErr {
            logger.info("Registered ⌘⇧V hotkey")
        } else {
            logger.error("Failed to register hotkey: \(regStatus)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    fileprivate func handleHotkeyPressed() {
        DispatchQueue.main.async { [weak self] in
            self?.callback?()
        }
    }

    deinit {
        unregister()
    }
}

/// Four-char code helper
private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) | OSType(char)
    }
    return result
}

/// C callback for Carbon event handler
private func carbonHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
    let hotkey = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
    hotkey.handleHotkeyPressed()
    return noErr
}
