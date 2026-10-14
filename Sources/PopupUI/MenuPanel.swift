import AppKit

/// One row in a MenuPanel
struct MenuEntry {
    let title: String
    /// Shown right-aligned, e.g. "⌘P"
    var shortcut: String = ""
    /// Shown right-aligned instead of a shortcut, e.g. the current value of a submenu
    var detail: String = ""
    /// Key that triggers this entry while the menu is open
    var keyCode: UInt16?
    var needsCommand = false
    var isChecked = false
    /// Highlights red instead of the accent color
    var isDestructive = false
    let perform: () -> Void
    /// Opens a submenu beside this row instead of running `perform`
    var submenu: (() -> [MenuEntry?])? = nil
}

/// A menu styled like the main popup (blur, corners, border, 30px rows, accent highlight).
/// Used for the item actions menu and the menu bar dropdown.
/// `nil` entries are separators.
final class MenuPanel: PopupPanel {

    /// Called when the menu should close (Esc, ←, or after an entry runs)
    var onClose: (() -> Void)? {
        get { menuController.onClose }
        set { menuController.onClose = newValue }
    }

    /// Called after an entry runs; defaults to `onClose`. A submenu uses this
    /// to close its parent menu too.
    var onPerformed: (() -> Void)? {
        get { menuController.onPerformed }
        set { menuController.onPerformed = newValue }
    }

    private let menuController: MenuViewController
    private let width: CGFloat

    init(entries: [MenuEntry?], width: CGFloat = TrayTheme.ActionMenu.width, tint: NSColor? = nil) {
        self.width = width
        menuController = MenuViewController(entries: entries, width: width, tint: tint)
        super.init(width: width)
        contentViewController = menuController
    }

    private var visibleSize: NSSize {
        NSSize(width: width, height: menuController.contentHeight)
    }

    /// Shows the menu beside `parentFrame`, level with the row it belongs to (screen coordinates).
    /// `takeFocus: false` leaves keyboard focus where it is (a submenu opened by hovering).
    func show(besideRow rowFrame: NSRect, in parentFrame: NSRect, takeFocus: Bool = true) {
        place(size: visibleSize, besideRow: rowFrame, of: parentFrame, margin: TrayTheme.Appear.margin)
        present(takeFocus: takeFocus)
    }

    /// Gives the menu keyboard focus with its first row highlighted
    func focusFirstEntry() {
        makeKey()
        makeFirstResponder(menuController)
        menuController.selectFirstEntry()
    }

    /// Shows the menu just below `anchor` (e.g. a menu bar icon), left edges aligned (screen coordinates)
    func show(below anchor: NSRect) {
        let size = visibleSize
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        let x = max(visible.minX + 4, min(anchor.minX, visible.maxX - size.width - 4))
        let y = anchor.minY - TrayTheme.StatusMenu.gap - size.height
        let m = TrayTheme.Appear.margin
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height).insetBy(dx: -m, dy: -m), display: true)
        present()
    }

    private func present(takeFocus: Bool = true) {
        if takeFocus {
            makeKeyAndOrderFront(nil)
            makeFirstResponder(menuController)
        } else {
            orderFront(nil)
        }
        startForwardingEvents()
        // Menus appear instantly; only the main popup animates in
    }

    func dismiss() {
        for child in childWindows ?? [] { (child as? MenuPanel)?.dismiss() } // open submenu
        stopForwardingEvents()
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}

// MARK: - Item actions

extension MenuEntry {
    /// Pin / Hide / Rename / Delete for a clipboard item; nil marks a separator
    static func actions(for item: ClipboardItem, perform: @escaping (ClipboardAction) -> Void) -> [MenuEntry?] {
        var entries: [MenuEntry?] = [
            MenuEntry(title: item.isPinned ? "Unpin" : "Pin", shortcut: "⌘P", keyCode: 35, needsCommand: true) {
                perform(item.isPinned ? .unpin : .pin)
            },
            MenuEntry(title: item.isHidden ? "Unhide" : "Hide", shortcut: "⌘H", keyCode: 4, needsCommand: true) {
                perform(item.isHidden ? .unhide : .hide)
            },
        ]
        if item.isHidden {
            entries.append(MenuEntry(title: "Rename", shortcut: "⌘R", keyCode: 15, needsCommand: true) {
                perform(.rename(""))
            })
        }
        entries.append(nil)
        entries.append(MenuEntry(title: "Delete", shortcut: "⌫", keyCode: 51, isDestructive: true) {
            perform(.delete)
        })
        return entries
    }
}

// MARK: - Controller

private final class MenuViewController: NSViewController {

    var onClose: (() -> Void)?
    var onPerformed: (() -> Void)?

