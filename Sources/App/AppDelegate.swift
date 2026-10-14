import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "AppDelegate")

class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Modules

    private var clipboardStore: ClipboardStore!
    private var clipboardMonitor: ClipboardMonitor!
    private var preferencesManager: PreferencesManager!
    private var hotkeyManager: HotkeyManager!
    private var pasteEngine: PasteEngine!
    private var menuBarManager: MenuBarManager!

    // MARK: - UI

    private var popupWindow: PopupWindow?
    private var popupVC: PopupViewController?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("Tray launched")

        NSApp.setActivationPolicy(.accessory)
        BackgroundCursor.enable()

        if PreviewMode.isEnabled {
            setupPreview()
            return
        }

        setupPreferences()
        setupStorage()
        setupClipboardMonitor()
        setupHotkey()
        setupPasteEngine()
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stopMonitoring()
        hotkeyManager?.unregister()
        logger.info("Tray terminated")
    }

    // MARK: - Setup

    private func setupPreferences() {
        preferencesManager = PreferencesManager()
        preferencesManager.syncLoginItem()
    }

    private func setupStorage() {
        do {
            clipboardStore = try ClipboardStore(
                maxHistoryItems: preferencesManager.maxHistoryItems
            )
            logger.info("Storage initialized")
        } catch {
            logger.error("Failed to initialize storage: \(error.localizedDescription)")
            do {
                clipboardStore = try ClipboardStore(inMemory: true, maxHistoryItems: preferencesManager.maxHistoryItems)
                logger.warning("Using in-memory storage as fallback")
            } catch {
                logger.fault("Both disk and in-memory storage failed: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.messageText = "Tray couldn't start"
                alert.informativeText = "Its clipboard storage couldn't be opened. Try restarting your Mac."
                alert.runModal()
                NSApp.terminate(nil)
            }
        }
    }

    private func setupClipboardMonitor() {
        clipboardMonitor = ClipboardMonitor(
            store: clipboardStore,
            preferences: preferencesManager
        )
        clipboardMonitor.startMonitoring()
        logger.info("Clipboard monitor started")
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager()
        hotkeyManager.register { [weak self] in
            self?.togglePopup()
        }
    }

    private func setupPasteEngine() {
        pasteEngine = PasteEngine()
    }

    private func setupMenuBar() {
        menuBarManager = MenuBarManager()
        menuBarManager.onShowHistory = { [weak self] in
            self?.togglePopup()
        }
        menuBarManager.onHistoryLimitChanged = { [weak self] limit in
            self?.clipboardStore.setMaxHistoryItems(limit)
            self?.refreshPopup()
        }
        menuBarManager.setup(preferences: preferencesManager)
    }

    private func setupPreview() {
        preferencesManager = PreferencesManager()
        // Fresh sample images each launch so they don't pile up
        try? FileManager.default.removeItem(atPath: PreviewMode.imagesPath)
        let imageStorage = ImageStorage(baseDirectory: URL(fileURLWithPath: PreviewMode.imagesPath))
        guard let store = try? ClipboardStore(inMemory: true, maxHistoryItems: preferencesManager.maxHistoryItems, imageStorage: imageStorage) else {
            NSApp.terminate(nil)
            return
        }
        clipboardStore = store
        PreviewMode.seed(clipboardStore, imageStorage: imageStorage)
        pasteEngine = PasteEngine()
        NSApp.activate(ignoringOtherApps: true)
        setupMenuBar()
        showPreviewPopup()
        logger.info("Preview mode: popup shown")
    }

    /// Preview mode: show the popup at the top-center of the screen, ignoring outside clicks
    private func showPreviewPopup() {
        showPopup()
        popupWindow?.staysOpen = true
        if let window = popupWindow, let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: f.midX - window.frame.width / 2, y: f.maxY - 120))
        }
        if let id = popupWindow?.windowNumber {
            try? String(id).write(toFile: PreviewMode.windowIDPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Popup

    private func togglePopup() {
        if let window = popupWindow, window.isVisible {
            dismissPopup()
        } else {
            showPopup()
        }
    }

    private func showPopup() {
        // Capture the frontmost app BEFORE showing popup
        pasteEngine.targetApp = NSWorkspace.shared.frontmostApplication

        let window = PopupWindow()
        let vc = PopupViewController()

        // Wire callbacks
        vc.onItemSelected = { [weak self] item in
            self?.handleItemSelected(item)
        }
        vc.onAction = { [weak self] action, item in
            self?.handleAction(action, on: item)
        }
        vc.onDismissRequested = { [weak self] in
            self?.dismissPopup()
        }
        vc.previewDataProvider = { [weak self] item in
            self?.clipboardStore.getFullData(id: item.id)
        }
        vc.onClearAll = { [weak self] in
            self?.handleClearAll()
        }

        window.contentViewController = vc

        // Load data
        let pinned = clipboardStore.fetchPinned()
        let recent = clipboardStore.fetchRecent(limit: preferencesManager.maxHistoryItems)
        vc.update(pinned: pinned, recent: recent)

        window.showAtCursor()

        self.popupWindow = window
        self.popupVC = vc
    }

    private func dismissPopup() {
        popupWindow?.dismiss()
        popupWindow = nil
        popupVC = nil

        // Preview mode: reopen shortly after, so Esc replays the opening animation
        if PreviewMode.isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard self?.popupWindow == nil else { return }
                self?.showPreviewPopup()
            }
        }
    }

    // MARK: - Item Selection

    private func handleItemSelected(_ item: ClipboardItem) {
        logger.info("Item selected: \(item.id) type=\(item.type.rawValue)")
        if PreviewMode.isEnabled { return }
        guard let data = clipboardStore.getFullData(id: item.id) else {
            logger.error("Could not load full data for item \(item.id)")
            return
        }
        dismissPopup()
        logger.info("Popup dismissed, initiating paste")
        pasteEngine.paste(item: item, data: data)
    }

    // MARK: - Actions

    private func handleAction(_ action: ClipboardAction, on item: ClipboardItem) {
        do {
            switch action {
            case .pin, .unpin:
                try clipboardStore.togglePin(id: item.id)
            case .hide:
                try clipboardStore.toggleHide(id: item.id)
                // Pause click monitoring so the modal alert isn't dismissed by outside clicks
                popupWindow?.pauseClickMonitoring()
                promptRename(for: item, title: "Name Hidden Item", message: "Enter a name for this hidden item (optional):", placeholder: item.customName ?? item.contentPreview)
                popupWindow?.resumeClickMonitoring()
                return
            case .unhide:
                try clipboardStore.toggleHide(id: item.id)
            case .rename(let name):
                if name.isEmpty {
                    popupWindow?.pauseClickMonitoring()
                    promptRename(for: item)
                    popupWindow?.resumeClickMonitoring()
                    return
                }
                try clipboardStore.rename(id: item.id, name: name)
            case .delete:
                try clipboardStore.delete(id: item.id)
            }

            refreshPopup()
        } catch {
            logger.error("Action failed: \(error.localizedDescription)")
        }
    }

    private func promptRename(for item: ClipboardItem, title: String = "Rename Item", message: String = "Enter a custom name:", placeholder: String? = nil) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Skip")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.stringValue = item.customName ?? ""
        input.placeholderString = placeholder ?? "Hidden item"
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty {
                try? clipboardStore.rename(id: item.id, name: newName)
            }
        }
        refreshPopup()
    }

    private func refreshPopup() {
        let pinned = clipboardStore.fetchPinned()
        let recent = clipboardStore.fetchRecent(limit: preferencesManager.maxHistoryItems)
        popupVC?.update(pinned: pinned, recent: recent)
    }

    // MARK: - Clear All

    private func handleClearAll() {
        if PreviewMode.isEnabled { return } // keep the sample data
        dismissPopup()
        let usage = clipboardStore.storageUsage()
        let size = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "Your history uses \(size(usage.total)). "
            + "Clearing removes everything except pinned items and frees about \(size(usage.clearable))."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        try? clipboardStore.deleteAll()
    }
}
