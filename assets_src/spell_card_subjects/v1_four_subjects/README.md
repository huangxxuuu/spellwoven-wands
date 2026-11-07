# 四种法术卡主图 v1

依据 `docs/20_法术卡分类与视觉设计规范.md` 第 4.4–4.5 节，为火焰弹、冰霜弹、重能量球、工具刻印制作独立主图。工具代表选用园艺锄 `edge_farm_hoe`。

## 制作方式

第一轮先保存四份完整 prompt，再使用内置 image_gen 逐张生成透明背景主图。各 `.prompt.txt` 为当时实际提交的提示词；`prompts.json` 记录参考路径和提示词。

**2026-11-07 后续确认：有对应原版武器或道具的卡原则上直接使用原版素材，只在边框内等比缩放并尽量大；旋斧攻击 `whirl`、长矛戳击 `thrust`、玻璃刀砍 `slash` 为用户明确指定的单绘例外。** 这三个例外以对应原版武器的可辨形象配合旋转、前刺、挥砍轨迹表达动作，另在 `../v2_melee_actions/` 制作。本轮四主图中的园艺锄仍选用 [原版主体](edge_farm_hoe.native.png)，第一轮生成版不再作为工具主图。火焰、冰霜、重球仍使用已生成的自定义主体。当前选择统一记录于 `selection.json`。

当前公开卡表共有 64 张具备明确原版来源：61 张原版直用（60 张 `edge_` 卡与火药 `gunpowder`），3 张为上述单绘动作例外。这是素材选择规则与制作分工，不代表全部运行时卡面已经迁移。

## 统一约束

单主体、真实透明背景、无卡框/纸底/文字/角标。自定义弹体保持现行形象并按手绘大明暗色块制作。原版直用清单中的主体直接复用原版图像，保留颜色、结构、朝向和比例；只整理透明外边距、等比缩放与定位，完整容纳在边框内缘中并尽量大。三个近战动作例外允许单绘武器与动作轨迹，两者同样必须完整位于框内。高清图仍需后续小尺寸和边框组合检查。

## 当前阶段

已完成四张第一轮主图候选，均为 1254×1254 RGBA PNG；已检查主体形象、透明背景、可见轮廓完整性，并逐文件校验与生成原图的 SHA-256 一致。尚未接入运行时。

| 主体 | 完整提示词 | 主图 |
| --- | --- | --- |
| 火焰弹 | [fire.prompt.txt](fire.prompt.txt) | [fire.png](fire.png) |
| 冰霜弹 | [frost.prompt.txt](frost.prompt.txt) | [frost.png](frost.png) |
| 重能量球 | [heavy.prompt.txt](heavy.prompt.txt) | [heavy.png](heavy.png) |
| 工具刻印·园艺锄 | 原版素材直接复用，不使用生成 prompt | [edge_farm_hoe.native.png](edge_farm_hoe.native.png) |

原版园艺锄来源为 `anim/quagmire_hoe.zip` 中 `hoe01` 第 0 帧，直接复制已提取的 `assets_src/projectiles/tools_v1/farm_hoe-native.png`，文件哈希一致。无重绘、换色、旋转或拉伸。

[原版园艺锄与 v3 边框的适配预览](edge_farm_hoe.native_card_preview.png)使用当前样稿的内缘安全区域，等比放到该区域可容纳的最大尺寸；[独立定位层](edge_farm_hoe.native_layout.png)与 `native_hoe_layout.json` 保留布局信息。可运行 `build_native_hoe_preview.py` 复现。此处边框仍为 v3 候选，不表示最终边框已定稿。

旧 [园艺锄生成主图](edge_farm_hoe.png)及其 [prompt](edge_farm_hoe.prompt.txt)只作为历史记录，`generation_manifest.json` 和原始生成校验也保持对应旧输出，不作为当前素材选择表。

`generation_manifest.json` 记录内置生成器输出来源与对应关系；`validation.json` 记录尺寸、透明通道、主体边界和文件哈希。四张原始输出背景存在 alpha=1/255 的极淡残留像素，已原样保留；后续自动居中与裁切应使用有效透明阈值，不能直接将所有非零 alpha 的包围盒作为主体范围。当前检查使用 alpha≥8 的可见边界，所有主体均完整位于画布内。

下一阶段为与边框组合、64/32 像素可读性及最终布局检查。当前文件是高清主图候选，不代表已完成小尺寸资源或实机验收。

