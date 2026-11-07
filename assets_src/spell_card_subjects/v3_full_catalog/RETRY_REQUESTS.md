# 主图重试建议

后续进展：上述三张已按用户授权完成第二次尝试，原问题均已修正，见[第二次尝试与前后对比](../v4_retry_three/README.md)。以下保留首轮检查历史。

本批103张均只生成一次。以下重试提示词已保存，但没有执行重绘或清理原图。

## 建议重新尝试

这些项目存在可见内容、边缘或构图问题，建议后续交给用户指定的 high 推理强度模型。

| 法术卡 | 问题 | 原图与提示词 |
| --- | --- | --- |
| 击退（knockback） | 冲击尖角之间出现带颗粒的半透明青灰雾，边界不够干净，不符合仅用实心运动笔触的要求。 | [原图](modifiers/knockback.png) · [原始 prompt](modifiers/knockback.prompt.txt) · [完整重试 prompt](modifiers/knockback.retry.prompt.txt) |
| 双倍施法（repeat_2） | 双倍施法底端菱形贴近并触及画布下边缘：6 个 alpha≥8 像素落在边界，最大 alpha 108。主体需要完整安全留白。 | [原图](projectiles_controls/repeat_2.png) · [原始 prompt](projectiles_controls/repeat_2.prompt.txt) · [完整重试 prompt](projectiles_controls/repeat_2.retry.prompt.txt) |
| 选取中立生物（target_neutral） | 兔子长耳上方额外出现两条卷曲触角状笔画，影响原版兔子形象。 | [原图](music_targets/target_neutral.png) · [原始 prompt](music_targets/target_neutral.prompt.txt) · [完整重试 prompt](music_targets/target_neutral.retry.prompt.txt) |

## 可选改善

以下保持候选：部分预览彩边只在低 alpha 像素中，另有完整横画布可在接入时等比适配。它们不计入建议重绘数量；只有实际合成后仍不满意时才需要尝试。

- 照明（light）：[原图](music_targets/light.png) · [可选重试 prompt](music_targets/light.retry.prompt.txt)。详见[逐图检查](music_targets/light.result.json)。
- 护卫环（guard_ring）：[原图](fields/guard_ring.png) · [可选重试 prompt](fields/guard_ring.retry.prompt.txt)。详见[逐图检查](fields/guard_ring.result.json)。
- 前后阵（two_way）：[原图](projectiles_controls/two_way.png) · [可选重试 prompt](projectiles_controls/two_way.retry.prompt.txt)。详见[逐图检查](projectiles_controls/two_way.result.json)。
- 幻鹿诱饵（deer_decoy）：[原图](fields/deer_decoy.png) · [可选重试 prompt](fields/deer_decoy.retry.prompt.txt)。详见[逐图检查](fields/deer_decoy.result.json)。
- 萤虫伴飞（fireflies）：[原图](fields/fireflies.png) · [可选重试 prompt](fields/fireflies.retry.prompt.txt)。详见[逐图检查](fields/fireflies.result.json)。
- 局部雷云（storm_cloud）：[原图](fields/storm_cloud.png) · [可选重试 prompt](fields/storm_cloud.retry.prompt.txt)。详见[逐图检查](fields/storm_cloud.result.json)。
- 灼光环（searing_halo）：[原图](fields/searing_halo.png) · [可选重试 prompt](fields/searing_halo.retry.prompt.txt)。详见[逐图检查](fields/searing_halo.result.json)。
- 双弹电弧（twin_arc）：[原图](fields/twin_arc.png) · [可选重试 prompt](fields/twin_arc.retry.prompt.txt)。详见[逐图检查](fields/twin_arc.result.json)。
- 双侧余烬（side_embers）：[原图](fields/side_embers.png) · [可选重试 prompt](fields/side_embers.retry.prompt.txt)。详见[逐图检查](fields/side_embers.result.json)。

## 使用方式

重试文件包含完整的首次约束与定向修正，可直接交给下一次生成任务使用。若配有 reference 字段，参考图路径保存在该卡 result.json 中。建议将新结果另存为 attempt2，保留本轮 PNG 与记录，以便对比。
