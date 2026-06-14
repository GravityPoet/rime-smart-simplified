# 隐私说明

这套配置的设计原则是本地优先：

- 不调用云输入接口。
- 不上传输入内容。
- 不要求账号登录。
- 本地学习数据写在 Rime 用户目录。
- 安装脚本可能下载官方万象 LTS 语言模型；这是安装期资产下载，不是输入内容上传。

需要特别注意：Rime 的用户目录会自然积累个人输入习惯。以下文件可能含个人信息，不应公开：

- `custom_phrase.txt`
- `context_boost.tsv`
- `pin_by_select.tsv`
- `pin_by_select_v2.tsv`
- `predict.db`
- `*.userdb/`
- `sync/`
- `installation.yaml`
- `user.yaml`
- `*.gram`

公开 fork 或发 PR 前，请先运行：

```bash
rg -n -i "email|phone|token|secret|password|api[_-]?key|/Users/|@[A-Z0-9.-]+\\.[A-Z]{2,}" .
```
