import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "HotkeyManager")

/// Registers global ⌘⇧V hotkey using Carbon.
final class HotkeyManager {

    private let carbonHotkey = CarbonHotkey()

    func register(handler: @escaping () -> Void) {
        carbonHotkey.register(handler: handler)
    }

    func unregister() {
        carbonHotkey.unregister()
    }
}
