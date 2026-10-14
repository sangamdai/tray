import AppKit

/// Single-line row: [icon] [title...] [swatch?] [source app] [› when selected]
final class ClipboardItemCellView: NSTableCellView {

    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let timeLabel = NSTextField(labelWithString: "")
    let chevronView = NSImageView()
    /// Color items only: swatch right after the hex text
    let swatchView = NSImageView()
    private var swatchTrailingLimit: NSLayoutConstraint!

    // Source app sits flush right, or left of the chevron when selected
    private var timeTrailingToEdge: NSLayoutConstraint!
    private var timeTrailingToChevron: NSLayoutConstraint!

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

        let pad = TrayTheme.Row.horizontalPadding
        let iconSz = TrayTheme.Row.iconSize

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = TrayTheme.Colors.iconTint
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = TrayTheme.Typography.primaryFont
        titleLabel.textColor = TrayTheme.Colors.primaryText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.cell?.truncatesLastVisibleLine = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.font = TrayTheme.Typography.secondaryFont
        timeLabel.textColor = TrayTheme.Colors.tertiaryText
        timeLabel.alignment = .right
        timeLabel.lineBreakMode = .byClipping
        timeLabel.maximumNumberOfLines = 1
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(timeLabel)

        swatchView.translatesAutoresizingMaskIntoConstraints = false
        swatchView.isHidden = true
        addSubview(swatchView)

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.image = TrayTheme.Icons.chevronRight
        chevronView.contentTintColor = .white.withAlphaComponent(0.6)
        chevronView.isHidden = true
        addSubview(chevronView)

        // Fixed constraints
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: iconSz),
            iconView.heightAnchor.constraint(equalToConstant: iconSz),

            // Lucide's chevron has ~6px of empty space on its right at 16px,
            // so it lands visually ~12px from the edge
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: TrayTheme.Icons.size),
            chevronView.heightAnchor.constraint(equalToConstant: TrayTheme.Icons.size),

            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: TrayTheme.Row.spacing),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -4),

            swatchView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            swatchView.centerYAnchor.constraint(equalTo: centerYAnchor),
            swatchView.widthAnchor.constraint(equalToConstant: TrayTheme.Icons.swatchSize),
            swatchView.heightAnchor.constraint(equalToConstant: TrayTheme.Icons.swatchSize),
        ])

        // Only active when the swatch shows, so other rows keep the full title width
        swatchTrailingLimit = swatchView.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -4)

        timeTrailingToEdge = timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad)
        timeTrailingToChevron = timeLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -8)
        timeTrailingToEdge.isActive = true

    }

    func configure(with item: ClipboardItem) {
        if item.isHidden {
            iconView.image = TrayTheme.Icons.hidden
            titleLabel.font = TrayTheme.Typography.hiddenFont
            titleLabel.stringValue = item.displayLabel
        } else {
            iconView.image = TrayTheme.Icons.itemIcon(for: item)
            titleLabel.font = TrayTheme.Typography.primaryFont
            titleLabel.stringValue = item.displayLabel
        }

        timeLabel.stringValue = item.sourceAppName ?? ""

        let swatch = item.type == .color && !item.isHidden
            ? item.metadata.colorHex.flatMap { TrayTheme.Icons.colorSwatch(hex: $0) }
            : nil
        swatchView.image = swatch
        swatchView.isHidden = swatch == nil
        swatchTrailingLimit.isActive = swatch != nil
    }

    /// The clickable area around the "›" (opens the actions menu), in this view's coordinates
    var chevronHitFrame: NSRect? {
        guard !chevronView.isHidden else { return nil }
        let minX = chevronView.frame.minX - 6
        return NSRect(x: minX, y: 0, width: bounds.maxX - minX, height: bounds.height)
    }

    func setSelected(_ selected: Bool) {
        chevronView.isHidden = !selected
        timeTrailingToEdge.isActive = !selected
        timeTrailingToChevron.isActive = selected

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
}
