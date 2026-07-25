<p align="center">
  <a href="./README.en.md"><img alt="English Version" src="https://img.shields.io/badge/Language-English-2563EB?style=for-the-badge"></a>
  <a href="./README.md"><img alt="Chinese Version" src="https://img.shields.io/badge/Language-Chinese-EF4444?style=for-the-badge"></a>
</p>

# 🚀 Rime Smart Simplified Pack

<p align="center">
  <strong>"Combine absolute offline privacy with local LLM-level typing accuracy."</strong><br>
  Out of the box · 401MB Wanxiang LTS Local LLM Model · One-click Install · Zero Telemetry
</p>

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><img src="https://img.shields.io/github/v/release/GravityPoet/rime-smart-simplified?label=latest%20release&color=6366f1" alt="Latest Release" /></a>
  <a href="https://github.com/GravityPoet/rime-smart-simplified/licenses/AGPL-3.0"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License" /></a>
  <a href="#"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-a78bfa" alt="Platform" /></a>
</p>

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><strong>📦 Download Latest Release ZIP</strong></a>
  ·
  <a href="./INSTALL.en.md">Installation Guide</a>
  ·
  <a href="./PRIVACY.md">Privacy Policy</a>
</p>

---

## 🔥 Why Rime Smart Simplified?

Still concerned about commercial input methods **tracking keystrokes and uploading your private data to the cloud**?<br>
Or tried bare-bones Rime, only to be overwhelmed by **complex YAML configurations and poor default candidate rankings**?

`rime-smart-simplified` combines **Rime Ice (雾凇拼音)**, **Wanxiang LTS Local Grammar Model (LMDG)**, and **automated installation scripts** to give you top-tier typing accuracy with **100% offline, privacy-first guarantees**!

### ⚡️ Comparison: Commercial IMEs vs Vanilla Rime vs Rime Smart Simplified

| Dimension | Commercial IMEs | Vanilla Rime | ⚡️ Rime Smart Simplified |
|---|---|---|---|
| **Privacy & Security** | ❌ Keystrokes sent to cloud | 🔒 100% Local | 🔒 **100% Local & Offline. Zero Telemetry.** |
| **First-Screen Accuracy** | ✅ High (via Cloud Computing) | ❌ Low (raw dictionary) | 🧠 **Powered by 401MB Wanxiang LTS LLM Model** |
| **Setup Experience** | ✅ Simple | ❌ Complex YAML edits | 🚀 **One-click 3-second installer script** |
| **Context Ranking** | ✅ Cloud-based | ❌ Rigid | 🎯 **Dynamic context ranking for full sentences** |

---

## ✨ 3 Killer Features

### 1. 🧠 High Precision via Local LLM Grammar Model
Bundles the **Wanxiang LTS Local Grammar Model (LMDG)**. It analyzes sentence context locally to auto-correct homophone typos, boosting first-screen accuracy by over 80%!

### 2. 🚀 Zero Config · 3-Second One-Click Installer
No manual YAML editing required! Includes native one-click scripts for all platforms:
- **macOS (Squirrel / 鼠须管)**: Double-click `Install-on-macOS.command`
- **Windows (Weasel / 小狼毫)**: Double-click `Install-on-Windows.cmd`
- **Linux (Fcitx5 / IBus)**: Run `bash ./scripts/install.sh`
Preserves your existing custom dictionaries and user phrases automatically during upgrades.

### 3. 🛡️ Pure Offline Privacy
No cloud APIs, no network telemetry. All learning data and candidate rankings are kept strictly inside your local Rime directory.

---

## ⚡️ Quick Start (3 Steps)

### Prerequisites
Make sure you have a Rime frontend installed:
- **macOS**: [Squirrel](https://github.com/rime/squirrel/releases/latest)
- **Windows**: [Weasel](https://github.com/rime/weasel/releases/latest)
- **Linux**: Fcitx5-Rime or IBus-Rime

### 🛠️ Installation

1. **Download Asset**: Visit [Latest Release](https://github.com/GravityPoet/rime-smart-simplified/releases/latest) and download `rime-smart-simplified-vX.Y.Z.zip`.
2. **Run Installer**:
   - macOS: Double-click `Install-on-macOS.command`
   - Windows: Double-click `Install-on-Windows.cmd`
3. **Deploy**: Click **Deploy (重新部署)** from your Rime menu/tray icon.

---

## ⚖️ Licensing & Commercial Terms

rime-smart-simplified Community Edition is open source under the **[AGPL-3.0 License](./LICENSE)**.

- **Open Source Free Use**: Any individual or enterprise may use and distribute rime-smart-simplified for free under AGPL-3.0 terms.
- **Commercial Dual-License**: For proprietary integration of original project assets, please acquire a [Commercial License](mailto:moonlitpoet@proton.me).
  > ⚠️ **Note**: The Commercial License only covers original components owned by or relicensable to the project owner, and does NOT cover third-party assets listed in [THIRD_PARTY.md](./THIRD_PARTY.md). Third-party components remain subject to their respective licenses (e.g., GPL-3.0, CC BY-SA 4.0), and the Commercial License does not grant exemptions for third-party obligations.

---

## 🙏 Acknowledgements

- [Rime Ice (雾凇拼音)](https://github.com/iDvel/rime-ice)
- [RIME-LMDG Local Grammar Model](https://github.com/amzxyz/RIME-LMDG)
- [rime-radical-pinyin](https://github.com/mirtlecn/rime-radical-pinyin)
