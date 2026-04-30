# SakuraClipboard

SakuraClipboard 是一个轻量的 macOS 菜单栏剪贴板历史工具。它在本地保存最近的文本和图片记录，从系统菜单栏打开，不提供额外主面板。

## 功能特性

- 自动记录文本与图片剪贴板历史
- 原生菜单栏界面，没有主面板
- 菜单内显示当前剪贴板摘要
- 固定高度 History 菜单，支持内部滚动和继续加载
- 点击历史条目即可重新复制到剪贴板
- 图片历史支持悬停预览
- 支持按保留时间自动清理
- 支持设置历史条数上限：100、200、350、500、1000、2000、5000
- 使用 SQLite 本地存储
- 支持中文/英文界面切换
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

## 使用说明

- 从 macOS 菜单栏打开应用。
- 打开 History 查看最近的剪贴板记录。
- 在 History 内滚动可继续加载更多记录。
- 鼠标悬停在图片条目上可预览图片。
- 通过 Auto Clean 设置记录保留时间。
- 通过 History Limit 设置最多保存多少条记录。

## 项目结构

- `Sources/ClipboardItem.swift`：数据模型
- `Sources/ClipboardStore.swift`：SQLite 存储与历史查询
- `Sources/ClipboardMonitor.swift`：剪贴板监听
- `Sources/HistoryListPopoverController.swift`：菜单内历史列表
- `Sources/AppDelegate.swift`：应用生命周期与菜单栏行为
- `Sources/main.swift`：程序入口

## 作者

Sakura
