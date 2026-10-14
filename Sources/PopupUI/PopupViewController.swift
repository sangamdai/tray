import AppKit
import os

private let logger = Logger(subsystem: "com.tray.app", category: "PopupViewController")

/// Row types in the menu
enum PopupRow {
    case clipboardItem(ClipboardItem)
    case separator
    case clearAll
}

/// Rows visible before the list scrolls
private let maxVisibleRows = 8

/// Overlay scroller with a thin knob and no track
private final class ThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        let width = TrayTheme.Scroller.knobWidth
        let rect = NSRect(
            x: bounds.maxX - width - TrayTheme.Scroller.knobInset,
            y: knob.minY + TrayTheme.Scroller.knobInset,
            width: width,
            height: max(knob.height - TrayTheme.Scroller.knobInset * 2, width)
        )
        TrayTheme.Scroller.knobColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: width / 2, yRadius: width / 2).fill()
    }
}

/// Top-to-bottom document view for the scrolling list
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The main list controller for the popup. Clipboard items scroll; "Clear all" stays pinned below.
final class PopupViewController: NSViewController {

    // MARK: - Callbacks

    var onItemSelected: ((ClipboardItem) -> Void)?
    var onAction: ((ClipboardAction, ClipboardItem) -> Void)?
    var onDismissRequested: (() -> Void)?
    var onClearAll: (() -> Void)?
    /// Loads an item's full data (e.g. image bytes) for the preview panel
    var previewDataProvider: ((ClipboardItem) -> ClipboardItemData?)?

    // MARK: - UI

    private var effectView: NSView!
    private let scrollView = NSScrollView()
    private let listStack = NSStackView()
    private let footerStack = NSStackView()
    private var scrollHeightConstraint: NSLayoutConstraint!
    private var footerTopConstraint: NSLayoutConstraint!
    private let emptyLabel = NSTextField(labelWithString: "")
    private var stackTopConstraint: NSLayoutConstraint!
    /// Padding above the first row lives inside the scroll view, so rows scroll
    /// up to the window edge instead of being cut off at the padding line
    private var listTopConstraint: NSLayoutConstraint!

    // MARK: - Data

    private var rows: [PopupRow] = []
    private var rowViews: [NSView] = []
    private var pinnedItems: [ClipboardItem] = []
    private var recentItems: [ClipboardItem] = []
    private var selectedIndex: Int = -1
    /// Trailing rows that live in the fixed footer instead of the scroll view
    private var footerRowCount = 0
    /// Open actions menu, if any. While open, it has keyboard focus.
    private var actionMenu: MenuPanel?

    /// Preview beside the popup, shown after resting on a row for TrayTheme.Preview.hoverDelay
    private var previewPanel: PreviewPanel?
    private var previewTimer: Timer?
    /// True while we scroll the list ourselves (keyboard, reload), so it isn't treated as the user scrolling
    private var isScrollingProgrammatically = false

    // MARK: - Lifecycle

    /// The visible popup (rounded, blurred, bordered). The window is larger by
    /// TrayTheme.Appear.margin on every side, transparent, so the entrance can scale up.
    private(set) var chromeView: NSView!

    /// The visible popup's frame on screen (the window minus its transparent margin)
    var visibleFrameOnScreen: NSRect {
        guard let window = view.window else { return .zero }
        let m = TrayTheme.Appear.margin
        return window.frame.insetBy(dx: m, dy: m)
    }

