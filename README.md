<div align="center">

<img src="docs/media/icon.png" width="96" alt="OneSync 图标">

# OneSync

**点一下，本地 ⇄ OneDrive 双向同步。**
液态玻璃小窗 · 每个文件都看得见 · 默认不丢数据

A tiny macOS app for one-click, two-way OneDrive sync — built on `rclone bisync`, wrapped in Liquid Glass.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)
![rclone](https://img.shields.io/badge/rclone-bisync-3f79ad)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

<!-- 展示位 ①  主视觉 hero.png
     效果：浅色桌面壁纸上，OneSync 小窗悬浮在右上角，液态玻璃质感清楚可见；
     窗口停在「同步完成」状态，顶部提示条写着「已同步 N 个文件」，下面一排彩色计数胶囊。
     建议：Retina 截图（⌘⇧4 + 空格 点窗口），宽 1600 左右，PNG。 -->
<img src="docs/media/hero.png" width="720" alt="OneSync 主界面">

</div>

---

## 一眼看懂

<!-- 展示位 ②  一键同步全流程 sync.gif（最重要的一张）
     效果：点中间大圆按钮 → 「正在检查变化…」→ 确认卡片里文件一行行滑入（绿色新增/蓝色修改/红色删除）
     → 按回车开始 → 每个文件右侧虚线圈依次变成 ✓ → 顶部弹出「已同步」提示条。
     建议：提前在 ~/OneDrive 里新建 2 个、改 1 个、删 1 个文件；录 8–12 秒；
     用 Kap / CleanShot 录制，导出 GIF 宽 720、15fps、<8MB。 -->
<p align="center"><img src="docs/media/sync.gif" width="420" alt="一键同步"></p>

<table>
<tr>
<td width="50%" align="center">

<!-- 展示位 ③  选择 OneDrive 文件夹 picker.gif
     效果：设置 → 点「OneDrive 目录」那一行 → 页面滑入文件夹浏览器，彩色文件夹依次弹出
     → 鼠标悬停有放大 → 点进一个文件夹（网格左右滑动转场，面包屑增加一级）→ 点「选择」返回。
     建议：6–8 秒，宽 600。 -->
<img src="docs/media/picker.gif" width="100%" alt="可视化选择文件夹">

**点着选目录**<br>彩色文件夹一眼分清，不用手打路径

</td>
<td width="50%" align="center">

<!-- 展示位 ④  冲突处理 conflict.png
     效果：两边同时改了同一个文件后同步，确认卡片里出现橙色「冲突 · 保留较新的，另一份改名」，
     完成后显示「冲突副本」卡片，列出 xxx.conflict1。
     建议：静态截图即可，宽 600。 -->
<img src="docs/media/conflict.png" width="100%" alt="冲突处理">

**冲突不丢数据**<br>较新的赢，另一份改名保留

</td>
</tr>
<tr>
<td align="center">

<!-- 展示位 ⑤  删除刹车 brake.png
     效果：一次删除很多文件后点同步，确认卡片显示「⚠️ 删除较多（超过 10%）」+ 红色删除列表 + 「删除→回收区」计数。
     建议：静态截图，宽 600。 -->
<img src="docs/media/brake.png" width="100%" alt="删除刹车">

**删除有刹车**<br>大批删除先确认，删掉的进回收区

</td>
<td align="center">

<!-- 展示位 ⑥  外观三种风格 styles.png
     效果：同一状态下 液态玻璃 / 磨砂 / 超透明（或 白色/深色）三个窗口横排拼一张图。
     建议：分别截图后拼图，宽 1200，背景用同一张壁纸方便对比。 -->
<img src="docs/media/styles.png" width="100%" alt="外观风格">

**三种玻璃 + 深浅色**<br>默认官方白色液态玻璃

</td>
</tr>
</table>

## 特点

- **一键同步**：先预览，每个文件标明新增 / 修改 / 删除 / 冲突和去向，确认后执行；同步中逐个打勾，完成弹提示
- **默认安全**
  - 冲突：较新的版本赢，另一份改名为 `文件名.conflict1` 保留，不丢数据
  - 删除/覆盖：旧文件进回收区（本地 `~/Library/Application Support/OneSync/backup/`，云端 `_onesync_backup/`）
  - 一次删除超过 10% 时会明确提示，需要确认
  - 两边各有一个 `RCLONE_TEST` 标记文件，任一边缺失（例如外置盘没挂上）就拒绝同步
  - 首次同步 / 改目录后只合并，不删除任何文件
- **零配置**：默认本地 `~/OneDrive` ⇄ 云端 `OneSync/`，目录不存在会自动创建；设置里可以直接浏览 OneDrive、点选文件夹
- **外观**：液态玻璃（macOS 26，默认）/ 磨砂 / 超透；白色 / 深色 / 跟随系统
- **权限小**：不需要辅助功能、全盘访问等任何系统权限；只读写你选的目录

## 要求

- macOS 14+（液态玻璃需要 macOS 26，旧系统自动用磨砂）
- Xcode 命令行工具（Swift 5.10+）
- rclone ≥ 1.66（`brew install rclone`）

## 1. 用最小权限配置 OneDrive

rclone 默认申请整个 OneDrive + SharePoint 的读写权限。OneSync 只需要**你自己的文件**，建议收窄为：

```
Files.ReadWrite offline_access
```

- `Files.ReadWrite`：只读写登录用户自己的文件（不含别人共享给你的、不含 SharePoint）
- `offline_access`：允许刷新令牌，不用每次重新登录

新建 remote：

```sh
rclone config create onedrive onedrive access_scopes "Files.ReadWrite offline_access"
```

已有 remote 想收窄：

```sh
rclone config update onedrive access_scopes "Files.ReadWrite offline_access"
rclone config reconnect onedrive:
```

> 收窄后要重新登录授权才生效。之前授予过的大权限，可以在 <https://account.live.com/consent/Manage> 撤销 rclone 的授权后再 reconnect。

OneSync 会自动在 `~/.config/rclone/` 里挑一个**未加密、包含 onedrive** 的配置文件。如果你的配置加了密，在设置里输入配置密码，会存进系统钥匙串。

## 2. 编译安装

```sh
git clone https://github.com/Yanming41/onesync.git && cd onesync
./scripts/make-signing-cert.sh   # 可选，推荐：生成本机自签名证书，让钥匙串授权在重新编译后不失效
./build.sh                        # 编译并安装到 ~/Applications/OneSync.app
open ~/Applications/OneSync.app
```

可选环境变量：`BUNDLE_ID`（默认 `io.github.onesync`）、`SIGN_IDENTITY`（已有 Developer ID 时填它）。

第一次打开未公证的 App，如被拦截：系统设置 → 隐私与安全性 → 仍要打开。

## 同步参数

OneSync 实际执行的是：

```sh
rclone bisync <本地> <remote>:<目录> \
  --conflict-resolve newer --conflict-loser num --conflict-suffix conflict \
  --backup-dir1 <本地回收区> --backup-dir2 <remote>:_onesync_backup/<时间> \
  --max-delete 10 --check-access --check-filename RCLONE_TEST \
  --compare size,modtime --resilient --recover --create-empty-src-dirs \
  --exclude .DS_Store
```

## 已知限制

- 只比较大小和修改时间。OneDrive 会改写部分 Office 文件，偶尔可能产生多余的冲突副本（不会丢数据）。
- 目前只支持一组目录。
- 云端目录不能是 OneDrive 根目录（避免和回收区重叠）。

## 开发

`scripts/rc.sh <rclone 参数>`：在 GUI 会话里用 App 的配置跑 rclone，便于通过 SSH 调试。

## License

MIT
