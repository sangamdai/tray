import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.tray.app", category: "Permissions")

final class PermissionsHelper {

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
