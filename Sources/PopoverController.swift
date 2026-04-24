import Cocoa
import ServiceManagement

// MARK: - PopoverController
class PopoverController: NSViewController, NSTextFieldDelegate {
    private let popoverWidth: CGFloat = 338
    private let rowWidth: CGFloat = 314
    private let footerHeight: CGFloat = 122
    private let scrollView = NSScrollView()
    private let contentStack = NSStackView()
    private var copiedToast: NSView?
    private let historySubtitleLabel = NSTextField(labelWithString: "")
    private let maxItemsValueLabel = NSTextField(labelWithString: "")
    private let maxItemsStepper = NSStepper()
    private let storageUsageLabel = NSTextField(labelWithString: "")
    private let searchField = NSSearchField()
    private let typeTabs = NSSegmentedControl()
    private let favoriteFolderFilter = NSPopUpButton()
    private let retentionPolicyFilter = NSPopUpButton()
    private let languageFilter = NSPopUpButton()
    private weak var expandedRow: ClipRowView?
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var visibleSyncWorkItem: DispatchWorkItem?
    private var lastRenderSignature = ""
    private var hasPendingReload = true
    private var isPopoverVisible = false
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
            self, selector: #selector(handleClipboardUpdated),
            name: .clipboardUpdated, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        DispatchQueue.main.async {
            self.refreshMetaLabels(refreshFolders: true)
        }
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
        divider.borderColor = DS.border.withAlphaComponent(0.55)
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
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
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
            header.heightAnchor.constraint(equalToConstant: 140),

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
            footer.heightAnchor.constraint(equalToConstant: footerHeight)
        ])
    }

    private func buildHeader() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = DS.headerBg.cgColor

        let icon = NSTextField(labelWithString: "⌘")
        icon.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        icon.textColor = DS.accent

        let title = NSTextField(labelWithString: I18N.t("剪贴板历史", "Clipboard History"))
        title.font = DS.fontTitleStrong
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

        let clearBtn = makeTextButton(I18N.t("清空未收藏", "Clear Others"), color: DS.danger)
        clearBtn.target = self
        clearBtn.action = #selector(clearAll)
        clearBtn.translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = I18N.t("按关键字搜索文本", "Search text by keyword")
        searchField.controlSize = .large
        searchField.maximumRecents = 0
        searchField.recentsAutosaveName = nil
        searchField.target = self
        searchField.action = #selector(searchTextChanged)
        searchField.sendsSearchStringImmediately = true

        let tabTitles = [
            I18N.t("全部", "All"),
            I18N.t("文本", "Text"),
            I18N.t("图片", "Image"),
            I18N.t("收藏", "Favorites")
        ]
        let previousTypeIndex = max(typeTabs.selectedSegment, 0)
        typeTabs.segmentCount = tabTitles.count
        for (idx, title) in tabTitles.enumerated() {
            typeTabs.setLabel(title, forSegment: idx)
            typeTabs.setWidth(42, forSegment: idx)
        }
        typeTabs.selectedSegment = min(previousTypeIndex, tabTitles.count - 1)
        typeTabs.segmentStyle = .rounded
        typeTabs.controlSize = .small
        typeTabs.target = self
        typeTabs.action = #selector(filtersChanged)

        refreshFavoriteFolderFilterOptions(preserveSelection: true)
        favoriteFolderFilter.controlSize = .large
        favoriteFolderFilter.target = self
        favoriteFolderFilter.action = #selector(filtersChanged)
        updateFavoriteFolderFilterState()

        let topRow = NSStackView(views: [left, NSView(), clearBtn])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.alignment = .centerY

        let filterRow = NSStackView(views: [typeTabs, favoriteFolderFilter])
        filterRow.orientation = .horizontal
        filterRow.spacing = 8
        filterRow.alignment = .centerY

        let stack = NSStackView(views: [topRow, searchField, filterRow])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -10),
            typeTabs.widthAnchor.constraint(equalToConstant: 168),
            favoriteFolderFilter.widthAnchor.constraint(equalToConstant: 138)
        ])

        return v
    }

    private func buildFooter() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = DS.footerBg.cgColor

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

        let retentionLabel = NSTextField(labelWithString: I18N.t("自动清理", "Auto clean"))
        retentionLabel.font = DS.fontSmall
        retentionLabel.textColor = DS.textSec

        configureRetentionPolicyFilter()

        let retentionGroup = NSStackView(views: [retentionLabel, retentionPolicyFilter])
        retentionGroup.orientation = .horizontal
        retentionGroup.spacing = 6
        retentionGroup.alignment = .centerY

        // Buttons
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

        languageFilter.widthAnchor.constraint(equalToConstant: 86).isActive = true

        let spacer1 = NSView()
        let spacer2 = NSView()
        let spacer3 = NSView()

        let row1 = NSStackView(views: [toggleGroup, spacer1, languageFilter, limitGroup])
        row1.orientation = .horizontal
        row1.spacing = 8
        row1.alignment = .centerY

        storageUsageLabel.font = DS.fontSmall
        storageUsageLabel.textColor = DS.textSec

        let openFinderBtn = makeTextButton(I18N.t("打开访达", "Open in Finder"), color: DS.accent)
        openFinderBtn.target = self
        openFinderBtn.action = #selector(openStorageInFinder)

        let row2 = NSStackView(views: [retentionGroup, spacer2, storageUsageLabel])
        row2.orientation = .horizontal
        row2.spacing = 8
        row2.alignment = .centerY

        let row3 = NSStackView(views: [spacer3, openFinderBtn, aboutBtn, quitBtn])
        row3.orientation = .horizontal
        row3.spacing = 12
        row3.alignment = .centerY

        let stack = NSStackView(views: [row1, row2, row3])
        stack.orientation = .vertical
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: v.centerYAnchor)
        ])

        refreshMetaLabels(refreshFolders: true)

        return v
    }

    private func makeTextButton(_ title: String, color: NSColor) -> NSButton {
        let btn = NSButton(title: title, target: nil, action: nil)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = DS.fontLabel
        btn.contentTintColor = color
        btn.setButtonType(.momentaryChange)
        return btn
    }

    private func configureRetentionPolicyFilter() {
        retentionPolicyFilter.removeAllItems()
        retentionPolicyFilter.addItems(withTitles: [
            I18N.t("1天", "1 day"),
            I18N.t("3天", "3 days"),
            I18N.t("5天", "5 days"),
            I18N.t("7天", "7 days"),
            I18N.t("15天", "15 days"),
            I18N.t("30天", "30 days"),
            I18N.t("永久", "Forever")
        ])
        retentionPolicyFilter.target = self
        retentionPolicyFilter.action = #selector(retentionPolicyChanged)
        if !retentionPolicyFilter.constraints.contains(where: { $0.firstAttribute == .width }) {
            retentionPolicyFilter.widthAnchor.constraint(equalToConstant: 86).isActive = true
        }
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
            title: I18N.t("确认清空未收藏内容？", "Clear non-favorites?"),
            message: I18N.t(
                "此操作只会删除未收藏条目，已收藏内容会保留。若想删除某个收藏条目，请先取消收藏，再执行清空。",
                "This only removes unfavorited items and keeps favorites. To remove a favorite item, unfavorite it first, then clear."
            )
        ) else { return }
        ClipboardStore.shared.clear()
        refreshMetaLabels(refreshFolders: true)
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
        refreshMetaLabels(refreshFolders: true)
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
        title.textColor = .labelColor

        let subtitle = NSTextField(labelWithString: I18N.t(
            "轻量、快速、可搜索的剪贴板历史工具",
            "A lightweight, fast, searchable clipboard history tool"
        ))
        subtitle.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = .secondaryLabelColor

        let features = NSTextField(wrappingLabelWithString: I18N.t(
            "• 文本/图片历史\n• 关键词、类型、时间过滤\n• 收藏保留与安全清空\n• SQLite 持久化与更大历史支持",
            "• Text/Image history\n• Filter by keyword/type/time\n• Favorite-safe clearing\n• SQLite persistence for larger history"
        ))
        features.font = NSFont.systemFont(ofSize: 13)
        features.textColor = .labelColor

        let version = NSTextField(labelWithString: I18N.t("版本：1.0.0", "Version: 1.0.0"))
        version.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        version.textColor = .secondaryLabelColor

        let author = NSTextField(labelWithString: I18N.t("作者：Sakura", "Author: Sakura"))
        author.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        author.textColor = .controlAccentColor

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
        refreshMetaLabels(refreshFolders: false)
    }

    @objc private func retentionPolicyChanged() {
        let mappedDays: [Int?] = [1, 3, 5, 7, 15, 30, nil]
        let idx = max(0, min(retentionPolicyFilter.indexOfSelectedItem, mappedDays.count - 1))
        ClipboardStore.shared.setRetentionDays(mappedDays[idx])
        refreshMetaLabels(refreshFolders: false)
        reload()
    }

    @objc private func filtersChanged() {
        updateFavoriteFolderFilterState()
        reload()
    }

    @objc private func handleClipboardUpdated() {
        if isPopoverVisible {
            reload()
        } else {
            hasPendingReload = true
        }
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
            refreshFavoriteFolderFilterOptions(preserveSelection: true)
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
        refreshFavoriteFolderFilterOptions(preserveSelection: true)
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
        favoriteFolderValues = [nil] + folders.map { Optional($0) }
        favoriteFolderFilter.addItems(withTitles: [
            I18N.t("全部收藏", "All Favorites")
        ] + folders)

        if let oldValue, let idx = favoriteFolderValues.firstIndex(where: { $0 == oldValue }) {
            favoriteFolderFilter.selectItem(at: idx)
        } else {
            favoriteFolderFilter.selectItem(at: 0)
        }

        updateFavoriteFolderFilterState()
    }

    private func updateFavoriteFolderFilterState() {
        let isFavoriteMode = typeTabs.selectedSegment == 3
        favoriteFolderFilter.isEnabled = isFavoriteMode
        favoriteFolderFilter.alphaValue = isFavoriteMode ? 1 : 0.55
    }

    private func currentQuery() -> ClipboardStore.Query {
        let type: ClipboardStore.FilterType
        let favoritesOnly = typeTabs.selectedSegment == 3
        switch typeTabs.selectedSegment {
        case 1: type = .text
        case 2: type = .image
        default: type = .all
        }

        let selectedFolder = favoritesOnly
            ? (favoriteFolderValues[safe: favoriteFolderFilter.indexOfSelectedItem] ?? nil)
            : nil

        return ClipboardStore.Query(
            keyword: searchField.stringValue,
            filterType: type,
            favoritesOnly: favoritesOnly,
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
        guard isPopoverVisible else {
            hasPendingReload = true
            return
        }
        hasPendingReload = false
        refreshMetaLabels(refreshFolders: false)
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
            if item.kind == .image {
                row.hydrateDeferredContent()
            }

            if pendingFavoriteItemID == item.id {
                let editor = makeInlineFavoriteEditorView(for: item)
                contentStack.addArrangedSubview(editor)
                editor.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
            }
        }
        scheduleVisibleRowsMaintenance(immediate: true)
    }

    @objc private func scrollBoundsChanged() {
        scheduleVisibleRowsMaintenance(immediate: false)
    }

    private func syncVisibleRowsHoverState() {
        for row in visibleRows() {
            row.syncHoverStateWithMouseLocation()
        }
    }

    private func hydrateVisibleRowsDeferredContent() {
        let rows = visibleRows().filter { $0.needsDeferredImageHydration }
        for row in rows.prefix(2) {
            row.hydrateDeferredContent()
        }
        if rows.count > 2 {
            scheduleVisibleRowsMaintenance(immediate: false)
        }
    }

    private func visibleRows() -> [ClipRowView] {
        guard let docView = scrollView.documentView else { return [] }
        view.layoutSubtreeIfNeeded()
        let visibleRect = docView.convert(scrollView.contentView.bounds, from: scrollView.contentView)
            .insetBy(dx: 0, dy: -80)
        let rows = contentStack.arrangedSubviews.compactMap { $0 as? ClipRowView }.filter {
            $0.frame.intersects(visibleRect)
        }
        if !rows.isEmpty { return rows }
        return Array(contentStack.arrangedSubviews.compactMap { $0 as? ClipRowView }.prefix(10))
    }

    private func scheduleVisibleRowsMaintenance(immediate: Bool) {
        visibleSyncWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.hydrateVisibleRowsDeferredContent()
            self?.syncVisibleRowsHoverState()
        }
        visibleSyncWorkItem = work
        if immediate {
            DispatchQueue.main.async(execute: work)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04, execute: work)
        }
    }

    func popoverVisibilityChanged(isVisible: Bool) {
        isPopoverVisible = isVisible
        if isVisible {
            refreshMetaLabels(refreshFolders: true)
            if hasPendingReload {
                reload()
            } else {
                scheduleVisibleRowsMaintenance(immediate: true)
            }
        } else {
            visibleSyncWorkItem?.cancel()
        }
    }

    private func renderSignature(query: ClipboardStore.Query, items: [ClipboardItem]) -> String {
        var parts: [String] = []
        parts.append(query.keyword)
        parts.append("\(query.filterType.rawValue)")
        parts.append(query.favoritesOnly ? "1" : "0")
        parts.append(query.favoriteFolder ?? "")
        parts.append(pendingFavoriteItemID ?? "")
        parts.append("\(items.count)")
        let sampled = items.prefix(40).map { "\($0.id):\($0.isFavorite ? 1 : 0):\($0.favoriteFolder ?? ""):\($0.textLength)" }
        parts.append(sampled.joined(separator: "|"))
        parts.append(items.last?.id ?? "")
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

    private func refreshMetaLabels(refreshFolders: Bool) {
        let maxItems = ClipboardStore.shared.maxItems
        historySubtitleLabel.stringValue = I18N.t("最近 \(maxItems) 条记录", "Latest \(maxItems) records")
        maxItemsValueLabel.stringValue = "\(maxItems)"
        maxItemsStepper.integerValue = maxItems
        let retentionDays = ClipboardStore.shared.retentionDays
        let mappedDays: [Int?] = [1, 3, 5, 7, 15, 30, nil]
        retentionPolicyFilter.selectItem(at: mappedDays.firstIndex(where: { $0 == retentionDays }) ?? (mappedDays.count - 1))
        storageUsageLabel.stringValue = I18N.t(
            "存储占用: \(ClipboardStore.shared.storageUsageDescription())",
            "Storage: \(ClipboardStore.shared.storageUsageDescription())"
        )
        if refreshFolders {
            refreshFavoriteFolderFilterOptions(preserveSelection: true)
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
