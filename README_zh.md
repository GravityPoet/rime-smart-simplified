# ⚡️ Rime Smart Simplified (简体中文)

<div align="center">
  <p><strong>把商业输入法的丝滑体验，带入纯本地、无广告、零隐私泄露的开源生态。</strong></p>
</div>

<p align="center">
  🌐 <a href="./README.md">English Version</a>
</p>

---

一套**开箱即用**、面向日常输入深度优化的 Rime (中州韵/鼠须管/小狼毫) 简体中文配置。基于「雾凇拼音」、万象语言模型 (LMDG) 与多项增强脚本，为您提供**安全、聪明、免折腾**的输入体验。

---

## ✨ 核心亮点 (Why Choose This?)

### 1. 🚀 开箱即用的商业级体验
告别 Rime 陡峭的入门门槛！我们为你精调了痛点，无需折腾直接上手：
- **极准的首屏候选**：打字如飞，无需频繁按 +/- 翻页。
- **搜狗感模糊音**：极稳的自动容错（zh/ch/sh、n/l、an/ang、en/eng 等），手残党福音。
- **无缝中英混输**：直接拼写英文单词（如 `hi` `app` `bug`），无需频繁敲击 Shift 切换中英文。
- **Emoji 与符号支持**：自然语言直接打出颜文字与常用 Emoji ( ´ ▽ ` )ﾉ。

### 2. 🧠 AI 语言模型加持 (Smart)
引入 **万象 LTS** 强大的 n-gram 语言模型，让输入法“长脑子”：
- **上下文智能调序**：根据你输入的前半句话，动态预测并调整下一个词的候选顺序。
- **本地学习进化**：你的每一次选择都会被记忆，越用越懂你。配合**短码降频与回滚机制**，就算不小心选错也能轻松纠正。

### 3. 🛡️ 100% 绝对隐私安全 (Privacy First)
你的输入法，绝不应该成为暴露隐私的后门。
- **零联网，零数据上传**：代码全开源，所有功能均在本地离线运行。
- **数据属于你**：词库与个人习惯仅保存在你的硬盘。
- **杜绝商业追踪**：从根本上解决“刚在微信聊完，淘宝就推广告”的隐私劫持痛点。

### 4. 🎯 简体中文极度舒适
- **短码守门**：繁体字、生僻字、英文、Emoji 会被智能后移，绝不干扰常用的短拼音基础输入。
- **海量词库底座**：基于雾凇拼音的千万级词库及专属英文词典，日常交流、专业术语一网打尽。

---

## 💻 快速安装

### macOS (鼠须管 Squirrel)

本配置内置了一键安装脚本（自动下载配置与大语言模型）：

```bash
git clone https://github.com/GravityPoet/rime-smart-simplified.git
cd rime-smart-simplified
./scripts/install.sh
```

> **注意**：脚本会自动从 GitHub Release 下载 `wanxiang-lts-zh-hans.gram` 语言模型文件（约 401MB）。

### Windows (小狼毫 Weasel) / Linux

1. 将本仓库中除 `.git/`、`scripts/`、`third_party/` 等文档外的所有配置文件（`*.yaml`, `*.txt`, `lua/`, `opencc/` 等），复制到你的 Rime 用户目录。
2. 手动下载万象语言模型 `wanxiang-lts-zh-hans.gram`，放入 Rime 用户目录。
3. 在 Rime 菜单中点击 **重新部署 (Deploy)** 即可生效。

---

## 🔒 隐私边界与数据说明

安装后在本地生成的 `custom_phrase.txt` (私密条目)、`context_boost.tsv`、`predict.db` 等用户习惯记录，均属于你的**绝对私密资产**。本仓库提供的仅为「引擎配置与公开词库」，不会收集或要求你上传任何数据。建议将这些文件加入你的 `.gitignore`。

---

## 📄 鸣谢与许可证

站在巨人的肩膀上，本仓库是一个多来源聚合优化的项目。感谢开源社区的无私奉献：
- 核心词库与方案基于 [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice) (GPL-3.0)
- 语言模型数据来自 [万象 (RIME-LMDG)](https://github.com/wongstz/rime-lmdg) (CC-BY-4.0)
- 部首组件来自 [rime-radical-pinyin](https://github.com/mirtlecn/rime-radical-pinyin) (GPL-3.0)

详细协议请参考 [LICENSE](./LICENSE) 与 [THIRD_PARTY.md](./THIRD_PARTY.md)。

---
**如果你觉得好用，别忘了给项目点个 ⭐ Star 呀！**
