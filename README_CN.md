# SakuraClipboard

轻量级 macOS 菜单栏剪贴板历史工具。从系统菜单栏快速访问文本和图片记录。

[![Build](https://github.com/yueseqaz/SakuraClipboard/actions/workflows/build.yml/badge.svg)](https://github.com/yueseqaz/SakuraClipboard/actions/workflows/build.yml)

## 功能特性

- **剪贴板历史** — 自动保存文本和图片记录
- **快速访问** — 打开菜单后悬停“历史记录与搜索”即可展开，无需再次点击；也可用 `Cmd+Shift+C` 直接打开
- **一体化搜索** — 直接在历史记录中搜索，`Cmd+Shift+F` 聚焦同一面板的搜索框，支持中文输入
- **预览** — 悬停文字或图片即可预览，不再显示每条记录前的预览按钮
- **来源应用** — 新复制的内容显示来源应用图标，未保存来源的旧记录使用通用图标
- **预览交互** — 文字和图片直接显示在历史面板左侧的内嵌预览区，可移入阅读或滚动，无需弹出或激活额外窗口
- **分类与收藏** — 历史面板提供“全部 / 文本 / 图片 / 收藏”四个分类；点击记录右侧星标或右键收藏，再次点击取消，切换分类时保留搜索关键词
- **安全清理** — 手动清理默认保留收藏，只有勾选“同时清理收藏”才一并删除；重复复制同一内容不会丢失收藏状态
- **自动清理** — 可配置保留时间（1-30 天或永久），自动过期与容量淘汰均保留收藏
- **历史条数** — 普通历史记录 100 到 5000 条，收藏不计入此上限
- **忽略应用** — 排除特定应用的剪贴板监听
- **开机自启** — 可选自动启动
- **中英文界面** — 语言切换

## 下载

从 [Releases](https://github.com/yueseqaz/SakuraClipboard/releases) 下载最新 DMG：

- `SakuraClipboard-arm64.dmg` — Apple Silicon (M1/M2/M3)
- `SakuraClipboard-x86_64.dmg` — Intel

## Homebrew 安装

通过 [Homebrew](https://brew.sh) 安装：

```bash
brew tap yueseqaz/sakura-clipboard https://github.com/yueseqaz/SakuraClipboard
brew trust yueseqaz/sakura-clipboard
brew install --cask sakura-clipboard
```

后续升级：

```bash
brew upgrade --cask sakura-clipboard
```

## 产品官网

官网源码位于 `docs/`，使用原生 HTML、CSS 和 JavaScript，无需构建依赖。包含可交互的历史记录、搜索与预览演示，以及功能介绍、快捷键和下载入口。

本地预览：`python3 -m http.server 4173 --bind 127.0.0.1 --directory docs`，然后访问 `http://127.0.0.1:4173`。部署与维护见 [官网说明](docs/WEBSITE.md)。

## 从源码构建

```bash
./build.sh
```

默认构建同时支持 Apple Silicon 和 Intel。仅构建 Apple Silicon 版本：

```bash
ARCHS=arm64 ./build.sh
```

运行 UI 回归测试（图标的 1x/2x 渲染，以及无需点击的历史记录悬停）：

```bash
bash Tests/run.sh
```

输出：
- `SakuraClipboard.app`
- `SakuraClipboard.dmg`

## 快捷键

| 快捷键 | 功能 |
|--------|------|
| `Cmd+Shift+C` | 打开历史记录与搜索 |
| `Cmd+Shift+F` | 聚焦同一历史面板的搜索框 |
| `Cmd+F` | 面板打开时聚焦搜索框 |
| `↑` / `↓`、回车 | 选择并预览结果，回车复制 |
| `Esc` | 清空搜索，再按一次关闭 |

## 项目结构

```
Sources/
├── AppDelegate.swift           # 应用生命周期、菜单栏、设置
├── ClipboardItem.swift         # 数据模型
├── ClipboardStore.swift        # SQLite 存储
├── ClipboardMonitor.swift      # 剪贴板监听
├── HistoryListPopoverController.swift  # 历史列表 UI
├── HistoryPanel.swift          # 历史与搜索共用面板、焦点管理
├── HUDWindow.swift             # 复制提示
├── KeyboardShortcut.swift      # 全局快捷键
├── ThemeManager.swift          # 深色/浅色模式
├── Localization.swift          # 国际化
└── main.swift                  # 入口
```

## 项目架构

### 分层架构图

![Architecture](docs/diagrams/architecture.svg)

### 数据流图

![Data Flow](docs/diagrams/dataflow.svg)

## 许可证

MIT

## 作者

Sakura
