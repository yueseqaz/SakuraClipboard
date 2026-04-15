# SakuraClipboard

SakuraClipboard 是一个轻量的 macOS 剪贴板历史工具，支持文本与图片。

## 功能特性

- 文本与图片历史记录
- 支持按关键字、类型、时间筛选
- 支持收藏/固定重要内容
- 清空操作二次确认，防止误删
- 使用 SQLite 持久化，检索更快、容量更大
- 图片悬浮预览
- 长文本自动折叠/展开
- 支持中文/英文切换
- 支持开机自启

## 构建方式

```bash
./build.sh
```

构建产物：

- `SakuraClipboard.app`
- `SakuraClipboard.dmg`

DMG 内容：

- `SakuraClipboard.app`
- `Applications` 快捷方式

## 项目结构

- `Sources/ClipboardItem.swift`：数据模型
- `Sources/ClipboardStore.swift`：SQLite 存储与查询
- `Sources/ClipboardMonitor.swift`：自适应轮询监听
- `Sources/UIComponents.swift`：可复用 UI 组件
- `Sources/PopoverController.swift`：主弹窗界面与交互
- `Sources/AppDelegate.swift`：应用生命周期与菜单栏行为
- `Sources/main.swift`：程序入口

## 作者

Sakura
