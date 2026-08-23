# 安装、使用、校验与回滚

本项目提供的是 **Rime 用户目录配置**，不是鼠须管、小狼毫、Fcitx 或 IBus 本体。请先安装对应的 Rime 前端，再安装本配置。

官方前端入口：

- macOS： [鼠须管 Squirrel](https://github.com/rime/squirrel/releases/latest)，适用于 macOS 13+
- Windows： [小狼毫 Weasel](https://github.com/rime/weasel/releases/latest)，适用于 Windows 8.1–11
- Linux： [Fcitx5 Rime](https://github.com/fcitx/fcitx5-rime) 或 [IBus Rime](https://github.com/rime/ibus-rime)

## 从 Release ZIP 安装（推荐）

在 [Release 页面](https://github.com/GravityPoet/rime-smart-simplified/releases/latest)下载：

```text
rime-smart-simplified-vX.Y.Z.zip
rime-smart-simplified-vX.Y.Z.zip.sha256
```

不要下载 GitHub 自动生成的 `Source code (zip)`。macOS/Linux 可在 ZIP 所在目录校验：

```bash
shasum -a 256 -c rime-smart-simplified-vX.Y.Z.zip.sha256
```

Windows PowerShell 校验：

```powershell
$zip = "rime-smart-simplified-vX.Y.Z.zip"
$check = (Get-Content "${zip}.sha256").Trim().Split()[0].ToLowerInvariant()
$actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $check) { throw "SHA-256 mismatch: expected $check actual $actual" }
Write-Host "SHA-256 OK: $actual"
```

解压后，文件夹根目录会有 `Install-on-macOS.command`、`Install-on-Windows.cmd` 和 `scripts/`。

### macOS / 鼠须管

1. 在 Finder 中双击 `Install-on-macOS.command`。
2. 如果 macOS 阻止首次打开，对文件按住 Control，选择“打开”。
3. 也可以在解压目录打开终端执行：

   ```bash
   bash ./scripts/install.sh
   ```

默认目标目录：`~/Library/Rime`。

### Windows / 小狼毫

1. 双击 `Install-on-Windows.cmd`。
2. 如需命令行参数，在解压目录打开 PowerShell 执行：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
   ```

默认目标目录：`%APPDATA%\Rime`。

### Linux / Fcitx5 或 IBus

在解压目录打开终端，根据正在使用的前端执行一条命令：

```bash
# Fcitx5 Rime
RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" bash ./scripts/install.sh

# IBus Rime（不要与上一条同时执行）
RIME_USER_DIR="$HOME/.config/ibus/rime" bash ./scripts/install.sh
```

安装器会先把所需模型下载到临时目录并完成校验，再触碰 Rime 用户目录；写入前创建不会重名的时间戳备份，保留已有私人短语、聊天短语和冷词偏好。写入失败时会自动恢复已覆盖文件并删除本轮新增文件。首次安装可能下载约 401 MB 的万象 LTS 语法模型和约 7 MB 的预测数据。

## 部署与第一次使用

安装器输出 `Installed` 后，还必须在 Rime 前端菜单执行 **Deploy / 重新部署**：

1. 打开鼠须管、小狼毫、Fcitx5 或 IBus 的托盘菜单。
2. 点击“重新部署 / Deploy”。
3. 将系统输入法切换到对应的 Rime 前端。
4. 在方案菜单中选择“雾凇拼音 / Rime Ice”。
5. 在文本框输入 `nihao`，选择“你好”；再输入 `rq` 测试日期。

方案菜单快捷键：`Control + 反引号键`；macOS 若功能键被系统占用，也可使用 `Fn + F4`。

常用输入：`rq` / `sj` / `xq` / `dt`（日期、时间、星期、日期时间，UTC+8）、`nl`（农历）、`uuid`（随机 UUID）。候选翻页使用 `-`、`=`、`[`、`]`；组词时按 `Shift` 可临时输入英文。

提交后预测默认关闭，并会在每次新会话重置为关闭，避免联想候选打断连续输入。安装脚本会自动下载官方 `predict.db` 预测数据（librime-predict `data-1.0`，固定 SHA-256 校验）；需要时可在方案菜单临时打开「预测」。普通拼音输入不依赖预测数据库；不需要该文件时可用 `--no-download-predict`（Windows：`-NoDownloadPredict`）跳过。

中英混排自动空格（如 `VIP中P` → `VIP 中 P`、连续英文自动加空格）由方案菜单「空格」开关控制，默认关闭，状态会被记住。

## 高级细节：macOS 安装器参数与模型

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

下载完成后，脚本会从 GitHub Release API 读取该资产的 `sha256` digest，并在移动到目标目录前校验临时 staging 文件。只有 API 受限且你接受未校验下载时，才使用：

```bash
cd /path/to/rime-smart-simplified && ./scripts/install.sh --skip-verify-gram
```

如果你已经手动放好了该文件，脚本会复用目标目录里的文件。若只想安装配置、不下载语言模型：

```bash
cd /path/to/rime-smart-simplified && ./scripts/install.sh --no-download-gram
```

安装脚本默认只备份将被覆盖的同名文件。若发生覆盖，备份目录形如：

```text
~/Library/Rime.backup.YYYYMMDD-HHMMSS[.N]
```

首次安装或没有同名文件被覆盖时，脚本会输出：

```text
Backup: none needed
```

仓库中的 `custom_phrase.txt`、`smart_chat_phrases.txt` 和三个 `lua/cold_word_drop/*_words.lua` 只是公开模板：首次安装时会复制；目标目录已有这些文件时，安装器会原样保留，不会覆盖私人短语、聊天短语或冷词隐藏、删除、软降频记录。

每次成功安装还会在目标目录写入 `.rime-smart-simplified.install-manifest`。它只记录本工具实际写入的文件及摘要，不记录用户运行时数据库。需要完整移除本配置包时，先退出对应 Rime 前端，再预览并执行精确卸载：

```bash
cd /path/to/rime-smart-simplified
RIME_USER_DIR="$HOME/Library/Rime" ./scripts/uninstall.sh --dry-run
RIME_USER_DIR="$HOME/Library/Rime" ./scripts/uninstall.sh --apply
```

卸载器会校验 manifest 的源记录摘要、当前包源文件/模型锁摘要、重复项和本包可安装路径；如果你手动编辑、截断或迁移了 manifest，它会停止并保留目标文件，不会把任意私有路径或伪造摘要当成可删除项。此时请从当前仓库重新运行一次安装器生成新的 manifest，再重新预览卸载。`RIME_PACKAGE_VERSION` 只能使用单行安全版本字符，含换行或制表符的值会让安装在写入前熔断。

Linux 将 `RIME_USER_DIR` 换成 Fcitx5 或 IBus 的实际目录。卸载器只删除摘要仍与安装时一致的项目文件；被你修改过的 YAML、词库、私人短语、学习偏好和已有模型会保留，并逐项报告。默认会在删除前创建时间戳备份；`--no-backup` 只适合你已有独立备份时使用。Windows 等价命令为：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -RimeUserDir (Join-Path $env:APPDATA "Rime") -DryRun
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -RimeUserDir (Join-Path $env:APPDATA "Rime") -Apply
```

卸载不会删除空目录，也不会替你删除 Squirrel/小狼毫/Fcitx5/IBus 本体；完成后按前端需要重新部署或切换方案。

## 高级细节：Linux 目标目录

选择你正在使用的 Rime 前端目录：

```bash
# Fcitx5 Rime
RIME_USER_DIR="$HOME/.local/share/fcitx5/rime"

# IBus Rime
RIME_USER_DIR="$HOME/.config/ibus/rime"
```

Linux 上不指定 `RIME_USER_DIR` 时，安装器会直接停止并列出这两个命令，不会误写到 macOS 的 `~/Library/Rime`。如果待写文件或其目标内父目录是 symlink，安装器也会在写入前停止；只有 `RIME_USER_DIR` 指向的整个目标目录本身可为 symlink。

安装到 Fcitx5 Rime：

```bash
cd /path/to/rime-smart-simplified && RIME_USER_DIR="$HOME/.local/share/fcitx5/rime" ./scripts/install.sh
```

安装到 IBus Rime：

```bash
cd /path/to/rime-smart-simplified && RIME_USER_DIR="$HOME/.config/ibus/rime" ./scripts/install.sh
```

Linux 上若语法模型不生效，优先确认你的发行版已安装 Rime 语法模型支持组件，例如 `librime-plugin-octagram` 或发行版对应包名。

## 高级细节：Windows 手动复制（不推荐）

小狼毫用户目录通常是：

```powershell
$env:APPDATA\Rime
```

推荐直接双击解压目录中的 `Install-on-Windows.cmd`。它会调用带备份和私人状态保护的 `scripts/install.ps1`，安装完成后仍需在小狼毫菜单中执行“重新部署”。

PowerShell 等价命令：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

高级参数：`-DryRun`、`-NoDownloadGram`、`-SkipVerifyGram`、`-NoDownloadPredict`、`-NoBackup`。

如需手动复制（仅用于无法运行 PowerShell 安装器的环境）：

```powershell
$repo = "C:\path\to\rime-smart-simplified"
$rime = Join-Path $env:APPDATA "Rime"
New-Item -ItemType Directory -Force $rime | Out-Null

Get-ChildItem $repo -File -Filter *.yaml |
  Where-Object { $_.Name -notin @("user.yaml", "installation.yaml") } |
  Copy-Item -Destination $rime -Force

Copy-Item -Path (Join-Path $repo "rime.lua") -Destination $rime -Force

foreach ($name in @("custom_phrase.txt", "smart_chat_phrases.txt")) {
  $target = Join-Path $rime $name
  if (-not (Test-Path $target)) {
    Copy-Item -Path (Join-Path $repo $name) -Destination $target
  } else {
    Write-Host "Private phrases: preserving existing $name"
  }
}

$coldState = @{}
foreach ($rel in @(
  "lua\cold_word_drop\drop_words.lua",
  "lua\cold_word_drop\hide_words.lua",
  "lua\cold_word_drop\reduce_freq_words.lua"
)) {
  $path = Join-Path $rime $rel
  if (Test-Path $path) {
    $coldState[$rel] = [System.IO.File]::ReadAllBytes($path)
  }
}

foreach ($dir in @("cn_dicts", "cn_dicts_wanxiang", "en_dicts", "lua", "opencc")) {
  Copy-Item -Path (Join-Path $repo $dir) -Destination $rime -Recurse -Force
}

foreach ($rel in $coldState.Keys) {
  [System.IO.File]::WriteAllBytes((Join-Path $rime $rel), $coldState[$rel])
}
```

手动下载并校验语言模型：

```powershell
$api = "https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS"
$name = "wanxiang-lts-zh-hans.gram"
$asset = (Invoke-RestMethod $api).assets | Where-Object { $_.name -eq $name }
$gram = Join-Path $rime $name
$gramTmp = "$gram.tmp"

Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $gramTmp
$expected = $asset.digest -replace "^sha256:", ""
$actual = (Get-FileHash $gramTmp -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) {
  throw "SHA-256 mismatch: expected $expected actual $actual"
}
Move-Item -LiteralPath $gramTmp -Destination $gram -Force

$predictUrl = "https://github.com/rime/librime-predict/releases/download/data-1.0/predict.db"
$predict = Join-Path $rime "predict.db"
$predictTmp = "$predict.tmp"
$predictExpected = "2a5a2b7c77f8f3d7c0836dfc8fd8b791ac2574d8bd93a3a2baaae1ee4861f5be"
Invoke-WebRequest -Uri $predictUrl -OutFile $predictTmp
$predictActual = (Get-FileHash $predictTmp -Algorithm SHA256).Hash.ToLowerInvariant()
if ($predictActual -ne $predictExpected) {
  throw "predict.db SHA-256 mismatch: expected $predictExpected actual $predictActual"
}
Move-Item -LiteralPath $predictTmp -Destination $predict -Force
```

然后在小狼毫菜单中执行“重新部署”。手动复制不会替代安装器的自动备份能力，普通客户应优先使用 `Install-on-Windows.cmd`。

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

仓库还提供不触碰真实用户目录的上游锁定和基准检查：

```bash
cd /path/to/rime-smart-simplified
./scripts/check_upstream_freshness.sh --local-only --strict
./scripts/benchmark.sh --iterations 20 --output /tmp/rime-smart-simplified-benchmark.jsonl
```

基准输出明确标记 `proxy: true` 和 `accuracy_claim: false`；它能证明安装、构建、librime API 候选 smoke 及 Lua 候选流的可重复工程信号，但不冒充真实前端首字延迟或准确率。详见 [`docs/BENCHMARK.md`](./docs/BENCHMARK.md)。

## 回滚

安装过程失败时，新版安装器会自动恢复；下面的命令用于成功安装后主动恢复被覆盖的旧文件。先退出对应 Rime 前端，将备份目录里的文件复制回用户目录，再重新部署。时间戳备份不删除本次新增文件，因此它是“恢复旧文件”，不是完整卸载。

macOS 示例：

```bash
rsync -a ~/Library/Rime.backup.YYYYMMDD-HHMMSS/ ~/Library/Rime/
```

Linux Fcitx5 示例：

```bash
rsync -a ~/.local/share/fcitx5/rime.backup.YYYYMMDD-HHMMSS/ ~/.local/share/fcitx5/rime/
```

Windows PowerShell 示例：

```powershell
$backup = Join-Path $env:APPDATA "Rime.backup.YYYYMMDD-HHMMSS"
$target = Join-Path $env:APPDATA "Rime"
Copy-Item -Path (Join-Path $backup "*") -Destination $target -Recurse -Force
```

上下文学习日志首次达到压缩阈值前，会在用户目录自动保留 `context_boost.tsv.bak.pre-journal-v2`（以及存在旧日志时对应的日志备份）。压缩只合并快照与增量日志，不按时间或库大小删除有效学习记录。如需单独回滚学习数据，退出 Rime 前端后将该快照复制回 `context_boost.tsv`，删除 `context_boost.journal.tsv`，再恢复旧版 `lua/context_boost_filter.lua` 并重新部署。

## 不要提交的本地文件

- `context_boost.tsv`
- `context_boost.journal.tsv`
- `context_boost*.bak.*`
- `pin_by_select.tsv`
- `pin_by_select_v2.tsv`
- `predict.db`
- `*.userdb/`
- `sync/`
- `build/`
- `installation.yaml`
- `user.yaml`
- `*.gram`
- 含个人邮箱、手机号、账号、暗号、客户名、内部项目名的 `custom_phrase.txt` 或 `smart_chat_phrases.txt`
