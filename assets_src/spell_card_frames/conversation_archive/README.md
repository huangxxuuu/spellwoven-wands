# 早期法术卡交互预览归档

归档日期：2026-11-07。HTML 与 PNG 从应用工作目录原样复制，用户地面牌堆参照从其附件路径复制。来源、大小与 SHA256 见 [archive_manifest.json](archive_manifest.json)。这些文件可随项目保留，无需依赖原对话缓存。

| 内容 | 预览 | 截图 | 采用情况 |
| --- | --- | --- | --- |
| 三类边框 | [HTML](three-spell-frames.html) | [PNG](three-spell-frames-preview.png) | 采用「保留绘图空间」；具体轮廓按主规范 |
| 纸底比较 | [HTML](spell-card-backgrounds.html) | [上下渐变](spell-card-backgrounds-linear.png) | 采用极轻上下渐变；纯色、径向渐变截图仅作对照 |
| 角标位置 | [HTML](spell-card-badge-position.html) | [压右下角](spell-card-badge-overlap.png) | 采用右下轻压边框；框内方案仅作对照 |
| 卡面构成 | [HTML](spell-card-structure.html) | [PNG](spell-card-preview.png) | 早期职责与空间示意，当前材质看 v3 |
| 旧卡堆探索 | [HTML](spell-pile-appearance.html) | [PNG](spell-pile-appearance-default.png) | 历史探索，不作为平放姿态和六角夹层的最终依据；以 v5 为准 |
| 用户地面参照 | — | [PNG](user-ground-pile-reference.png) | 用户要求平躺地面、由下向上叠高的参照 |

最后收到的界面状态：底色预览为 64 像素、武器主图；角标预览为 64 像素；卡面结构为 64 像素且未启用灰度；边框比较为 64 像素且未启用纯剪影。这些是查看状态，不代表正式输出只制作 64 像素，也不代表其他主图无需验证。

最后收到的三个选择分别是「轻微上下渐变（推荐）」「压在右下框角（推荐）」「保留绘图空间（推荐）」。这些选择已写入[主规范](../../../docs/20_法术卡分类与视觉设计规范.md)。HTML 保留原始交互源码，应用的桥接能力未作浏览器移植；截图可直接查看。其余 `preview`、`small` 和候选截图保留作比较，不把早期图例的符号和所有临时参数自动升级为定稿。
