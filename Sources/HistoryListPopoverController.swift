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

final class HistoryListPopoverController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    enum Mode {
        case all
        case favorites
    }

    private let pageSize = 15
    private var mode: Mode = .all
    private(set) var items: [ClipboardItem] = []
    private let store: ClipboardStore
    private(set) var keyword = ""
    var onRequestClose: (() -> Void)?
    private var offset = 0
    private var isLoading = false
    private var hasMore = true
    private var hoveredRow: Int?

    private let tableView = HoverHistoryTableView()
    private let scrollView = NSScrollView()
    private let effectView = NSVisualEffectView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var isResetting = false

    private var previewImageView: NSImageView?
    private let textPreviewCache = NSCache<NSString, NSScrollView>()
    private let previewInteraction = HistoryPreviewInteraction()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    private let sourceIconProvider = ClipboardSourceIconProvider()
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

    init(store: ClipboardStore = .shared) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    func beginBrowsing(focusSearch: Bool) {
        resetAndLoad()
        tableView.startHoverTracking()
        if focusSearch { self.focusSearch() }
    }

    func focusSearch() {
        view.window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    func updateSearch(_ text: String) {
        if searchField.stringValue != text { searchField.stringValue = text }
        let nextKeyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nextKeyword != keyword else { return }
        keyword = nextKeyword
        resetAndLoad()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField,
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        updateSearch(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === searchField, !textView.hasMarkedText() else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            copyRow(tableView.selectedRow >= 0 ? tableView.selectedRow : 0)
        case #selector(NSResponder.cancelOperation(_:)):
            cancelSearchOrClose()
        default:
            return false
        }
        return true
    }

    func cancelSearchOrClose() {
        if !searchField.stringValue.isEmpty {
            updateSearch("")
            focusSearch()
        } else {
            onRequestClose?()
        }
    }

    private func moveSelection(by direction: Int) {
        guard !items.isEmpty else { return }
        let current = tableView.selectedRow
        let row = current < 0 ? (direction > 0 ? 0 : items.count - 1)
            : max(0, min(items.count - 1, current + direction))
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        handleHover(row)
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

        searchField.placeholderString = I18N.t("搜索历史记录…", "Search history…")
        searchField.setAccessibilityLabel(I18N.t("搜索历史记录", "Search history"))
        searchField.font = NSFont.systemFont(ofSize: 13)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(searchField)

        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true
        effectView.addSubview(emptyLabel)

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

            searchField.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            searchField.heightAnchor.constraint(equalToConstant: 28),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(lessThanOrEqualTo: scrollView.widthAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8)
        ])
    }

    private func resetAndLoad() {
        guard !isResetting else { return }
        isResetting = true
        defer { isResetting = false }
        hidePreview()
        tableView.resetHover()
        tableView.deselectAll(nil)
        items.removeAll()
        offset = 0
        hasMore = true
        tableView.reloadData()
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        loadNextPageIfNeeded(force: true)
    }

    @objc private func handleClipboardUpdated() {
        resetAndLoad()
    }

    @objc private func scrollChanged() {
        guard !isResetting else { return }
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
            keyword: keyword,
            filterType: .all,
            favoritesOnly: mode == .favorites,
            favoriteFolder: nil
        )

        let batch = store.filteredItems(query: query, limit: pageSize, offset: offset)
        items.append(contentsOf: batch)
        offset += batch.count
        hasMore = batch.count == pageSize
        isLoading = false
        tableView.reloadData()
        emptyLabel.stringValue = keyword.isEmpty ? I18N.t("暂无历史记录", "No clipboard history")
            : I18N.t("没有匹配的记录", "No matching records")
        emptyLabel.isHidden = !items.isEmpty
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        tableView.tableColumns.first?.width = scrollView.contentSize.width
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
        let cell: HistoryRecordCell
        if let reused = tableView.makeView(withIdentifier: cellId, owner: self) as? HistoryRecordCell {
            cell = reused
        } else {
            cell = HistoryRecordCell()
            cell.identifier = cellId
        }

        cell.configure(item: item, sourceImage: sourceIconProvider.icon(for: item.sourceApp),
                       thumbnailImage: item.kind == .image ? thumbnail(for: item) : nil,
                       title: item.kind == .text ? short(item.text ?? "") : I18N.t("[图片]", "[Image]"),
                       isHovering: row == hoveredRow)
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
        guard let image = store.image(for: item.id) else { return nil }
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
        copyRow(row)
    }

    private func copyRow(_ row: Int) {
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
            if let text = store.fullText(for: item.id) ?? item.text {
                pb.setString(text, forType: .string)
            }
        } else if let image = store.image(for: item.id) {
            pb.writeObjects([image])
        }
        ClipboardSource.writeOriginal(item.sourceApp, to: pb)
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
        store.toggleFavorite(id: id)
        resetAndLoad()
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        store.deleteItem(id: id)
        resetAndLoad()
    }

    // MARK: - Hover & Preview

    private func handleHover(_ row: Int?) {
        // The embedded preview remains readable until another record is hovered or the menu closes.
        guard let row, row >= 0, row < items.count else { return }
        guard row != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = row
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
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
            guard let image = self.store.image(for: item.id) else { return }
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
        if let onRequestClose {
            onRequestClose()
            return
        }
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
        operation.addExecutionBlock { [weak self, weak operation, store] in
            guard let operation, !operation.isCancelled else { return }
            // List rows contain only a prefix; previews must fetch the stored full text.
            let text = store.fullText(for: item.id) ?? item.text ?? ""
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
