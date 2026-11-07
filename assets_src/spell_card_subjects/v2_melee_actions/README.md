# 三种近战动作主图 v2

用户明确指定旋斧攻击 `whirl`、长矛戳击 `thrust`、玻璃刀砍 `slash` 单独绘制主图，作为原版武器与道具直接复用规则的三个例外。

先保存完整 prompt，再使用内置 image_gen 分别生成。`references/` 是从安装游戏原版动画提取的武器身份参考，来源见 `references/sources.json`；新图允许重绘武器与动作轨迹。

- 旋斧攻击：原版木柄灰刃斧头与近圆扫转轨迹。
- 长矛戳击：原版绑绳石尖长矛与沿矛轴的直线突刺轨迹。
- 玻璃刀砍：原版青绿色锯齿长刃与开放的挥砍弧线，避免旧稿的弯月刀形状。

统一为单个完整武器主体、真实透明背景、无文字/卡框/纸底/角标。只添加必要的动作轨迹，仍需后续边框组合与小尺寸检验。

当前阶段：三张主图已生成并完成背景清理，均为 1254×1254 RGBA PNG。已视觉检查武器身份和动作构图，并检查透明通道、主体完整入画与原文件复制一致性。它们仍是主图候选，尚未替换运行时资源。

| 法术 | 主图 | 原始提示词 | 背景清理提示词 |
| --- | --- | --- | --- |
| 旋斧攻击 | [whirl.png](whirl.png) | [whirl.prompt.txt](whirl.prompt.txt) | [whirl.cleanup.prompt.txt](whirl.cleanup.prompt.txt) |
| 长矛戳击 | [thrust.png](thrust.png) | [thrust.prompt.txt](thrust.prompt.txt) | [thrust.cleanup.prompt.txt](thrust.cleanup.prompt.txt) |
| 玻璃刀砍 | [slash.png](slash.png) | [slash.prompt.txt](slash.prompt.txt) | [slash.cleanup.prompt.txt](slash.cleanup.prompt.txt) |

第一轮 `.attempt1.png` 保留追溯，其中玻璃刀曾有明显背景灰雾，不能作为选中版本。背景清理也使用内置 image_gen，保留武器与动作构图。`generation_manifest.json` 记录两次生成的来源与提示词，`validation.json` 记录最终文件尺寸、alpha≥8 的可见主体范围及哈希。生成原图可能含极淡 alpha 残留，后续布局不要直接以所有非零 alpha 像素确定主体范围。

