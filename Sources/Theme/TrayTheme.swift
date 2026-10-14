import AppKit

/// Centralized theme for all Tray UI. Modify this file to change the entire look.
/// All UI components read from TrayTheme — no hardcoded values anywhere else.
enum TrayTheme {

    // MARK: - Window

    enum Window {
        static let width: CGFloat = 260
        /// Concentric with rows: selection radius + content inset
        static let cornerRadius: CGFloat = 24
        static let material: NSVisualEffectView.Material = .menu
        static let blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
        static let state: NSVisualEffectView.State = .active
    }

    // MARK: - Borders

    enum Border {
        static let outerColor: NSColor = .labelColor.withAlphaComponent(0.16)
        static let outerWidth: CGFloat = 0.5
    }

    // MARK: - Rows

    enum Row {
        /// All rows same height — single line, matches native menu item
        static let height: CGFloat = 30
        static let actionHeight: CGFloat = 30
        static let separatorHeight: CGFloat = 1
        static let horizontalPadding: CGFloat = 10
        static let iconSize: CGFloat = 16
        static let spacing: CGFloat = 10
        /// Vertical gap between rows
        static let gap: CGFloat = 0
        /// Space between the end of the list and the "Clear all" footer
        static let footerGap: CGFloat = 6
        static let selectionCornerRadius: CGFloat = 8
    }

    // MARK: - Typography

    enum Typography {
        static let primaryFont: NSFont = .menuFont(ofSize: 13)
        static let secondaryFont: NSFont = .menuFont(ofSize: 10)
        /// Keyboard shortcuts in the actions menu, same size as the title like native menus
        static let shortcutFont: NSFont = .menuFont(ofSize: 13)
        /// ⌫ draws small next to letters at the same size
        static let deleteGlyphFont: NSFont = .menuFont(ofSize: 15)
        static let actionFont: NSFont = .menuFont(ofSize: 13)
        static let emptyStateFont: NSFont = .systemFont(ofSize: 12, weight: .medium)
        static let hiddenFont: NSFont = {
            let descriptor = NSFont.systemFont(ofSize: 13).fontDescriptor.withSymbolicTraits(.italic)
            return NSFont(descriptor: descriptor, size: 13) ?? .systemFont(ofSize: 13)
        }()
    }

    // MARK: - Colors (all semantic — auto adapt to dark/light mode)

    enum Colors {
        static let primaryText: NSColor = .labelColor
        static let secondaryText: NSColor = .secondaryLabelColor
        static let tertiaryText: NSColor = .tertiaryLabelColor
        static let iconTint: NSColor = .tertiaryLabelColor
        static let separator: NSColor = .labelColor.withAlphaComponent(0.06)
        /// Native macOS selection blue
        static let selection: NSColor = .controlAccentColor
        /// Highlight for destructive rows like "Clear all"
        static let destructiveSelection: NSColor = .systemRed
    }

    // MARK: - Icons (Lucide)

    enum Icons {
        static let size: CGFloat = 16

        static let chevronRight = LucideIcon.chevronRight.image(size: size)
        static let checkSize: CGFloat = 14
        static let check = LucideIcon.check.image(size: checkSize)
        static let hidden = LucideIcon.eyeOff.image(size: size)

        static let swatchSize: CGFloat = 12
        static let swatchCornerRadius: CGFloat = 2

        static func itemIcon(for item: ClipboardItem) -> NSImage? {
            if isEmailAddress(item) {
                return LucideIcon.mail.image(size: size)
            }
            return item.type.icon.image(size: size)
        }

        private static let emailPattern = try! NSRegularExpression(
            pattern: #"^(mailto:)?[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
            options: .caseInsensitive
        )

        /// A clip that is exactly one email address (or a mailto: link).
        private static func isEmailAddress(_ item: ClipboardItem) -> Bool {
            guard item.type == .plainText || item.type == .url else { return false }
            let text = item.contentPreview.trimmingCharacters(in: .whitespacesAndNewlines)
            let range = NSRange(text.startIndex..., in: text)
            return emailPattern.firstMatch(in: text, range: range) != nil
        }

