import Cocoa

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

final class HistoryListPopoverController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
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
    private let effectView = NSVisualEffectView()
    private let headerLabel = NSTextField(labelWithString: "")

    private var previewImageView: NSImageView?
    private let textPreviewCache = NSCache<NSString, NSScrollView>()
    private let previewInteraction = HistoryPreviewInteraction()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let previewImageCache = NSCache<NSString, NSImage>()
    private let previewLoadQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.sakura.clipboard.history.preview"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var pendingPreviewItemID: String?

    private var menuContent: HistoryMenuContentView? { view.superview as? HistoryMenuContentView }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 336, height: 420))
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
        menuTrackingDidEnd()
    }

    deinit {
        previewLoadQueue.cancelAllOperations()
        NotificationCenter.default.removeObserver(self)
    }

    func switchMode(_ mode: Mode) {
        self.mode = mode
        resetAndLoad()
    }

    func setMenuEmbeddedStyle(width: CGFloat, height: CGFloat) {
        _ = view  // Load view
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func buildUI() {
        textPreviewCache.countLimit = 12
        textPreviewCache.totalCostLimit = 8 * 1024 * 1024
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .menu
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        view.addSubview(effectView)

        headerLabel.stringValue = I18N.t("剪贴板历史", "Clipboard History")
        headerLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(headerLabel)

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
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
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
        tableView.resolveHoverRow = { [weak self] row, point in
            guard let self else { return row }
            return self.previewInteraction.resolve(row: row, pointer: point)
        }

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        tableView.menu = contextMenu

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.width = 320
        tableView.addTableColumn(col)

        scrollView.documentView = tableView
        effectView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: view.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            headerLabel.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 10),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8)
        ])
    }

    private func resetAndLoad() {
        hidePreview()
        tableView.resetHover()
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

        let cellId = NSUserInterfaceItemIdentifier("historyCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellId

            let icon = NSImageView()
            icon.tag = 100
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 3
            icon.layer?.masksToBounds = true
            cell.addSubview(icon)

            let label = NSTextField(labelWithString: "")
            label.tag = 101
            label.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)

            let timeLabel = NSTextField(labelWithString: "")
            timeLabel.tag = 102
            timeLabel.font = NSFont.systemFont(ofSize: 10)
            timeLabel.textColor = .tertiaryLabelColor
            timeLabel.alignment = .right
            timeLabel.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(timeLabel)

            let previewBtn = NSButton()
            previewBtn.tag = 103
            previewBtn.bezelStyle = .inline
            previewBtn.title = I18N.t("预览", "Peek")
            previewBtn.font = NSFont.systemFont(ofSize: 10)
            previewBtn.translatesAutoresizingMaskIntoConstraints = false
            previewBtn.isBordered = false
            previewBtn.setContentHuggingPriority(.required, for: .horizontal)
            cell.addSubview(previewBtn)

            NSLayoutConstraint.activate([
                previewBtn.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                previewBtn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                previewBtn.widthAnchor.constraint(equalToConstant: 30),

                icon.leadingAnchor.constraint(equalTo: previewBtn.trailingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),

                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

                timeLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                timeLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                timeLabel.widthAnchor.constraint(equalToConstant: 45)
            ])
        }

        let icon = cell.viewWithTag(100) as? NSImageView
        let label = cell.viewWithTag(101) as? NSTextField
        let timeLabel = cell.viewWithTag(102) as? NSTextField
        let previewBtn = cell.viewWithTag(103) as? NSButton

        label?.textColor = row == hoveredRow ? .selectedMenuItemTextColor : .labelColor
        timeLabel?.stringValue = I18N.relativeTime(from: item.date)
        timeLabel?.textColor = row == hoveredRow ? .selectedMenuItemTextColor : .tertiaryLabelColor

        // Setup preview button
        previewBtn?.target = self
        previewBtn?.action = #selector(previewButtonClicked(_:))
        previewBtn?.identifier = NSUserInterfaceItemIdentifier("\(row)")

        let isText = item.kind == .text && item.text != nil && !item.text!.isEmpty
        previewBtn?.isHidden = !isText

        if isText {
            label?.stringValue = short(item.text!)
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
        let n = 42
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
        let size = NSSize(width: 16, height: 16)
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
        copyItem(item)
        tableView.deselectAll(nil)
        hidePreview()
        closeContainingMenu()
    }

    private func copyItem(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.kind == .text {
            if let text = ClipboardStore.shared.fullText(for: item.id) ?? item.text {
                pb.setString(text, forType: .string)
            }
        } else if let image = ClipboardStore.shared.image(for: item.id) {
            pb.writeObjects([image])
        }
        HUDWindow.show(I18N.t("已复制", "Copied"))
    }

    // MARK: - Context Menu

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === view.enclosingMenuItem?.menu else { return }
        tableView.startHoverTracking()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === view.enclosingMenuItem?.menu else { return }
        menuTrackingDidEnd()
    }

    func menuTrackingDidEnd() {
        tableView.stopHoverTracking()
        hidePreview()
    }

    func dismissPreview() {
        hidePreview()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === tableView.menu else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else {
            menu.removeAllItems()
            return
        }

        let item = items[row]
        menu.removeAllItems()

        let copyItem = NSMenuItem(title: I18N.t("复制", "Copy"), action: #selector(contextCopy(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = item.id
        menu.addItem(copyItem)

        // Preview option for long text
        if item.kind == .text, let text = item.text, text.count > 42 {
            let previewItem = NSMenuItem(title: I18N.t("预览", "Preview"), action: #selector(contextPreview(_:)), keyEquivalent: "")
            previewItem.target = self
            previewItem.representedObject = item.id
            menu.addItem(previewItem)
        }

        menu.addItem(.separator())

        let favTitle = item.isFavorite ? I18N.t("取消收藏", "Unfavorite") : I18N.t("收藏", "Favorite")
        let favItem = NSMenuItem(title: favTitle, action: #selector(contextToggleFavorite(_:)), keyEquivalent: "")
        favItem.target = self
        favItem.representedObject = item.id
        menu.addItem(favItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: I18N.t("删除", "Delete"), action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = item.id
        menu.addItem(deleteItem)
    }

    @objc private func contextCopy(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        guard let item = items.first(where: { $0.id == id }) else { return }
        copyItem(item)
    }

    @objc private func contextPreview(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let item = items.first(where: { $0.id == id }) else { return }
        showTextPreview(for: item)
    }

    @objc private func contextToggleFavorite(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ClipboardStore.shared.toggleFavorite(id: id)
        resetAndLoad()
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        ClipboardStore.shared.deleteItem(id: id)
        resetAndLoad()
    }

    @objc private func previewButtonClicked(_ sender: NSButton) {
        guard let rowStr = sender.identifier?.rawValue, let row = Int(rowStr) else { return }
        guard row >= 0, row < items.count else { return }
        let item = items[row]
        if item.kind == .text {
            showTextPreview(for: item)
        }
    }

    // MARK: - Hover & Preview

    private func handleHover(_ row: Int?) {
        // The embedded preview remains readable until another record is hovered or the menu closes.
        guard let row, row >= 0, row < items.count else { return }
        guard row != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = row
        if let previous {
            (tableView.rowView(atRow: previous, makeIfNecessary: false) as? HoverHistoryRowView)?.isHovering = false
            setRowTextColor(previous, isHovering: false)
        }
        (tableView.rowView(atRow: row, makeIfNecessary: false) as? HoverHistoryRowView)?.isHovering = true
        setRowTextColor(row, isHovering: true)
        let item = items[row]
        if item.kind == .image {
            showPreview(for: item)
        } else {
            showTextPreview(for: item)
        }
    }

    private func setRowTextColor(_ row: Int, isHovering: Bool) {
        guard row >= 0,
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let label = cell.viewWithTag(101) as? NSTextField else { return }
        label.textColor = isHovering ? .selectedMenuItemTextColor : .labelColor
    }

    private func showPreview(for item: ClipboardItem) {
        previewLoadQueue.cancelAllOperations()
        pendingPreviewItemID = item.id
        updatePreviewInteraction(for: item)
        let key = item.id as NSString
        if let cached = previewImageCache.object(forKey: key) {
            showPreview(cached, for: item)
            return
        }

        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else { return }
            guard let image = ClipboardStore.shared.image(for: item.id) else { return }
            guard !operation.isCancelled else { return }
            self.previewImageCache.setObject(image, forKey: key)
            // NSMenu runs a nested tracking loop; publish without waiting for a click.
            RunLoop.main.perform(inModes: [.default, .eventTracking]) { [weak self] in
                guard let self, !operation.isCancelled, self.pendingPreviewItemID == item.id else { return }
                self.showPreview(image, for: item)
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        previewLoadQueue.addOperation(operation)
    }

    private func closeContainingMenu() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.enclosingMenuItem?.menu?.cancelTracking()
        }
    }

    private func showTextPreview(for item: ClipboardItem) {
        previewLoadQueue.cancelAllOperations()
        pendingPreviewItemID = item.id
        updatePreviewInteraction(for: item)
        if let cached = textPreviewCache.object(forKey: item.id as NSString) {
            showTextPreview(cached, for: item)
            return
        }
        if !item.hasMoreText, let text = item.text, !text.isEmpty {
            showTextPreview(text, for: item)
            return
        }
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            // List rows contain only a prefix; previews must fetch the stored full text.
            let text = ClipboardStore.shared.fullText(for: item.id) ?? item.text ?? ""
            guard !operation.isCancelled else { return }
            RunLoop.main.perform(inModes: [.default, .eventTracking]) { [weak self] in
                guard let self, !operation.isCancelled, self.pendingPreviewItemID == item.id, !text.isEmpty else { return }
                self.showTextPreview(text, for: item)
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
        previewLoadQueue.addOperation(operation)
    }

    private func showPreview(_ image: NSImage, for item: ClipboardItem) {
        if previewImageView == nil {
            let iv = NSImageView()
            iv.imageScaling = .scaleProportionallyDown
            previewImageView = iv
        }
        previewImageView?.image = image
        if let previewImageView { presentPreview(previewImageView, for: item) }
    }

    private func showTextPreview(_ text: String, for item: ClipboardItem) {
        let size = menuContent?.previewContentSize ?? NSSize(width: 344, height: 366)
        let scrollView = Self.makeTextPreviewView(text: text, size: size)
        textPreviewCache.setObject(scrollView, forKey: item.id as NSString, cost: text.utf16.count * 8)
        showTextPreview(scrollView, for: item)
    }

    private func showTextPreview(_ scrollView: NSScrollView, for item: ClipboardItem) {
        presentPreview(scrollView, for: item)
    }

    private func updatePreviewInteraction(for item: ClipboardItem) {
        guard let row = items.firstIndex(where: { $0.id == item.id }),
              let window = tableView.window, window.isVisible,
              let previewFrame = menuContent?.previewScreenFrame else { return }
        let source = window.convertToScreen(tableView.convert(tableView.rect(ofRow: row), to: nil))
        previewInteraction.show(row: row, sourceFrame: source, previewFrame: previewFrame)
    }

    private func presentPreview(_ content: NSView, for item: ClipboardItem) {
        guard pendingPreviewItemID == item.id, let menuContent,
              menuContent.window?.isVisible == true else { return }
        menuContent.showPreview(content)
    }

    static func makeTextPreviewView(text: String, size: NSSize) -> NSScrollView {
        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .windowBackgroundColor

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(
            width: max(1, scrollView.contentSize.width - 24),
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        textView.string = text
        if let container = textView.textContainer, let layout = textView.layoutManager {
            layout.ensureLayout(for: container)
            let contentHeight = layout.usedRect(for: container).height + 2 * textView.textContainerInset.height
            textView.setFrameSize(NSSize(width: scrollView.contentSize.width,
                                        height: max(scrollView.contentSize.height, ceil(contentHeight))))
        }
        return scrollView
    }

    private func hidePreview() {
        if let hoveredRow {
            (tableView.rowView(atRow: hoveredRow, makeIfNecessary: false) as? HoverHistoryRowView)?.isHovering = false
            setRowTextColor(hoveredRow, isHovering: false)
        }
        hoveredRow = nil
        pendingPreviewItemID = nil
        previewLoadQueue.cancelAllOperations()
        previewInteraction.reset()
        menuContent?.clearPreview()
    }
}
