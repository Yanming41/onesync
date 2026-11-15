# OneSync

一个极简的 macOS 小工具：点一下，把本地文件夹和 OneDrive 文件夹**双向同步**。液态玻璃小窗，基于 [rclone](https://rclone.org) `bisync`。

A tiny macOS app for one-click, two-way OneDrive sync, built on `rclone bisync`, with a Liquid Glass floating window.

## 特点

- **一键同步**：先预览（多少文件要传、要删、有冲突），确认后执行
- **默认安全**
  - 冲突：较新的版本赢，另一份改名为 `文件名.conflict1` 保留，不丢数据
  - 删除/覆盖：旧文件进回收区（本地 `~/Library/Application Support/OneSync/backup/`，云端 `_onesync_backup/`）
  - 一次删除超过 10% 时会明确提示，需要确认
  - 两边各有一个 `RCLONE_TEST` 标记文件，任一边缺失（例如外置盘没挂上）就拒绝同步
  - 首次同步 / 改目录后只合并，不删除任何文件
- **零配置**：默认本地 `~/OneDrive` ⇄ 云端 `OneSync/`，目录不存在会自动创建；可在设置里改
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
