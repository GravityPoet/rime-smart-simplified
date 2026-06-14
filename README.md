# Rime Smart Simplified

一套面向简体中文日常输入的 Rime 配置：本地优先、离线可用、可学习、可回滚。目标是把商业输入法里常用的体验做成开源替代：更好的首屏候选、更稳的模糊音、上下文调序、短码降噪、可恢复降频、中英混输、Emoji、万象 LTS 语言模型。

## 特性

- 简体中文优先：短码守门会把繁体、生僻字、Emoji、英文候选后移。
- 搜狗感模糊音：覆盖 zh/ch/sh、n/l、f/h、an/ang、en/eng、in/ing 等常见误差。
- 本地学习：候选选择、上下文搭配、降频反馈都只写入本机 Rime 用户目录。
- 隐私友好：输入过程不联网、不上传输入内容、不内置个人用户词库。
- 大词库底座：基于雾凇拼音、万象 LTS 简体词库、英文与中英混输词库。
- 跨平台配置：包含 macOS 鼠须管 `squirrel.custom.yaml` 和 Windows 小狼毫 `weasel.custom.yaml`。

## 安装

macOS 鼠须管：

```bash
cd /path/to/Rime Smart Simplified && ./scripts/install.sh
```

安装脚本会在本机缺少 `wanxiang-lts-zh-hans.gram` 时，从万象 `RIME-LMDG` 的官方 `LTS` release 下载语言模型。这个文件约 401MB，未提交到本仓库，因为 GitHub 单文件限制是 100MB。

Windows 小狼毫或 Linux 用户可以把本仓库中除 `.git/`、文档、`scripts/`、`third_party/` 之外的配置文件复制到自己的 Rime 用户目录，再从 `RIME-LMDG` 官方 release 下载 `wanxiang-lts-zh-hans.gram` 放入 Rime 用户目录，然后重新部署。

## 隐私边界

本仓库不包含作者本机的 `custom_phrase.txt` 私密条目、`context_boost.tsv`、`pin_by_select_v2.tsv`、`predict.db`、`*.userdb`、`sync/`、`build/`、`installation.yaml`、`user.yaml` 或大型 `.gram` 语言模型。安装后这些文件可能在你的机器上生成，它们属于你的本地数据或外部资产，不建议提交到公开仓库。

## 许可证

本仓库是多来源聚合项目，不能简单视为单一来源作品：

- 基于 `rime-ice` 的配置与词库遵循 GPL-3.0。
- 万象 `RIME-LMDG` 数据遵循 CC-BY-4.0。
- `rime-radical-pinyin` 相关组件遵循 GPL-3.0。
- Rime/plum 许可证文本仅用于归档第三方许可证说明，遵循 LGPL-3.0。

详见 `THIRD_PARTY.md` 与 `third_party/licenses/`。
