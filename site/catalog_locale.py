"""English templates for catalog-only acquisition and numeric fields.

Card names/effects come directly from the mod's English locale.
"""
import json
import re
from pathlib import Path

PHRASES = {
    "（爽快/平衡；掉落限定不可制作）": " (Fun/Balanced; unavailable in Loot Only)",
    "极稀有随机掉落 · 最大生命超过 200 的合资格生物，此次既无散卡也无携卡法杖时，从全卡池（道具招牌除外）等概率抽一张。默认掉率倍率下，爽快/平衡为 ": "Very rare random drop · Eligible creatures with over 200 maximum health can draw uniformly from all cards except Mini Sign when they drop neither a loose card nor a loaded wand. At the default drop-rate multiplier, the chance is ",
    "，平衡·掉落限定为 ": " in Fun/Balanced and ",
    "；实际概率再乘法术卡掉率倍率。": " in Balanced: Loot Only; the card drop-rate multiplier scales this chance.",
    "首次 Boss 额外奖励 · 胜利时在 12 单位内且尚未领取的玩家，每人额外掉一张：5% 碰撞触发修饰，95% 等概率抽六种基础弹的碰撞变体。不占普通掉卡名额。": "First-boss bonus · Each player within 12 units at victory who has not received this reward adds one extra card drop: 5% Collision Trigger Modifier, otherwise an equal choice among the six basic collision variants. Separate from the normal card limit.",
    "入门法杖的第一格自带一张。": "Included in the first slot of a Starter Wand.",
    "定向掉落（标准倍率） · ": "Signature drops (normal multiplier) · ",
    "材料关联掉落 · ": "Material-associated drops · ",
    "。可击败": ". Example creatures: ", "等生物尝试。": ".",
    "生物按材料掉落「": "May replace ", "」时，有机会改为本变体。": " when a creature drops that spell through its material pool.",
    "部分首领掉落的成品法杖有机会预装此卡，可带到奥术台拆下。": "May be installed in wands dropped by certain bosses. Remove it at an Arcane Workbench.",
    "极稀有随机掉落 · 最大生命超过 200 的合资格生物，此次既无散卡也无携卡法杖时，标准倍率下有 0.01% 机会从全卡池（道具招牌除外）等概率抽一张。": "Very rare random drop · Eligible creatures with over 200 maximum health have a 0.01% chance at normal settings to draw uniformly from all cards except Mini Sign, if they dropped neither a loose card nor a loaded wand.",
    "奥术台": "Arcane Workbench", "武器刻印台": "Weapon Engraving Table", "刻写": " inscription",
    "命中治疗": "Healing on hit", "基础伤害": "Base damage", " 枚": " projectiles",
    "水柱伤害 85": "Water-spout damage 85", "水柱半径 2.75 单位": "Water-spout radius 2.75 units", "加湿半径 2 单位": "Wetness radius 2 units",
    "基础位面伤害": "Base planar damage", "单条弹跳链 最多命中 5 次": "Up to 5 hits per bouncing chain",
    "满尺寸伤害 27.2 物理 + 27.2 位面": "Full-size damage 27.2 physical + 27.2 planar", "成长时间 约 0.67 秒": "Growth time about 0.67 s",
    "整次施法冷却下限": "Minimum total cast cooldown", " 秒（含触发载荷）": " s (including payloads)",
    "生成位置 杖头或载体触发点": "Spawn point: wand tip or carrier trigger point", "寿命与环境效果 原版星体": "Native star lifetime and environmental effects", "基础移速 0，可用移动修饰启动": "Base speed 0; movement modifiers can start it moving",
    "水平初速": "Initial horizontal speed", "轨迹 斜向上抛出，落地结算": "Lobbed trajectory; resolves on landing",
    "环绕半径": "Orbit radius", "单盾耐久 50 点": "Shield durability 50", "持续时间": "Duration",
    "去程速度": "Outbound speed", "触发去程": "Outbound trigger travel", "落点游荡 5 秒": "Wanders at destination for 5 s",
    "弹速": "Speed", "寿命": "Lifetime", "基础直射距离": "Base straight-line range", "（默认无额外射程限制）": " (no extra travel limit by default)",
    "基准散射": "Base spread", "（以 6° 法杖计）": " (with a 6° wand)",
    "弹道延寿 +8%（不同类型合计最多 +24%）": "Trajectory lifetime +8% (different types total at most +24%)",
    "飞行寿命倍率": "Flight lifetime multiplier", "（同组相乘）": " (multiplies within a group)",
    "攻击距离": "Reach", "指定距离上限": "Maximum aim distance", "基础音高": "Base pitch", "近战": "Melee",
    " 单位/秒": " units/s", " 单位": " units", " 秒": " s", "、": ", ",
}
PHRASES.update(json.loads((Path(__file__).parent / 'native_names.en.json').read_text(encoding='utf8')))
PATTERN = re.compile('|'.join(re.escape(k) for k in sorted(PHRASES, key=len, reverse=True)))

def translate_tree(value):
    if isinstance(value, dict):
        return {k: translate_tree(v) for k, v in value.items()}
    if isinstance(value, list):
        return [translate_tree(v) for v in value]
    if isinstance(value, str):
        text = PATTERN.sub(lambda match: PHRASES[match[0]], value)
        assert not re.search(r'[\u4e00-\u9fff]', text), f'Missing catalog translation: {text}'
        return text
    return value
