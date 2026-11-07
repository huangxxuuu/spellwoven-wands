# 乐器主图音名符号修订

2026-11-07，使用内置 imagegen 局部编辑，每张仅调用一次；未重试，保留原始生成文件和此前版本。

- [陶笛 A5 主图](ocarina_a2.png)：原 A2 改为 A5。完整 [prompt](ocarina_a2.prompt.txt)、[生成与校验记录](ocarina_a2.result.json)。
- [弦琴 C 主图](kantele_dsharp.png)：原 D# 改为 C。完整 [prompt](kantele_dsharp.prompt.txt)、[生成与校验记录](kantele_dsharp.result.json)。

编辑要求仅替换音名文字，保留乐器、装饰音符、配色与构图。其余音符主图未重新生成。两张图的透明通道、保存文件与生成源的哈希、符号及组合效果已检查；未发现需要再次生成的可见杂色。

基础音组见 [base_notes.json](base_notes.json)：陶笛 A B C D E F G# A5，弦琴 A C D E G。原陶笛 G 保留，不纳入这组基础音预览。

已更新两张卡的主图选择、组合卡牌、物品栏和地面展示图，以及预览用名称。查看 [13 张基础音对照](../../spell_cards_composed/v1/music_base_review.html)、[对照图片](../../spell_cards_composed/v1/music_base_review.png)、[完整卡牌总览](../../spell_cards_composed/v1/index.html)。选择映射见 [selected_overrides.json](../selected_overrides.json)，展示名称见 [selected_labels.json](../selected_labels.json)。

本次仅改美术符号，未修改游戏运行时资源、音名定义或实际音高。为保持资源引用稳定，文件 ID 仍为 ocarina_a2、kantele_dsharp；弦琴 C 的游戏音高仍为旧 D#4，待声音调整时同步。陶笛旧 A2 定义本身已经对应 A5。

验证：组合脚本语法检查通过，两张卡共 10 个导出文件尺寸及源文件哈希检查通过，组合时的边框容纳检查通过。未运行完整游戏测试。

重建命令：`python tools/compose_spell_cards.py --cards ocarina_a2 kantele_dsharp`
