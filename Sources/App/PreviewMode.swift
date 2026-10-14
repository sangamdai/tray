import AppKit

/// Dev-only preview: `Tray --preview` opens the popup with sample data in an
/// in-memory store. No hotkey, no clipboard monitoring, no pasting.
enum PreviewMode {

    static let isEnabled = CommandLine.arguments.contains("--preview")

    /// Written on launch so Scripts/preview.sh can screenshot the popup window.
    static let windowIDPath = ".build/preview-window-id"

    /// Sample images live here, not in the real ~/Library/Application Support/Tray
    static let imagesPath = ".build/preview-images"

    static func seed(_ store: ClipboardStore, imageStorage: ImageStorage) {
        let now = Date()
        let samples: [(ClipboardItemType, String, String, TimeInterval, Bool, Bool)] = [
            (.plainText, "ssh deploy@10.0.4.21 -p 2222", "Terminal", 2 * 86400, true, false),
            (.plainText, "hello@example.com", "Notes", 5 * 86400, true, false),
            (.plainText, "func handleItemSelected(_ item: ClipboardItem) { guard let data = clipboardStore.getFullData(id: item.id) else { return } }", "Xcode", 2, false, false),
            (.url, "https://developer.apple.com/documentation/appkit/nsvisualeffectview", "Safari", 120, false, false),
            (.image, "Screenshot 2026-10-13 at 9.41.22 PM", "Screenshot", 840, false, false),
            (.plainText, "Hey — can we push the sync to Thursday? I want to finish the paste engine refactor first.", "Slack", 1860, false, false),
            (.color, "#0A7AFF", "Figma", 3600, false, false),
            (.plainText, "sk_test_51Hx…", "1Password", 7200, false, true),
            (.plainText, "SELECT id, content_preview FROM clipboard_items WHERE is_pinned = 1;", "TablePlus", 10800, false, false),
            (.url, "https://github.com/sindresorhus/KeyboardShortcuts", "Chrome", 18000, false, false),
            (.plainText, "Tray 1.2 — scrolling history, previews, and ⌘1–9 quick paste.", "Notes", 86400, false, false),
            (.plainText, "brew install --cask tray", "Terminal", 90000, false, false),
        ]

        for (i, s) in samples.enumerated() {
            let (type, text, app, age, pinned, hidden) = s
            let id = UUID()
            var metadata = ClipboardItemMetadata()
            switch type {
            case .url: metadata.urlString = text
            case .color:
                metadata.colorHex = text
                if let c = TrayTheme.Icons.color(hex: text) {
                    metadata.colorRGBA = [c.redComponent, c.greenComponent, c.blueComponent, 1].map(Double.init)
                }
            case .image:
                metadata.imageWidth = 1440
                metadata.imageHeight = 900
                if let png = sampleImagePNG(width: 1440, height: 900) {
                    metadata.imagePath = imageStorage.saveImage(png, id: id)
                }
            default: metadata.plainText = text
            }
            let item = ClipboardItem(
                id: id,
                type: type,
                createdAt: now.addingTimeInterval(-age),
                isPinned: pinned,
                isHidden: hidden,
                customName: hidden ? "Stripe test key" : nil,
                sourceAppName: app,
                contentPreview: text,
                dataHash: "preview-\(i)",
                metadata: metadata
            )
            try? store.save(item)
        }

        // Older filler so the list has enough rows to scroll
        for i in 0..<40 {
            let text = "Older clip #\(i + 1) — lorem ipsum dolor sit amet"
            var metadata = ClipboardItemMetadata()
            metadata.plainText = text
            try? store.save(ClipboardItem(
                type: .plainText,
                createdAt: now.addingTimeInterval(-Double(2 + i) * 86400 - 100_000),
                sourceAppName: "Notes",
                contentPreview: text,
                dataHash: "preview-filler-\(i)",
                metadata: metadata
            ))
        }
    }

    /// A fake screenshot: window-ish shapes on a gradient, so image previews have something to show
    private static func sampleImagePNG(width: Int, height: Int) -> Data? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(
                starting: NSColor(srgbRed: 0.16, green: 0.20, blue: 0.45, alpha: 1),
                ending: NSColor(srgbRed: 0.55, green: 0.25, blue: 0.50, alpha: 1)
            )?.draw(in: rect, angle: -35)

            let window = NSRect(x: 220, y: 160, width: 1000, height: 600)
            NSColor(white: 0.12, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: window, xRadius: 22, yRadius: 22).fill()

            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 252 + i * 36, y: 718, width: 20, height: 20)).fill()
            }
            NSColor(white: 1, alpha: 0.14).setFill()
            for row in 0..<7 {
                let w = [760, 620, 700, 420, 680, 540, 300][row]
                NSBezierPath(roundedRect: NSRect(x: 280, y: 630 - row * 62, width: w, height: 22), xRadius: 6, yRadius: 6).fill()
            }
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
