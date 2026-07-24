## 🌐 [点击这里切换到：中文版 (Chinese Version)](./README.zh-CN.md)

<p align="center">
  <a href="./README.md"><img alt="English" src="https://img.shields.io/badge/Language-English-2563EB?style=for-the-badge"></a>
  <a href="./README.zh-CN.md"><img alt="Chinese" src="https://img.shields.io/badge/Language-Chinese-EF4444?style=for-the-badge"></a>
</p>

# Rime Smart Simplified

> A local-first Rime configuration for comfortable Simplified Chinese input, with contextual ranking, fuzzy pinyin, English mixing, and privacy-friendly learning.

[Download the latest ZIP](https://github.com/GravityPoet/rime-smart-simplified/releases/latest) · [Installation and rollback guide](./INSTALL.en.md) · [Privacy boundary](./PRIVACY.md)

This project is a **Rime user-directory configuration pack**. It is not a standalone input-method application. Install a Rime frontend first, then apply this pack to that frontend's user directory.

## What you get

- **A sensible first screen:** Rime Ice (雾凇拼音) with Simplified Chinese defaults, fuzzy pinyin, English mixing, emoji, and common dictionaries.
- **Local adaptation:** context ranking and learning data stay in the local Rime user directory. Existing private phrases and cold-word preferences are preserved during updates.
- **Optional local assistance:** the bundled configuration can use the local Wanxiang LTS grammar model. Post-commit prediction is off by default so ordinary copy/paste shortcuts are not intercepted.

## Before you download

You need one Rime frontend already installed:

| Platform | Frontend | Official entry point |
| --- | --- | --- |
| macOS 13+ | Squirrel (鼠须管) | [Rime downloads](https://rime.im/download/) · [Squirrel releases](https://github.com/rime/squirrel/releases/latest) |
| Windows 8.1–11 | Weasel (小狼毫) | [Rime downloads](https://rime.im/download/) · [Weasel releases](https://github.com/rime/weasel/releases/latest) |
| Linux | Fcitx5 Rime or IBus Rime | [Fcitx5 Rime](https://github.com/fcitx/fcitx5-rime) · [IBus Rime](https://github.com/rime/ibus-rime) |

The first installation may download the official `wanxiang-lts-zh-hans.gram` grammar model (about 401 MB). Runtime input is not uploaded by this project; the installer only contacts GitHub when it needs to obtain or verify that model.

## Install from the ZIP (recommended)

### 1. Download the correct file

On the [Release page](https://github.com/GravityPoet/rime-smart-simplified/releases/latest), download the asset named:

```text
rime-smart-simplified-vX.Y.Z.zip
```

Do **not** choose GitHub's generic `Source code (zip)` link. The named asset includes the customer entry points and the matching `.sha256` checksum file.

### 2. Extract, then run the platform entry point

#### macOS / Squirrel

1. Extract the ZIP in Finder.
2. Open the extracted folder and double-click `Install-on-macOS.command`.
3. If macOS asks for confirmation, Control-click the file and choose **Open**. The terminal fallback is:

   ```bash
   bash ./scripts/install.sh
   ```

#### Windows / Weasel

1. Extract the ZIP.
2. Double-click `Install-on-Windows.cmd`.
3. If you prefer PowerShell, open PowerShell in the extracted folder and run:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
   ```

The Windows installer defaults to `%APPDATA%\Rime`. It creates a timestamped backup before replacing existing files and keeps existing private phrase and cold-word files.

#### Linux / Fcitx5 or IBus

Open a terminal in the extracted folder and choose the directory matching your frontend:

```bash
# Fcitx5 Rime
RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/install.sh

# IBus Rime (use this instead of the line above)
RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/install.sh
```

### 3. Deploy and select the scheme

After the installer finishes:

1. Open your frontend's tray/menu item.
2. Choose **Deploy / 重新部署**.
3. Switch the operating-system input method to Squirrel, Weasel, Fcitx5 Rime, or IBus Rime.
4. In the scheme menu, select **雾凇拼音 / Rime Ice** if it is not already selected.

## First-use test

Open any text field and try these three checks:

1. Type `nihao`, then choose `你好` with `Enter` or the candidate number.
2. Type `rq` to show today's date, or `sj` to show the current time (UTC+8).
3. Press `Control` + the backtick key (macOS may also use `Fn + F4`) to open the scheme menu.

Useful everyday controls:

| Action | Shortcut / input |
| --- | --- |
| Temporary English | `Shift` while composing, or `Caps Lock` according to the frontend setting |
| Previous / next candidate page | `-` / `=` or `[` / `]` |
| Date, time, weekday | `rq`, `sj`, `xq`, `dt` |
| Lunar date / UUID | `nl`, `uuid` |
| Scene modes | Open the scheme menu and choose normal, chat, writing, or code |

Prediction is intentionally **off by default**. If your frontend provides a compatible local `predict.db`, it can be enabled temporarily from the scheme menu; it is not required for ordinary pinyin input.

## Update and rollback

Run the same platform installer for a later release. It backs up files that it is about to overwrite, preserves existing private phrases and cold-word preferences, and prints the backup directory. Restore that directory, then deploy again:

```bash
rsync -a "$HOME/Library/Rime.backup.YYYYMMDD-HHMMSS/" "$HOME/Library/Rime/"
```

See [INSTALL.en.md](./INSTALL.en.md) for Linux/Windows paths, checksum verification, model download controls, and the complete rollback procedure.

## Support the project

If this configuration saves you time or keeps your input local, a Star or a small sponsorship helps fund compatibility testing and maintenance.

| WeChat | PayPal |
| :---: | :---: |
| <img src="./docs/sponsors/wechat_pay.jpg" width="220" alt="WeChat sponsorship QR code" /> | <img src="./docs/sponsors/paypal.jpg" width="220" alt="PayPal sponsorship QR code" /> |

## Trust and limits

- This repository ships configuration, Lua extensions, dictionaries, and scripts; it does not ship Squirrel, Weasel, Fcitx, or IBus themselves.
- The grammar model is downloaded from the upstream [RIME-LMDG](https://github.com/amzxyz/RIME-LMDG) release and checked against its GitHub asset digest by default.
- The package does not provide cloud prediction or cloud synchronization. Your local Rime frontend still controls OS-level input-method behavior.
- The ZIP is released under the repository's license. Third-party licenses are listed in [THIRD_PARTY.md](./THIRD_PARTY.md).

## Acknowledgements

This configuration builds on [Rime Ice](https://github.com/iDvel/rime-ice), [RIME-LMDG](https://github.com/amzxyz/RIME-LMDG), and [rime-radical-pinyin](https://github.com/mirtlecn/rime-radical-pinyin). See [LICENSE](./LICENSE) and [THIRD_PARTY.md](./THIRD_PARTY.md).

---

## ⚖️ Licensing & Commercial Terms

rime-smart-simplified Community Edition is open source under the **[AGPL-3.0 License](./LICENSE)**.

- **Open Source Free Use**: Any individual or enterprise may use and distribute rime-smart-simplified for free in accordance with AGPL-3.0 license terms.
- **Commercial Dual-License**: If you or your organization need closed-source integration, exemption from AGPL-3.0 copyleft obligations, or proprietary redistribution rights, please contact us for a [Commercial License](mailto:moonlitpoet@proton.me). For third-party attributions, see [THIRD_PARTY.md](./THIRD_PARTY.md).
