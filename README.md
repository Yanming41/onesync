<div align="center">

<img src="docs/media/icon.png" width="96" alt="OneSync icon">

# OneSync

**One click. Two-way sync between your Mac and OneDrive.**
Liquid Glass floating window · every file change visible · safe by default

**English** · [简体中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.10-orange?logo=swift)
![rclone](https://img.shields.io/badge/rclone-bisync-3f79ad)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

<!-- Slot 1 · hero.png — see docs/media/README.md -->
<img src="docs/media/hero.png" width="720" alt="OneSync main window">

</div>

---

## At a glance

<!-- Slot 2 · sync.gif — click → preview list → ✓ per file → done toast -->
<p align="center"><img src="docs/media/sync.gif" width="420" alt="One-click sync"></p>

<table>
<tr>
<td width="50%" align="center">

<!-- Slot 3 · picker.gif -->
<img src="docs/media/picker.gif" width="100%" alt="Visual folder picker">

**Pick folders visually**<br>Colorful folders, no typing paths

</td>
<td width="50%" align="center">

<!-- Slot 4 · conflict.png -->
<img src="docs/media/conflict.png" width="100%" alt="Conflict handling">

**Conflicts never lose data**<br>Newer wins, the other copy is renamed

</td>
</tr>
<tr>
<td align="center">

<!-- Slot 5 · brake.png -->
<img src="docs/media/brake.png" width="100%" alt="Delete brake">

**A brake on mass deletes**<br>Big deletions need confirmation and go to a recycle area

</td>
<td align="center">

<!-- Slot 6 · styles.png -->
<img src="docs/media/styles.png" width="100%" alt="Appearance styles">

**Three glass styles, light & dark**<br>Official white Liquid Glass by default

</td>
</tr>
</table>

## Features

- **One-click sync**: a dry-run preview first, with every file marked as new / modified / deleted / conflict and where it goes; runs after you confirm, ticks off each file live, and shows a summary toast when done
- **Safe by default**
  - Conflicts: the newer version wins; the other is kept as `name.conflict1`
  - Deletes / overwrites: old files go to a recycle area (local `~/Library/Application Support/OneSync/backup/`, cloud `_onesync_backup/`)
  - Deleting more than 10% of files requires explicit confirmation
  - An `RCLONE_TEST` marker on each side; if either is missing (e.g. an external disk isn't mounted), sync is refused
  - The first sync / a sync after changing folders only merges, never deletes
- **Zero config**: `~/OneDrive` ⇄ `OneSync/` on OneDrive by default, created if missing; browse OneDrive and click a folder in Settings to change it
- **Appearance**: Liquid Glass (macOS 26, default) / Frosted / Clear; Light / Dark / System
- **Minimal permissions**: no Accessibility, Full Disk Access or any other system permission; only touches the folders you pick

## Requirements

- macOS 14+ (Liquid Glass needs macOS 26; older systems fall back to Frosted)
- Xcode Command Line Tools (Swift 5.10+)
- rclone ≥ 1.66 (`brew install rclone`)

## 1. Set up OneDrive with minimal scope

By default rclone requests read/write access to all of OneDrive plus SharePoint. OneSync only needs **your own files**, so narrow it to:

```
Files.ReadWrite offline_access
```

- `Files.ReadWrite`: read/write the signed-in user's own files only (no files shared with you, no SharePoint)
- `offline_access`: lets the token refresh so you don't have to sign in every time

New remote:

```sh
rclone config create onedrive onedrive access_scopes "Files.ReadWrite offline_access"
```

Narrow an existing remote:

```sh
rclone config update onedrive access_scopes "Files.ReadWrite offline_access"
rclone config reconnect onedrive:
```

> The new scope only takes effect after re-authorizing. To drop previously granted broader access, revoke rclone at <https://account.live.com/consent/Manage>, then reconnect.

OneSync automatically picks an **unencrypted config containing a onedrive remote** from `~/.config/rclone/`. If your config is encrypted, enter its password in Settings; it is stored in the macOS Keychain.

## 2. Build & install

```sh
git clone https://github.com/Yanming41/onesync.git && cd onesync
./scripts/make-signing-cert.sh   # optional, recommended: a local self-signed cert so Keychain access survives rebuilds
./build.sh                        # builds and installs to ~/Applications/OneSync.app
open ~/Applications/OneSync.app
```

Optional env vars: `BUNDLE_ID` (default `io.github.onesync`), `SIGN_IDENTITY` (use your Developer ID if you have one).

If macOS blocks the un-notarized app on first launch: System Settings → Privacy & Security → Open Anyway.

## What it runs

```sh
rclone bisync <local> <remote>:<folder> \
  --conflict-resolve newer --conflict-loser num --conflict-suffix conflict \
  --backup-dir1 <local recycle> --backup-dir2 <remote>:_onesync_backup/<time> \
  --max-delete 10 --check-access --check-filename RCLONE_TEST \
  --compare size,modtime --resilient --recover --create-empty-src-dirs \
  --exclude .DS_Store
```

## Known limitations

- Compares size and modtime only. OneDrive rewrites some Office files, which may occasionally produce an extra conflict copy (no data is lost).
- One folder pair at a time.
- The cloud folder can't be the OneDrive root (to keep it apart from the recycle area).

## Development

`scripts/rc.sh <rclone args>`: run rclone with the app's config inside the GUI session — handy when debugging over SSH.

## License

MIT
