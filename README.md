# 织法之杖 · Spellwoven Wands

**正式版 1.0.7 · 2026-11-15**

[Steam 创意工坊订阅](https://steamcommunity.com/sharedfiles/filedetails/?id=3834454416) · [中文资料站](https://huangxxuuu.github.io/spellwoven-wands/) · [English field guide](https://huangxxuuu.github.io/spellwoven-wands/en/) · [下载正式版](https://github.com/huangxxuuu/spellwoven-wands/releases/tag/v1.0.7)

收集随机法杖，自由编排法术卡，将战斗、工具与乐器组合进同一套玩法。支持中文与 English；房主启用，参与玩家安装。1.0.7 增加伤害倍率设置，优化并修复目标选择系列法术卡，并将速度上限提高到 95。[本版说明](docs/releases/1.0.7-public.txt) · [完整发布记录](docs/releases/1.0.7-commit.txt)

Collect randomized wands and arrange spell cards to create your own attacks in Don't Starve Together. Inspired by Noita. Chinese and English are supported.

## 开发入口

新需求按[开发导航](docs/开发导航.md)定位源码、约束和测试；[当前状态](docs/当前状态.md)区分正式版与工作区差异。[文档索引](docs/文档索引.md)用于查专题或历史决定，无需通读旧交接。

| 目录 | 用途 |
| --- | --- |
| `mod/` | 游戏运行代码、贴图、动画与声音 |
| `tools/`、`tests/` | 构建、定向回归、安装与发布工具 |
| `assets_src/` | 源素材和候选稿；从[有效资源索引](docs/art/05_资源索引.md)选择输入 |
| `site/` | 页面源、翻译与构建器；`site/public/` 为生成目录 |
| `docs/` | 现行规范、专题记录与按需历史资料 |

在根目录 PowerShell 使用已有 `.venv/Scripts/python.exe`；首次配置环境时安装 `tools/requirements-dev.txt`。

```powershell
.venv/Scripts/python.exe tools/context.py
.venv/Scripts/python.exe tools/run_tests.py tests/test_modifier_scope.lua
.venv/Scripts/python.exe tools/run_python_tests.py -p test_wand_container_native.py
```

测试、资料站构建、专服和本地安装的完整入口见[验证与安装](docs/验证与安装.md)。默认先跑对应模块检查；测试成功仅输出总结，异常输出失败摘要，完整日志保存在 `test_reports/`，加 `--verbose` 可查看全部。Lua runner 无参数仍运行全套。自动检查与客户端实机验收分别记录。

## 美术与发布

新图、改图及 Prompt 先读[美术任务流程](docs/art/00_美术任务流程.md)；只构建已有资源时按资源索引选择脚本。源图、候选与游戏资源各自保留身份。

发布前读[版本发布约定](docs/协作/版本发布约定.md)及[发布流程](docs/发布流程.txt)。使用独立发布 checkout 和正式脚本，先确认对外说明，再执行 `prepare → commit → publish`；普通本地构建不部署，不修改工坊元数据。

## 历史与许可

已发布版本见[正式记录索引](docs/文档索引.md#正式记录与历史资料)，早期开发过程见[整理前 README](docs/历史/README_20261114整理前.md)。历史版本号不代表当前工作区、安装或发布状态。

原创代码采用 [MIT 许可证](LICENSE)，作者 **yuejian**。原版游戏素材与第三方内容的范围见 [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES.txt)。本项目开发使用 Codex。[提交问题](https://github.com/huangxxuuu/spellwoven-wands/issues)
