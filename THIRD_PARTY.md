# 第三方来源与许可证

本仓库聚合了多个 Rime 生态项目和词库。发布日期前请保留原始来源、作者信息与许可证文本。

| 来源 | 本仓库用途 | 许可证 | 官方链接 |
|---|---|---|---|
| rime-ice | 雾凇拼音方案、基础配置、部分词库与 Lua 组件 | GPL-3.0 | https://github.com/iDvel/rime-ice |
| RIME-LMDG | 万象 LTS 简体词库与语言模型数据 | CC-BY-4.0 | https://github.com/amzxyz/RIME-LMDG |
| rime-radical-pinyin | 部件拆字反查（方案与词库按 GPL-3.0，lua/search.lua 头部标注 CC BY-SA 4.0） | GPL-3.0 / CC BY-SA 4.0 | https://github.com/mirtlecn/rime-radical-pinyin |
| plum | Rime 配方管理工具，许可证文本归档 | LGPL-3.0 | https://github.com/rime/plum |

许可证文本位于：

- `third_party/licenses/rime-ice-GPL-3.0.txt`
- `third_party/licenses/RIME-LMDG-CC-BY-4.0.txt`
- `third_party/licenses/rime-radical-pinyin-GPL-3.0.txt`
- `third_party/licenses/plum-LGPL-3.0.txt`

特定文件许可证注解：

- `lua/search.lua`：由上游作者 Mirtle 在文件头部显式声明为 **CC BY-SA 4.0** 许可证（Creative Commons 官方仅将其列为单向兼容至 GPLv3，未包含 AGPLv3）。在使用或再分发时，该文件需遵循 CC BY-SA 4.0 及其兼容条件，不涵盖在本项目所有者的商业独占许可免除范围内。

注意：这不是法律意见。公开发布前如果要包装成“商业输入法平替”并做大范围传播，建议避免夸大兼容性，保留“基于 Rime 生态的开源配置方案”这个表述。
