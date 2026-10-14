import AppKit

/// Read-only preview of a clipboard item, shown beside the popup after hovering a row.
/// Never takes focus or mouse events, so the popup keeps keyboard and hover.
final class PreviewPanel: PopupPanel {

    init() {
        super.init(width: TrayTheme.Preview.maxWidth)
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }

    /// Shows `item` beside the popup, vertically centered on `rowFrame` (screen coordinates).
    /// Returns false if the item has nothing to preview (e.g. hidden items).
    @discardableResult
    func show(_ item: ClipboardItem, data: ClipboardItemData?, besideRow rowFrame: NSRect, in parentFrame: NSRect) -> Bool {
        guard !item.isHidden, let content = PreviewContent.make(for: item, data: data) else {
            orderOut(nil)
            return false
        }

        let wasVisible = isVisible
        let pad = TrayTheme.Spacing.contentInset
        let m = TrayTheme.Appear.margin
        let chrome = PopupChrome.make(
            width: content.fittingSize.width + pad * 2,
            cornerRadius: TrayTheme.ActionMenu.cornerRadius
        )
        content.translatesAutoresizingMaskIntoConstraints = false
        chrome.content.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: chrome.content.topAnchor, constant: pad),
            content.leadingAnchor.constraint(equalTo: chrome.content.leadingAnchor, constant: pad),
            content.trailingAnchor.constraint(equalTo: chrome.content.trailingAnchor, constant: -pad),
            content.bottomAnchor.constraint(equalTo: chrome.content.bottomAnchor, constant: -pad),
        ])
        // Transparent margin around the visible panel, so the wider start isn't clipped
        let root = NSView()
        chrome.root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(chrome.root)
        NSLayoutConstraint.activate([
            chrome.root.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            chrome.root.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m),
            chrome.root.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            chrome.root.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
        ])
        contentView = root

        let size = NSSize(width: content.fittingSize.width + pad * 2, height: content.fittingSize.height + pad * 2)
        let onRight = place(size: size, besideRow: rowFrame, of: parentFrame, alignment: .centered, margin: m)
        orderFront(nil)

        // Animate only when it first appears; following the selection stays instant
        if !wasVisible {
            root.layoutSubtreeIfNeeded()
            let bounds = chrome.root.bounds
            animateAppearance(
                of: chrome.root,
                fromScaleX: TrayTheme.Appear.previewFromScaleX,
                fromScaleY: 1,
                anchor: CGPoint(x: onRight ? bounds.minX : bounds.maxX, y: bounds.midY)
            )
        }
        return true
    }
}

// MARK: - Content

/// Builds the preview body: the content itself plus a one-line caption
/// (source app, age, and size details).
private enum PreviewContent {

    static func make(for item: ClipboardItem, data: ClipboardItemData?) -> NSView? {
        let body: NSView
        var details: String?

        switch item.type {
        case .image:
            guard let raw = data?.rawData, let image = downsampledImage(raw) else { return nil }
            body = imageView(image)
            if let w = item.metadata.imageWidth, let h = item.metadata.imageHeight {
                details = "\(w) × \(h)"
            }

        case .color:
            guard let hex = item.metadata.colorHex else { return nil }
            body = colorView(hex: hex, rgba: item.metadata.colorRGBA)

        case .file:
            body = textView(item.metadata.filePath ?? item.contentPreview)
            if let size = item.metadata.fileSize {
                details = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }

        default:
            let text = item.metadata.plainText ?? item.metadata.urlString ?? item.contentPreview
            body = textView(text)
            details = "\(text.count) characters"
        }

        let caption = [item.sourceAppName, RelativeTimeFormatter.string(from: item.createdAt), details]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        let stack = NSStackView(views: [body, captionLabel(caption)])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        return stack
    }

    /// Decodes only enough pixels for the preview (2× its max size for Retina),
    /// instead of the full image: a 5K screenshot would otherwise take ~60MB per hover
    private static func downsampledImage(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let maxPixels = max(TrayTheme.Preview.maxImageSize.width, TrayTheme.Preview.maxImageSize.height) * 2
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // Point size = pixels / 2, so it displays at its natural Retina size
        return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2))
    }

    private static func imageView(_ image: NSImage) -> NSView {
        let max = TrayTheme.Preview.maxImageSize
        let scale = min(max.width / image.size.width, max.height / image.size.height, 1)
        let size = NSSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = TrayTheme.Preview.imageCornerRadius
        view.layer?.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size.width),
            view.heightAnchor.constraint(equalToConstant: size.height),
        ])
        return view
    }

    private static func colorView(hex: String, rgba: [Double]?) -> NSView {
        let swatch = NSView()
        swatch.wantsLayer = true
        swatch.layer?.cornerRadius = TrayTheme.Preview.imageCornerRadius
        swatch.layer?.backgroundColor = TrayTheme.Icons.color(hex: hex)?.cgColor
        swatch.layer?.borderWidth = 0.5
        swatch.layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        swatch.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: TrayTheme.Preview.swatchSize),
            swatch.heightAnchor.constraint(equalToConstant: TrayTheme.Preview.swatchSize),
        ])

        var lines = [hex]
        if let rgba, rgba.count >= 3 {
            let (r, g, b) = (TypeDetector.byte(rgba[0]), TypeDetector.byte(rgba[1]), TypeDetector.byte(rgba[2]))
            lines.append("rgb(\(r), \(g), \(b))")
        }
        // Small swatch beside the values
        let stack = NSStackView(views: [swatch, textView(lines.joined(separator: "\n"))])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
    }

    private static func textView(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = TrayTheme.Preview.textFont
        label.textColor = TrayTheme.Colors.primaryText
        label.maximumNumberOfLines = TrayTheme.Preview.maxTextLines
        // Must wrap, not truncate: a truncating line break mode turns wrapping off.
        // Long unbroken strings (URLs, code) fall back to breaking mid-word.
        label.lineBreakMode = .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        // Hugs short text; wraps at the max width
        label.preferredMaxLayoutWidth = TrayTheme.Preview.maxWidth
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(lessThanOrEqualToConstant: TrayTheme.Preview.maxWidth).isActive = true
        return label
    }

    private static func captionLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = TrayTheme.Preview.metaFont
        label.textColor = TrayTheme.Colors.tertiaryText
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(lessThanOrEqualToConstant: TrayTheme.Preview.maxWidth).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}
