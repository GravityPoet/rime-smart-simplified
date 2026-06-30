# 安装、校验与回滚

本仓库提供的是 Rime 用户目录配置。安装后需要在输入法菜单里执行“重新部署/Deploy”。

## macOS 鼠须管 Squirrel

Dry run：

```bash
cd /path/to/rime-smart-simplified && ./scripts/install.sh --dry-run
```

安装：

```bash
cd /path/to/rime-smart-simplified && ./scripts/install.sh
```

脚本默认安装到：

```text
~/Library/Rime
```

如需指定目标目录：

```bash
cd /path/to/rime-smart-simplified && RIME_USER_DIR="$HOME/Library/Rime" ./scripts/install.sh
```

默认安装会在目标 Rime 目录缺少 `wanxiang-lts-zh-hans.gram` 时下载官方万象 LTS 语言模型：

```text
https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram
```

下载完成后，脚本会从 GitHub Release API 读取该资产的 `sha256` digest，并在移动到目标目录前校验 `.tmp` 文件。只有 API 受限且你接受未校验下载时，才使用：

```bash
cd /path/to/rime-smart-simplified && ./scripts/install.sh --skip-verify-gram
```

如果你已经手动放好了该文件，脚本会复用目标目录里的文件。若只想安装配置、不下载语言模型：

```bash
cd /path/to/rime-smart-simplified && ./scripts/install.sh --no-download-gram
```

安装脚本默认只备份将被覆盖的同名文件。若发生覆盖，备份目录形如：

```text
~/Library/Rime.backup.YYYYMMDD-HHMMSS
```

首次安装或没有同名文件被覆盖时，脚本会输出：

```text
Backup: none needed
```

## Linux

选择你正在使用的 Rime 前端目录：

```bash
# Fcitx5 Rime
RIME_USER_DIR="$HOME/.local/share/fcitx5/rime"

# IBus Rime
RIME_USER_DIR="$HOME/.config/ibus/rime"
```

安装到 Fcitx5 Rime：

```bash
cd /path/to/rime-smart-simplified && RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" ./scripts/install.sh
```

安装到 IBus Rime：

```bash
cd /path/to/rime-smart-simplified && RIME_USER_DIR="$HOME/.config/ibus/rime" ./scripts/install.sh
```

Linux 上若语法模型不生效，优先确认你的发行版已安装 Rime 语法模型支持组件，例如 `librime-plugin-octagram` 或发行版对应包名。

## Windows 小狼毫 Weasel

小狼毫用户目录通常是：

```powershell
$env:APPDATA\Rime
```

PowerShell 安装：

```powershell
$repo = "C:\path\to\rime-smart-simplified"
$rime = Join-Path $env:APPDATA "Rime"
New-Item -ItemType Directory -Force $rime | Out-Null

Get-ChildItem $repo -File -Filter *.yaml |
  Where-Object { $_.Name -notin @("user.yaml", "installation.yaml") } |
  Copy-Item -Destination $rime -Force

Copy-Item -Path (Join-Path $repo "rime.lua"), (Join-Path $repo "custom_phrase.txt") -Destination $rime -Force

foreach ($dir in @("cn_dicts", "cn_dicts_wanxiang", "en_dicts", "lua", "opencc")) {
  Copy-Item -Path (Join-Path $repo $dir) -Destination $rime -Recurse -Force
}
```

手动下载并校验语言模型：

```powershell
$api = "https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS"
$name = "wanxiang-lts-zh-hans.gram"
$asset = (Invoke-RestMethod $api).assets | Where-Object { $_.name -eq $name }
$gram = Join-Path $rime $name

Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $gram
$expected = $asset.digest -replace "^sha256:", ""
$actual = (Get-FileHash $gram -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) {
  throw "SHA-256 mismatch: expected $expected actual $actual"
}
```

然后在小狼毫菜单中执行“重新部署”。

## 手动 SHA-256 校验

macOS / Linux 手动下载后，可用 GitHub Release API 的当前 digest 校验：

```bash
cd /path/to/rime-smart-simplified
name="wanxiang-lts-zh-hans.gram"
digest="$(curl -fsSL https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS | awk -v name="$name" 'index($0, "\"name\": \"" name "\"") { found = 1 } found && index($0, "\"digest\":") { sub(/^.*"digest": "/, "", $0); sub(/".*$/, "", $0); print; exit }')"
expected="${digest#sha256:}"
actual="$(shasum -a 256 "$name" | awk '{print $1}')"
test "$actual" = "$expected"
```

`LTS` 是上游 rolling Release；不要把旧 digest 当作永久固定值。每次重新下载时都应读取当时的 GitHub Release API digest。

## 回滚

将备份目录里的文件复制回 Rime 用户目录，然后重新部署。

macOS 示例：

```bash
rsync -a ~/Library/Rime.backup.YYYYMMDD-HHMMSS/ ~/Library/Rime/
```

Linux Fcitx5 示例：

```bash
rsync -a ~/.local/share/fcitx5/rime.backup.YYYYMMDD-HHMMSS/ ~/.local/share/fcitx5/rime/
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
