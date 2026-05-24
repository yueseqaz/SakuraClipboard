# SakuraClipboard UX 改进实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 提升 SakuraClipboard 的日常使用体验，使其达到主流剪贴板工具的交互水平

**Architecture:** 在现有 NSMenu + NSViewController 架构上增量改进，不改变核心数据层。通过 NSEvent 全局监听实现快捷键，通过 NSPopover 实现 HUD 反馈，右键菜单通过 NSMenu 实现。

**Tech Stack:** Swift, Cocoa, SQLite3, Carbon (全局快捷键)

---

## 改动概览

| 文件 | 改动内容 |
|------|----------|
| `Sources/AppDelegate.swift` | 添加全局快捷键、搜索栏、HUD 反馈 |
| `Sources/HistoryListPopoverController.swift` | 时间戳显示、扩展文本、右键菜单、数字键快捷粘贴 |
| `Sources/ClipboardItem.swift` | 无需改动 |
| `Sources/ClipboardStore.swift` | 搜索查询支持 |
| `Sources/KeyboardShortcut.swift` | 新建：全局快捷键管理 |
| `Sources/HUDWindow.swift` | 新建：复制成功 HUD 提示 |

---

### Task 1: 全局键盘快捷键

**Files:**
- Create: `Sources/KeyboardShortcut.swift`
- Modify: `Sources/AppDelegate.swift`
- Modify: `build.sh` (添加 Carbon framework)

- [ ] **Step 1: 创建 KeyboardShortcut.swift**

```swift
import Cocoa
import Carbon.HIToolbox

final class KeyboardShortcut {
    static let shared = KeyboardShortcut()
    
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    
    private init() {}
    
    func register(key: Int, modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.action = action
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let wrapper = Unmanaged.passRetained(HotKeyWrapper(action: action))
        let ptr = wrapper.toOpaque()
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, ptr -> OSStatus in
                guard let ptr else { return OSStatus(eventNotHandledErr) }
                let wrapper = Unmanaged<HotKeyWrapper>.fromOpaque(ptr).takeUnretainedValue()
                wrapper.action()
                return noErr
            },
            1,
            &eventType,
            ptr,
            &handler
        )
        
        var hotKeyID = EventHotKeyID(signature: OSType(0x53434C50), id: 1) // 'SCLP'
        RegisterEventHotKey(
            UInt32(key),
            modifiers.carbonFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
    
    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }
    
    deinit {
        unregister()
    }
}

private class HotKeyWrapper {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
}

extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }
}
```

- [ ] **Step 2: 修改 AppDelegate 注册快捷键**

在 `applicationDidFinishLaunching` 末尾添加：

```swift
KeyboardShortcut.shared.register(key: kVK_ANSI_C, modifiers: [.command, .shift]) { [weak self] in
    self?.showFromKeyboard()
}
```

添加方法：

```swift
@objc private func showFromKeyboard() {
    guard let btn = statusItem.button else { return }
    showNativeMenu(relativeTo: btn)
}
```

- [ ] **Step 3: 更新 build.sh 添加 Carbon framework**

修改编译命令，添加 `-framework Carbon`：

```bash
swiftc -O -framework Cocoa -framework ServiceManagement -framework Carbon -lsqlite3 Sources/*.swift -o "$BUILD_DIR/$APP_NAME"
```

- [ ] **Step 4: 测试编译**

```bash
./build.sh
```

预期：编译成功，无错误

- [ ] **Step 5: 提交**

```bash
git add Sources/KeyboardShortcut.swift Sources/AppDelegate.swift build.sh
git commit -m "feat: add global keyboard shortcut Cmd+Shift+C"
```

---

### Task 2: 历史列表显示时间戳

**Files:**
- Modify: `Sources/HistoryListPopoverController.swift`
- Modify: `Sources/Localization.swift`

- [ ] **Step 1: 在 Localization.swift 添加时间格式化函数**

