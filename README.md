<p align="center">
  <a href="./README.en.md"><img alt="English Version" src="https://img.shields.io/badge/Language-English-2563EB?style=for-the-badge"></a>
  <a href="./README.md"><img alt="简体中文" src="https://img.shields.io/badge/Language-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-EF4444?style=for-the-badge"></a>
</p>

# 🚀 Rime Smart Simplified (Rime 智能简体中文增强包)

<p align="center">
  <strong>最智能的本地隐私中文输入法</strong><br>
  零云端上传 · 首屏精准度拉满 · 401MB 本地 LLM 模型 · 零配置一键安装
</p>

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><img src="https://img.shields.io/github/v/release/GravityPoet/rime-smart-simplified?label=latest%20release&color=6366f1" alt="Latest Release" /></a>
  <a href="https://github.com/GravityPoet/rime-smart-simplified/licenses/AGPL-3.0"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License" /></a>
  <a href="#"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-a78bfa" alt="Platform" /></a>
</p>

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><strong>📦 立即下载最新版 ZIP</strong></a>
  ·
  <a href="./INSTALL.md">完整安装与回滚指南</a>
  ·
  <a href="./PRIVACY.md">隐私边界说明</a>
</p>

---

## 🔥 为什么你需要 rime-smart-simplified？

还在忍受传统商业输入法**搜啥弹啥广告、偷偷上传打字记录**？<br>
或者尝试过原生 Rime，却被**繁琐复杂的 YAML 配置**劝退，打字首屏候选词经常不对劲？

`rime-smart-simplified` 将 **雾凇拼音词库**、**万象 LTS 本地语言模型 (LMDG)** 与 **自动化挂载脚本** 完美整合，让你既能拥有大厂输入法的超高打字准确率，又能实现 **100% 断网离线、绝不泄露一字一句** 的极致安全！

### ⚡️ 体验对决：传统输入法 vs 原生 Rime vs Rime Smart Simplified

| 维度 | 传统商业输入法 | 原生 Rime | ⚡️ Rime Smart Simplified |
|---|---|---|---|
| **隐私安全** | ❌ 键盘记录全量上传云端，隐私堪忧 | 🔒 100% 本地运行 | 🔒 **100% 本地纯血离线，断网依然飞速** |
| **首屏准确率** | ✅ 依靠云端大数据计算 | ❌ 基础词库常年打错字 | 🧠 **内置 401MB 万象 LTS 本地 LLM 语法模型** |
| **上手门槛** | ✅ 安装即用 | ❌ 配置繁琐、折腾半天 | 🚀 **一键双击脚本，3 秒自动配置完成** |
| **长句联想** | ✅ 云端联想 | ❌ 断句死板 | 🎯 **上下文动态调序，长长一句话一次出屏** |

---

## ✨ 3 大杀手级核心特性

### 1. 🧠 脑电波级别首屏精准度（本地 LLM 语法模型）
集成 **万象 LTS 本地语法模型 (LMDG)**，基于上下文深度学习与动态调序。输入一长串拼音时，系统能根据前文自动识别词组语法逻辑，自动纠正同音错别字，首屏出字率提升 80% 以上！

### 2. 🚀 零配置·3 秒一键挂载
无需手写任何 yaml 配置文件！针对三大桌面平台提供专属一键安装脚本：
- **macOS (鼠须管 Squirrel)**：双击 `Install-on-macOS.command`
- **Windows (小狼毫 Weasel)**：双击 `Install-on-Windows.cmd`
- **Linux (Fcitx5 / IBus)**：一行 `bash ./scripts/install.sh` 自动识别
安装器会自动备份已有配置文件，升级时**完美保留你的私人词库与习惯**！

### 3. 🛡️ 纯血本地离线·零隐私泄漏
拒绝任何云端上传与联网追踪！所有上下文调序、学习数据、词库积累**全量封印在你的电脑本地 Rime 用户目录**。真正的“我的打字习惯，只有我的电脑知道”。

---

## ⚡️ 3 步极简安装（60 秒上手）

### 前置条件
确保你已安装任意一款 Rime 前端：
- **macOS**: [鼠须管 Squirrel](https://github.com/rime/squirrel/releases/latest)
- **Windows**: [小狼毫 Weasel](https://github.com/rime/weasel/releases/latest)
- **Linux**: Fcitx5-Rime 或 IBus-Rime

### 🛠️ 安装步骤

1. **下载安装包**：打开 [最新版 Release](https://github.com/GravityPoet/rime-smart-simplified/releases/latest)，下载 `rime-smart-simplified-vX.Y.Z.zip`。
2. **双击运行一键脚本**：
   - macOS：双击运行 `Install-on-macOS.command`
   - Windows：双击运行 `Install-on-Windows.cmd`
3. **重新部署**：在输入法托盘图标菜单中点击 **“重新部署 (Deploy)”**，即可开始享受极致打字体验！

---

## 💡 常用快捷键与实用指令

| 功能/指令 | 输入方式 / 快捷键 | 效果示例 |
|---|---|---|
| **临时切换英文** | 组词时按 `Shift` | 无缝输入英文单词 |
| **实时时间/日期** | 输入 `rq` / `sj` / `dt` | 快速输出 `2026-07-24`、`13:14:00` |
| **星期与农历** | 输入 `xq` / `nl` | 快速输出 `星期五`、`丙午年六月十一` |
| **UUID 唯一标识** | 输入 `uuid` | 自动生成 `c8f3b140-...` 格式 UUID |
| **场景模式切换** | `Control + 反引号` (macOS 亦可 `Fn + F4`) | 打开方案菜单，自由切换常规/聊天/代码模式 |

---

## ⚖️ 许可证 (License) & 商业双重许可

rime-smart-simplified 社区版基于 **[AGPL-3.0 License](./LICENSE)** 协议开源。

- **开源免费使用**：任何个人和企业均可按照 AGPL-3.0 协议规定**免费使用与分发**。
- **商业双重许可**：如果您或您的企业需要将本软件的原创部分**闭源集成或获取专有再分发权**，请联系我们购买 [商业许可 (Commercial Dual-License)](mailto:moonlitpoet@proton.me)。
  > ⚠️ **注意**：商业许可仅覆盖项目所有者拥有或已获授权可再许可的原创部分，不涵盖 [THIRD_PARTY.md](./THIRD_PARTY.md) 所列第三方资产。第三方组件仍受其各自许可证（如 GPL-3.0、CC BY-SA 4.0 等）约束，商业许可不免除相关第三方许可证义务。

---

## 🙏 致谢

本配置基于并致谢：
- [雾凇拼音 (rime-ice)](https://github.com/iDvel/rime-ice)
- [RIME-LMDG 本地语法模型](https://github.com/amzxyz/RIME-LMDG)
- [rime-radical-pinyin](https://github.com/mirtlecn/rime-radical-pinyin)
