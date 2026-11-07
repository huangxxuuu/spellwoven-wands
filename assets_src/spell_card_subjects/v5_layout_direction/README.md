# 主图方向与盾牌内侧修订

2026-11-07，按用户要求分别修改双倍施法与护卫环。本轮每张只调用一次内置 imagegen，原图、完整 prompt、来源与校验结果均保留；此前版本未覆盖。

- [双倍施法](repeat_2.png)：参照三倍施法改成从左到右，一个输入、两个输出，保留正向×2文字与紫色晶体。见 [prompt](repeat_2.prompt.txt)、[记录](repeat_2.result.json)。
- [护卫环](guard_ring.png)：前方两盾保持正面，后排三盾展示木撑与皮革握带的内侧，总数仍为五。见 [prompt](guard_ring.prompt.txt)、[记录](guard_ring.result.json)。
- [音乐评估](music_review.md)：陶笛与弦琴当前音组、完整定义音高、升号与A2标签的解释，以及尚未实施的调整建议。

两张图已通过视觉初检，RGBA、可见边界和原始文件哈希检查通过。已更新[卡牌总览](../../spell_cards_composed/v1/index.html)对应单卡、物品栏、地面版与使用双倍施法作顶牌的卡堆预览。

最新主图覆盖关系统一记录在 [selected_overrides.json](../selected_overrides.json)。只重建这两张卡可运行 `python tools/compose_spell_cards.py --cards repeat_2 guard_ring`。本次未修改游戏运行时资源、音高、音名或音源；修正了测试指南中一条仍描述旧半音行为的文字。
