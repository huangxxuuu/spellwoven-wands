# 四张调音修饰卡主图

2026-11-07。用户确认将音高修饰与加速、减速分离；本批制作四张独立透明主图。使用内置 imagegen，每张仅生成一次，完整 prompt、生成源路径与结果分别保存。

| 主图 | 音高偏移 | 视觉设计 | Prompt |
| --- | --- | --- | --- |
| [升八度](pitch_octave_up.png) | +12 半音 | 金色音符、青绿长上箭头、+12 | [完整 prompt](pitch_octave_up.prompt.txt) |
| [降八度](pitch_octave_down.png) | −12 半音 | 金色音符、紫色长下箭头、−12 | [完整 prompt](pitch_octave_down.prompt.txt) |
| [升半音](pitch_semitone_up.png) | +1 半音 | 金色音符、青绿短上箭头、+1 | [完整 prompt](pitch_semitone_up.prompt.txt) |
| [降半音](pitch_semitone_down.png) | −1 半音 | 金色音符、紫色短下箭头、−1 | [完整 prompt](pitch_semitone_down.prompt.txt) |

主图沿用现有卡牌的手绘深棕墨线、清楚大形与少量明暗面。四张中的音符始终正立，箭头负责表达升降；八度与半音同时通过箭头长度和数值区分。无卡框、机制角标或环境背景。原始透明 PNG 不作程序性重绘。

查看 [主图和六角修饰卡预览](index.html)、[四张对照图](review.png)。预览沿用已选修饰卡边框，等比缩放并检查可见主体落在内框中；另导出 128、64、32 像素版本。运行 `python tools/build_pitch_modifier_preview.py` 可重新组合。

0.25.13 已将四张主图接入正式法术卡资源，总卡数由182增至186；同组调音、低成本配方及文本已经实现。设计 ID 与音高偏移保存在 [cards.json](cards.json)。历史生成记录不被覆盖，新增卡牌已加入[统一卡牌总览](../../spell_cards_composed/v1/index.html)。

同轮代码变更：删除加速、减速附带的 ±12 半音转调；保留加速、减速对移动速度和寿命的原有影响，更新活动说明及已有断言。只做 Lua 语法检查，不运行完整游戏测试。音源与基础音符定义暂不调整。