```swift
extension I18N {
    static func relativeTime(from date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return current == .zh ? "刚刚" : "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return current == .zh ? "\(mins)分钟前" : "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return current == .zh ? "\(hours)小时前" : "\(hours)h ago"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return current == .zh ? "\(days)天前" : "\(days)d ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = current == .zh ? "MM/dd" : "MM/dd"
            return formatter.string(from: date)
        }
    }
}
```

- [ ] **Step 2: 修改 HistoryListPopoverController 的 tableView cell**

在 `tableView(_:viewFor:row:)` 方法中，修改 cell 创建部分，添加时间戳标签：

在 `cell.addSubview(label)` 之后添加：

```swift
let timeLabel = NSTextField(labelWithString: "")
timeLabel.identifier = NSUserInterfaceItemIdentifier("timeLabel")
timeLabel.font = NSFont.systemFont(ofSize: 11)
timeLabel.textColor = .secondaryLabelColor
timeLabel.alignment = .right
timeLabel.translatesAutoresizingMaskIntoConstraints = false
cell.addSubview(timeLabel)
```

更新约束，将 label 的 trailing 改为给 timeLabel 留空间：

```swift
NSLayoutConstraint.activate([
    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    icon.widthAnchor.constraint(equalToConstant: 18),
    icon.heightAnchor.constraint(equalToConstant: 18),

    label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
    label.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -8),
    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    
    timeLabel.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
    timeLabel.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50)
])
```

在 cell 数据填充部分添加：

```swift
let timeLabel = cell.subviews.first(where: { $0.identifier?.rawValue == "timeLabel" }) as? NSTextField
timeLabel?.stringValue = I18N.relativeTime(from: item.date)
timeLabel?.textColor = row == hoveredRow ? .selectedMenuItemTextColor : .secondaryLabelColor
```

- [ ] **Step 3: 测试编译**

```bash
./build.sh
```

- [ ] **Step 4: 提交**

```bash
git add Sources/HistoryListPopoverController.swift Sources/Localization.swift
git commit -m "feat: show relative timestamps in history list"
```

---

### Task 3: 扩展文本显示长度

**Files:**
- Modify: `Sources/HistoryListPopoverController.swift`

- [ ] **Step 1: 修改 short() 函数**

将 `short()` 函数的截断长度从 18 改为 50：

```swift
private func short(_ text: String) -> String {
    let line = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    let n = 50
    guard line.count > n else { return line }
    let idx = line.index(line.startIndex, offsetBy: n)
    return String(line[<idx]) + "…"
}
```

- [ ] **Step 2: 调整列宽以适应更长文本**

在 `buildUI()` 方法中，修改列宽：

```swift
let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
col.width = 320
```

保持 320 不变，因为已经为 timeLabel 留了空间。

- [ ] **Step 3: 测试编译**

```bash
./build.sh
```

- [ ] **Step 4: 提交**

```bash
git add Sources/HistoryListPopoverController.swift
git commit -m "feat: expand text preview from 18 to 50 characters"
```

---

### Task 4: 搜索功能

**Files:**
- Modify: `Sources/HistoryListPopoverController.swift`
- Modify: `Sources/ClipboardStore.swift` (已支持搜索，只需确保 Query 使用正确)

- [ ] **Step 1: 添加搜索栏到 HistoryListPopoverController**

添加属性：

```swift
private let searchField = NSSearchField()
private var searchKeyword = ""
```

在 `buildUI()` 方法中，在 scrollView 之前添加搜索栏：

```swift
searchField.placeholderString = I18N.t("搜索历史记录...", "Search history...")
searchField.font = NSFont.systemFont(ofSize: 13)
searchField.translatesAutoresizingMaskIntoConstraints = false
searchField.target = self
searchField.action = #selector(searchChanged)
searchField.sendsSearchStringImmediately = true
effectView.addSubview(searchField)
```

添加搜索栏约束：

```swift
NSLayoutConstraint.activate([
    // ... 现有约束 ...
    
    searchField.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 8),
    searchField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 12),
    searchField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -12),
    searchField.heightAnchor.constraint(equalToConstant: 28),
])
```

