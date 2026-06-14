# 安装与回滚

## macOS 鼠须管

Dry run：

```bash
cd /path/to/Rime Smart Simplified && ./scripts/install.sh --dry-run
```

安装：

```bash
cd /path/to/Rime Smart Simplified && ./scripts/install.sh
```

默认安装会在目标 Rime 目录缺少 `wanxiang-lts-zh-hans.gram` 时下载官方万象 LTS 语言模型：

```text
https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram
```

如果你已经手动放好了该文件，脚本会复用目标目录里的文件。若只想安装配置、不下载语言模型：

```bash
cd /path/to/Rime Smart Simplified && ./scripts/install.sh --no-download-gram
```

安装脚本默认只备份将被覆盖的同名文件，备份目录形如：

```text
~/Library/Rime.backup.YYYYMMDD-HHMMSS
```

安装后在鼠须管菜单里执行“重新部署”。

## 回滚

将备份目录里的文件复制回 Rime 用户目录，然后重新部署。

```bash
rsync -a ~/Library/Rime.backup.YYYYMMDD-HHMMSS/ ~/Library/Rime/
```

## 不要提交的本地文件

- `context_boost.tsv`
- `pin_by_select.tsv`
- `pin_by_select_v2.tsv`
- `predict.db`
- `*.userdb/`
- `sync/`
- `build/`
- `installation.yaml`
- `user.yaml`
- `*.gram`
- 含个人邮箱、手机号、账号、暗号、客户名、内部项目名的 `custom_phrase.txt`
