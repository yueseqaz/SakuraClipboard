import Cocoa

private final class HoverHistoryTableView: NSTableView {
    var onHoverRow: ((Int?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let ta = NSTrackingArea(
            rect: .zero,
            options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(ta)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let r = row(at: p)
        onHoverRow?(r >= 0 ? r : nil)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverRow?(nil)
        super.mouseExited(with: event)
    }
}

private final class HoverHistoryRowView: NSTableRowView {
    private let selectionEffectView = NSVisualEffectView()

    var isHovering = false {
        didSet { selectionEffectView.isHidden = !isHovering }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSelectionEffect()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSelectionEffect()
    }

    private func setupSelectionEffect() {
        selectionEffectView.material = .selection
        selectionEffectView.blendingMode = .withinWindow
        selectionEffectView.state = .active
        selectionEffectView.isHidden = true
        addSubview(selectionEffectView, positioned: .below, relativeTo: nil)
    }

    override func layout() {
        super.layout()
        selectionEffectView.frame = bounds
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

final class HistoryListPopoverController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    enum Mode {
        case all
        case favorites
    }

    private let pageSize = 15
    private var mode: Mode = .all
    private var items: [ClipboardItem] = []
    private var offset = 0
    private var isLoading = false
    private var hasMore = true
    private var hoveredRow: Int?

    private let tableView = HoverHistoryTableView()
    private let scrollView = NSScrollView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let topDivider = NSBox()
    private let effectView = NSVisualEffectView()
    private var scrollTopWithHeaderConstraint: NSLayoutConstraint?
    private var scrollTopCompactConstraint: NSLayoutConstraint?

    private var previewPanel: NSPanel?
    private var previewImageView: NSImageView?
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let previewImageCache = NSCache<NSString, NSImage>()
    private let previewLoadQueue = DispatchQueue(label: "com.sakura.clipboard.history.preview", qos: .userInitiated)
    private var pendingPreviewItemID: String?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 420))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipboardUpdated),
            name: .clipboardUpdated,
            object: nil
        )
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        destroyPreviewPanel()
    }

    deinit {
        destroyPreviewPanel()
        NotificationCenter.default.removeObserver(self)
    }

    func switchMode(_ mode: Mode) {
        self.mode = mode
        titleLabel.stringValue = mode == .favorites ? I18N.t("收藏记录", "Favorites") : I18N.t("历史记录", "History")
        resetAndLoad()
    }

    func setMenuEmbeddedStyle(width: CGFloat, height: CGFloat) {
        loadViewIfNeeded()
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        titleLabel.isHidden = true
        topDivider.isHidden = true
        scrollTopWithHeaderConstraint?.isActive = false
        scrollTopCompactConstraint?.isActive = true
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
    }

    private func buildUI() {
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .menu
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        view.addSubview(effectView)

        titleLabel.stringValue = I18N.t("历史记录", "History")
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        topDivider.boxType = .separator
        topDivider.borderColor = .separatorColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        tableView.headerView = nil
        tableView.rowHeight = 25
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(copySelected)
        tableView.doubleAction = nil
        tableView.onHoverRow = { [weak self] row in
            self?.handleHover(row)
        }

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.width = 320
        tableView.addTableColumn(col)

        scrollView.documentView = tableView

        effectView.addSubview(titleLabel)
        effectView.addSubview(topDivider)
        effectView.addSubview(scrollView)

        scrollTopWithHeaderConstraint = scrollView.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 8)
        scrollTopCompactConstraint = scrollView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 6)
        scrollTopCompactConstraint?.isActive = false

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: view.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),

            topDivider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            topDivider.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            topDivider.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),

            scrollTopWithHeaderConstraint!,
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8)
        ])
    }

    private func resetAndLoad() {
        items.removeAll()
        offset = 0
        hasMore = true
        tableView.reloadData()
        loadNextPageIfNeeded(force: true)
    }

    @objc private func handleClipboardUpdated() {
        resetAndLoad()
    }

    @objc private func scrollChanged() {
        guard let doc = scrollView.documentView else { return }
        let visibleMaxY = scrollView.contentView.bounds.maxY
        if doc.frame.height - visibleMaxY < 180 {
            loadNextPageIfNeeded(force: false)
        }
    }

    private func loadNextPageIfNeeded(force: Bool) {
        if !force {
            guard hasMore else { return }
        }
        guard !isLoading else { return }
        isLoading = true

        let query = ClipboardStore.Query(
            keyword: "",
            filterType: .all,
            favoritesOnly: mode == .favorites,
            favoriteFolder: nil
        )

        let batch = ClipboardStore.shared.filteredItems(query: query, limit: pageSize, offset: offset)
        items.append(contentsOf: batch)
        offset += batch.count
        hasMore = batch.count == pageSize
        isLoading = false
        tableView.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("hoverRowView")
        let rowView: HoverHistoryRowView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? HoverHistoryRowView {
            rowView = reused
        } else {
            rowView = HoverHistoryRowView()
            rowView.identifier = id
        }
        rowView.isHovering = (row == hoveredRow)
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        let id = NSUserInterfaceItemIdentifier("row")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id

            let icon = NSImageView()
            icon.identifier = NSUserInterfaceItemIdentifier("icon")
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 3
            icon.layer?.masksToBounds = true

            let label = NSTextField(labelWithString: "")
            label.identifier = NSUserInterfaceItemIdentifier("label")
            label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(icon)
            cell.addSubview(label)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18),

                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let icon = cell.subviews.first(where: { $0.identifier?.rawValue == "icon" }) as? NSImageView
        let label = cell.subviews.first(where: { $0.identifier?.rawValue == "label" }) as? NSTextField
        label?.textColor = row == hoveredRow ? .selectedMenuItemTextColor : .labelColor

        if let text = item.text, !text.isEmpty {
            label?.stringValue = short(text)
            icon?.image = nil
            icon?.isHidden = true
        } else {
            label?.stringValue = I18N.t("[图片]", "[Image]")
            icon?.image = thumbnail(for: item)
            icon?.isHidden = false
        }

        return cell
    }

    private func short(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let n = 18
        guard line.count > n else { return line }
        let idx = line.index(line.startIndex, offsetBy: n)
        return String(line[..<idx]) + "…"
    }

    private func thumbnail(for item: ClipboardItem) -> NSImage? {
        let key = item.id as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let image = ClipboardStore.shared.image(for: item.id) else { return nil }
        let size = NSSize(width: 18, height: 18)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    @objc private func copySelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.kind == .text {
            if let text = ClipboardStore.shared.fullText(for: item.id) ?? item.text {
                pb.setString(text, forType: .string)
            }
        } else if let image = ClipboardStore.shared.image(for: item.id) {
            pb.writeObjects([image])
        }
        tableView.deselectRow(row)
        hidePreview()
        closeContainingMenu()
    }

    private func handleHover(_ row: Int?) {
        let previous = hoveredRow
        hoveredRow = row
        if let previous {
            (tableView.rowView(atRow: previous, makeIfNecessary: false) as? HoverHistoryRowView)?.isHovering = false
            setRowTextColor(previous, isHovering: false)
        }
        if let row {
            (tableView.rowView(atRow: row, makeIfNecessary: false) as? HoverHistoryRowView)?.isHovering = true
            setRowTextColor(row, isHovering: true)
        }

        guard let row, row >= 0, row < items.count else {
            hidePreview()
            return
        }
        let item = items[row]
        guard item.kind == .image else {
            hidePreview()
            return
        }
        showPreview(for: item)
    }

    private func setRowTextColor(_ row: Int, isHovering: Bool) {
        guard row >= 0,
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let label = cell.subviews.first(where: { $0.identifier?.rawValue == "label" }) as? NSTextField else { return }
        label.textColor = isHovering ? .selectedMenuItemTextColor : .labelColor
    }

    private func showPreview(for item: ClipboardItem) {
        let key = item.id as NSString
        if let cached = previewImageCache.object(forKey: key) {
            showPreview(cached)
            return
        }

        hidePreview()
        pendingPreviewItemID = item.id
        previewLoadQueue.async { [weak self] in
            guard let self else { return }
            guard let image = ClipboardStore.shared.image(for: item.id) else { return }
            self.previewImageCache.setObject(image, forKey: key)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingPreviewItemID == item.id else { return }
                self.showPreview(image)
            }
        }
    }

    private func closeContainingMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.enclosingMenuItem?.menu?.cancelTracking()
        }
    }

    private func showPreview(_ image: NSImage) {
        let maxSize = NSSize(width: 360, height: 280)
        let fitted = fit(image.size, max: maxSize)

        if previewPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: fitted),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = true
            panel.backgroundColor = NSColor.black
            panel.hasShadow = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .transient]

            let iv = NSImageView(frame: NSRect(origin: .zero, size: fitted))
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 8
            iv.layer?.masksToBounds = true
            panel.contentView = iv
            previewPanel = panel
            previewImageView = iv
        }

        previewImageView?.image = image
        previewImageView?.frame = NSRect(origin: .zero, size: fitted)
        previewPanel?.setContentSize(fitted)

        let mouse = NSEvent.mouseLocation
        var x = mouse.x + 24
        var y = max(16, mouse.y - fitted.height * 0.5)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            if x + fitted.width > screen.visibleFrame.maxX - 8 {
                x = mouse.x - fitted.width - 16
            }
            if y + fitted.height > screen.visibleFrame.maxY - 8 {
                y = screen.visibleFrame.maxY - fitted.height - 8
            }
        }

        previewPanel?.setFrameOrigin(NSPoint(x: x, y: y))
        previewPanel?.orderFrontRegardless()
    }

    private func hidePreview() {
        pendingPreviewItemID = nil
        previewPanel?.orderOut(nil)
    }

    private func destroyPreviewPanel() {
        previewPanel?.orderOut(nil)
        previewPanel?.close()
        previewPanel = nil
        previewImageView = nil
    }

    private func fit(_ source: NSSize, max: NSSize) -> NSSize {
        guard source.width > 0, source.height > 0 else { return max }
        let scale = min(max.width / source.width, max.height / source.height, 1)
        return NSSize(width: floor(source.width * scale), height: floor(source.height * scale))
    }
}