更新 scrollView 的 top 约束：

```swift
scrollTopWithHeaderConstraint = searchField.bottomAnchor.constraint(equalTo: scrollView.topAnchor, constant: -8)
```

- [ ] **Step 2: 添加搜索处理方法**

```swift
@objc private func searchChanged() {
    searchKeyword = searchField.stringValue
    resetAndLoad()
}
```

- [ ] **Step 3: 修改 loadNextPageIfNeeded 使用搜索关键词**

```swift
let query = ClipboardStore.Query(
    keyword: searchKeyword,
    filterType: .all,
    favoritesOnly: mode == .favorites,
    favoriteFolder: nil
)
```

- [ ] **Step 4: 在 setMenuEmbeddedStyle 中隐藏搜索栏**

```swift
func setMenuEmbeddedStyle(width: CGFloat, height: CGFloat) {
    loadViewIfNeeded()
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    titleLabel.isHidden = true
    topDivider.isHidden = true
    searchField.isHidden = true  // 添加这行
    scrollTopWithHeaderConstraint?.isActive = false
    scrollTopCompactConstraint?.isActive = true
    tableView.rowHeight = 24
    tableView.intercellSpacing = NSSize(width: 0, height: 2)
}
```

- [ ] **Step 5: 测试编译**

```bash
./build.sh
```

- [ ] **Step 6: 提交**

```bash
git add Sources/HistoryListPopoverController.swift
git commit -m "feat: add search bar to history list"
```

---

### Task 5: 右键上下文菜单

**Files:**
- Modify: `Sources/HistoryListPopoverController.swift`

- [ ] **Step 1: 添加右键菜单支持**

修改 tableView 创建，添加 menu 代理：

```swift
tableView.menu = createContextMenu()
```

添加方法：

```swift
private func createContextMenu() -> NSMenu {
    let menu = NSMenu()
    menu.delegate = self
    return menu
}
```

让类遵循 NSMenuDelegate：

```swift
final class HistoryListPopoverController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
```

- [ ] **Step 2: 实现 NSMenuDelegate**

```swift
func menuNeedsUpdate(_ menu: NSMenu) {
    let row = tableView.clickedRow
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
```

- [ ] **Step 3: 实现菜单动作**

```swift
@objc private func contextCopy(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    let item = items.first(where: { $0.id == id })
    guard let item else { return }
    
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

@objc private func contextToggleFavorite(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    ClipboardStore.shared.toggleFavorite(id: id)
    resetAndLoad()
}

@objc private func contextDelete(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    // 需要在 ClipboardStore 添加 delete 方法
    ClipboardStore.shared.deleteItem(id: id)
    resetAndLoad()
}
```

- [ ] **Step 4: 在 ClipboardStore 添加删除方法**

```swift
func deleteItem(id: String) {
    dbLock.lock()
    defer { dbLock.unlock() }
    execute(
        "DELETE FROM clipboard_items WHERE id = ?;",
        bind: { stmt in
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        }
    )
    loadAll()
    notifyClipboardUpdated()
}
```

- [ ] **Step 5: 测试编译**

```bash
./build.sh
```

- [ ] **Step 6: 提交**

```bash
git add Sources/HistoryListPopoverController.swift Sources/ClipboardStore.swift
git commit -m "feat: add right-click context menu with copy/favorite/delete"
```

---

### Task 6: 数字键快捷粘贴

**Files:**
- Modify: `Sources/HistoryListPopoverController.swift`

- [ ] **Step 1: 添加键盘事件监听**

添加属性：

```swift
private var localMonitor: Any?
```

在 `viewDidLoad` 末尾添加：

```swift
localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    self?.handleKeyDown(event)
    return event
}
```

在 `deinit` 中清理：

```swift
if let localMonitor {
    NSEvent.removeMonitor(localMonitor)
}
```

- [ ] **Step 2: 实现键盘处理**

