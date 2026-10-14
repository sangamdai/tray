import AppKit

/// 1px separator row, drawn in TrayTheme.Colors.separator
final class SeparatorCellView: NSTableCellView {

    override func draw(_ dirtyRect: NSRect) {
        let pad = TrayTheme.Row.horizontalPadding
        let line = NSRect(
            x: pad,
            y: (bounds.height - TrayTheme.Row.separatorHeight) / 2,
            width: bounds.width - pad * 2,
            height: TrayTheme.Row.separatorHeight
        )
        TrayTheme.Colors.separator.setFill()
        line.fill(using: .sourceOver)
    }
}
