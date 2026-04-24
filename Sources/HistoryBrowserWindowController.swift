import Cocoa

private final class HoverTableView: NSTableView {
    var onHoverRow: ((Int?) -> Void)?
    private var track: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let track {
            removeTrackingArea(track)
        }
        let t = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(t)
        track = t
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = row(at: p)
        onHoverRow?(row >= 0 ? row : nil)
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverRow?(nil)
        super.mouseExited(with: event)
    }
}

final class HistoryBrowserWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    enum Mode {
        case all
        case favorites
    }

    private let mode: Mode
    private let pageSize = 24
    private var currentPage = 1
    private var totalCount = 0
    private var items: [ClipboardItem] = []

    private let titleLabel = NSTextField(labelWithString: "")
    private let pageLabel = NSTextField(labelWithString: "")
    private let prevButton = NSButton(title: "", target: nil, action: nil)
    private let nextButton = NSButton(title: "", target: nil, action: nil)
    private let tableView = HoverTableView()

    private var previewPanel: NSPanel?
    private var previewImageView: NSImageView?
    private let thumbnailCache = NSCache<NSString, NSImage>()

    private let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt
    }()

    init(mode: Mode) {
        self.mode = mode

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = mode == .favorites ? I18N.t("收藏记录", "Favorites") : I18N.t("历史记录", "History")
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        buildUI()
        refreshNow()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClipboardUpdated),
            name: .clipboardUpdated,
            object: nil
        )
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        destroyPreviewPanel()
        NotificationCenter.default.removeObserver(self)
    }

    func windowWillClose(_ notification: Notification) {
        destroyPreviewPanel()
    }

    func windowDidResignKey(_ notification: Notification) {
        hideImagePreview()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.stringValue = mode == .favorites ? I18N.t("收藏记录", "Favorites") : I18N.t("历史记录", "History")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        pageLabel.font = .systemFont(ofSize: 12, weight: .medium)
        pageLabel.textColor = .secondaryLabelColor
        pageLabel.alignment = .center
        pageLabel.translatesAutoresizingMaskIntoConstraints = false

        prevButton.title = I18N.t("上一页", "Previous")
        prevButton.bezelStyle = .rounded
        prevButton.target = self
        prevButton.action = #selector(goPrev)
        prevButton.translatesAutoresizingMaskIntoConstraints = false

        nextButton.title = I18N.t("下一页", "Next")
        nextButton.bezelStyle = .rounded
        nextButton.target = self
        nextButton.action = #selector(goNext)
        nextButton.translatesAutoresizingMaskIntoConstraints = false

        let topBar = NSStackView(views: [titleLabel, NSView(), prevButton, pageLabel, nextButton])
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.alignment = .centerY
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(copySelected)
        tableView.onHoverRow = { [weak self] row in
            self?.hoverRowChanged(row)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.width = 540
        tableView.addTableColumn(column)

        scroll.documentView = tableView

        content.addSubview(topBar)
        content.addSubview(scroll)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            scroll.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),

            pageLabel.widthAnchor.constraint(equalToConstant: 84)
        ])
    }

    @objc func refreshNow() {
        let query = ClipboardStore.Query(keyword: "", filterType: .all, favoritesOnly: mode == .favorites, favoriteFolder: nil)
        totalCount = ClipboardStore.shared.filteredCount(query: query)

        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        if currentPage > totalPages { currentPage = totalPages }
        if currentPage < 1 { currentPage = 1 }

        let offset = (currentPage - 1) * pageSize
        items = ClipboardStore.shared.filteredItems(query: query, limit: pageSize, offset: offset)

        tableView.reloadData()
        updatePager()
    }

    private func updatePager() {
        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        pageLabel.stringValue = "\(currentPage)/\(totalPages)"
        prevButton.isEnabled = currentPage > 1
        nextButton.isEnabled = currentPage < totalPages
    }

    @objc private func goPrev() {
        guard currentPage > 1 else { return }
        currentPage -= 1
        refreshNow()
    }

    @objc private func goNext() {
        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        guard currentPage < totalPages else { return }
        currentPage += 1
        refreshNow()
    }

    @objc private func copySelected() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        copy(items[row])
    }

    private func copy(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.kind == .text {
            if let text = ClipboardStore.shared.fullText(for: item.id) ?? item.text {
                pb.setString(text, forType: .string)
            }
        } else if let image = item.image ?? ClipboardStore.shared.image(for: item.id) {
            pb.writeObjects([image])
        }
    }

    @objc private func handleClipboardUpdated() {
        refreshNow()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        let id = NSUserInterfaceItemIdentifier("historyCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 3
            icon.layer?.masksToBounds = true
            icon.identifier = NSUserInterfaceItemIdentifier("icon")

            let label = NSTextField(labelWithString: "")
            label.font = .systemFont(ofSize: 14, weight: .medium)
            label.lineBreakMode = .byTruncatingTail
            label.identifier = NSUserInterfaceItemIdentifier("label")
            label.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(icon)
            cell.addSubview(label)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18),

                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        let icon = cell.subviews.first { $0.identifier?.rawValue == "icon" } as? NSImageView
        let label = cell.subviews.first { $0.identifier?.rawValue == "label" } as? NSTextField

        let time = dateFormatter.string(from: item.date)
        let text: String
        if let t = item.text, !t.isEmpty {
            text = "\(time)  \(compactTitle(t))"
        } else {
            text = "\(time)  \(I18N.t("[图片]", "[Image]"))"
        }
        label?.stringValue = text

        if item.kind == .image, let image = thumbnailImage(for: item) {
            icon?.image = image
            icon?.isHidden = false
        } else {
            icon?.image = NSImage(named: NSImage.touchBarTextBoldTemplateName)
            icon?.isHidden = false
        }

        return cell
    }

    private func compactTitle(_ raw: String) -> String {
        let maxLen = 24
        let oneLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard oneLine.count > maxLen else { return oneLine }
        let idx = oneLine.index(oneLine.startIndex, offsetBy: maxLen)
        return String(oneLine[..<idx]) + "…"
    }

    private func thumbnailImage(for item: ClipboardItem) -> NSImage? {
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

    private func hoverRowChanged(_ row: Int?) {
        guard let row, row >= 0, row < items.count else {
            hideImagePreview()
            return
        }
        let item = items[row]
        guard item.kind == .image, let image = ClipboardStore.shared.image(for: item.id) else {
            hideImagePreview()
            return
        }
        showImagePreview(image)
    }

    private func showImagePreview(_ image: NSImage) {
        let maxSize = NSSize(width: 360, height: 280)
        let fitted = fitSize(image.size, max: maxSize)

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

    private func hideImagePreview() {
        previewPanel?.orderOut(nil)
    }

    private func destroyPreviewPanel() {
        previewPanel?.orderOut(nil)
        previewPanel?.close()
        previewPanel = nil
        previewImageView = nil
    }

    private func fitSize(_ source: NSSize, max: NSSize) -> NSSize {
        guard source.width > 0, source.height > 0 else { return max }
        let scale = min(max.width / source.width, max.height / source.height, 1)
        return NSSize(width: floor(source.width * scale), height: floor(source.height * scale))
    }
}
