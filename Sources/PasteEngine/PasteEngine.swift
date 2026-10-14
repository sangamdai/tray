import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "PasteEngine")

/// Writes item to pasteboard, dismisses popup, fires synthetic ⌘V
/// targeted at the previously-focused app.
final class PasteEngine: PastePerforming {

    /// The app that was frontmost before we showed the popup
    var targetApp: NSRunningApplication?

    func paste(item: ClipboardItem, data: ClipboardItemData) {
        // 1. Write to pasteboard
        PasteboardWriter.write(data)

        let app = targetApp
        let pid = app?.processIdentifier ?? 0
        logger.info("Paste: type=\(item.type.rawValue) target=\(app?.bundleIdentifier ?? "nil") pid=\(pid)")

        // 2. Activate the target app
        app?.activate()

        // 3. Wait for activation, then fire synthetic ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.firePaste()
        }
    }

    private static func firePaste() {
        let source = CGEventSource(stateID: .privateState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            logger.error("Failed to create CGEvent")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        logger.info("Posted ⌘V via cgSessionEventTap")
    }
}
