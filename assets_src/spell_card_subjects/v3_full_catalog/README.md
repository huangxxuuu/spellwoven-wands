# 全量法术卡主图 v3

后续进展：三张建议重试的主图已完成第二次尝试，见[最新结果与对比](../v4_retry_three/README.md)。本目录继续保留首轮原图与检查记录。

日期：2026-11-07。已完成本批 **103张新主图**，每张只生成一次，完整 prompt 与生成器原始 PNG 均在本地保存。没有自动重试、修图或清理 PNG。

- [打开本地总览](index.html)：182张公开法术卡，可按名称、组别和审核状态筛选；支持浅灰/白/深灰底和64px查看。
- [建议重试清单](RETRY_REQUESTS.md)：3张建议重新尝试，另有9张可选改善提示词；本轮均未执行。
- [全量索引](catalog.json)：逐卡选图、prompt、来源、审核意见和校验信息。
- [原始范围](roster.json) / [保存校验](validation.json) / [统一提示词约束](common_prompt.txt)。

## 覆盖范围

公开卡共182张：61张原版武器/道具直用；6张已完成主图继续使用（火焰弹、冰霜弹、重能量球、旋斧攻击、长矛戳击、玻璃刀砍）；12张碰撞/定时变体共享六种基础弹主图；本批补齐其余103张。园艺锄沿用此前选定的原版动画主体。

| 新绘分组 | 数量 | 目录 |
| --- | ---: | --- |
| 投射物与施法控制 | 27 | [projectiles_controls](projectiles_controls) |
| 场地、召唤与光环 | 22 | [fields](fields) |
| 通用法术修饰 | 28 | [modifiers](modifiers) |
| 音乐、目标与辅助 | 26 | [music_targets](music_targets) |

本批结果为 **100张候选、3张建议重试、0张生成失败**。候选表示初步视觉检查通过，仍需在正式卡框下确认缩放与小尺寸识别。

## 文件约定

每张卡保存 `id.prompt.txt`（完整首次提示词）、`id.png`（未经修改的工具输出）、`id.attempt.json`（调用前记录）、`id.result.json`（完成结果与审核）。`attempt.json` 的 started 是历史开始记录，最终状态以 result.json / catalog.json 为准。需要时另附 `id.retry.prompt.txt`，仅供后续尝试。

103张均核验透明 RGBA、文件可读取、prompt完整、每张尝试次数为1，并逐一核对 PNG 与生成器源文件的 SHA-256 一致。接近透明的 RGB 彩色残留与真正可见污染分别记录，没有因预览彩边自动重绘。

当前交付是主图素材与浏览索引；尚未替换游戏运行时卡牌资源。入框时以主体边界做等比缩放，完整放在卡框内部并尽量大。共享变体的碰撞/定时角标在卡牌合成层添加，不烘焙进主图。

## 更新索引

```powershell
python tools/finalize_spell_subject_catalog.py
python tools/build_spell_subject_gallery.py
```

以上命令在仓库根目录执行，只核验并生成索引，不调用生图器或修改图片。
