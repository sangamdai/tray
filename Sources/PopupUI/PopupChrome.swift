import AppKit

/// The rounded, blurred, bordered background shared by the main popup and the actions menu.
enum PopupChrome {

    /// Returns the root view to install as the controller's view, and the
    /// effect view that content should be added to (it clips to the rounded corners).
    /// `tint`, if given, is laid over the blur to shift its color (e.g. darker).
    /// Content goes in the returned `content` view, above the blur and tint.
    static func make(
        width: CGFloat,
        cornerRadius: CGFloat = TrayTheme.Window.cornerRadius,
        tint: NSColor? = nil
    ) -> (root: NSView, content: NSView) {
        // Wrapper view — transparent, holds the background layers, content, and border overlay
        let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        wrapper.wantsLayer = true

        // Effect view — native macOS blur, background only
        let effectView = NSVisualEffectView(frame: .zero)
        effectView.material = TrayTheme.Window.material
        effectView.blendingMode = TrayTheme.Window.blendingMode
        effectView.state = TrayTheme.Window.state

        // Content container — clips everything to the rounded rect
        let content = NSView(frame: .zero)

        var layers: [NSView] = [effectView]
        if let tint { layers.append(TintView(color: tint)) }
        layers.append(content)

        // Border overlay — sits on top, NOT inside the clipped views
        let borderView = RoundedBorderView(cornerRadius: cornerRadius)
        layers.append(borderView)

        for v in layers {
            v.translatesAutoresizingMaskIntoConstraints = false
            if v !== borderView {
                v.wantsLayer = true
                v.layer?.cornerRadius = cornerRadius
                v.layer?.masksToBounds = true
            }
            wrapper.addSubview(v)
            NSLayoutConstraint.activate([
                v.topAnchor.constraint(equalTo: wrapper.topAnchor),
                v.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
                v.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            ])
        }

        return (wrapper, content)
    }
}

/// Fills with a color, resolved at draw time so light/dark variants follow the appearance
private final class TintView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill(using: .sourceOver)
    }
}

/// Draws a rounded border using NSBezierPath — avoids layer border rectangle issues
private final class RoundedBorderView: NSView {
    private let radius: CGFloat

    init(cornerRadius: CGFloat) {
        radius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let lineWidth = TrayTheme.Border.outerWidth
        let inset = lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.lineWidth = lineWidth
        TrayTheme.Border.outerColor.setStroke()
        path.stroke()
    }
}

/// Borderless, transparent, non-activating panel that floats above everything.
/// Base for the main popup and the actions menu.
class PopupPanel: NSPanel {

    init(width: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false
        level = .init(Int(CGWindowLevelForKey(.maximumWindow)))
        // The system shadow draws a hard outline around borderless windows; our border replaces it
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Spotlight-style entrance for `view` (which must sit inside the window with
    /// TrayTheme.Appear.margin around it): fades `view` in while it scales from
    /// the given scale to 100% on a spring, with a slight overshoot.
    /// Call right after ordering the panel front.
    /// `anchor` (in `view`'s coordinates) stays fixed while scaling; defaults to the center.
    func animateAppearance(of view: NSView, fromScaleX: CGFloat, fromScaleY: CGFloat, anchor: CGPoint? = nil) {
        view.wantsLayer = true
        if let layer = view.layer {
            let pivot = anchor ?? CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            var from = CATransform3DMakeTranslation(pivot.x, pivot.y, 0)
            from = CATransform3DScale(from, fromScaleX, fromScaleY, 1)
            from = CATransform3DTranslate(from, -pivot.x, -pivot.y, 0)

            let spring = CASpringAnimation(keyPath: "transform")
            spring.fromValue = NSValue(caTransform3D: from)
            spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            spring.stiffness = TrayTheme.Appear.stiffness
            spring.damping = TrayTheme.Appear.damping
            spring.duration = spring.settlingDuration
            layer.add(spring, forKey: "appear")

            // Fade on the layer, not the window: animating the window's alphaValue
            // jumped straight to 1 (measured), so the fade never showed
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = TrayTheme.Appear.fadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: "appearFade")
        }
        alphaValue = 1
    }

    enum RowAlignment {
        /// The panel's first row lines up with the row (menus)
        case firstRow
        /// The panel is vertically centered on the row (previews)
        case centered
    }

    /// Places this panel beside `parentFrame` (right, or left if there's no room),
    /// aligned to `rowFrame`. Both in screen coordinates. `size` is the visible panel;
    /// `margin` is extra transparent window space around it. Returns true if placed on the right.
    @discardableResult
    func place(size: NSSize, besideRow rowFrame: NSRect, of parentFrame: NSRect,
               alignment: RowAlignment = .firstRow, margin: CGFloat = 0) -> Bool {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(parentFrame) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? parentFrame
        let gap = TrayTheme.SidePanel.gap

        var x = parentFrame.maxX + gap
        if x + size.width > visible.maxX {
            x = parentFrame.minX - gap - size.width
        }
        let preferredY: CGFloat
        switch alignment {
        case .firstRow: preferredY = rowFrame.maxY + TrayTheme.Spacing.contentInset - size.height
        case .centered: preferredY = rowFrame.midY - size.height / 2
        }
        let y = max(visible.minY + 4, min(preferredY, visible.maxY - size.height - 4))
        let rect = NSRect(origin: NSPoint(x: x, y: y), size: size)
        setFrame(rect.insetBy(dx: -margin, dy: -margin), display: true)
        return x > parentFrame.minX
    }

    // MARK: - Event forwarding

    private var localEventMonitor: Any?

    /// Forwards key and mouse-down events in this panel to its view controller.
    /// Non-activating panels don't reliably route these through the responder chain.
    func startForwardingEvents() {
        guard localEventMonitor == nil else { return }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, event.window === self, let vc = self.contentViewController else { return event }
            switch event.type {
            case .keyDown: vc.keyDown(with: event)
            case .leftMouseDown: vc.mouseDown(with: event)
            case .rightMouseDown: vc.rightMouseDown(with: event)
            default: return event
            }
            return nil // consumed
        }
    }

    func stopForwardingEvents() {
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
    }

    deinit {
        stopForwardingEvents()
    }
}
