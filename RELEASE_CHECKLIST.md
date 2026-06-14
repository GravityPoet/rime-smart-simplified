# 发布前检查清单

- [ ] `git status --short --branch` 干净或只包含预期文件。
- [ ] 用自己的邮箱、手机号、账号名、内部项目名替换下面的占位符后扫描：`rg -n -i "YOUR_HANDLE|YOUR_EMAIL|YOUR_PHONE|YOUR_PRIVATE_PROJECT" .`。
- [ ] `find . -name "*.bak*" -o -name "*.userdb*" -o -name "predict.db" -o -name "context_boost.tsv" -o -name "pin_by_select*.tsv"` 无运行数据命中。
- [ ] `git ls-files | rg "\.gram$"` 无命中。
- [ ] 官方许可证链接仍可访问。
- [ ] macOS 鼠须管重新部署成功。
- [ ] README 没有宣称“完全替代所有商业输入法云能力”。
- [ ] GitHub 仓库首次发布前使用 private 仓库复核一遍，再改 public。
