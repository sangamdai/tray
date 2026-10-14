import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "ClipboardMonitor")

/// Size limits for what gets saved to history
enum ClipLimits {
    /// Plain text (or rich formatting) larger than this isn't kept
    static let maxTextBytes = 1_000_000
    /// Images larger than this after PNG compression aren't kept
    static let maxImageBytes = 25_000_000
}

final class ClipboardMonitor: ClipboardMonitoring {

    private let store: ClipboardStoring
    private let preferences: PreferencesManaging
    private let imageStorage: ImageStorage
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int
    private let pollInterval: TimeInterval
    /// All clipboard work (reading, hashing, image conversion, saving) runs here,
    /// never on the main thread, so a large copy can't stall the UI
    private let queue = DispatchQueue(label: "com.tray.clipboard", qos: .utility)

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
        let timer = DispatchSource.makeTimerSource(queue: queue)
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

        processPasteboard()
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
        guard applySizeLimits(to: &metadata, type: type) else { return }

        // Compute hash for deduplication
        let hashData = detected.imageData ?? hashableData(type: type, metadata: metadata)
        let dataHash = HashHelper.sha256(hashData)

        // Handle image storage — only save files for genuinely new items
        let itemID = UUID()
        if type == .image, let imageData = detected.imageData, !store.hashExists(dataHash) {
            guard let png = Self.compressedImage(imageData), png.count <= ClipLimits.maxImageBytes else {
                logger.info("Skipped image: over \(ClipLimits.maxImageBytes / 1_000_000)MB")
                return
            }
            metadata.imagePath = imageStorage.saveImage(png, id: itemID)
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

    /// Keeps history small: drops formatting from huge rich text (the plain text is
    /// kept), and skips clips whose plain text alone is too large. Returns false to skip.
    private func applySizeLimits(to metadata: inout ClipboardItemMetadata, type: ClipboardItemType) -> Bool {
        let plainBytes = (metadata.plainText?.utf8.count ?? 0) + (metadata.tsvData?.utf8.count ?? 0)
        if plainBytes > ClipLimits.maxTextBytes {
            logger.info("Skipped \(type.rawValue): text over \(ClipLimits.maxTextBytes / 1_000_000)MB")
            return false
        }
        let richBytes = (metadata.rtfData?.count ?? 0) + (metadata.htmlString?.utf8.count ?? 0)
        if richBytes > ClipLimits.maxTextBytes {
            if metadata.plainText == nil { return false } // nothing left to keep
            metadata.rtfData = nil
            metadata.htmlString = nil
            logger.info("Dropped formatting over \(ClipLimits.maxTextBytes / 1_000_000)MB; kept plain text")
        }
        return true
    }

    /// PNG as-is; single-image RGB/gray TIFF (the usual uncompressed copy, often 5–10×
    /// larger) converted to PNG. Lossless: every pixel is kept. Anything PNG can't hold
    /// exactly (CMYK, multi-page) is stored as copied.
    private static func compressedImage(_ data: Data) -> Data? {
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        if data.prefix(pngSignature.count) == pngSignature { return data }
        let reps = NSBitmapImageRep.imageReps(with: data)
        guard reps.count == 1, let rep = reps.first as? NSBitmapImageRep,
              rep.colorSpace.colorSpaceModel == .rgb || rep.colorSpace.colorSpaceModel == .gray,
              let png = rep.representation(using: .png, properties: [:]) else { return data }
        return png
    }

    private func hashableData(type: ClipboardItemType, metadata: ClipboardItemMetadata) -> Data {
        switch type {
        case .plainText, .url, .tabularData:
            return (metadata.plainText ?? "").data(using: .utf8) ?? Data()
        case .richText:
            return metadata.rtfData ?? (metadata.plainText ?? "").data(using: .utf8) ?? Data()
        case .html:
            return (metadata.htmlString ?? "").data(using: .utf8) ?? Data()
        case .image:
            return Data() // hashed from the image bytes by the caller
        case .file:
            return (metadata.filePath ?? "").data(using: .utf8) ?? Data()
        case .color:
            return (metadata.colorHex ?? "").data(using: .utf8) ?? Data()
        }
    }
}
