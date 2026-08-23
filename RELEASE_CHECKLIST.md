# 发布前检查清单

- [ ] `git status --short --branch` 干净或只包含预期文件。
- [ ] `./scripts/verify.sh` 本地通过。
- [ ] `./scripts/check_release_archive.sh` 通过；归档不含 ownership manifest、benchmark 输出、用户/运行时数据库、模型、构建产物或备份目录。
- [ ] `./scripts/check_upstream_freshness.sh --local-only --strict` 通过，且 `UPSTREAM_ASSETS.lock.json` 与七个万象词库内容一致。
- [ ] 发布前 `./scripts/check_upstream_freshness.sh --strict` 通过；若 GitHub API 不可用，停止发布而不是使用 `--offline-ok`。
- [ ] GitHub Actions `CI` 在目标提交的 `verify`、`benchmark`、`windows-installer`、`macos-rime`、`linux-frontends`、`upstream-freshness` 六个 check 均为 `completed/success`。
- [ ] 用自己的邮箱、手机号、账号名、内部项目名替换下面的占位符后扫描：`rg -n -i "YOUR_HANDLE|YOUR_EMAIL|YOUR_PHONE|YOUR_PRIVATE_PROJECT" .`。
- [ ] `git ls-files | rg '(^|/)(.*\.bak($|\.)|.*\.backup\.|.*\.userdb($|/)|predict\.db$|.*\.gram$|\.rime-smart-simplified\.install-manifest$|benchmark-results\.jsonl$|context_boost.*\.tsv$|pin_by_select.*\.tsv$|runLog\.txt$)'` 无运行数据或备份命中；本机已忽略的回滚目录不会进入 `git archive`。
- [ ] `git ls-files | rg "\.gram$"` 无命中。
- [ ] 若重新下载了 `wanxiang-lts-zh-hans.gram`，已按 `INSTALL.md` 校验 GitHub Release API 的当前 SHA-256 digest。
- [ ] 若运行 `scripts/update_dicts.sh --apply`，已保留报告的 `cn_dicts_wanxiang.backup.<timestamp>`，并确认 `cn_dicts/` 下的本地/领域词库未被改动。
- [ ] 官方许可证链接仍可访问。
- [ ] macOS 鼠须管重新部署成功。
- [ ] Release ZIP 解压后包含 `Install-on-macOS.command`、`Install-on-Windows.cmd`、`scripts/install.ps1`。
- [ ] 客户路径已从“下载 ZIP → 解压 → 运行平台入口 → 重新部署 → 首次输入”走通。
- [ ] README 没有宣称“完全替代所有商业输入法云能力”。
- [ ] `THIRD_PARTY.md` 覆盖 rime-ice、RIME-LMDG、rime-wanxiang、librime-predict 与 radical-pinyin 的当前来源和许可证。
- [ ] GitHub 仓库首次发布前使用 private 仓库复核一遍，再改 public。
