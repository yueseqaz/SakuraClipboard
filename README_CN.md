# SakuraClipboard

轻量级 macOS 菜单栏剪贴板历史工具。从系统菜单栏快速访问文本和图片记录。

[![Build](https://github.com/yueseqaz/SakuraClipboard/actions/workflows/build.yml/badge.svg)](https://github.com/yueseqaz/SakuraClipboard/actions/workflows/build.yml)

## 功能特性

- **剪贴板历史** — 自动保存文本和图片记录
- **快速访问** — 菜单栏点击或 `Cmd+Shift+C` 打开
- **搜索** — `Cmd+Shift+F` 打开搜索面板，支持中文输入
- **预览** — 点击"预览"按钮查看完整文本，悬停图片可预览
- **收藏** — 右键收藏条目
- **自动清理** — 可配置保留时间（1-30 天或永久）
- **历史条数** — 100 到 5000 条
- **忽略应用** — 排除特定应用的剪贴板监听
- **开机自启** — 可选自动启动
- **中英文界面** — 语言切换

## 下载

从 [Releases](https://github.com/yueseqaz/SakuraClipboard/releases) 下载最新 DMG：

- `SakuraClipboard-arm64.dmg` — Apple Silicon (M1/M2/M3)
- `SakuraClipboard-x86_64.dmg` — Intel

## 从源码构建

```bash
./build.sh
```

输出：
- `SakuraClipboard.app`
- `SakuraClipboard.dmg`

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd+Shift+C` | 打开历史菜单 |
| `Cmd+Shift+F` | 打开搜索面板 |

## 项目结构

```
Sources/
├── AppDelegate.swift           # 应用生命周期、菜单栏、设置
├── ClipboardItem.swift         # 数据模型
├── ClipboardStore.swift        # SQLite 存储
├── ClipboardMonitor.swift      # 剪贴板监听
├── HistoryListPopoverController.swift  # 历史列表 UI
├── SearchPanel.swift           # 搜索面板 UI
├── HUDWindow.swift             # 复制提示
├── KeyboardShortcut.swift      # 全局快捷键
├── ThemeManager.swift          # 深色/浅色模式
├── Localization.swift          # 国际化
└── main.swift                  # 入口
```

## 许可证

MIT

## 作者

Sakura