```swift
private func handleKeyDown(_ event: NSEvent) {
    // 数字键 1-9 快速粘贴
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
        let chars = event.charactersIgnoringModifiers ?? ""
        if let num = Int(chars), num >= 1, num <= 9, num <= items.count {
            let index = num - 1
            let item = items[index]
            copyItem(item)
            tableView.deselectRow(index)
        }
    }
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
```

- [ ] **Step 3: 在列表项前显示数字**

修改 `tableView(_:viewFor:row:)` 中的 label 显示：

```swift
if let text = item.text, !text.isEmpty {
    let prefix = row < 9 ? "\(row + 1)  " : "   "
    label?.stringValue = prefix + short(text)
    icon?.image = nil
    icon?.isHidden = true
} else {
    let prefix = row < 9 ? "\(row + 1)  " : "   "
    label?.stringValue = prefix + I18N.t("[图片]", "[Image]")
    icon?.image = thumbnail(for: item)
    icon?.isHidden = false
}
```

- [ ] **Step 4: 测试编译**

```bash
./build.sh
```

- [ ] **Step 5: 提交**

```bash
git add Sources/HistoryListPopoverController.swift
git commit -m "feat: add number key quick paste (1-9)"
```

---

### Task 7: 复制成功 HUD 提示

**Files:**
- Create: `Sources/HUDWindow.swift`
- Modify: `Sources/HistoryListPopoverController.swift` (调用 HUD)

- [ ] **Step 1: 创建 HUDWindow.swift**

```swift
import Cocoa

final class HUDWindow {
    private static var window: NSWindow?
    private static var hideWorkItem: DispatchWorkItem?
    
    static func show(_ text: String) {
        hideWorkItem?.cancel()
        window?.close()
        
        let width: CGFloat = 120
        let height: CGFloat = 36
        
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let x = screenFrame.midX - width / 2
        let y = screenFrame.minY + 100
        
        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        
        let bgView = NSVisualEffectView(frame: contentView.bounds)
        bgView.material = .hudWindow
        bgView.blendingMode = .behindWindow
        bgView.state = .active
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 8
        bgView.layer?.masksToBounds = true
        contentView.addSubview(bgView)
        
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = contentView.bounds
        contentView.addSubview(label)
        
        panel.contentView = contentView
        panel.alphaValue = 0
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        
        panel.orderFrontRegardless()
        window = panel
        
        let workItem = DispatchWorkItem {
            hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }
    
    private static func hide() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
            self.window = nil
        })
    }
}
```

- [ ] **Step 2: 在 copySelected 中调用 HUD**

修改 `copySelected()` 方法：

```swift
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
    HUDWindow.show(I18N.t("已复制", "Copied"))  // 添加这行
}
```

- [ ] **Step 3: 测试编译**

```bash
./build.sh
```

- [ ] **Step 4: 提交**

```bash
git add Sources/HUDWindow.swift Sources/HistoryListPopoverController.swift
git commit -m "feat: add HUD notification on copy"
```

---

### Task 8: 最终集成测试

- [ ] **Step 1: 完整编译**

```bash
./build.sh
```

预期：编译成功，生成 SakuraClipboard.app 和 SakuraClipboard.dmg

- [ ] **Step 2: 功能验证清单**

手动测试以下功能：
- [ ] Cmd+Shift+C 呼出菜单
- [ ] 列表显示时间戳
- [ ] 文本显示 50 字符
- [ ] 搜索功能正常
- [ ] 右键菜单可用
- [ ] 数字键 1-9 快速复制
- [ ] 复制后显示 HUD

- [ ] **Step 3: 最终提交**

```bash
git add -A
git commit -m "chore: UX improvements complete"
```

---

## 执行方式选择

**Plan complete and saved to `docs/superpowers/plans/2026-05-24-ux-improvements.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 每个 Task 分配一个独立 subagent，任务间有 review，迭代快

**2. Inline Execution** - 在当前会话中按顺序执行，批量执行带检查点

**选择哪种方式？**
