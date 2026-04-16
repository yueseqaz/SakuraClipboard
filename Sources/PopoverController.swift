import Cocoa
import ServiceManagement

// MARK: - PopoverController
class PopoverController: NSViewController, NSTextFieldDelegate {
    private let popoverWidth: CGFloat = 338
    private let rowWidth: CGFloat = 314
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private var copiedToast: NSView?
    private let historySubtitleLabel = NSTextField(labelWithString: "")
    private let maxItemsValueLabel = NSTextField(labelWithString: "")
    private let maxItemsStepper = NSStepper()
    private let storageUsageLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let typeFilter = NSPopUpButton()
    private let timeFilter = NSPopUpButton()
    private let favoriteFolderFilter = NSPopUpButton()
    private let languageFilter = NSPopUpButton()
    private weak var expandedRow: ClipRowView?
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var lastRenderSignature = ""
    private var favoriteFolderValues: [String?] = [nil]
    private var pendingFavoriteItemID: String?
    private var pendingFavoriteDraftFolder: String = ""
    private let favoriteInlineInput = NSTextField()
    private let favoriteInlinePicker = NSPopUpButton()
    private var aboutWindowController: NSWindowController?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: popoverWidth, height: 540))
        view.wantsLayer = true
        view.layer?.backgroundColor = DS.bg.cgColor

        buildUI()

        NotificationCenter.default.addObserver(
            self, selector: #selector(reload),
            name: .clipboardUpdated, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        DispatchQueue.main.async { self.reload() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildUI() {
        // ── Header ──────────────────────────────────────────────
        let header = buildHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        // Divider
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        // ── Scroll area ─────────────────────────────────────────
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay
        view.addSubview(scrollView)

        // Use a flipped document view so content starts from the top
        let docView = FlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView

        contentStack.orientation = .vertical
        contentStack.spacing = 8
        contentStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(contentStack)

        // contentStack fills docView width
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: docView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor),
            docView.widthAnchor.constraint(equalToConstant: popoverWidth)
        ])

        // ── Footer ──────────────────────────────────────────────
        let footer = buildFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 132),

            divider.topAnchor.constraint(equalTo: header.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: 130)
        ])
    }

    private func buildHeader() -> NSView {
        let v = NSView()
        v.wantsLayer = true

        let icon = NSTextField(labelWithString: "⌘")
        icon.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        icon.textColor = DS.accent

        let title = NSTextField(labelWithString: I18N.t("剪贴板历史", "Clipboard History"))
        title.font = DS.fontTitle
        title.textColor = DS.textPrimary

        historySubtitleLabel.font = DS.fontSmall
        historySubtitleLabel.textColor = DS.textSec

        let titleStack = NSStackView(views: [title, historySubtitleLabel])
        titleStack.orientation = .vertical
        titleStack.spacing = 1
        titleStack.alignment = .leading

        let left = NSStackView(views: [icon, titleStack])
        left.orientation = .horizontal
        left.spacing = 8
        left.translatesAutoresizingMaskIntoConstraints = false

        let clearBtn = makeTextButton(I18N.t("清空", "Clear"), color: DS.danger)
        clearBtn.target = self
        clearBtn.action = #selector(clearAll)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = I18N.t("按关键字搜索文本", "Search text by keyword")
        searchField.controlSize = .large
        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        searchField.sendsSearchStringImmediately = true

        let previousTypeIndex = max(typeFilter.indexOfSelectedItem, 0)
        typeFilter.removeAllItems()
        typeFilter.addItems(withTitles: [
            I18N.t("全部类型", "All Types"),
            I18N.t("仅文本", "Text Only"),
            I18N.t("仅图片", "Image Only")
        ])
        typeFilter.selectItem(at: min(previousTypeIndex, typeFilter.numberOfItems - 1))
        typeFilter.controlSize = .large
        typeFilter.target = self
        typeFilter.action = #selector(filtersChanged)

        let previousTimeIndex = max(timeFilter.indexOfSelectedItem, 0)
        timeFilter.removeAllItems()
        timeFilter.addItems(withTitles: [
            I18N.t("全部时间", "All Time"),
            I18N.t("最近1小时", "Last 1 Hour"),
            I18N.t("今天", "Today"),
            I18N.t("最近7天", "Last 7 Days"),
            I18N.t("最近30天", "Last 30 Days")
        ])
        timeFilter.selectItem(at: min(previousTimeIndex, timeFilter.numberOfItems - 1))
        timeFilter.controlSize = .large
        timeFilter.target = self
        timeFilter.action = #selector(filtersChanged)

        refreshFavoriteFolderFilterOptions(preserveSelection: true)
        favoriteFolderFilter.controlSize = .large
        favoriteFolderFilter.target = self
        favoriteFolderFilter.action = #selector(filtersChanged)

        let topRow = NSStackView(views: [left, NSView(), clearBtn])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.alignment = .centerY

        let filterRow = NSStackView(views: [typeFilter, timeFilter, favoriteFolderFilter])
        filterRow.orientation = .horizontal
        filterRow.spacing = 6
        filterRow.alignment = .centerY

        let stack = NSStackView(views: [topRow, searchField, filterRow])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -8),
            typeFilter.widthAnchor.constraint(equalToConstant: 84),
            timeFilter.widthAnchor.constraint(equalToConstant: 84),
            favoriteFolderFilter.widthAnchor.constraint(equalToConstant: 120)
        ])

        return v
    }

    private func buildFooter() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = DS.surface.cgColor

        // Top border
        let border = CALayer()
        border.backgroundColor = DS.border.cgColor

        // Launch at login toggle
        let loginLabel = NSTextField(labelWithString: I18N.t("开机自启", "Launch at Login"))
        loginLabel.font = DS.fontSmall
        loginLabel.textColor = DS.textSec

        let toggle = ToggleSwitch()
        toggle.isOn = isLoginItemEnabled()
        toggle.onToggle = { [weak self] on in
            self?.setLoginItem(enabled: on)
        }

        let toggleGroup = NSStackView(views: [loginLabel, toggle])
        toggleGroup.orientation = .horizontal
        toggleGroup.spacing = 6

        // History limit
        let limitLabel = NSTextField(labelWithString: I18N.t("历史条数", "History Limit"))
        limitLabel.font = DS.fontSmall
        limitLabel.textColor = DS.textSec

        maxItemsValueLabel.font = DS.fontSmall
        maxItemsValueLabel.textColor = DS.textPrimary
        maxItemsValueLabel.alignment = .right
        maxItemsValueLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        maxItemsStepper.minValue = 10
        maxItemsStepper.maxValue = 5000
        maxItemsStepper.increment = 10
        maxItemsStepper.target = self
        maxItemsStepper.action = #selector(historyLimitChanged(_:))

        let limitGroup = NSStackView(views: [limitLabel, maxItemsValueLabel, maxItemsStepper])
        limitGroup.orientation = .horizontal
        limitGroup.spacing = 6
        limitGroup.alignment = .centerY

        // Buttons
        let clearStorageBtn = makeTextButton(I18N.t("清理存储", "Clear Storage"), color: DS.danger)
        clearStorageBtn.target = self
        clearStorageBtn.action = #selector(clearStorage)

        let quitBtn = makeTextButton(I18N.t("退出", "Quit"), color: DS.textSec)
        quitBtn.target = self
        quitBtn.action = #selector(quitApp)

        let aboutBtn = makeTextButton(I18N.t("关于", "About"), color: DS.textSec)
        aboutBtn.target = self
        aboutBtn.action = #selector(showAbout)

        languageFilter.removeAllItems()
        languageFilter.addItems(withTitles: [I18N.t("中文", "Chinese"), "English"])
        languageFilter.selectItem(at: I18N.current == .zh ? 0 : 1)
        languageFilter.target = self
        languageFilter.action = #selector(languageChanged)

        let row1 = NSStackView(views: [toggleGroup, NSView(), languageFilter, limitGroup])
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.alignment = .centerY

        storageUsageLabel.font = DS.fontSmall
        storageUsageLabel.textColor = DS.textSec

        let openFinderBtn = makeTextButton(I18N.t("打开访达", "Open in Finder"), color: DS.accent)
        openFinderBtn.target = self
        openFinderBtn.action = #selector(openStorageInFinder)

        let row2 = NSStackView(views: [storageUsageLabel, NSView(), openFinderBtn, aboutBtn, clearStorageBtn, quitBtn])
        row2.orientation = .horizontal
        row2.spacing = 8
        row2.alignment = .centerY

        let stack = NSStackView(views: [row1, row2])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])

        border.frame = CGRect(x: 0, y: 129, width: popoverWidth, height: 1)
        v.layer?.addSublayer(border)
        refreshMetaLabels()

        return v
    }

    private func makeTextButton(_ title: String, color: NSColor) -> NSButton {
        let btn = NSButton(title: title, target: nil, action: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = DS.fontSmall
        btn.contentTintColor = color
        return btn
    }

    // MARK: - Login Item

    private func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Legacy: check via LSSharedFileList (deprecated but functional pre-13)
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }

    private func setLoginItem(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("SMAppService error: \(error)")
            }
        } else {
            // For pre-13: store preference and guide user
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        }
    }

    // MARK: - Actions

    @objc private func clearAll() {
        guard confirm(
            title: I18N.t("确认清空历史？", "Clear all history?"),
            message: I18N.t("将删除所有历史记录（含收藏）。此操作不可撤销。", "This will delete all history (including favorites). This action cannot be undone.")
        ) else { return }
        ClipboardStore.shared.clear()
    }

    @objc private func clearStorage() {
        guard confirm(
            title: I18N.t("确认清理存储？", "Clear storage?"),
            message: I18N.t("将删除 SQLite 历史数据库文件并清空记录。", "This will remove the SQLite history database and clear all records.")
        ) else { return }
        ClipboardStore.shared.clearStorage()
        refreshMetaLabels()
    }

    @objc private func openStorageInFinder() {
        ClipboardStore.shared.revealInFinder()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func languageChanged() {
        I18N.current = languageFilter.indexOfSelectedItem == 0 ? .zh : .en
        lastRenderSignature = ""
        view.subviews.forEach { $0.removeFromSuperview() }
        buildUI()
        reload()
    }

    @objc private func showAbout() {
        if let window = aboutWindowController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "SakuraClipboard")
        title.font = NSFont.systemFont(ofSize: 24, weight: .semibold)
        title.textColor = DS.textPrimary

        let subtitle = NSTextField(labelWithString: I18N.t(
            "轻量、快速、可搜索的剪贴板历史工具",
            "A lightweight, fast, searchable clipboard history tool"
        ))
        subtitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = DS.textSec

        let features = NSTextField(wrappingLabelWithString: I18N.t(
            "• 文本/图片历史\n• 关键词、类型、时间过滤\n• 收藏固定与误清空确认\n• SQLite 持久化与更大历史支持",
            "• Text/Image history\n• Filter by keyword/type/time\n• Favorites and clear confirmation\n• SQLite persistence for larger history"
        ))
        features.font = NSFont.systemFont(ofSize: 13)
        features.textColor = DS.textPrimary

        let version = NSTextField(labelWithString: I18N.t("版本：1.0.0", "Version: 1.0.0"))
        version.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        version.textColor = DS.textSec

        let author = NSTextField(labelWithString: I18N.t("作者：Sakura", "Author: Sakura"))
        author.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        author.textColor = DS.accent

        let stack = NSStackView(views: [title, subtitle, features, version, author])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24)
        ])

        let win = NSWindow(
            contentRect: content.frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = I18N.t("关于 SakuraClipboard", "About SakuraClipboard")
        win.center()
        win.contentView = content
        win.isReleasedWhenClosed = false

        let controller = NSWindowController(window: win)
        aboutWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func historyLimitChanged(_ sender: NSStepper) {
        ClipboardStore.shared.setMaxItems(Int(sender.intValue))
        refreshMetaLabels()
    }

    @objc private func filtersChanged() {
        reload()
    }

    @objc private func searchTextChanged() {
        searchDebounceWorkItem?.cancel()
        let job = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        searchDebounceWorkItem = job
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: job)
    }

    private func handleFavoriteToggle(for item: ClipboardItem) {
        if item.isFavorite {
            ClipboardStore.shared.updateFavorite(id: item.id, isFavorite: false)
            if pendingFavoriteItemID == item.id {
                cancelInlineFavoriteEditing()
            }
            return
        }

        if pendingFavoriteItemID == item.id {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.view.window?.makeFirstResponder(self.favoriteInlineInput)
            }
            return
        }

        pendingFavoriteItemID = item.id
        pendingFavoriteDraftFolder = item.favoriteFolder ?? ""
        reload()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.favoriteInlineInput)
        }
    }

    private func makeInlineFavoriteEditorView(for item: ClipboardItem) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = DS.surfaceHov.cgColor
        card.layer?.cornerRadius = DS.radiusSm
        card.layer?.borderWidth = 1
        card.layer?.borderColor = DS.accent.withAlphaComponent(0.18).cgColor

        let title = NSTextField(labelWithString: I18N.t("收藏到当前收藏夹", "Save to folder"))
        title.font = DS.fontSmall
        title.textColor = DS.textPrimary

        let hintText: String
        if let text = item.text, !text.isEmpty {
            hintText = String(text.prefix(18))
        } else {
            hintText = I18N.t("图片内容", "Image item")
        }
        let subtitle = NSTextField(labelWithString: I18N.t("当前项目：\(hintText)", "Current item: \(hintText)"))
        subtitle.font = DS.fontSmall
        subtitle.textColor = DS.textSec.withAlphaComponent(0.9)
        subtitle.lineBreakMode = .byTruncatingTail

        favoriteInlineInput.placeholderString = I18N.t("输入新收藏夹名称", "Enter a new folder name")
        favoriteInlineInput.stringValue = pendingFavoriteDraftFolder
        favoriteInlineInput.font = DS.fontLabel
        favoriteInlineInput.delegate = self
        favoriteInlineInput.target = self
        favoriteInlineInput.action = #selector(saveInlineFavoriteFolder)

        favoriteInlinePicker.removeAllItems()
        favoriteInlinePicker.addItem(withTitle: I18N.t("已有收藏夹", "Existing folders"))
        favoriteInlinePicker.addItems(withTitles: ClipboardStore.shared.allFavoriteFolders())
        favoriteInlinePicker.target = self
        favoriteInlinePicker.action = #selector(inlineFavoritePickerChanged(_:))

        let saveBtn = NSButton(title: I18N.t("保存", "Save"), target: self, action: #selector(saveInlineFavoriteFolder))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .small
        saveBtn.keyEquivalent = "\r"

        let cancelBtn = NSButton(title: I18N.t("取消", "Cancel"), target: self, action: #selector(cancelInlineFavoriteFolder))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.controlSize = .small

        let titleRow = NSStackView(views: [title, NSView(), cancelBtn, saveBtn])
        titleRow.orientation = .horizontal
        titleRow.spacing = 8
        titleRow.alignment = .centerY

        let inputRow = NSStackView(views: [favoriteInlineInput, favoriteInlinePicker])
        inputRow.orientation = .horizontal
        inputRow.spacing = 8
        inputRow.alignment = .centerY

        favoriteInlinePicker.widthAnchor.constraint(equalToConstant: 118).isActive = true

        let stack = NSStackView(views: [titleRow, subtitle, inputRow])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])

        return card
    }

    @objc private func inlineFavoritePickerChanged(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem > 0 else { return }
        favoriteInlineInput.stringValue = sender.titleOfSelectedItem ?? ""
        pendingFavoriteDraftFolder = favoriteInlineInput.stringValue
    }

    @objc private func saveInlineFavoriteFolder() {
        guard let id = pendingFavoriteItemID else { return }
        let cleaned = favoriteInlineInput.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        ClipboardStore.shared.updateFavorite(id: id, isFavorite: true, folderName: cleaned.isEmpty ? nil : cleaned)
        cancelInlineFavoriteEditing()
    }

    @objc private func cancelInlineFavoriteFolder() {
        cancelInlineFavoriteEditing()
    }

    private func cancelInlineFavoriteEditing() {
        pendingFavoriteItemID = nil
        pendingFavoriteDraftFolder = ""
        favoriteInlineInput.stringValue = ""
        favoriteInlinePicker.removeAllItems()
        reload()
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === favoriteInlineInput else { return }
        pendingFavoriteDraftFolder = favoriteInlineInput.stringValue
    }

    private func refreshFavoriteFolderFilterOptions(preserveSelection: Bool) {
        let oldValue = preserveSelection ? favoriteFolderValues[safe: favoriteFolderFilter.indexOfSelectedItem] ?? nil : nil

        let folders = ClipboardStore.shared.allFavoriteFolders()
        favoriteFolderFilter.removeAllItems()
        favoriteFolderValues = [nil, ClipboardStore.QueryFolderFilter.unfavoritedOnly] + folders.map { Optional($0) }
        favoriteFolderFilter.addItems(withTitles: [
            I18N.t("全部项目", "All Items"),
            I18N.t("仅未收藏", "Unfavorited Only")
        ] + folders)

        if let oldValue, let idx = favoriteFolderValues.firstIndex(where: { $0 == oldValue }) {
            favoriteFolderFilter.selectItem(at: idx)
        } else {
            favoriteFolderFilter.selectItem(at: 0)
        }
    }

    private func currentQuery() -> ClipboardStore.Query {
        let type: ClipboardStore.FilterType
        switch typeFilter.indexOfSelectedItem {
        case 1: type = .text
        case 2: type = .image
        default: type = .all
        }

        let time: ClipboardStore.TimeFilter
        switch timeFilter.indexOfSelectedItem {
        case 1: time = .lastHour
        case 2: time = .today
        case 3: time = .last7Days
        case 4: time = .last30Days
        default: time = .all
        }

        let selectedFolder = favoriteFolderValues[safe: favoriteFolderFilter.indexOfSelectedItem] ?? nil

        return ClipboardStore.Query(
            keyword: searchField.stringValue,
            filterType: type,
            timeFilter: time,
            favoriteFolder: selectedFolder
        )
    }

    private func confirm(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: I18N.t("确认", "Confirm"))
        alert.addButton(withTitle: I18N.t("取消", "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Reload

    @objc func reload() {
        refreshMetaLabels()
        let query = currentQuery()
        let items = ClipboardStore.shared.filteredItems(query: query)
        let signature = renderSignature(query: query, items: items)
        guard signature != lastRenderSignature else { return }
        lastRenderSignature = signature

        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        expandedRow = nil

        if items.isEmpty {
            let wrapper = NSView()
            wrapper.translatesAutoresizingMaskIntoConstraints = false

            let iconLabel = NSTextField(labelWithString: "📋")
            iconLabel.font = NSFont.systemFont(ofSize: 32)

            let msgLabel = NSTextField(labelWithString: "暂无剪贴板记录")
            msgLabel.stringValue = I18N.t("暂无剪贴板记录", "No clipboard history")
            msgLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
            msgLabel.textColor = DS.textSec

            let hint = NSTextField(labelWithString: I18N.t("复制任何文本或图片后将在此显示", "Copy any text or image and it will appear here"))
            hint.font = DS.fontSmall
            hint.textColor = DS.textSec.withAlphaComponent(0.5)

            let emptyStack = NSStackView(views: [iconLabel, msgLabel, hint])
            emptyStack.orientation = .vertical
            emptyStack.spacing = 6
            emptyStack.alignment = .centerX
            emptyStack.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(emptyStack)

            NSLayoutConstraint.activate([
                emptyStack.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                emptyStack.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
                wrapper.heightAnchor.constraint(equalToConstant: 200)
            ])

            contentStack.addArrangedSubview(wrapper)
            wrapper.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            return
        }

        for item in items {
            let row = ClipRowView(item: item)
            row.onCopy = { [weak self] itm in
                self?.copyToClipboard(itm)
                self?.showCopiedToast()
            }
            row.onToggleFavorite = { [weak self] itm in
                self?.handleFavoriteToggle(for: itm)
            }
            row.onRequestImage = { itm in
                ClipboardStore.shared.image(for: itm.id)
            }
            row.onExpandChanged = { [weak self] sourceRow, isExpanded in
                guard let self else { return }
                if isExpanded {
                    if let old = self.expandedRow, old !== sourceRow {
                        old.collapseTextIfNeeded()
                    }
                    self.expandedRow = sourceRow
                } else if self.expandedRow === sourceRow {
                    self.expandedRow = nil
                }
            }
            contentStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            row.hydrateDeferredContent()

            if pendingFavoriteItemID == item.id {
                let editor = makeInlineFavoriteEditorView(for: item)
                contentStack.addArrangedSubview(editor)
                editor.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            }
        }
        syncVisibleRowsHoverState()
    }

    @objc private func scrollBoundsChanged() {
        syncVisibleRowsHoverState()
    }

    private func syncVisibleRowsHoverState() {
        for case let row as ClipRowView in contentStack.arrangedSubviews {
            row.syncHoverStateWithMouseLocation()
        }
    }

    private func renderSignature(query: ClipboardStore.Query, items: [ClipboardItem]) -> String {
        var parts: [String] = []
        parts.append(query.keyword)
        parts.append("\(query.filterType.rawValue)")
        parts.append("\(query.timeFilter.rawValue)")
        parts.append(query.favoriteFolder ?? "")
        parts.append(pendingFavoriteItemID ?? "")
        parts.append("\(items.count)")
        parts.append(items.map { "\($0.id):\($0.isFavorite ? 1 : 0):\($0.favoriteFolder ?? ""):\($0.textLength)" }.joined(separator: "|"))
        return parts.joined(separator: "#")
    }

    private func copyToClipboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.kind == .text {
            let textToCopy = item.hasMoreText
                ? (ClipboardStore.shared.fullText(for: item.id) ?? item.text)
                : item.text
            if let textToCopy {
                pb.setString(textToCopy, forType: .string)
            }
        } else if let i = item.image ?? ClipboardStore.shared.image(for: item.id) {
            pb.writeObjects([i])
        }
    }

    private func showCopiedToast() {
        copiedToast?.removeFromSuperview()

        let toast = NSView()
        toast.wantsLayer = true
        toast.layer?.cornerRadius = DS.radiusSm
        toast.layer?.backgroundColor = DS.accent.withAlphaComponent(0.95).cgColor
        toast.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: I18N.t("✓ 已复制到剪贴板", "✓ Copied to clipboard"))
        label.font = DS.fontSmall
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        toast.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: toast.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: toast.centerYAnchor),
            toast.widthAnchor.constraint(equalTo: label.widthAnchor, constant: 20),
            toast.heightAnchor.constraint(equalToConstant: 28)
        ])

        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -60)
        ])

        toast.layer?.opacity = 0
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            toast.layer?.opacity = 1
        }, completionHandler: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.3
                    toast.layer?.opacity = 0
                }, completionHandler: {
                    toast.removeFromSuperview()
                })
            }
        })

        copiedToast = toast
    }

    private func refreshMetaLabels() {
        let maxItems = ClipboardStore.shared.maxItems
        historySubtitleLabel.stringValue = I18N.t("最近 \(maxItems) 条记录", "Latest \(maxItems) records")
        maxItemsValueLabel.stringValue = "\(maxItems)"
        maxItemsStepper.integerValue = maxItems
        storageUsageLabel.stringValue = I18N.t(
            "存储占用: \(ClipboardStore.shared.storageUsageDescription())",
            "Storage: \(ClipboardStore.shared.storageUsageDescription())"
        )
        refreshFavoriteFolderFilterOptions(preserveSelection: true)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
