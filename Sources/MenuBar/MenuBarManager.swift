import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "MenuBarManager")

final class MenuBarManager {

    private var statusItem: NSStatusItem?
    private let permissionsHelper = PermissionsHelper()
    private weak var preferences: PreferencesManager?

    var onShowHistory: (() -> Void)?
    /// User picked a new history limit (already saved to preferences)
    var onHistoryLimitChanged: ((Int) -> Void)?

    /// The dropdown, a MenuPanel styled like the popup (the system menu's border can't be restyled)
    private var menu: MenuPanel?
    private var outsideClickMonitor: Any?

    func setup(preferences: PreferencesManager) {
        self.preferences = preferences

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Tray")?
                .withSymbolConfiguration(config)
            button.image = image
            button.target = self
            button.action = #selector(toggleMenu)
            // Open on press, like system menus
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
    }

    // MARK: - Dropdown

    @objc private func toggleMenu() {
        if menu != nil { closeMenu() } else { openMenu() }
    }

    private func openMenu() {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }

        let panel = MenuPanel(
            entries: menuEntries(),
            width: TrayTheme.StatusMenu.width,
            tint: TrayTheme.StatusMenu.tint
        )
        panel.onClose = { [weak self] in self?.closeMenu() }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        panel.show(below: anchor)
        menu = panel
        button.highlight(true)

        // Close on clicks in other apps
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closeMenu()
        }
    }

    private func closeMenu() {
        menu?.dismiss()
        menu = nil
        statusItem?.button?.highlight(false)
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    /// Rebuilt each time it opens, so checkmarks and the accessibility row stay current
    private func menuEntries() -> [MenuEntry?] {
        var entries: [MenuEntry?] = [
            MenuEntry(title: "Open Tray", shortcut: "⌘⇧V") { [weak self] in self?.showHistory() },
            nil,
            MenuEntry(title: "Launch at Login", isChecked: preferences?.launchAtLogin ?? false) { [weak self] in
                self?.toggleLaunchAtLogin()
            },
        ]
        let currentLimit = preferences?.maxHistoryItems ?? 0
        entries.append(MenuEntry(title: "Clipboard history", detail: "\(currentLimit)", perform: {}, submenu: { [weak self] in
            PreferencesManager.historyLimitOptions.map { limit in
                MenuEntry(title: "\(limit) items", isChecked: limit == currentLimit) { self?.setHistoryLimit(limit) }
            }
        }))
        entries.append(nil)
        // Accessibility — only show if not granted
        if !permissionsHelper.isAccessibilityGranted {
            entries.append(MenuEntry(title: "Grant Accessibility Access") { [weak self] in self?.grantAccess() })
            entries.append(nil)
        }
        if let releases = AppInfo.releasesURL {
            entries.append(MenuEntry(title: "Check for Updates…") { NSWorkspace.shared.open(releases) })
        }
        entries.append(MenuEntry(title: "About Tray") { [weak self] in self?.showAbout() })
        entries.append(nil)
        entries.append(MenuEntry(title: "Quit Tray", shortcut: "⌘Q", keyCode: 12, needsCommand: true) { [weak self] in
            self?.quitApp()
        })
        return entries
    }

    // MARK: - Actions

    private func showHistory() {
        onShowHistory?()
    }

    private func setHistoryLimit(_ limit: Int) {
        guard let prefs = preferences, prefs.maxHistoryItems != limit else { return }
        prefs.maxHistoryItems = limit
        onHistoryLimitChanged?(limit)
    }

    private func toggleLaunchAtLogin() {
        // Preview mode is a dev build; don't register it as a login item
        guard !PreviewMode.isEnabled, let prefs = preferences else { return }
        prefs.launchAtLogin = !prefs.launchAtLogin
    }

    private func grantAccess() {
        permissionsHelper.requestAccessibility()
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        // Standard About window (icon, name, version, copyright from Info.plist),
        // plus a tagline and, once there is one, a link to the repo
        let credits = NSMutableAttributedString(string: AppInfo.tagline, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        if let repo = AppInfo.repositoryURL {
            credits.append(NSAttributedString(string: "\n"))
            credits.append(NSAttributedString(string: repo.absoluteString, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: repo,
            ]))
        }
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func quitApp() {
        NSApp.terminate(nil)
    }
}
