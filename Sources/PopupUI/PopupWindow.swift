import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "PopupWindow")

/// The main popup panel: shows at the cursor, dismisses on outside clicks.
/// The vibrancy background is handled by PopupViewController's root view.
final class PopupWindow: PopupPanel {

    private var globalClickMonitor: Any?

    /// Preview mode: ignore outside clicks so the popup stays up while iterating.
    var staysOpen = false {
        didSet { if staysOpen { stopMonitoringClicks() } }
    }

    init() {
        super.init(width: TrayTheme.Window.width)
    }

    func showAtCursor() {
        let mouseLocation = NSEvent.mouseLocation

        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!

        // The window has a transparent margin around the visible popup; position the popup itself
        let m = TrayTheme.Appear.margin
        let visibleFrame = screen.visibleFrame.insetBy(dx: -m, dy: -m)
        let windowSize = frame.size

        var origin = NSPoint(
            x: mouseLocation.x - windowSize.width / 2,
            y: mouseLocation.y - windowSize.height + m
        )

        origin.x = max(visibleFrame.minX + 4, min(origin.x, visibleFrame.maxX - windowSize.width - 4))
        origin.y = max(visibleFrame.minY + 4, min(origin.y, visibleFrame.maxY - windowSize.height - 4))

        setFrameOrigin(origin)

        alphaValue = 0
        orderFrontRegardless()
        makeKey()

        // Make VC first responder for keyboard events
        if let vc = contentViewController {
            makeFirstResponder(vc)
        }

        if let chrome = (contentViewController as? PopupViewController)?.chromeView {
            animateAppearance(of: chrome, fromScaleX: TrayTheme.Appear.fromScaleX, fromScaleY: TrayTheme.Appear.fromScaleY)
        }

        startMonitoringClicks()
        startForwardingEvents()
    }

    func dismiss() {
        stopMonitoringClicks()
        stopForwardingEvents()
        childWindows?.forEach { $0.orderOut(nil) }
        orderOut(nil)
    }

    /// Temporarily pause global click monitoring (e.g. while a modal alert is shown)
    func pauseClickMonitoring() {
        stopMonitoringClicks()
    }

    /// Resume global click monitoring after a modal alert is dismissed
    func resumeClickMonitoring() {
        startMonitoringClicks()
    }

    private func startMonitoringClicks() {
        guard !staysOpen else { return }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func stopMonitoringClicks() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    deinit {
        stopMonitoringClicks()
    }
}
