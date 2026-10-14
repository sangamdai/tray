import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "ClipboardMonitor")

final class ClipboardMonitor: ClipboardMonitoring {

    private let store: ClipboardStoring
    private let preferences: PreferencesManaging
    private let imageStorage: ImageStorage
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private let pollInterval: TimeInterval

    init(
        store: ClipboardStoring,
        preferences: PreferencesManaging,
        imageStorage: ImageStorage = ImageStorage(),
        pollInterval: TimeInterval = 0.5
    ) {
        self.store = store
        self.preferences = preferences
        self.imageStorage = imageStorage
        self.pollInterval = pollInterval
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func startMonitoring() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        // Leeway lets macOS batch this wakeup with others (energy); a copy is
        // still picked up within ~0.6s
        timer.schedule(
            deadline: .now() + pollInterval,
            repeating: pollInterval,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in
            self?.checkPasteboard()
        }
        timer.resume()
        self.timer = timer
        logger.info("Monitoring started (interval: \(self.pollInterval)s)")
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        logger.info("Monitoring stopped")
    }

    // MARK: - Private

    private func checkPasteboard() {
        let currentCount = NSPasteboard.general.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        DispatchQueue.main.sync { processPasteboard() }
    }

    private func processPasteboard() {
        let pasteboard = NSPasteboard.general

        // Skip Tray's own pastes: history order follows when things were copied, not pasted
        if pasteboard.types?.contains(PasteboardWriter.ownWriteMarker) == true {
            logger.debug("Skipped Tray's own pasteboard write")
            return
        }

        // Skip concealed (passwords), transient, and auto-generated content
        if TypeDetector.shouldIgnore(pasteboard: pasteboard) {
            logger.debug("Skipped concealed/transient pasteboard content")
            return
        }

        // Check excluded apps
        let sourceApp = SourceAppDetector.frontmostApp()
        if let bundleID = sourceApp.bundleID,
           preferences.excludedAppBundleIDs.contains(bundleID) {
            logger.debug("Skipped content from excluded app: \(bundleID)")
            return
        }

        // Detect type and extract metadata
        guard let detected = TypeDetector.detect(from: pasteboard) else {
            logger.debug("Could not detect pasteboard type")
            return
        }
        let type = detected.type
        var metadata = detected.metadata

        // Compute hash for deduplication
        let hashData = hashableData(from: pasteboard, type: type, metadata: metadata)
        let dataHash = HashHelper.sha256(hashData)

        // Handle image storage — only save files for genuinely new items
        let itemID = UUID()
        if type == .image, !store.hashExists(dataHash) {
            if let imageData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
                metadata.imagePath = imageStorage.saveImage(imageData, id: itemID)
            }
        }

        // Build the item
        let preview = TypeDetector.preview(for: type, metadata: metadata)
        let item = ClipboardItem(
            id: itemID,
            type: type,
            sourceAppBundleID: sourceApp.bundleID,
            sourceAppName: sourceApp.name,
            contentPreview: preview,
            dataHash: dataHash,
            metadata: metadata
        )

        // Save to store
        do {
            try store.save(item)
            logger.debug("Captured \(type.rawValue) from \(sourceApp.name ?? "unknown")")
        } catch {
            logger.error("Failed to save clipboard item: \(error.localizedDescription)")
        }
    }

    private func hashableData(from pasteboard: NSPasteboard, type: ClipboardItemType, metadata: ClipboardItemMetadata) -> Data {
        switch type {
        case .plainText, .url, .tabularData:
            return (metadata.plainText ?? "").data(using: .utf8) ?? Data()
        case .richText:
            return metadata.rtfData ?? (metadata.plainText ?? "").data(using: .utf8) ?? Data()
        case .html:
            return (metadata.htmlString ?? "").data(using: .utf8) ?? Data()
        case .image:
            return pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) ?? Data()
        case .file:
            return (metadata.filePath ?? "").data(using: .utf8) ?? Data()
        case .color:
            return (metadata.colorHex ?? "").data(using: .utf8) ?? Data()
        }
    }
}
