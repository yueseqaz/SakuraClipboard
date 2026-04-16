# SakuraClipboard

SakuraClipboard 是一个轻量的 macOS 剪贴板历史工具，强调快速访问、清晰整理，以及对文本和图片的本地可靠存储。

## 功能特性

- 自动记录文本与图片剪贴板历史
- 支持按关键字搜索文本内容
- 支持按类型、时间范围、收藏状态/收藏夹筛选
- 可将任意条目加入收藏，并在列表内直接分配或修改收藏夹
- 支持图片预览与长文本折叠/展开
- 使用 SQLite 持久化，历史容量更大、检索更快
- 支持调整历史条数上限，并显示存储占用
- 可直接在 Finder 中打开存储位置
- 清空时仅删除未收藏条目，收藏内容会保留
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
- 点击任意条目即可重新复制回剪贴板。
- 点击收藏操作后，可直接在列表中为该条目设置或修改收藏夹。
- 通过收藏筛选器可以查看全部项目、仅未收藏项目，或指定收藏夹内容。

## 项目结构

- `Sources/ClipboardItem.swift`：数据模型
- `Sources/ClipboardStore.swift`：SQLite 存储、收藏夹与查询逻辑
- `Sources/ClipboardMonitor.swift`：自适应轮询监听
- `Sources/UIComponents.swift`：可复用 UI 组件
- `Sources/PopoverController.swift`：主界面、筛选器与收藏夹内联交互
- `Sources/AppDelegate.swift`：应用生命周期与菜单栏行为
- `Sources/main.swift`：程序入口

## 作者

Sakura
