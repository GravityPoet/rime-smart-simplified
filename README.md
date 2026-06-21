# ⚡️ Rime Smart Simplified

<div align="center">
  <p><strong>Bring the smooth, commercial-grade typing experience to a local, ad-free, and privacy-secure open-source ecosystem.</strong></p>
</div>

<p align="center">
  🌐 <a href="./README_zh.md">简体中文</a>
</p>

---

An **out-of-the-box**, highly optimized Simplified Chinese configuration for Rime (Squirrel on macOS, Weasel on Windows, and Ibus/Fcitx on Linux). Built on top of the popular **rime-ice** (雾凇拼音), the **万象 (RIME-LMDG)** AI language model, and various custom enhancers, it provides a secure, smart, and hassle-free typing experience.

---

## ✨ Core Highlights (Why Choose This?)

### 1. 🚀 Out-of-the-Box Commercial Experience
Skip the steep learning curve of Rime. We have pre-configured everything for you to get started immediately:
- **Highly Accurate First-Page Candidates**: Type naturally without constantly hunting through candidate lists.
- **Fuzzy Pinyin Support**: Robust typing correction and tolerance (e.g., automatically matching `zh/ch/sh`, `n/l`, `an/ang`, `en/eng`), making typing effortless.
- **Seamless English Mixing**: Spell English words directly (e.g., typing `hi`, `app`, `bug`) without manually hitting Shift to toggle input modes.
- **Emoji & Symbol Support**: Type emoticons and popular Emojis naturally using standard Pinyin (´ ▽ ` )ﾉ.

### 2. 🧠 AI Language Model Boost (Smart)
Integrated with the powerful **万象 (RIME-LMDG) LTS** n-gram language model to make your input engine smarter:
- **Context-Aware Candidate Ordering**: Dynamically predicts and rearranges candidate order based on the context of your current sentence.
- **Local Adaptive Learning**: Remembers and adjusts to your choices entirely offline. Paired with candidate de-boosting, it prevents dictionary pollution from accidental selection.

### 3. 🛡️ 100% Privacy & Offline-First (Privacy First)
Your keyboard should never be a backdoor for data collection.
- **Zero Cloud Communication**: All code is open-source and runs 100% locally and offline.
- **Absolute Data Ownership**: Your personal dictionary and typing habits are saved exclusively on your hard drive.
- **Anti-Targeted Ads**: Solves the privacy pain point of seeing matching ads on shopping apps right after typing about a product.

### 4. 🎯 Tailored for Simplified Chinese
- **Smart Candidate Filtering**: Traditional characters, rare words, and Emojis are pushed back, keeping your first page clean for regular daily typing.
- **Huge Vocabulary Base**: Powered by a multi-million vocabulary corpus and specialized English dictionary from `rime-ice`.

---

## 💻 Quick Installation

### macOS (Squirrel)

This repository includes a one-click installation script that automatically sets up the configurations and downloads the required language model:

```bash
git clone https://github.com/GravityPoet/rime-smart-simplified.git
cd rime-smart-simplified
./scripts/install.sh
```

> **Note**: The script will download the `wanxiang-lts-zh-hans.gram` language model file (approx. 401MB) directly from GitHub Releases.

### Windows (Weasel) / Linux

1. Copy all configuration files in this repository (excluding `.git/`, `scripts/`, and `third_party/` directories) to your Rime user directory.
2. Manually download the 万象 language model `wanxiang-lts-zh-hans.gram` and place it in your Rime user directory.
3. Click **Deploy** in your Rime menu to apply the configuration.

---

## 🔒 Privacy Boundaries & Data Policy

Files generated locally after installation, such as `custom_phrase.txt` (private phrases), `context_boost.tsv`, and `predict.db`, are your **strictly private assets**. This repository only provides the engine config and open-source dictionaries; it does not collect or request data uploads. We highly recommend adding these files to your local `.gitignore`.

---

## 📄 Acknowledgements & Licenses

FinalSub stands on the shoulders of giants. We express our deep gratitude to the open-source community:
- Core vocabulary and configuration schemes based on [rime-ice](https://github.com/iDvel/rime-ice) (GPL-3.0)
- Language model dataset from [RIME-LMDG](https://github.com/wongstz/rime-lmdg) (CC-BY-4.0)
- Radical input components from [rime-radical-pinyin](https://github.com/mirtlecn/rime-radical-pinyin) (GPL-3.0)

For detailed license terms, see [LICENSE](./LICENSE) and [THIRD_PARTY.md](./THIRD_PARTY.md).

---
**If you find this configuration helpful, don't forget to give this project a ⭐ Star!**