    override func loadView() {
        let m = TrayTheme.Appear.margin
        let chrome = PopupChrome.make(width: TrayTheme.Window.width)
        let root = NSView(frame: NSRect(x: 0, y: 0, width: TrayTheme.Window.width + m * 2, height: 100))
        chrome.root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(chrome.root)
        NSLayoutConstraint.activate([
            chrome.root.topAnchor.constraint(equalTo: root.topAnchor, constant: m),
            chrome.root.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -m),
            chrome.root.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: m),
            chrome.root.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -m),
        ])
        self.view = root
        self.chromeView = chrome.root
        self.effectView = chrome.content

        setupList()
        setupFooter()
        setupEmptyState()
        setupMouseTracking()
    }

    // MARK: - Public

    func update(pinned: [ClipboardItem], recent: [ClipboardItem]) {
        self.pinnedItems = pinned
        self.recentItems = recent
        rebuildRows()
        rebuildViews()
        resizeToFit()
        selectFirstRecentItem()
    }

    // MARK: - Setup

    private func setupList() {
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = TrayTheme.Row.gap

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(listStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.verticalScroller = ThinScroller()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.documentView = documentView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(listDidScroll),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        effectView.addSubview(scrollView)

        let pad = TrayTheme.Spacing.contentInset
        stackTopConstraint = scrollView.topAnchor.constraint(equalTo: effectView.topAnchor)
        listTopConstraint = listStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: pad)
        scrollHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            stackTopConstraint,
            scrollHeightConstraint,
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: pad),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -pad + TrayTheme.Scroller.trailingOutset),

            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),

            listTopConstraint,
            listStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
    }

    private func setupFooter() {
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.orientation = .vertical
        footerStack.alignment = .leading
        footerStack.spacing = TrayTheme.Row.gap
        effectView.addSubview(footerStack)

        let pad = TrayTheme.Spacing.contentInset
        footerTopConstraint = footerStack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: TrayTheme.Row.footerGap)
        NSLayoutConstraint.activate([
            footerTopConstraint,
            footerStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: pad),
            footerStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -pad),
        ])
    }

    private func setupEmptyState() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.stringValue = "No clipboard history yet.\nCopy something!"
        emptyLabel.font = TrayTheme.Typography.emptyStateFont
        emptyLabel.textColor = TrayTheme.Colors.tertiaryText
        emptyLabel.alignment = .center
        emptyLabel.maximumNumberOfLines = 2
        emptyLabel.isHidden = true
        effectView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
        ])
    }

    private func setupMouseTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
    }

    // MARK: - Mouse

    /// Index of the selectable row under `point` (in `view` coordinates).
    /// List rows only count inside the scroll view's visible area.
    private func rowIndex(at point: NSPoint) -> Int? {
        let listFrame = scrollView.convert(scrollView.bounds, to: view)
        for (i, rowView) in rowViews.enumerated() {
            if case .separator = rows[i] { continue }
            if !isFooterRow(i) && !listFrame.contains(point) { continue }
            if rowView.convert(rowView.bounds, to: view).contains(point) { return i }
        }
        return nil
    }

    override func mouseMoved(with event: NSEvent) {
        guard actionMenu == nil else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        guard let i = rowIndex(at: point) else {
            NSCursor.arrow.set()
            return
        }
        let rowChanged = i != selectedIndex
        if rowChanged { setSelection(i) }

        (chevronHitFrame(at: point) != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
        if rowChanged || (previewTimer == nil && previewPanel?.isVisible != true) {
            // New row (follow or start the timer), or resting with nothing pending
            selectionChangedByUser()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        hidePreview()
    }

    /// The "›" hit area under `point` (in row coordinates), with its row index
    private func chevronHitFrame(at point: NSPoint) -> (row: Int, frame: NSRect)? {
        guard let i = rowIndex(at: point),
              let cell = rowViews[i] as? ClipboardItemCellView,
              let frame = cell.chevronHitFrame,
              frame.contains(cell.convert(point, from: view)) else { return nil }
        return (i, frame)
    }

    override func mouseDown(with event: NSEvent) {
        let point = view.convert(event.locationInWindow, from: nil)
        // A click in the popup while the menu is open just closes the menu
        if actionMenu != nil {
            closeActionMenu()
            return
        }
        if let hit = chevronHitFrame(at: point) {
            showActionMenu(forRow: hit.row)
            return
        }
        guard let i = rowIndex(at: point) else { return }
        setSelection(i)
        handleSelection()
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = view.convert(event.locationInWindow, from: nil)
        guard let i = rowIndex(at: point), case .clipboardItem = rows[i] else { return }
        showActionMenu(forRow: i)
    }

    // MARK: - Row Building

    private func rebuildRows() {
        rows.removeAll()

        let hasPinned = !pinnedItems.isEmpty
        let hasRecent = !recentItems.isEmpty

        rows.append(contentsOf: pinnedItems.map { .clipboardItem($0) })
        if hasPinned && hasRecent { rows.append(.separator) }
        rows.append(contentsOf: recentItems.map { .clipboardItem($0) })

        footerRowCount = 0
        if hasPinned || hasRecent {
            rows.append(.separator)
            rows.append(.clearAll)
            footerRowCount = 2
        }

        emptyLabel.isHidden = hasPinned || hasRecent
    }

    private func isFooterRow(_ index: Int) -> Bool {
        index >= rows.count - footerRowCount
    }

    private func height(of row: PopupRow) -> CGFloat {
        switch row {
        case .clipboardItem: return TrayTheme.Row.height
        case .separator: return TrayTheme.Row.separatorHeight + 8
        case .clearAll: return TrayTheme.Row.actionHeight
        }
    }

    /// Stacked height of rows including the gaps between them
    private func stackedHeight(_ rows: ArraySlice<PopupRow>) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(0) { $0 + height(of: $1) } + TrayTheme.Row.gap * CGFloat(rows.count - 1)
    }

    private func rebuildViews() {
        // Remove old views
        hidePreview()
        for v in rowViews { v.removeFromSuperview() }
        isScrollingProgrammatically = true
        scrollView.contentView.scroll(to: .zero)
        isScrollingProgrammatically = false
        rowViews.removeAll()
        selectedIndex = -1

        let cellWidth = TrayTheme.Window.width - TrayTheme.Spacing.contentInset * 2

        for (index, row) in rows.enumerated() {
            let rowView: NSView

            switch row {
            case .clipboardItem(let item):
                let cell = ClipboardItemCellView()
                cell.configure(with: item)
                cell.setSelected(false)
                rowView = cell

            case .separator:
                let cell = SeparatorCellView()
                rowView = cell

            case .clearAll:
                let cell = ActionRowCellView()
                cell.configure(title: "Clear all")
                cell.setSelected(false)
                rowView = cell

            }

            rowView.translatesAutoresizingMaskIntoConstraints = false
            (isFooterRow(index) ? footerStack : listStack).addArrangedSubview(rowView)
            NSLayoutConstraint.activate([
                rowView.widthAnchor.constraint(equalToConstant: cellWidth),
                rowView.heightAnchor.constraint(equalToConstant: height(of: row)),
            ])
            rowViews.append(rowView)
        }
    }

    // MARK: - Window Sizing

    private func resizeToFit() {
        let listRows = rows[..<(rows.count - footerRowCount)]
        let footerRows = rows[(rows.count - footerRowCount)...]

        // Cap the list at maxVisibleRows item rows; anything beyond scrolls
        let maxListHeight = TrayTheme.Row.height * CGFloat(maxVisibleRows)
            + TrayTheme.Row.gap * CGFloat(maxVisibleRows - 1)
        let listHeight = min(stackedHeight(listRows), maxListHeight)
        let footerHeight = stackedHeight(footerRows)
        scrollHeightConstraint.constant = listTopConstraint.constant + listHeight
        footerTopConstraint.constant = footerRows.isEmpty ? 0 : TrayTheme.Row.footerGap

        var contentHeight = listTopConstraint.constant + listHeight
        if !footerRows.isEmpty {
            contentHeight += TrayTheme.Row.footerGap + footerHeight
        }

        if rows.isEmpty {
            contentHeight = 80
        }

        let m = TrayTheme.Appear.margin
        let totalHeight = contentHeight + TrayTheme.Spacing.contentInset + m * 2
        let width = TrayTheme.Window.width + m * 2

        guard let window = view.window else { return }
        var frame = window.frame
        let oldHeight = frame.height
        frame.size.width = width
        frame.size.height = totalHeight
        frame.origin.y += (oldHeight - totalHeight)
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Selection

    private func setSelection(_ index: Int) {
        // Deselect old
        if selectedIndex >= 0 && selectedIndex < rowViews.count {
            if let c = rowViews[selectedIndex] as? ClipboardItemCellView { c.setSelected(false) }
            else if let c = rowViews[selectedIndex] as? ActionRowCellView { c.setSelected(false) }
        }
        selectedIndex = index
        // Select new
        if selectedIndex >= 0 && selectedIndex < rowViews.count {
            if let c = rowViews[selectedIndex] as? ClipboardItemCellView { c.setSelected(true) }
            else if let c = rowViews[selectedIndex] as? ActionRowCellView { c.setSelected(true) }
        }
    }

    private func selectFirstRecentItem() {
        for (i, row) in rows.enumerated() {
            if case .clipboardItem(let item) = row, !item.isPinned {
                setSelection(i)
                scrollSelectionIntoView()
                return
            }
        }
        selectFirstSelectableRow()
    }

    private func selectFirstSelectableRow() {
        for (i, row) in rows.enumerated() {
            if case .separator = row { continue }
            setSelection(i)
            return
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let key = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if key == 53 { // Esc
            onDismissRequested?()
            return
        }
        if key == 36 || key == 76 { // Enter / Return
            handleSelection()
            return
        }
        if key == 126 { moveSelection(by: -1); return } // Up
        if key == 125 { moveSelection(by: 1); return }  // Down

        if key == 124 || (key == 31 && flags.contains(.command)) { // → or ⌘O
            showActionMenuForSelectedItem(); return
        }
        if key == 35 && flags.contains(.command) { togglePinOnSelected(); return }  // ⌘P
        if key == 4 && flags.contains(.command) { toggleHideOnSelected(); return }   // ⌘H

        if key == 51 { performActionOnSelected(.delete); return } // Delete/Backspace
        if key == 48 { jumpToNextSection(); return } // Tab

        super.keyDown(with: event)
    }

    private func moveSelection(by delta: Int) {
        var next = selectedIndex + delta
        while next >= 0 && next < rows.count {
            if case .separator = rows[next] { next += delta } else { break }
        }
        if next >= 0 && next < rows.count {
            setSelection(next)
            scrollSelectionIntoView()
            selectionChangedByUser()
        }
    }

    private func scrollSelectionIntoView() {
        guard selectedIndex >= 0 && selectedIndex < rowViews.count, !isFooterRow(selectedIndex),
              let documentView = scrollView.documentView else { return }
        let rowView = rowViews[selectedIndex]
        // Include the top padding so the first row scrolls fully back into place
        let pad = listTopConstraint.constant
        let rect = rowView.convert(rowView.bounds, to: documentView).insetBy(dx: 0, dy: -pad)
        isScrollingProgrammatically = true
        documentView.scrollToVisible(rect)
        isScrollingProgrammatically = false
    }

    private func jumpToNextSection() {
        for i in max(selectedIndex + 1, 0)..<max(rows.count, selectedIndex + 1) {
            if case .separator = rows[i], i + 1 < rows.count {
                if case .separator = rows[i + 1] { continue }
                setSelection(i + 1)
                scrollSelectionIntoView()
                selectionChangedByUser()
                return
            }
        }
        selectFirstSelectableRow()
    }

    private func handleSelection() {
        guard selectedIndex >= 0 && selectedIndex < rows.count else { return }
        switch rows[selectedIndex] {
        case .clipboardItem(let item): onItemSelected?(item)
        case .clearAll: onClearAll?()
        case .separator: break
        }
    }

    private func performActionOnSelected(_ action: ClipboardAction) {
        guard selectedIndex >= 0 && selectedIndex < rows.count,
              case .clipboardItem(let item) = rows[selectedIndex] else { return }
        onAction?(action, item)
    }

    private func togglePinOnSelected() {
        guard selectedIndex >= 0 && selectedIndex < rows.count,
              case .clipboardItem(let item) = rows[selectedIndex] else { return }
        onAction?(item.isPinned ? .unpin : .pin, item)
    }

    private func toggleHideOnSelected() {
        guard selectedIndex >= 0 && selectedIndex < rows.count,
              case .clipboardItem(let item) = rows[selectedIndex] else { return }
        onAction?(item.isHidden ? .unhide : .hide, item)
    }

    // MARK: - Action Menu

    private func showActionMenuForSelectedItem() {
        guard selectedIndex >= 0 && selectedIndex < rows.count else { return }
        showActionMenu(forRow: selectedIndex)
    }

    /// Opens the actions menu beside the popup, level with row `index`
    private func showActionMenu(forRow index: Int) {
        guard case .clipboardItem(let item) = rows[index], let window = view.window else { return }
        closeActionMenu()
        hidePreview()
        setSelection(index)

        let rowView = rowViews[index]
        let rowOnScreen = window.convertToScreen(rowView.convert(rowView.bounds, to: nil))
        let menu = MenuPanel(entries: MenuEntry.actions(for: item) { [weak self] action in
            self?.onAction?(action, item)
        })
        menu.onClose = { [weak self] in self?.closeActionMenu() }
        window.addChildWindow(menu, ordered: .above)
        menu.show(besideRow: rowOnScreen, in: visibleFrameOnScreen)
        actionMenu = menu
        NSCursor.arrow.set()
    }

    /// Closes the actions menu and gives keyboard focus back to the popup
    private func closeActionMenu() {
        guard let menu = actionMenu else { return }
        actionMenu = nil
        menu.dismiss()
        view.window?.makeKey()
        view.window?.makeFirstResponder(self)
    }

    // MARK: - Preview

    /// User scrolled the list: rows moved under the mouse, so close the preview,
    /// highlight whatever row is now under the mouse, and restart the hover delay.
    @objc private func listDidScroll() {
        guard !isScrollingProgrammatically, actionMenu == nil, let window = view.window else { return }
        hidePreview()
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard let i = rowIndex(at: point) else { return }
        if i != selectedIndex { setSelection(i) }
        selectionChangedByUser()
    }

    /// Mouse or keyboard moved the selection: if a preview is up, follow along
    /// right away; otherwise wait for the hover delay before showing one.
    private func selectionChangedByUser() {
        previewTimer?.invalidate()
        previewTimer = nil
        guard actionMenu == nil else { return }

        if previewPanel?.isVisible == true {
            showPreviewForSelection()
            return
        }
        previewTimer = Timer.scheduledTimer(withTimeInterval: TrayTheme.Preview.hoverDelay, repeats: false) { [weak self] _ in
            self?.previewTimer = nil
            self?.showPreviewForSelection()
        }
    }

    private func showPreviewForSelection() {
        guard actionMenu == nil, let window = view.window,
              selectedIndex >= 0, selectedIndex < rows.count,
              case .clipboardItem(let item) = rows[selectedIndex] else {
            hidePreview()
            return
        }
        let panel = previewPanel ?? PreviewPanel()
        previewPanel = panel

        let rowView = rowViews[selectedIndex]
        let rowOnScreen = window.convertToScreen(rowView.convert(rowView.bounds, to: nil))
        // Attach only once it has content, so it never flashes empty
        if panel.show(item, data: previewDataProvider?(item), besideRow: rowOnScreen, in: visibleFrameOnScreen),
           panel.parent == nil {
            window.addChildWindow(panel, ordered: .above)
        }
    }

    private func hidePreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewPanel?.orderOut(nil)
    }

    // MARK: - First Responder

    override var acceptsFirstResponder: Bool { true }
}
