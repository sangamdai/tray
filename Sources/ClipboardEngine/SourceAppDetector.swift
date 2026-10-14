import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "SourceAppDetector")

enum SourceAppDetector {
    struct AppInfo {
        let bundleID: String?
        let name: String?
    }

    static func frontmostApp() -> AppInfo {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return AppInfo(bundleID: nil, name: nil)
        }
        return AppInfo(
            bundleID: app.bundleIdentifier,
            name: app.localizedName
        )
    }
}
