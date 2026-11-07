# 三张主图第二次尝试

本次按用户授权，对击退、双倍施法、选取中立生物各重试一次，使用内置 imagegen 编辑首轮原图。没有第三次调用，没有后处理图片。首轮文件完整保留在 v3_full_catalog。

[打开前后对比](index.html) · [完整提示词集合](prompts.json) · [本次候选选图](selection.json)

| 主图 | prompt 调整与结果 | 文件 |
| --- | --- | --- |
| 击退 | 以清晰实心尖角替代冲击灰雾，灰雾已移除。 | [PNG](knockback.png) · [prompt](knockback.prompt.txt) |
| 双倍施法 | 统一四周至少12%留白，保留1输入、2输出与×2；实测最小可见留白200px，尖角完整。 | [PNG](repeat_2.png) · [prompt](repeat_2.prompt.txt) |
| 选取中立生物 | 明确删除额外卷曲笔画，只保留两只正常兔耳；已修正。 | [PNG](target_neutral.png) · [prompt](target_neutral.prompt.txt) |

三张均通过本次视觉初检，作为新的候选图；RGBA、透明通道和源文件 SHA-256 校验通过。部分预览中的高饱和红边只存在于极低 alpha 像素，alpha≥8时红色污染计数为0。击退与中立生物的留白未完全达到提示比例，但可见主体完整，后续卡框合成时按主体边界等比缩放即可，无需因此继续生图。

本次没有替换运行时资源，也没有覆盖 v3 的首轮审核档案。后续接入这三张时采用本目录 selection.json 中的候选。
