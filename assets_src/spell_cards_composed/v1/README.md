# 法术卡、载荷角标与卡堆组合 v1

2026-11-07。依据 docs/20 的三种轮廓、右下轻压角、浅暖灰纸底与 v5 卡堆缺角规则，组合现有主图。当前已接入正式运行时资源，详见下方版本记录；未启动完整游戏测试。

[打开全部卡牌与卡堆总览](index.html) · [单卡检查图](cards_review.png) · [64/32px 与数量检查](small_size_review.png) · [三种角标](badges_review.png) · [十二种卡堆](pile_matrix.png)

## 已完成

- 186张公开卡：125基础法术、49法术修饰、12施法控制；逐卡映射见 [card_visuals.json](card_visuals.json)。独立触发修饰与输出复制归施法控制，不按旧内部 kind 误用六角框。
- 1024px收藏册合成、独立简化边框的128/64/32px物品栏合成、256px地面单卡各186张。主图仅整理透明边距、等比缩放和定位；原始图片不修改。原版主图不重绘。新增四张调音修饰来自 v7_pitch_modifiers；原 v3 的182张历史清单保持不变，通过扩展清单接入。
- 61张原版直用、此前6张单绘、103张新绘与12基础弹变体按已有选图关联；击退、中立选择采用 v4_retry_three；双倍施法的左到右布局、护卫环后三盾内侧采用 v5_layout_direction。最新覆盖关系见 `assets_src/spell_card_subjects/selected_overrides.json`；园艺锄采用此前选定的原版动画主体。
- 纸底、主图、边框、角标按顺序组合。纸底不透明，外部透明；框内适配按实际内缘与主体轮廓校验。物品栏使用单独简化边框，并单独核对内缘安全区。
- 碰撞6张、定时7张、被击破1张，共14张角标卡。独立碰撞/定时控制卡、普通晶雷、休眠晶体、火药、命中爆炸等不加同义角标。
- 收藏册角标按64px折算位于 `(43,44)–(61,62)`，约72%面积留在卡内。0.25.11 的物品栏版扩大边框至 `(2,1)–(62,63)`，角标调整为 `(45,45)–(63,63)`，保留完整图案及轻压右下角的布局。浅色不透明底遮住下面的框线。普通、碰撞、定时三张同系列主图尺寸与位置严格一致，普通版不放空底座。
- 地面顶牌完整卡面统一接受透视；底牌按RR/HR/RH/HH四种真实轮廓叠放，与R/H/N顶牌形成12组合，每组合输出薄/中/厚3档，共36张512px预览。H缺角没有虚构矩形侧墙，接地高度保持稳定。

## 三种角标的最新方案

用户要求直接参考并尽可能复用已有主图。本轮已用真实主图替代首轮程序线条符号：

| 角标 | 直接复用 | 使用对象 |
| --- | --- | --- |
| 碰撞载荷 | `imprint_hit` 碰撞触发修饰主图 | 六种基础弹的碰撞变体 |
| 定时载荷 | `imprint_timer` 定时触发修饰主图 | 六种基础弹的定时变体、延迟符印 |
| 被击破载荷 | `payload_egg` 空心载荷卵破壳主图 | 空心载荷卵 |

只等比缩放到角标内，保留整张主图的配色和轮廓，没有新增生图调用。[角标来源与哈希](badges/sources.json)记录原图；PNG用于合成，SVG保留可编辑底座并引用对应裁去透明外边距的主体。64px下可依靠撞击、沙漏、破壳三种大形区分；32px下细节会合并，需要实机进一步确认。

## 边框与可复现构建

基础框复用 v3 独立高清框。另两类由内置 imagegen 参照 v3设计板与基础框各生成一次，完整 prompt、原始图和来源记录保存于 `frames/`。派生层分别保存于 `layers/`；源图均保留。边框母版归一到统一卡面包围盒，主图不做非等比变形。

```powershell
python tools/compose_spell_cards.py
python tools/compose_spell_cards.py --only-badges
python tools/compose_spell_cards.py --cards repeat_2 guard_ring
python tools/check_composed_spell_cards.py
```

在仓库根目录运行。前两条只构建本目录，不生成新图，也不修改 mod 运行时资源。`--only-badges` 沿用已构建普通卡，只重建角标卡与组合预览。检查结果保存为 [validation.json](validation.json)，完整布局、尺寸和来源见 [manifest.json](manifest.json)。

## 接入边界

0.25.12 修复：原生 inventoryitem 的图集和图名经 `net_hash` 同步，UI 尺寸适配同时处理数字哈希与字符串路径，物品栏/换图恢复64单位，法杖编辑框可继续覆盖自身尺寸。控制卡凹口使用边缘平行内缩生成各色边框，补齐凹口的两条竖边。专项记录见 [修复检查](../../../test_reports/card_icon_02512_validation.json)。

0.25.11：物品栏正式纹理使用现有高清素材导出的 128×128 PNG，合并为 2048×2048 图集。显示逻辑仍为64单位，自定义UI可继续指定尺寸；不改变原生数量、耐久或鼠标拖拽的缩放。物品栏边框减少外部留白并重新适配主图；收藏册与地面资源不变。没有生图调用。[对比图](../../../test_reports/inventory_128_comparison.png) · [专项检查](../../../test_reports/inventory_128_validation.json)。只更新此用途可顺序运行 `tools/compose_spell_cards.py --inventory-only` 和 `tools/build_card_resources.py --inventory-only`。

2026-11-07 已通过 `tools/build_card_resources.py` 接入 mod 0.25.10：182 张正式卡及 34 个兼容 ID 的物品栏图集、地面单卡与卡堆资源已编译；第二、第三张卡的真实类别同步和容器顺序选择已接入。三档厚度只用近表层轮廓概括厚度，不宣称还原25张的完整类型顺序。两张牌仅显示一张底牌；三张及以上显示两张底牌；底层施法控制卡按矩形处理。类别统计及收藏册界面尚未实现；256px 高清卡面图集已经随 mod 保存供后续界面使用。

更新组合稿后，运行 `.\.venv\Scripts\python.exe tools/build_card_resources.py` 编译正式资源，再运行 `.\.venv\Scripts\python.exe tools/check_card_resources.py` 检查。仅运行组合脚本不会修改游戏资源。当前编译清单与结果见 [构建记录](../../../test_reports/card_resources.json)、[检查记录](../../../test_reports/card_resources_validation.json)、[编译后卡堆效果](../../../test_reports/card_resources_compiled.png)。

原生堆叠数字未烘焙到导出PNG；仅在 `small_size_review.png` 中用12作位置检查。候选边框与角标仍需在实际UI及地面显示中确认。
