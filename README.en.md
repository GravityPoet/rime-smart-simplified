<p align="center">
  <a href="./README.en.md"><img alt="English Version" src="https://img.shields.io/badge/Language-English-2563EB?style=for-the-badge"></a>
  <a href="./README.md"><img alt="Chinese Version" src="https://img.shields.io/badge/Language-Chinese-EF4444?style=for-the-badge"></a>
</p>

# 🚀 Rime Smart Simplified Pack

<p align="center">
  <strong>A locally processed Rime configuration pack for Simplified Chinese.</strong><br>
  No runtime input uploads · Wanxiang LTS local 3-gram model · Cross-platform install scripts
</p>

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><img src="https://img.shields.io/github/v/release/GravityPoet/rime-smart-simplified?label=latest%20release&color=6366f1" alt="Latest Release" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License" /></a>
  <a href="#"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-a78bfa" alt="Platform" /></a>
</p>

> This is not a standalone input method. Install Squirrel, Weasel, Fcitx5 Rime, or IBus Rime first. The pack provides a full-pinyin scheme, dictionaries, a local grammar model, and Lua enhancements.

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><strong>📦 Download Latest Release ZIP</strong></a>
  ·
  <a href="./INSTALL.en.md">Installation Guide</a>
  ·
  <a href="./PRIVACY.en.md">Privacy Boundary</a>
  ·
  <a href="./docs/BENCHMARK.md">Reproducible Benchmark</a>
</p>

---

## 🔥 Why Rime Smart Simplified?

Want candidate quality without depending on a cloud input service, ads, or an account?<br>
Or tried bare-bones Rime, only to be overwhelmed by **complex YAML configurations and poor default candidate rankings**?

`rime-smart-simplified` combines **Rime Ice (雾凇拼音)**, the **Wanxiang LTS local grammar model (LMDG)**, and automated installation scripts. The first install downloads verified assets from official GitHub Releases; daily typing and local learning do not use a cloud input API.

### ⚡️ Comparison: Commercial IMEs vs Vanilla Rime vs Rime Smart Simplified

| Dimension | Commercial IMEs | Vanilla Rime | ⚡️ Rime Smart Simplified |
|---|---|---|---|
| **Privacy & Security** | Some candidate features depend on cloud services, depending on product and settings | 🔒 Local input engine | 🔒 **Local runtime processing; official assets downloaded during installation** |
| **First-Screen Accuracy** | Cloud corpora and ranking | Depends on the selected scheme, dictionaries, and configuration | 🧠 **Wanxiang LTS local 3-gram model plus local dictionaries** |
| **Setup Experience** | Usually install and type | Requires choosing and maintaining a scheme | 🚀 **Install a Rime frontend, run the script, then deploy** |
| **Long-sentence candidates** | Common cloud-assisted suggestions | Depends on the scheme and dictionaries | 🎯 **Local context ranking for longer input** |

---

## ✨ 3 Killer Features

### 1. 🧠 Local Context Ranking via a 3-gram Model
Bundles the **Wanxiang LTS local grammar model (LMDG)** to improve long-sentence candidates with local phrase probabilities and dynamic ranking. The repository does not claim an accuracy percentage without a reproducible benchmark; compare it with your own common sentences.

### 2. 🚀 One-Command Configuration Install
No manual YAML editing required! Includes native one-click scripts for all platforms:
- **macOS (Squirrel / 鼠须管)**: Double-click `Install-on-macOS.command`
- **Windows (Weasel / 小狼毫)**: Double-click `Install-on-Windows.cmd`
- **Linux / Fcitx5**: `RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/install.sh`
- **Linux / IBus**: `RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/install.sh`
The installer backs up files it will overwrite and preserves existing private phrases, chat phrases, and cold-word preferences. Merge custom YAML changes from the timestamped backup when needed.

### 3. 🛡️ Local Runtime Processing
The scheme does not call a cloud input API or upload typed content. Candidate ranking and learning data stay in the local Rime directory. The first install downloads and verifies the grammar model and prediction data from official GitHub Releases; see the [privacy boundary](./PRIVACY.en.md).

---

## ⚡️ Quick Start

### Prerequisites
Make sure you have a Rime frontend installed:
- **macOS**: [Squirrel](https://github.com/rime/squirrel/releases/latest)
- **Windows**: [Weasel](https://github.com/rime/weasel/releases/latest)
- **Linux**: Fcitx5-Rime or IBus-Rime

### 🛠️ Installation

The default first install downloads a roughly 401 MB grammar model and 7 MB prediction database, so completion time depends on your connection. You must still deploy Rime afterward.

1. **Download Asset**: Visit [Latest Release](https://github.com/GravityPoet/rime-smart-simplified/releases/latest) and download `rime-smart-simplified-vX.Y.Z.zip`.
2. **Run Installer**:
   - macOS: Double-click `Install-on-macOS.command`
   - Windows: Double-click `Install-on-Windows.cmd`
3. **Deploy**: Click **Deploy (重新部署)** from the corresponding Rime frontend menu, then select Rime Ice.

To remove this configuration pack later, use the ownership-manifest uninstaller described in the [installation guide](./INSTALL.en.md). It preserves edited configuration, private phrases, and learning data.

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
