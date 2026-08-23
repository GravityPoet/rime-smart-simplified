<p align="center">
  <a href="./README.en.md"><img alt="English Version" src="https://img.shields.io/badge/Language-English-2563EB?style=for-the-badge"></a>
  <a href="./README.md"><img alt="简体中文" src="https://img.shields.io/badge/Language-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-EF4444?style=for-the-badge"></a>
</p>

# 🚀 Rime Smart Simplified (Rime 智能简体中文增强包)

<p align="center">
  <strong>本地运行的 Rime 智能简体中文配置包</strong><br>
  输入运行时不上传 · 万象 LTS 本地 3-gram 语法模型 · 跨平台安装脚本
</p>

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><img src="https://img.shields.io/github/v/release/GravityPoet/rime-smart-simplified?label=latest%20release&color=6366f1" alt="Latest Release" /></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-blue" alt="License" /></a>
  <a href="#"><img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-a78bfa" alt="Platform" /></a>
</p>

> 这不是独立输入法：请先安装鼠须管、小狼毫、Fcitx5 Rime 或 IBus Rime。本项目面向全拼用户，负责安装方案、词库、本地语法模型与 Lua 增强。

<p align="center">
  <a href="https://github.com/GravityPoet/rime-smart-simplified/releases/latest"><strong>📦 立即下载最新版 ZIP</strong></a>
  ·
  <a href="./INSTALL.md">完整安装与回滚指南</a>
  ·
  <a href="./PRIVACY.md">隐私边界说明</a>
</p>

---

## 🔥 为什么你需要 rime-smart-simplified？

不想让候选质量依赖云端服务，也不想被广告和账号体系打断输入？<br>
或者尝试过原生 Rime，却被**繁琐复杂的 YAML 配置**劝退，打字首屏候选词经常不对劲？

`rime-smart-simplified` 将 **雾凇拼音词库**、**万象 LTS 本地语法模型 (LMDG)** 与 **自动安装脚本** 整合在一起。首次安装会联网下载并校验官方模型；完成后，日常输入与本地学习不依赖云端输入接口。

### ⚡️ 体验对决：传统输入法 vs 原生 Rime vs Rime Smart Simplified

| 维度 | 传统商业输入法 | 原生 Rime | ⚡️ Rime Smart Simplified |
|---|---|---|---|
| **隐私安全** | 部分候选能力依赖云端，取决于产品与设置 | 🔒 输入引擎本地运行 | 🔒 **输入运行时本地处理；安装期联网下载官方资产** |
| **首屏准确率** | 云端语料与模型调序 | 取决于所选方案、词库和配置 | 🧠 **万象 LTS 本地 3-gram 语法模型 + 本地词库** |
| **上手门槛** | 通常安装即用 | 需要自行选择和维护配置 | 🚀 **安装 Rime 前端后，运行脚本并重新部署** |
| **长句候选** | 常见云端联想能力 | 取决于方案与词库 | 🎯 **本地上下文动态调序，改善长句候选** |

---

## ✨ 3 大杀手级核心特性

### 1. 🧠 本地上下文调序（3-gram 语法模型）
集成 **万象 LTS 本地语法模型 (LMDG)**，用相邻词组概率和本地动态调序改善长句候选。仓库不宣称未经基准测试验证的准确率数字；你可以用自己的常用句直接比较首屏候选。

### 2. 🚀 一键安装配置
无需手写任何 yaml 配置文件！针对三大桌面平台提供专属一键安装脚本：
- **macOS (鼠须管 Squirrel)**：双击 `Install-on-macOS.command`
- **Windows (小狼毫 Weasel)**：双击 `Install-on-Windows.cmd`
- **Linux / Fcitx5**：`RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/install.sh`
- **Linux / IBus**：`RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/install.sh`
安装器会备份将被覆盖的同名文件，并原样保留私人短语、聊天短语与冷词偏好；自定义 YAML 可从时间戳备份中合并恢复。

### 3. 🛡️ 输入运行时本地处理
方案不调用云输入接口，也不上传输入内容；上下文调序、学习数据和词库积累保存在本机 Rime 用户目录。首次安装会从官方 GitHub Release 下载并校验语法模型与预测数据，具体边界见[隐私说明](./PRIVACY.md)。

---

## ⚡️ 3 步安装

### 前置条件
确保你已安装任意一款 Rime 前端：
- **macOS**: [鼠须管 Squirrel](https://github.com/rime/squirrel/releases/latest)
- **Windows**: [小狼毫 Weasel](https://github.com/rime/weasel/releases/latest)
- **Linux**: Fcitx5-Rime 或 IBus-Rime

### 🛠️ 安装步骤

首次安装默认下载约 401 MB 语法模型和约 7 MB 预测数据，耗时取决于网络；安装后仍需手动重新部署 Rime。

1. **下载安装包**：打开 [最新版 Release](https://github.com/GravityPoet/rime-smart-simplified/releases/latest)，下载 `rime-smart-simplified-vX.Y.Z.zip`。
2. **双击运行一键脚本**：
   - macOS：双击运行 `Install-on-macOS.command`
   - Windows：双击运行 `Install-on-Windows.cmd`
3. **重新部署**：在对应 Rime 前端的菜单中点击 **“重新部署 (Deploy)”**，然后切换到“雾凇拼音”。

---

## 💡 常用快捷键与实用指令

| 功能/指令 | 输入方式 / 快捷键 | 效果示例 |
|---|---|---|
| **临时切换英文** | 组词时按 `Shift` | 无缝输入英文单词 |
| **实时时间/日期** | 输入 `rq` / `sj` / `dt` | 快速输出 `2026-07-24`、`13:14:00` |
| **星期与农历** | 输入 `xq` / `nl` | 快速输出 `星期五`、`丙午年六月十一` |
| **UUID 唯一标识** | 输入 `uuid` | 自动生成 `c8f3b140-...` 格式 UUID |
| **场景模式切换** | `Control + 反引号` (macOS 亦可 `Fn + F4`) | 打开方案菜单，自由切换常规/聊天/代码模式 |
| **上下文调序** | 方案菜单「上下文」 | 默认开启，改善长句候选排序 |
| **提交后预测** | 方案菜单「预测」 | 默认关闭，每次新会话重置为关闭 |
| **中英自动空格** | 方案菜单「空格」 | 默认关闭，手动选择会被记住 |

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