    private let entries: [MenuEntry?]
    private let width: CGFloat
    private let tint: NSColor?
    private var rowViews: [NSView] = []
    private var selectedIndex = -1
    private var submenu: MenuPanel?
    private var submenuIndex: Int?

    init(entries: [MenuEntry?], width: CGFloat, tint: NSColor?) {
        self.entries = entries
        self.width = width
        self.tint = tint
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static let separatorHeight = TrayTheme.Row.separatorHeight + 8

    var contentHeight: CGFloat {
        let rows = entries.reduce(0) { $0 + ($1 == nil ? Self.separatorHeight : TrayTheme.Row.height) }
        return rows + TrayTheme.Spacing.contentInset * 2
    }

    override func loadView() {
        let m = TrayTheme.Appear.margin
        let chrome = PopupChrome.make(width: width, cornerRadius: TrayTheme.ActionMenu.cornerRadius, tint: tint)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width + m * 2, height: contentHeight + m * 2))
        chrome.root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(chrome.root)
        NSLayoutConstraint.activate([
            chrome.root.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            chrome.root.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m),
            chrome.root.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            chrome.root.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
        ])
        view = root

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        chrome.content.addSubview(stack)

        let pad = TrayTheme.Spacing.contentInset
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: chrome.content.topAnchor, constant: pad),
            stack.leadingAnchor.constraint(equalTo: chrome.content.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: chrome.content.trailingAnchor, constant: -pad),
        ])

        // Leave room for checkmarks only when some entry can be checked
        let hasChecks = entries.contains { $0?.isChecked == true }
        let rowWidth = width - pad * 2
        for entry in entries {
            let row: NSView
            if let entry {
                let cell = MenuRowView(showsCheckColumn: hasChecks)
                cell.configure(with: entry)
                row = cell
            } else {
                row = SeparatorCellView()
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalToConstant: rowWidth),
                row.heightAnchor.constraint(equalToConstant: entry == nil ? Self.separatorHeight : TrayTheme.Row.height),
            ])
            rowViews.append(row)
        }

        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override var acceptsFirstResponder: Bool { true }

    // MARK: Mouse

    private func rowIndex(at event: NSEvent) -> Int? {
        let point = view.convert(event.locationInWindow, from: nil)
        for (i, row) in rowViews.enumerated() where entries[i] != nil {
            if row.convert(row.bounds, to: view).contains(point) { return i }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard let i = rowIndex(at: event), i != selectedIndex else { return }
        setSelection(i)
        // Hovering a submenu row opens it (focus stays here); any other row closes it
        if entries[i]?.submenu != nil {
            openSubmenu(at: i, takeFocus: false)
        } else {
            closeSubmenu(refocus: false)
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Keep the submenu's row highlighted while the mouse is over the submenu
        if submenu == nil { setSelection(-1) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let i = rowIndex(at: event) else { return }
        setSelection(i)
        perform(at: i)
    }

    override func rightMouseDown(with event: NSEvent) {
        mouseDown(with: event)
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let hasCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        switch event.keyCode {
        case 53, 123: onClose?()                                          // Esc, ←
        case 36, 76: if selectedIndex >= 0 { perform(at: selectedIndex) } // Return, Enter
        case 124:                                                         // → opens a submenu
            if selectedIndex >= 0, entries[selectedIndex]?.submenu != nil { openSubmenu(at: selectedIndex, takeFocus: true) }
        case 126: moveSelection(by: -1)                                   // ↑
        case 125: moveSelection(by: 1)                                    // ↓
        default:
            if let i = entries.firstIndex(where: { $0?.keyCode == event.keyCode && $0?.needsCommand == hasCommand }) {
                perform(at: i)
            }
        }
    }

    func selectFirstEntry() {
        if let i = entries.firstIndex(where: { $0 != nil }) { setSelection(i) }
    }

    private func moveSelection(by delta: Int) {
        var next = selectedIndex < 0 ? (delta > 0 ? 0 : entries.count - 1) : selectedIndex + delta
        while next >= 0 && next < entries.count && entries[next] == nil { next += delta }
        if next >= 0 && next < entries.count { setSelection(next) }
    }

    /// Closes the menu, then runs the entry (like native menus). Submenu rows open their submenu.
    private func perform(at index: Int) {
        guard let entry = entries[index] else { return }
        if entry.submenu != nil {
            openSubmenu(at: index, takeFocus: true)
            return
        }
        (onPerformed ?? onClose)?()
        entry.perform()
    }

    // MARK: Submenu

    private func openSubmenu(at index: Int, takeFocus: Bool) {
        guard let makeEntries = entries[index]?.submenu, let window = view.window else { return }
        if submenuIndex == index, let open = submenu {
            if takeFocus { open.focusFirstEntry() }
            return
        }
        closeSubmenu(refocus: false)

        let panel = MenuPanel(entries: makeEntries(), width: TrayTheme.StatusMenu.submenuWidth, tint: tint)
        panel.onClose = { [weak self] in self?.closeSubmenu(refocus: true) }
        panel.onPerformed = { [weak self] in
            self?.closeSubmenu(refocus: false)
            (self?.onPerformed ?? self?.onClose)?() // choosing in the submenu closes the whole menu
        }
        window.addChildWindow(panel, ordered: .above)
        let row = rowViews[index]
        let rowOnScreen = window.convertToScreen(row.convert(row.bounds, to: nil))
        let m = TrayTheme.Appear.margin
        panel.show(besideRow: rowOnScreen, in: window.frame.insetBy(dx: m, dy: m), takeFocus: takeFocus)
        if takeFocus { panel.focusFirstEntry() }
        submenu = panel
        submenuIndex = index
    }

    private func closeSubmenu(refocus: Bool) {
        guard let open = submenu else { return }
        open.dismiss()
        submenu = nil
        submenuIndex = nil
        if refocus {
            view.window?.makeKey()
            view.window?.makeFirstResponder(self)
        }
    }

    private func setSelection(_ index: Int) {
        if selectedIndex >= 0, let row = rowViews[selectedIndex] as? MenuRowView { row.setSelected(false) }
        selectedIndex = index
        if selectedIndex >= 0, let row = rowViews[selectedIndex] as? MenuRowView { row.setSelected(true) }
    }
}

// MARK: - Row

/// [✓?] [title...] [shortcut or detail] [› for submenus]
private final class MenuRowView: NSView {

    private let checkView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private var shortcutTrailingToEdge: NSLayoutConstraint!
    private var shortcutTrailingToChevron: NSLayoutConstraint!
    private var isDestructive = false

    init(showsCheckColumn: Bool) {
        super.init(frame: .zero)
        wantsLayer = true

        let pad = TrayTheme.Row.horizontalPadding
        for v in [checkView, titleLabel, shortcutLabel, chevronView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        checkView.image = TrayTheme.Icons.check
        checkView.imageScaling = .scaleProportionallyDown
        chevronView.image = TrayTheme.Icons.chevronRight
        chevronView.isHidden = true
        titleLabel.font = TrayTheme.Typography.primaryFont
        shortcutLabel.font = TrayTheme.Typography.shortcutFont

        let titleLeading = showsCheckColumn
            ? titleLabel.leadingAnchor.constraint(equalTo: checkView.trailingAnchor, constant: 6)
            : titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad)
        NSLayoutConstraint.activate([
            checkView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            checkView.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkView.widthAnchor.constraint(equalToConstant: TrayTheme.Icons.checkSize),
            checkView.heightAnchor.constraint(equalToConstant: TrayTheme.Icons.checkSize),

            titleLeading,
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: shortcutLabel.leadingAnchor, constant: -8),

            shortcutLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Same placement as the "›" on clipboard rows
            chevronView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: TrayTheme.Icons.size),
            chevronView.heightAnchor.constraint(equalToConstant: TrayTheme.Icons.size),
        ])
        shortcutTrailingToEdge = shortcutLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad)
        shortcutTrailingToChevron = shortcutLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -2)
        shortcutTrailingToEdge.isActive = true
        setSelected(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(with entry: MenuEntry) {
        titleLabel.stringValue = entry.title
        shortcutLabel.stringValue = entry.detail.isEmpty ? entry.shortcut : entry.detail
        let hasSubmenu = entry.submenu != nil
        chevronView.isHidden = !hasSubmenu
        shortcutTrailingToEdge.isActive = !hasSubmenu
        shortcutTrailingToChevron.isActive = hasSubmenu
        // ⌫ draws small next to letters at the same size
        shortcutLabel.font = entry.shortcut == "⌫"
            ? TrayTheme.Typography.deleteGlyphFont
            : TrayTheme.Typography.shortcutFont
        checkView.isHidden = !entry.isChecked
        isDestructive = entry.isDestructive
    }

    func setSelected(_ selected: Bool) {
        if selected {
            let color = isDestructive ? TrayTheme.Colors.destructiveSelection : TrayTheme.Colors.selection
            layer?.backgroundColor = color.cgColor
            layer?.cornerRadius = TrayTheme.Row.selectionCornerRadius
            titleLabel.textColor = .white
            shortcutLabel.textColor = .white.withAlphaComponent(0.5)
            checkView.contentTintColor = .white
            chevronView.contentTintColor = .white.withAlphaComponent(0.6)
        } else {
            layer?.backgroundColor = nil
            titleLabel.textColor = TrayTheme.Colors.primaryText
            shortcutLabel.textColor = TrayTheme.Colors.tertiaryText
            checkView.contentTintColor = TrayTheme.Colors.primaryText
            chevronView.contentTintColor = TrayTheme.Colors.tertiaryText
        }
    }
}
