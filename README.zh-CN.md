## 🌐 [Click here to switch to: English Version](./README.md)

<p align="center">
  <a href="./README.md"><img alt="English" src="https://img.shields.io/badge/Language-English-2563EB?style=for-the-badge"></a>
  <a href="./README.zh-CN.md"><img alt="简体中文" src="https://img.shields.io/badge/Language-%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87-EF4444?style=for-the-badge"></a>
</p>

# Rime Smart Simplified

> 一套以本地运行为优先的 Rime 简体中文配置：上下文调序、模糊音、中英混输和本地学习，装好即可开始输入。

[下载最新版 ZIP](https://github.com/GravityPoet/rime-smart-simplified/releases/latest) · [完整安装与回滚说明](./INSTALL.md) · [隐私边界](./PRIVACY.md)

本项目是 **Rime 用户目录配置包**，不是独立的输入法 App。请先安装一个 Rime 前端，再把本配置安装到前端的用户目录。

## 你会得到什么

- **开箱即用的首屏候选**：雾凇拼音简体中文默认配置，包含模糊音、中英混输、Emoji 和常用词库。
- **本地适应**：上下文调序和学习数据保存在本机 Rime 用户目录；更新时保留已有私人短语及冷词偏好。
- **可选的本地智能辅助**：可使用万象 LTS 本地语法模型。提交后预测默认关闭，避免普通复制、粘贴快捷键被组合态干扰。

## 下载前先准备

你需要先安装一个 Rime 前端：

| 平台 | 前端 | 官方入口 |
| --- | --- | --- |
| macOS 13+ | 鼠须管 Squirrel | [Rime 下载页](https://rime.im/download/) · [Squirrel Releases](https://github.com/rime/squirrel/releases/latest) |
| Windows 8.1–11 | 小狼毫 Weasel | [Rime 下载页](https://rime.im/download/) · [Weasel Releases](https://github.com/rime/weasel/releases/latest) |
| Linux | Fcitx5 Rime 或 IBus Rime | [Fcitx5 Rime](https://github.com/fcitx/fcitx5-rime) · [IBus Rime](https://github.com/rime/ibus-rime) |

首次安装可能会下载官方 `wanxiang-lts-zh-hans.gram` 语法模型（约 401 MB）。本项目运行时不会上传输入内容；安装器只会在需要获取或校验模型时访问 GitHub。

## 从 ZIP 安装（推荐）

### 1. 下载正确的文件

打开[最新版 Release](https://github.com/GravityPoet/rime-smart-simplified/releases/latest)，下载名称为：

```text
rime-smart-simplified-vX.Y.Z.zip
```

不要下载 GitHub 自动生成的 `Source code (zip)`。应下载上面这个带项目名和版本号的资产；旁边的 `.sha256` 文件用于校验完整性。

### 2. 解压并运行对应平台入口

#### macOS / 鼠须管

1. 在 Finder 中解压 ZIP。
2. 打开解压后的文件夹，双击 `Install-on-macOS.command`。
3. 如果 macOS 弹出安全提示，对文件按住 Control 并选择“打开”。也可以在该文件夹中打开终端执行：

   ```bash
   bash ./scripts/install.sh
   ```

#### Windows / 小狼毫

1. 解压 ZIP。
2. 双击 `Install-on-Windows.cmd`。
3. 如果习惯使用 PowerShell，在解压后的文件夹中执行：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
   ```

Windows 安装器默认写入 `%APPDATA%\Rime`。覆盖已有文件前会创建带时间戳的备份，并保留已有私人短语和冷词文件。

#### Linux / Fcitx5 或 IBus

在解压后的文件夹中打开终端，根据你使用的前端选择一条命令：

```bash
# Fcitx5 Rime
RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/install.sh

# IBus Rime（不要与上一条同时执行）
RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/install.sh
```

### 3. 重新部署并选择方案

安装器完成后：

1. 打开输入法托盘图标或菜单。
2. 点击 **Deploy / 重新部署**。
3. 将系统当前输入法切换为鼠须管、小狼毫、Fcitx5 Rime 或 IBus Rime。
4. 在方案菜单中选择 **雾凇拼音 / Rime Ice**（如果尚未自动选中）。

## 第一次使用怎么验证

打开任意文本框，按下面三步确认已经生效：

1. 输入 `nihao`，按回车或候选序号选择“你好”。
2. 输入 `rq` 查看日期，输入 `sj` 查看当前时间（UTC+8）。
3. 按 `Control + 反引号键` 打开方案菜单；macOS 也可以按 `Fn + F4`。

常用操作：

| 操作 | 快捷键 / 输入 |
| --- | --- |
| 临时英文 | 组词时按 `Shift`，或按当前前端的 `Caps Lock` 设置 |
| 候选翻页 | `-` / `=` 或 `[` / `]` |
| 日期、时间、星期 | `rq`、`sj`、`xq`、`dt` |
| 农历、UUID | `nl`、`uuid` |
| 场景模式 | 打开方案菜单，选择常规、聊天、写作或代码 |

提交后预测默认**关闭**。如果你的前端提供兼容的本地 `predict.db`，可以在方案菜单中临时打开；普通拼音输入不依赖它。

## 更新与回滚

升级到新版本时仍运行对应平台的安装入口。安装器会备份将被覆盖的文件，保留私人短语和冷词偏好，并输出备份目录。恢复备份后，再执行一次“重新部署”：

```bash
rsync -a "$HOME/Library/Rime.backup.YYYYMMDD-HHMMSS/" "$HOME/Library/Rime/"
```

Linux、Windows 路径、SHA-256 校验、模型下载开关和完整回滚步骤见 [INSTALL.md](./INSTALL.md)。

## 支持项目

如果这套配置帮你节省了时间、守住了输入隐私，欢迎点 Star 或赞助维护工作。支持会用于多平台兼容测试、模型适配和持续维护。

| 微信赞赏码 | PayPal 收款码 |
| :---: | :---: |
| <img src="./docs/sponsors/wechat_pay.jpg" width="220" alt="微信赞赏码" /> | <img src="./docs/sponsors/paypal.jpg" width="220" alt="PayPal 收款码" /> |

## 信任边界与限制

- 本仓库提供配置、Lua 扩展、词库和脚本，不包含鼠须管、小狼毫、Fcitx 或 IBus 本体。
- 语法模型来自上游 [RIME-LMDG](https://github.com/amzxyz/RIME-LMDG) Release，默认按 GitHub 资产 digest 校验。
- 本项目不提供云端预测或云同步；系统级输入法行为仍由你安装的 Rime 前端控制。
- ZIP 遵循本仓库许可证发布，第三方许可证见 [THIRD_PARTY.md](./THIRD_PARTY.md)。

## 致谢

本配置基于并致谢 [雾凇拼音](https://github.com/iDvel/rime-ice)、[RIME-LMDG](https://github.com/amzxyz/RIME-LMDG) 和 [rime-radical-pinyin](https://github.com/mirtlecn/rime-radical-pinyin)。详见 [LICENSE](./LICENSE) 与 [THIRD_PARTY.md](./THIRD_PARTY.md)。

---

## ⚖️ 许可证 (License)

rime-smart-simplified 社区版基于 **[AGPL-3.0 License](./LICENSE)** 协议开源。

- **开源免费使用**：任何个人和企业均可按照 AGPL-3.0 协议规定**免费使用与分发**。
- **商业免开源许可**：如果您或您的企业需要将本软件**闭源集成、免除 AGPL-3.0 开源义务或获取专有再分发权**，请联系我们购买 [商业许可 (Commercial Dual-License)](mailto:moonlitpoet@proton.me)。第三方授权与归属详见 [THIRD_PARTY.md](./THIRD_PARTY.md) 文件。