        /// "#RRGGBB" → sRGB color
        static func color(hex: String) -> NSColor? {
            let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }

        /// Filled rounded square in the copied color, shown after the hex text.
        /// Display only; never part of what gets pasted. The hairline edge keeps
        /// white and near-background colors visible.
        static func colorSwatch(hex: String) -> NSImage? {
            guard let color = color(hex: hex) else { return nil }
            return NSImage(size: NSSize(width: swatchSize, height: swatchSize), flipped: false) { rect in
                let path = NSBezierPath(
                    roundedRect: rect.insetBy(dx: 0.25, dy: 0.25),
                    xRadius: swatchCornerRadius,
                    yRadius: swatchCornerRadius
                )
                color.setFill()
                path.fill()
                NSColor.black.withAlphaComponent(0.15).setStroke()
                path.lineWidth = 0.5
                path.stroke()
                return true
            }
        }
    }

    // MARK: - Actions menu

    enum ActionMenu {
        static let width: CGFloat = 170
        /// Selection radius + content inset, so the row highlights nest evenly
        static let cornerRadius: CGFloat = 16
    }

    // MARK: - Menu bar dropdown

    enum StatusMenu {
        static let width: CGFloat = 210
        static let submenuWidth: CGFloat = 130
        /// Extra darkening over the blur's built-in tint (macOS's menu material already
        /// tints dark in dark mode, light in light mode): black at 15% dark, 5% light
        static let tint = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor.black.withAlphaComponent(isDark ? 0.15 : 0.05)
        }
        /// Space between the menu bar icon and the dropdown
        static let gap: CGFloat = 6
    }

    // MARK: - Side panels (actions menu, preview)

    enum SidePanel {
        /// Space between the main popup and a panel opened beside it
        static let gap: CGFloat = 4
    }

    // MARK: - Preview

    enum Preview {
        static let hoverDelay: TimeInterval = 0.6
        /// Images scale down to fit inside this box
        static let maxImageSize = NSSize(width: 320, height: 320)
        /// Content hugs its size up to this width; longer text wraps
        static let maxWidth: CGFloat = 300
        static let maxTextLines = 4
        static let swatchSize: CGFloat = 40
        static let imageCornerRadius: CGFloat = 8
        static let textFont: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
        static let metaFont: NSFont = .menuFont(ofSize: 11)
    }

    // MARK: - Scroller

    enum Scroller {
        static let knobWidth: CGFloat = 4
        static let knobInset: CGFloat = 2
        /// How far the scroll area extends past the content padding on the right,
        /// so the knob sits closer to the window edge than the rows do
        static let trailingOutset: CGFloat = 4
        static let knobColor: NSColor = .tertiaryLabelColor
    }

    // MARK: - Appear animation

    /// Entrance: fades in while growing from slightly smaller,
    /// overshoots just past full size, then springs back to 100%
    enum Appear {
        /// Mostly vertical: height starts 6% shorter, width only 1% narrower
        static let fromScaleX: CGFloat = 0.99
        static let fromScaleY: CGFloat = 0.94
        /// The hover preview springs sideways instead: starts 6% narrower,
        /// growing out from the edge next to the popup
        static let previewFromScaleX: CGFloat = 0.94
        /// Damping ratio ≈ 0.55 (17.4 / (2 * √250)): overshoots to ~1.008, then settles in ~0.45s
        static let stiffness: CGFloat = 250
        static let damping: CGFloat = 17.4
        static let fadeDuration: TimeInterval = 0.2
        /// Transparent space around the popup so the overshoot isn't clipped by the window
        static let margin: CGFloat = 12
    }

    // MARK: - Spacing

    enum Spacing {
        /// Padding between the outer border and the inner content area
        static let contentInset: CGFloat = 8
    }
}
