# 灯芯、燃料与火焰：R4 参考及修改要求

本轮为游戏内建筑效果图修改，使用内置 image_gen。尚未替换动画或运行资源。

## 查阅来源

- [Ian Russell：The Chemical History of a Candle](https://www.interactives.co.uk/candle)：作者的蜡烛近照及说明；灯芯处于下部火焰的内部暗区，发光部分有包围结构。燃料位于灯芯周围。
- [Kreuzschnabel：Candle wick and flame closeup](https://commons.wikimedia.org/wiki/File:Candle_wick_and_flame_closeup.jpg)：蜂蜡蜡烛燃烧近照，观察炭化芯和局部灼亮芯头。
- [National Candle Association：Candle Science](https://candles.org/candle-science/)：灯芯吸取熔蜡及火焰不同区域的说明。

## 用于本游戏的绘制选择

奥术粉尘是虚构燃料；借用真实蜡烛的包围和遮挡关系，不将粉尘改为液体蜡。粉尘围住芯根，前侧粉尘盖住小金属固定环。短灯芯从中央露出，进入火焰下部内部；局部前层火光遮盖芯的轮廓。灯芯实体本身保持不透明；通过暗芯、局部灼亮和前层火光表达位于焰内。

本轮保持左侧空盘状态，修改右侧点燃效果。采用明确色块与局部覆盖，不将整团火焰统一降透明度。后续动画可以将后焰、内部灯芯、前焰分别组织，或把燃烧灯芯画入火焰帧；实现选择待设计确认后处理。

已实际读取共同画风规范、基础提示词和游戏内建筑规范。实际提交提示词见 `prompt.txt`，原始编辑目标为 `../wick_r3/wick_comparison.png`。
