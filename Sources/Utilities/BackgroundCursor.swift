import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "BackgroundCursor")

/// Tray never becomes the active app (the popup is a non-activating panel), and
/// macOS ignores NSCursor changes from inactive apps. This lets the popup set
/// the cursor anyway, e.g. the pointing hand over a row's "›".
///
/// Uses private CoreGraphics (SkyLight) calls, looked up at runtime: if a future
/// macOS drops them, this quietly does nothing instead of failing at launch.
enum BackgroundCursor {
    private typealias DefaultConnection = @convention(c) () -> Int32
    private typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    static func enable() {
        guard let handle = dlopen(nil, RTLD_LAZY),
              let connectionSym = dlsym(handle, "_CGSDefaultConnection"),
              let setPropertySym = dlsym(handle, "CGSSetConnectionProperty") else {
            logger.info("Background cursor calls unavailable; pointer stays default")
            return
        }
        let connection = unsafeBitCast(connectionSym, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setPropertySym, to: SetConnectionProperty.self)
        let result = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        if result != 0 {
            logger.error("SetsCursorInBackground failed: \(result)")
        }
    }
}
