import Cocoa
import ServiceManagement

// MARK: - FlippedView (scroll content starts from top)
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let monitor = ClipboardMonitor()

    private var inlineHistoryControllers: [HistoryListPopoverController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let btn = statusItem.button {
            btn.title = ""
            if let appIcon = (NSApp.applicationIconImage?.copy() as? NSImage) ?? NSApp.applicationIconImage {
                appIcon.size = NSSize(width: 18, height: 18)
                appIcon.isTemplate = false
                btn.image = appIcon
            }
            btn.imagePosition = .imageOnly
            btn.action = #selector(toggle)
            btn.target = self
        }

        monitor.start()
    }

    @objc func toggle() {
        guard let btn = statusItem.button else { return }
        showNativeMenu(relativeTo: btn)
    }

    private func showNativeMenu(relativeTo button: NSStatusBarButton) {
        inlineHistoryControllers.removeAll()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let latestItem = NSMenuItem(title: latestItemTitle(), action: nil, keyEquivalent: "")
        latestItem.isEnabled = false
        menu.addItem(latestItem)
        menu.addItem(.separator())

        let history = NSMenuItem(title: I18N.t("历史记录", "History"), action: nil, keyEquivalent: "")
        history.submenu = makeInlineHistorySubmenu(mode: .all)
        menu.addItem(history)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: I18N.t("开机自启", "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(loginItem)

        let retentionRoot = NSMenuItem(title: I18N.t("自动清理", "Auto Clean"), action: nil, keyEquivalent: "")
        retentionRoot.submenu = makeRetentionMenu()
        menu.addItem(retentionRoot)

        let historyLimitRoot = NSMenuItem(title: I18N.t("历史条数", "History Limit"), action: nil, keyEquivalent: "")
        historyLimitRoot.submenu = makeHistoryLimitMenu()
        menu.addItem(historyLimitRoot)

        let languageRoot = NSMenuItem(title: I18N.t("语言", "Language"), action: nil, keyEquivalent: "")
        languageRoot.submenu = makeLanguageMenu()
        menu.addItem(languageRoot)

        menu.addItem(.separator())

        let about = NSMenuItem(title: I18N.t("关于", "About"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: I18N.t("退出", "Quit"), action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func makeInlineHistorySubmenu(mode: HistoryListPopoverController.Mode) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let controller = HistoryListPopoverController()
        controller.loadViewIfNeeded()
        controller.switchMode(mode)
        controller.setMenuEmbeddedStyle(width: 336, height: 320)
        inlineHistoryControllers.append(controller)

        let contentItem = NSMenuItem()
        contentItem.view = controller.view
        submenu.addItem(contentItem)

        return submenu
    }

    func menuDidClose(_ menu: NSMenu) {
        inlineHistoryControllers.removeAll()
    }

    private func latestItemTitle() -> String {
        let item = ClipboardStore.shared.filteredItems(
            query: .init(keyword: "", filterType: .all, favoritesOnly: false, favoriteFolder: nil),
            limit: 1,
            offset: 0
        ).first
        guard let item else { return I18N.t("当前：无记录", "Current: No history") }
        if let text = item.text, !text.isEmpty {
            return I18N.t("当前：", "Current: ") + compactTitle(text, max: 18)
        }
        return I18N.t("当前：[图片]", "Current: [Image]")
    }

    private func compactTitle(_ raw: String, max: Int) -> String {
        let oneLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard oneLine.count > max else { return oneLine }
        let idx = oneLine.index(oneLine.startIndex, offsetBy: max)
        return String(oneLine[..<idx]) + "…"
    }

    private func makeRetentionMenu() -> NSMenu {
        let menu = NSMenu()
        let options: [(String, Int?)] = [
            (I18N.t("1天", "1 day"), 1),
            (I18N.t("3天", "3 days"), 3),
            (I18N.t("5天", "5 days"), 5),
            (I18N.t("7天", "7 days"), 7),
            (I18N.t("15天", "15 days"), 15),
            (I18N.t("30天", "30 days"), 30),
            (I18N.t("永久", "Forever"), nil)
        ]
        for (title, days) in options {
            let it = NSMenuItem(title: title, action: #selector(setRetentionFromMenu(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = days as Any?
            it.state = ClipboardStore.shared.retentionDays == days ? .on : .off
            menu.addItem(it)
        }
        return menu
    }

    @objc private func setRetentionFromMenu(_ sender: NSMenuItem) {
        ClipboardStore.shared.setRetentionDays(sender.representedObject as? Int)
    }

    private func makeHistoryLimitMenu() -> NSMenu {
        let menu = NSMenu()
        let values = [100, 200, 350, 500, 1000, 2000, 5000]
        for value in values {
            let it = NSMenuItem(title: "\(value)", action: #selector(setHistoryLimitFromMenu(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = value
            it.state = ClipboardStore.shared.maxItems == value ? .on : .off
            menu.addItem(it)
        }
        return menu
    }

    @objc private func setHistoryLimitFromMenu(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Int else { return }
        ClipboardStore.shared.setMaxItems(value)
    }

    private func makeLanguageMenu() -> NSMenu {
        let menu = NSMenu()
        let zh = NSMenuItem(title: "中文", action: #selector(setLanguageZh), keyEquivalent: "")
        zh.target = self
        zh.state = I18N.current == .zh ? .on : .off
        let en = NSMenuItem(title: "English", action: #selector(setLanguageEn), keyEquivalent: "")
        en.target = self
        en.state = I18N.current == .en ? .on : .off
        menu.addItem(zh)
        menu.addItem(en)
        return menu
    }

    @objc private func setLanguageZh() {
        I18N.current = .zh
    }

    @objc private func setLanguageEn() {
        I18N.current = .en
    }

    private func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let enabled = !isLoginItemEnabled()
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
            UserDefaults.standard.set(enabled, forKey: "launchAtLogin")
        }
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitFromMenu() {
        NSApplication.shared.terminate(nil)
    }
}
