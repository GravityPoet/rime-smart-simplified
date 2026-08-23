# Installation, use, verification, and rollback

This project is a **Rime user-directory configuration pack**, not Squirrel, Weasel, Fcitx, or IBus itself. Install a Rime frontend first, then apply this configuration.

Official frontend entry points:

- macOS: [Squirrel](https://github.com/rime/squirrel/releases/latest), macOS 13+
- Windows: [Weasel](https://github.com/rime/weasel/releases/latest), Windows 8.1–11
- Linux: [Fcitx5 Rime](https://github.com/fcitx/fcitx5-rime) or [IBus Rime](https://github.com/rime/ibus-rime)

## 1. Install from the Release ZIP

From the [latest Release](https://github.com/GravityPoet/rime-smart-simplified/releases/latest), download:

```text
rime-smart-simplified-vX.Y.Z.zip
rime-smart-simplified-vX.Y.Z.zip.sha256
```

Do not use GitHub's generic `Source code (zip)` link. On macOS/Linux, verify the named asset with:

```bash
shasum -a 256 -c rime-smart-simplified-vX.Y.Z.zip.sha256
```

On Windows PowerShell:

```powershell
$zip = "rime-smart-simplified-vX.Y.Z.zip"
$check = (Get-Content "${zip}.sha256").Trim().Split()[0].ToLowerInvariant()
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $check) { throw "SHA-256 mismatch: expected $check actual $actual" }
Write-Host "SHA-256 OK: $actual"
```

Extract the ZIP. The folder contains `Install-on-macOS.command`, `Install-on-Windows.cmd`, and `scripts/`.

### macOS / Squirrel

1. Double-click `Install-on-macOS.command` in Finder.
2. If macOS blocks the first launch, Control-click the file and choose **Open**.
3. The terminal fallback is:

   ```bash
   bash ./scripts/install.sh
   ```

The default target is `~/Library/Rime`.

### Windows / Weasel

1. Double-click `Install-on-Windows.cmd`.
2. For PowerShell, run this from the extracted folder:

   ```powershell
   powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
   ```

The default target is `%APPDATA%\Rime`.

### Linux / Fcitx5 or IBus

Open a terminal in the extracted folder and run one command for your frontend:

```bash
# Fcitx5 Rime
RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/install.sh

# IBus Rime (use this instead of the line above)
RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/install.sh
```

Your Linux distribution may also require its Rime, Lua, or grammar-model support packages. Package names vary by distribution.

The installers stage and verify downloads before changing the Rime directory, create a collision-free timestamped backup before overwriting files, and preserve existing `custom_phrase.txt`, `smart_chat_phrases.txt`, and cold-word preference files. A write failure restores overwritten files and removes files created by that attempt. On Linux, omitting `RIME_USER_DIR` fails with both valid commands instead of writing to a macOS path. A symlink at a destination or at a parent below the target fails closed; the `RIME_USER_DIR` target itself may still be a symlink.

Each successful install also writes `.rime-smart-simplified.install-manifest` in the target directory. It records only files written by this package and their digests; it does not record user runtime databases. To remove the package precisely, exit the Rime frontend first, preview the plan, then apply it:

```bash
cd /path/to/rime-smart-simplified
RIME_USER_DIR="$HOME/Library/Rime" ./scripts/uninstall.sh --dry-run
RIME_USER_DIR="$HOME/Library/Rime" ./scripts/uninstall.sh --apply
```

The uninstaller validates the manifest source-record digest, current package/model-lock digests, duplicate entries, and this package's installable-path allow-list. If the manifest was manually edited, truncated, or moved across package versions, it stops and preserves the target instead of treating an arbitrary private path or forged digest as removable. Re-run the current installer to generate a fresh manifest before retrying. `RIME_PACKAGE_VERSION` must be a single-line safe version value; a value containing a newline or tab aborts before the install is committed.

On Linux, use the actual Fcitx5 or IBus directory. The uninstaller removes only files whose digest still matches the install record. Edited YAML, dictionaries, private phrases, learning preferences, and pre-existing model files are preserved and reported. A timestamped backup is created by default; use `--no-backup` only when you already have an independent backup. Windows equivalents are:

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -RimeUserDir (Join-Path $env:APPDATA "Rime") -DryRun
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -RimeUserDir (Join-Path $env:APPDATA "Rime") -Apply
```

The uninstaller leaves empty directories in place and never removes Squirrel, Weasel, Fcitx5, or IBus itself.

## 2. Dry run and advanced options

Preview the target, backup policy, and manifest before writing:

```bash
RIME_USER_DIR="$HOME/Library/Rime" bash ./scripts/install.sh --dry-run
```

Options:

- `--no-download-gram`: install configuration without downloading the roughly 401 MB Wanxiang LTS grammar model.
- `--no-download-predict`: skip downloading the 7 MB official `predict.db` prediction data (librime-predict `data-1.0`, verified against a pinned SHA-256).
- `--skip-verify-gram`: download without the GitHub asset digest check. Use only when the API is unavailable and you accept the risk.
- `--no-backup`: skip backups. Not recommended for ordinary upgrades.

PowerShell equivalents are `-DryRun`, `-NoDownloadGram`, `-SkipVerifyGram`, `-NoDownloadPredict`, and `-NoBackup`.

## 3. Deploy and verify the first use

When the installer prints `Installed`, you must still choose **Deploy / 重新部署** from the Rime frontend menu:

1. Open the Squirrel, Weasel, Fcitx5, or IBus tray menu.
2. Choose **Deploy**.
3. Switch the OS input method to that Rime frontend.
4. Select **Rime Ice / 雾凇拼音** in the scheme menu if it is not already active.
5. In a text field, type `nihao` and choose `你好`; then type `rq` to test the date translator.

Open the scheme menu with `Control + backtick`; on macOS, `Fn + F4` is an alternative when function keys are reserved by the system.

Common inputs:

| Input | Result |
| --- | --- |
| `rq` / `sj` / `xq` / `dt` | Date / time / weekday / date-time (UTC+8) |
| `nl` | Lunar date |
| `uuid` | Random UUID |
| `Shift` | Temporary English while composing |
| `-`, `=`, `[`, `]` | Candidate paging |

Post-commit prediction is off by default and resets to off for each new session so prediction candidates do not interrupt continuous typing. The installer downloads the official `predict.db` prediction data automatically (librime-predict `data-1.0`, verified against a pinned SHA-256); turn "预测" on temporarily from the scheme menu when needed. Ordinary pinyin input does not require the prediction database. Use `--no-download-predict` (Windows: `-NoDownloadPredict`) to skip it.

Automatic spacing between Chinese and English (e.g. `VIP中P` → `VIP 中 P`, plus a leading space for consecutive English words) is controlled by the "空格" scheme-menu switch, off by default and remembered across sessions.

## 4. Install from source (developers)

```bash
git clone https://github.com/GravityPoet/rime-smart-simplified.git
cd rime-smart-simplified
bash ./scripts/install.sh
```

## 5. Grammar model and manual verification

The default model is downloaded from:

```text
https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram
```

`LTS` is a rolling upstream Release, so its digest can change. Read the current digest from the [RIME-LMDG Release API](https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS) whenever you download again.

For reproducible local checks that never touch a real user directory:

```bash
cd /path/to/rime-smart-simplified
./scripts/check_upstream_freshness.sh --local-only --strict
./scripts/benchmark.sh --iterations 20 --output /tmp/rime-smart-simplified-benchmark.jsonl
```

Benchmark records explicitly carry `proxy: true` and `accuracy_claim: false`. They cover install/build/librime candidate smoke and synthetic Lua candidate-stream timing, not real frontend first-key latency or accuracy. See [`docs/BENCHMARK.md`](./docs/BENCHMARK.md).

## 6. Rollback

Installation failures are restored automatically by the current installers. The commands below are for deliberately restoring overwritten files after a successful install: exit the Rime frontend, copy the timestamped backup, and deploy again. A timestamped backup does not remove files newly introduced by the install, so this is restoration rather than a complete uninstall.

macOS:

```bash
rsync -a "$HOME/Library/Rime.backup.YYYYMMDD-HHMMSS/" "$HOME/Library/Rime/"
```

Linux Fcitx5:

```bash
rsync -a "$HOME/.local/share/fcitx5/rime.backup.YYYYMMDD-HHMMSS/" "$HOME/.local/share/fcitx5/rime/"
```

Windows PowerShell:

```powershell
$backup = Join-Path $env:APPDATA "Rime.backup.YYYYMMDD-HHMMSS"
$target = Join-Path $env:APPDATA "Rime"
Copy-Item -Path (Join-Path $backup "*") -Destination $target -Recurse -Force
```

The learning layer also keeps `context_boost.tsv.bak.pre-journal-v2` before its first compression threshold. Restore that snapshot only after exiting the Rime frontend, remove `context_boost.journal.tsv`, and deploy again.

## 7. Local files never to commit

- `context_boost.tsv`, `context_boost.journal.tsv`, and `context_boost*.bak.*`
- `pin_by_select*.tsv`, `predict.db`, and `*.userdb/`
- `sync/`, `build/`, `installation.yaml`, and `user.yaml`
- `*.gram`
- Any `custom_phrase.txt` or `smart_chat_phrases.txt` containing personal information
