import AppKit

/// Centered text-only action row, e.g. "Clear all"
final class ActionRowCellView: NSTableCellView {

    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = TrayTheme.Typography.actionFont
        titleLabel.textColor = TrayTheme.Colors.secondaryText
        addSubview(titleLabel)

        let pad = TrayTheme.Row.horizontalPadding
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: pad),
        ])
    }

    func configure(title: String) {
        titleLabel.stringValue = title
        titleLabel.textColor = TrayTheme.Colors.secondaryText
    }

    func setSelected(_ selected: Bool) {
        if selected {
            layer?.backgroundColor = TrayTheme.Colors.destructiveSelection.cgColor
            layer?.cornerRadius = TrayTheme.Row.selectionCornerRadius
            titleLabel.textColor = .white
        } else {
            layer?.backgroundColor = nil
            titleLabel.textColor = TrayTheme.Colors.secondaryText
        }
    }
}
