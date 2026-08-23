# 可复现基准测试

`scripts/benchmark.sh` 提供一条不读取真实用户 Rime 目录、不上传输入内容的基准路径。它把“可测的工程信号”和“尚未测量的用户准确率”明确分开：

| 记录 | 测量内容 | 证据边界 |
| --- | --- | --- |
| `lua_filter` | 250 个合成候选流经过 `short_code_clean_filter`、`cold_word_drop.filter` 的 CPU 时间 | `synthetic: true`、`proxy: true`；不是准确率、不是 GUI 首字延迟 |
| `isolated_install_proxy` | 真实 `scripts/install.sh` 在临时 Rime 目录中的写入耗时 | `synthetic: false`、`proxy: true`；不代表真实前端部署时间 |
| `isolated_rime_build_proxy` | 真实 `rime_deployer --build` 在临时目录中的构建耗时 | `synthetic: false`、`proxy: true`；不代表用户端输入延迟 |
| `librime_candidate_smoke_proxy` | 真实 librime API 在隔离目录中提交 `nihao` 并检查 `你好` 是否出现在候选页 | `synthetic: false`、`proxy: true`、`real_frontend: false`；不等同于 Squirrel/Weasel/Fcitx/IBus 验收 |

所有 JSONL 记录都带 `accuracy_claim: false`。本项目不会把合成候选流或单条 smoke 输入包装成“准确率百分比”。要声明准确率，必须另行提供固定语料、标注标准、基线方案、候选页范围和统计脚本。

## 运行

只运行不依赖 Rime 前端、模型下载或 librime 开发包的 Lua 代理：

```bash
cd /Users/moonlitpoet/Tools/AI-tools/rime-smart-simplified
./scripts/benchmark.sh --lua-only --iterations 50 \
  --output /tmp/rime-smart-simplified-benchmark.jsonl
```

运行完整的隔离安装、构建和 librime API smoke（需要 `rime_deployer`、C++ 编译器、`pkg-config` 和 librime 开发文件）：

```bash
cd /Users/moonlitpoet/Tools/AI-tools/rime-smart-simplified
./scripts/benchmark.sh --iterations 20 \
  --output /tmp/rime-smart-simplified-benchmark-full.jsonl
```

脚本只在临时目录中安装和构建；不会使用 `~/Library/Rime`、`~/.local/share/fcitx5/rime`、`~/.config/ibus/rime` 或 Windows 用户目录。模型下载开关固定为 `--no-download-gram --no-download-predict`，因此基准不需要网络模型，也不会把模型下载时间混入结果。

## JSONL 解释

每次运行先输出一个 `record: "run"` 元数据行，再输出 Lua 记录和（完整模式下）三个隔离代理记录。`run_id`、`git_sha`、平台和迭代次数用于复现；Lua 行的 `samples_cpu_ms` 是 Lua `os.clock()` 进程 CPU 时间，不是墙钟首字延迟。

建议保存以下环境信息：

```bash
cd /Users/moonlitpoet/Tools/AI-tools/rime-smart-simplified
git rev-parse HEAD
lua -v
rime_deployer --version 2>/dev/null || true
uname -a
```

不同机器、Lua 版本、CPU、Rime 词库和系统负载之间不要直接比较绝对毫秒值。比较时应固定 commit、候选数量、迭代次数和运行环境，并报告中位数/P95以及完整原始 JSONL。

## 验收门槛

仓库验证脚本会运行轻量契约测试，确保输出仍是 JSONL、包含两个合成过滤器记录，并保留深分页候选。单独运行：

```bash
cd /Users/moonlitpoet/Tools/AI-tools/rime-smart-simplified
./tests/benchmark_contract_test.sh
```

发布前还应在目标平台完成真实前端路径：安装 → Rime 重新部署 → 首次输入 → 切换方案 → 恢复/卸载。该路径的结果不能用本文件中的 `proxy: true` 记录替代。
