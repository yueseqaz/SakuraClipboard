import Cocoa

final class SearchPanelController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    private let pageSize = 50
    private var items: [ClipboardItem] = []
    private var offset = 0
    private var isLoading = false
    private var hasMore = true

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let effectView = NSVisualEffectView()
    private let hintLabel = NSTextField(labelWithString: "")
    private let thumbnailCache = NSCache<NSString, NSImage>()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 520))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            view.window?.close()
        } else {
            super.keyDown(with: event)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }

    private func buildUI() {
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true
        view.addSubview(effectView)

        searchField.placeholderString = I18N.t("输入关键词搜索剪贴板历史...", "Type to search clipboard history...")
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        effectView.addSubview(searchField)

        hintLabel.stringValue = I18N.t("按 ESC 关闭", "Press ESC to close")
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hintLabel)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        tableView.headerView = nil
        tableView.rowHeight = 32
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.action = #selector(copySelected)

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        scrollView.documentView = tableView
        effectView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: view.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            searchField.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            searchField.heightAnchor.constraint(equalToConstant: 32),

            hintLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 4),
            hintLabel.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -8)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Update table column width to match scroll view
        let column = tableView.tableColumns.first
        column?.width = scrollView.contentView.bounds.width
    }

    func controlTextDidChange(_ obj: Notification) {
        performSearch()
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        // Keep results visible
    }

    private func performSearch() {
        let keyword = searchField.stringValue
        items.removeAll()
        offset = 0
        hasMore = true
        tableView.reloadData()

        guard !keyword.isEmpty else { return }
        loadResults(keyword: keyword)
    }

    private func loadResults(keyword: String) {
        guard !isLoading else { return }
        isLoading = true

        let query = ClipboardStore.Query(
            keyword: keyword,
            filterType: .all,
            favoritesOnly: false,
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
        let rowView = NSTableRowView()
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        let cellId = NSUserInterfaceItemIdentifier("searchCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: cellId, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = cellId

            let icon = NSImageView()
            icon.tag = 200
            icon.imageScaling = .scaleProportionallyDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 3
            icon.layer?.masksToBounds = true
            cell.addSubview(icon)

            let label = NSTextField(labelWithString: "")
            label.tag = 201
            label.font = NSFont.systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)

            let timeLabel = NSTextField(labelWithString: "")
            timeLabel.tag = 202
            timeLabel.font = NSFont.systemFont(ofSize: 10)
            timeLabel.textColor = .tertiaryLabelColor
            timeLabel.alignment = .right
            timeLabel.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(timeLabel)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),

                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

                timeLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                timeLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                timeLabel.widthAnchor.constraint(equalToConstant: 55)
            ])
        }

        let icon = cell.viewWithTag(200) as? NSImageView
        let label = cell.viewWithTag(201) as? NSTextField
        let timeLabel = cell.viewWithTag(202) as? NSTextField

        timeLabel?.stringValue = I18N.relativeTime(from: item.date)

        if let text = item.text, !text.isEmpty {
            label?.stringValue = String(text.prefix(50))
            icon?.image = nil
            icon?.isHidden = true
        } else {
            label?.stringValue = I18N.t("[图片]", "[Image]")
            icon?.image = thumbnail(for: item)
            icon?.isHidden = false
        }

        return cell
    }

    private func thumbnail(for item: ClipboardItem) -> NSImage? {
        let key = item.id as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let image = ClipboardStore.shared.image(for: item.id) else { return nil }
        let size = NSSize(width: 20, height: 20)
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        thumb.unlockFocus()
        thumbnailCache.setObject(thumb, forKey: key)
        return thumb
    }

    @objc private func copySelected() {
        let row = tableView.selectedRow
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
        HUDWindow.show(I18N.t("已复制", "Copied"))
        view.window?.close()
    }
}

// MARK: - Panel Manager

final class SearchPanel {
    static let shared = SearchPanel()

    private var panel: NSPanel?
    private var controller: SearchPanelController?

    private init() {}

    func show() {
        print("SearchPanel.show() called")
        
        // Close existing panel if any
        if let panel {
            panel.close()
            self.panel = nil
            self.controller = nil
        }

        let width: CGFloat = 420
        let height: CGFloat = 520

        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.midY - height / 2

        print("Creating panel at \(x), \(y)")
        
        let newPanel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        newPanel.title = I18N.t("搜索剪贴板", "Search Clipboard")
        newPanel.isFloatingPanel = true
        newPanel.level = .floating
        newPanel.isReleasedWhenClosed = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .transient]
        newPanel.backgroundColor = .windowBackgroundColor

        let searchController = SearchPanelController()
        newPanel.contentViewController = searchController
        newPanel.delegate = searchController
        
        print("Showing panel...")
        NSApp.activate(ignoringOtherApps: true)
        newPanel.makeKeyAndOrderFront(nil)
        
        self.panel = newPanel
        self.controller = searchController
        
        print("Panel shown, isVisible: \(newPanel.isVisible)")
    }

    func hide() {
        panel?.close()
    }

    func toggle() {
        if let panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }
}
