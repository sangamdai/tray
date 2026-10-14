import AppKit

/// Single-line row: [icon] [title...] [swatch?] [source app] [› when selected]
///
/// Lays itself out by hand in `layout()` rather than with Auto Layout: the popup can
/// hold 200 of these, and solving ~15 constraints per row made opening take ~140ms.
final class ClipboardItemCellView: NSView {

    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let timeLabel = NSTextField(labelWithString: "")
    let chevronView = NSImageView()
    /// Color items only: swatch right after the hex text
    let swatchView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = TrayTheme.Colors.iconTint

        titleLabel.font = TrayTheme.Typography.primaryFont
        titleLabel.textColor = TrayTheme.Colors.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true

        timeLabel.font = TrayTheme.Typography.secondaryFont
        timeLabel.textColor = TrayTheme.Colors.tertiaryText
        timeLabel.alignment = .right
        timeLabel.lineBreakMode = .byClipping
        timeLabel.maximumNumberOfLines = 1

        swatchView.isHidden = true

        chevronView.image = TrayTheme.Icons.chevronRight
        chevronView.contentTintColor = .white.withAlphaComponent(0.6)
        chevronView.isHidden = true

        for view in [iconView, titleLabel, timeLabel, swatchView, chevronView] as [NSView] {
            addSubview(view)
        }
    }

    func configure(with item: ClipboardItem) {
        if item.isHidden {
            iconView.image = TrayTheme.Icons.hidden
            titleLabel.font = TrayTheme.Typography.hiddenFont
        } else {
            iconView.image = TrayTheme.Icons.itemIcon(for: item)
            titleLabel.font = TrayTheme.Typography.primaryFont
        }
        titleLabel.stringValue = item.displayLabel
        timeLabel.stringValue = item.sourceAppName ?? ""

        let swatch = item.type == .color && !item.isHidden
            ? item.metadata.colorHex.flatMap { TrayTheme.Icons.colorSwatch(hex: $0) }
            : nil
        swatchView.image = swatch
        swatchView.isHidden = swatch == nil
        needsLayout = true
    }

    /// The clickable area around the "›" (opens the actions menu), in this view's coordinates
    var chevronHitFrame: NSRect? {
        guard !chevronView.isHidden else { return nil }
        let minX = chevronView.frame.minX - 6
        return NSRect(x: minX, y: 0, width: bounds.maxX - minX, height: bounds.height)
    }

    func setSelected(_ selected: Bool) {
        chevronView.isHidden = !selected
        needsLayout = true

        if selected {
            layer?.backgroundColor = TrayTheme.Colors.selection.cgColor
            layer?.cornerRadius = TrayTheme.Row.selectionCornerRadius
            titleLabel.textColor = .white
            timeLabel.textColor = .white.withAlphaComponent(0.5)
            iconView.contentTintColor = .white.withAlphaComponent(0.5)
        } else {
            layer?.backgroundColor = nil
            titleLabel.textColor = TrayTheme.Colors.primaryText
            timeLabel.textColor = TrayTheme.Colors.tertiaryText
            iconView.contentTintColor = TrayTheme.Colors.iconTint
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let pad = TrayTheme.Row.horizontalPadding
        let iconSize = TrayTheme.Row.iconSize
        let h = bounds.height

        func centered(_ x: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
            NSRect(x: x, y: ((h - height) / 2).rounded(), width: width, height: height)
        }

        iconView.frame = centered(pad, width: iconSize, height: iconSize)

        // Lucide's chevron has ~6px of empty space on its right at 16px,
        // so it lands visually ~12px from the edge
        let chevronSize = TrayTheme.Icons.size
        chevronView.frame = centered(bounds.width - 6 - chevronSize, width: chevronSize, height: chevronSize)

        // Source app: flush right, or 8px left of the chevron when selected
        let timeSize = timeLabel.stringValue.isEmpty ? .zero : timeLabel.intrinsicContentSize
        let timeRight = chevronView.isHidden ? bounds.width - pad : chevronView.frame.minX - 8
        timeLabel.frame = centered(timeRight - timeSize.width, width: timeSize.width, height: timeSize.height)

        // Title fills the space between the icon and the source app; a color swatch sits right after it
        let titleX = iconView.frame.maxX + TrayTheme.Row.spacing
        let available = max(timeLabel.frame.minX - 4 - titleX, 0)
        let titleHeight = titleLabel.intrinsicContentSize.height
        if swatchView.isHidden {
            titleLabel.frame = centered(titleX, width: available, height: titleHeight)
        } else {
            let swatchSize = TrayTheme.Icons.swatchSize
            let titleWidth = min(titleLabel.intrinsicContentSize.width, max(available - 6 - swatchSize, 0))
            titleLabel.frame = centered(titleX, width: titleWidth, height: titleHeight)
            swatchView.frame = centered(titleLabel.frame.maxX + 6, width: swatchSize, height: swatchSize)
        }
    }
}
