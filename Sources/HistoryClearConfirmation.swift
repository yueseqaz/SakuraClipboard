import Cocoa

enum HistoryClearConfirmation {
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = I18N.t("清理历史记录", "Clear Clipboard History")
        alert.informativeText = I18N.t(
            "默认保留收藏，只清理普通历史记录。勾选下方选项后，收藏也会被删除。此操作不可恢复。",
            "Favorites are kept by default. Select the option below to also delete favorites. This cannot be undone."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: I18N.t("清理", "Clear"))
        alert.addButton(withTitle: I18N.t("取消", "Cancel"))
        let checkbox = NSButton(checkboxWithTitle: I18N.t("同时清理收藏", "Also delete favorites"), target: nil, action: nil)
        checkbox.state = .off
        checkbox.sizeToFit()
        alert.accessoryView = checkbox
        return alert
    }

    static func includesFavorites(in alert: NSAlert) -> Bool {
        (alert.accessoryView as? NSButton)?.state == .on
    }
}
