# SakuraClipboard 官网

原生 HTML、CSS 与 JavaScript 实现，无需安装依赖或构建。演示内容为虚构数据，不读取系统剪贴板；仅在用户点击「复制命令」时写入 Homebrew 安装命令。

## 本地预览

在仓库根目录执行：

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory docs
```

访问 `http://127.0.0.1:4173`。

## 部署

可以将 `docs/` 作为静态站点目录部署，无需构建步骤。

使用 GitHub Pages 时，在仓库 Settings → Pages 中选择 Deploy from a branch，分支选择 `main`，目录选择 `/docs`。提交并推送站点文件后，等待 Pages 部署完成。此说明不代表站点已经发布。

## 维护

- `index.html`：页面结构、功能文案、下载与仓库链接。
- `assets/site.css`：样式、桌面与移动布局、减少动态效果支持。
- `assets/site.js`：示例记录的搜索、分类、悬停/触摸预览、方向键操作、安装命令复制。
- `assets/app-icon.png`：由项目构建生成的原生应用图标缩小导出。
- `assets/sample-capture.svg`：图片预览使用的虚构界面示例，不含私人内容。

下载入口指向 GitHub 最新 Release 页面，避免写死可能不存在的架构安装包地址。保留时间、记录容量与最低系统版本应与原生应用实现保持一致；不展示未经实测的内存、延迟或能耗数字。
