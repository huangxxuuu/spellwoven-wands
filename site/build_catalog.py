"""Rebuild the local field guide with the project's Lua 5.1 environment."""
import argparse
import json
import re
import shutil
from collections import defaultdict
from html import escape
from html.parser import HTMLParser
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
SITE = Path(__file__).resolve().parent
STATIONS = {"nw_workbench": "奥术台", "nw_engraver": "武器刻印台"}

# Native items and the creatures named in drop hints. Weapon names come from
# the mod's own catalog. Keeping the remaining labels here makes regeneration
# independent of the path or availability of a local DST installation.
LABELS = {
    "axe": "斧头", "batwing": "洞穴蝙蝠翅膀", "beefalowool": "牛毛", "bird_egg": "鸟蛋",
    "bluegem": "蓝宝石", "boomerang": "回旋镖", "butterflywings": "蝴蝶翅膀", "charcoal": "木炭",
    "cutreeds": "采下的芦苇", "feather_canary": "黄色羽毛", "feather_crow": "黑色羽毛",
    "feather_robin": "红色羽毛", "feather_robin_winter": "蓝色羽毛", "flint": "燧石",
    "gears": "齿轮", "glasscutter": "玻璃刀", "goldnugget": "金块", "goose_feather": "麋鹿鹅羽毛",
    "greengem": "绿宝石", "gunpowder": "火药", "houndstooth": "犬牙", "ice": "冰",
    "lightbulb": "荧光果", "lightninggoathorn": "伏特羊角", "livinglog": "活木头", "marble": "大理石",
    "moonrocknugget": "月岩", "mosquitosack": "蚊子血囊", "nightmarefuel": "噩梦燃料", "nitre": "硝石",
    "orangegem": "橙宝石", "papyrus": "莎草纸", "purplegem": "紫宝石", "redgem": "红宝石",
    "rocks": "石头", "rope": "绳子", "silk": "蜘蛛丝", "slurtle_shellpieces": "外壳碎片",
    "slurtleslime": "蛞蝓龟黏液", "spear": "长矛", "spore_small": "绿色孢子", "stinger": "针刺",
    "tentaclespots": "触手皮", "twigs": "树枝", "walrus_tusk": "海象牙", "yellowgem": "黄宝石",
    "robin": "红雀", "moose": "麋鹿鹅", "hound": "猎犬", "warg": "座狼", "killerbee": "杀人蜂",
    "beequeen": "蜂王", "lightflier": "球状光虫", "lightcrab": "发光蟹", "moonbutterfly": "月蛾",
    "mutatedhound": "恐怖猎犬", "spider_warrior": "蜘蛛战士", "spiderqueen": "蜘蛛女王",
    "alterguardian_phase3": "天体英雄", "rocky": "石虾", "lightninggoat": "伏特羊",
    "deer": "无眼鹿", "klaus": "克劳斯", "slurper": "啜食者", "crabking": "帝王蟹",
    "firehound": "火焰猎犬", "dragonfly": "龙蝇", "bishop": "发条主教", "bishop_nightmare": "损坏的发条主教",
    "minotaur": "远古守护者", "pigman": "猪人", "mutatedbearger": "装甲熊獾", "worm": "洞穴蠕虫",
    "stalker_atrium": "远古织影者", "daywalker": "梦魇疯猪", "bearger": "熊獾", "rook_nightmare": "损坏的发条战车",
    "toadstool": "毒菌蟾蜍", "toadstool_dark": "悲惨的毒菌蟾蜍", "alterguardian_phase4_lunarrift": "天体后裔",
    "shrouden": "暗影憎恶", "spider": "蜘蛛", "bee": "蜜蜂", "bat": "洞穴蝙蝠", "tentacle": "触手",
    "walrus": "海象", "deerclops": "独眼巨鹿", "malbatross": "邪天翁", "twins": "双子魔眼",
}


def array(table):
    """Use Lua's contiguous numeric keys, skipping any attached metadata."""
    return [table[i] for i in range(1, len(table) + 1)]


def icon_indices():
    atlas = ElementTree.parse(ROOT / "mod/images/inventoryimages/nw_icons.xml")
    result = {}
    for tile in atlas.findall(".//Element"):
        col = round(float(tile.get("u1")) * 16)
        row = round((1 - float(tile.get("v2"))) * 16)
        result[tile.get("name")] = row * 16 + col
    return result


def build(language="zh"):
    from lupa.lua51 import LuaRuntime

    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
    require = vm.globals().require
    require("nw/locale").configure(language, language)
    defs = require("nw/definitions")
    info = require("nw/spell_info")
    rules = require("nw/acquisition")
    rarity = require("nw/card_rarity")
    sources = require("nw/sources")
    notes = require("nw/arsenal").notes
    natural = require("nw/natural_loot")
    icons = icon_indices()
    labels = LABELS | {row[1]: row[2] for row in array(require("nw/weapon_catalog"))}
    for c in array(require("nw/arsenal").cards):
        if c.source_weapon and c.source_weapon not in labels:
            labels[c.source_weapon] = c.name
    labels.update({key: row[1] for key, row in rules.materials.items()})

    recipes = defaultdict(list)
    stations = {}
    recipe_order = {}
    for index, row in enumerate(array(rules.recipes)):
        if row.card:
            recipe_order.setdefault(row.card, index)
            costs = " + ".join(f"{labels[item[1]]} ×{item[2]}" for item in array(row.ingredients))
            stations[row.card] = STATIONS[row.station]
            recipes[row.card].append(f"{STATIONS[row.station]}刻写 · {costs}")

    direct = defaultdict(list)
    for creature, entries in sorted(sources.signature.items()):
        for entry in array(entries):
            direct[entry.id].append(f"{labels[creature]} {100 * entry.rate:.3g}%")

    # Use the same material -> card lookup as a victory. Only claim a material
    # route when the built-in natural-loot catalog includes a qualifying source.
    material_names = {mat for materials in natural.values() for mat in materials.keys()} | {"nw_beast_core"}
    materials_by_card = defaultdict(list)
    for material, ids in sorted(rules.by_material.items()):
        if material in material_names:
            for card_id in array(ids):
                materials_by_card[card_id].append(labels[material])

    examples = defaultdict(list)
    on_wands = set()
    for creature, materials in sorted(natural.items()):
        rule = sources.by_prefab[creature]
        group = rule.group if rule else None
        pool = array(sources.material_pool(materials, group))
        if creature in labels:
            for card_id in pool:
                examples[card_id].append(labels[creature])
        if group:
            on_wands.update(pool)
            on_wands.update(array(rule.cards))

    public_ids = array(rarity.pool)
    assert len(public_ids) == len(set(public_ids))
    guide = []
    # Preserve the familiar spell order without exposing compatibility-only IDs.
    for card_id in array(require("nw/cards").order):
        tier = rarity.tiers[card_id]
        if tier is None:
            continue
        d = defs.spells[card_id]
        group, title = rules.card_section(card_id)
        melee = d.kind == "melee"

        routes = recipes[card_id].copy()
        first_boss=require("nw/first_boss_reward")
        if card_id=="imprint_hit" or card_id in array(first_boss.variants):
            routes.append("首次 Boss 额外奖励 · 胜利时在 12 单位内且尚未领取的玩家，每人额外掉一张：5% 碰撞触发修饰，95% 等概率抽六种基础弹的碰撞变体。不占普通掉卡名额。")
        if card_id == "spark":
            routes.append("入门法杖的第一格自带一张。")
        if direct[card_id]:
            routes.append("定向掉落（标准倍率） · " + "、".join(direct[card_id]))
        if materials_by_card[card_id]:
            hint = "材料关联掉落 · " + "、".join(materials_by_card[card_id])
            if examples[card_id]:
                hint += "。可击败" + "、".join(examples[card_id][:3]) + "等生物尝试。"
            routes.append(hint)
        if d.base:
            routes.append(f"生物按材料掉落「{info.names[d.base]}」时，有机会改为本变体。")
        if card_id in on_wands or d.base in on_wands or card_id in ("imprint_hit", "imprint_timer", "heal_ally"):
            routes.append("部分首领掉落的成品法杖有机会预装此卡，可带到奥术台拆下。")
        if card_id != "edge_propsign":
            routes.append("极稀有随机掉落 · 最大生命超过 200 的合资格生物，此次既无散卡也无携卡法杖时，标准倍率下有 0.01% 机会从全卡池（道具招牌除外）等概率抽一张。")

        stats = []
        if d.heal and d.kind == "projectile":
            stats.append(f"命中治疗 {d.heal:g}")
        elif d.damage is not None:
            stats.append(f"基础伤害 {d.damage:g}" + (f" × {d.count} 枚" if d.count and d.count > 1 else ""))
        elif d.explosion_damage is not None:
            stats.append(f"基础伤害 {d.explosion_damage:g}")
        elif card_id == "gunpowder":
            stats.append("基础伤害 200")
        if d.engraving == "trident":
            stats.extend(["水柱伤害 85", "水柱半径 2.75 单位", "加湿半径 2 单位"])
        elif d.engraving == "staff_lunarplant":
            stats.extend(["基础位面伤害 10", "单条弹跳链 最多命中 5 次"])
        elif d.engraving == "voidcloth_boomerang":
            stats.extend(["满尺寸伤害 27.2 物理 + 27.2 位面", "成长时间 约 0.67 秒"])
        if d.planar:
            stats.append(f"基础位面伤害 {d.planar:g}")
        if d.cooldown:
            stats.append(f"整次施法冷却下限 {d.cooldown:g} 秒（含触发载荷）")
        if d.native_field:
            stats.extend(["生成位置 杖头或载体触发点", "寿命与环境效果 原版星体", "基础移速 0，可用移动修饰启动"])
        if d.ballistic:
            stats.extend([f"水平初速 {d.speed:g} 单位/秒", "轨迹 斜向上抛出，落地结算"])
        elif d.engraving == "shieldofterror":
            stats.extend(["环绕半径 2 单位", "单盾耐久 50 点", f"持续时间 {d.lifetime:g} 秒"])
        elif d.engraving == "staff_tornado":
            stats.extend([f"去程速度 {d.speed:g} 单位/秒", f"触发去程 {d.lifetime:g} 秒", "落点游荡 5 秒"])
        elif d.speed is not None:
            stats.extend([f"弹速 {d.speed:g} 单位/秒", f"寿命 {d.lifetime:g} 秒",
                          f"基础直射距离 {d.speed * d.lifetime:g} 单位（默认无额外射程限制）"])
        if d.halfangle is not None:
            stats.append(f"基准散射 ±{d.halfangle:g}°（以 6° 法杖计）")
        if defs.trajectory[card_id]:
            stats.append("弹道延寿 +8%（不同类型合计最多 +24%）")
        if d.lifetime_mult is not None:
            stats.append(f"飞行寿命倍率 ×{d.lifetime_mult:g}（同组相乘）")
        if d.reach:
            stats.append(f"攻击距离 {d.reach:g} 单位")
        if d.aim_range:
            stats.append(f"指定距离上限 {d.aim_range:g} 单位")
        if notes[card_id]:
            pitch = int(notes[card_id].pitch)
            names = ("C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B")
            stats.append(f"基础音高 {names[pitch % 12]}{3 + pitch // 12}")
        guide.append(dict(id=card_id, name=info.names[card_id], category="近战" if melee else title,
                          subgroup=title if melee else None, groupOrder=group, rarity=rarity.names[tier],
                          effect=info.brief(card_id), detailedEffect=info.effects[card_id], mana=d.mana, delay=round(d.delay, 5),
                          recharge=round(d.recharge, 5), stats=stats, sources=routes,
                          station=stations.get(card_id), iconIndex=icons[info.icon(card_id)]))

    assert {card["id"] for card in guide} == set(public_ids)
    assert all(card["name"] and card["effect"] and card["sources"] for card in guide)
    guide.sort(key=lambda card: (card["groupOrder"], recipe_order.get(card["id"], float("inf"))))
    result = {"cards": guide}
    if language == "en":
        from catalog_locale import translate_tree
        result = translate_tree(result)
    return result


class ReleaseHistory(HTMLParser):
    """The first release on the updates page is the latest confirmed publication."""
    latest = None

    def handle_starttag(self, tag, attrs):
        if tag == "section" and self.latest is None:
            self.latest = dict(attrs).get("data-release-version")


def sync_labels(directory, label):
    for page in directory.glob("*.html"):
        html = page.read_text(encoding="utf8")
        updated = re.sub(r"(<span data-mod-version>)[^<]*(</span>)",
                         lambda match: match[1] + escape(label) + match[2], html)
        if updated != html:
            page.write_text(updated, encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--local-labels", action="store_true", help="Refresh the local preview version only")
    mode.add_argument("--release", action="store_true", help="Export the confirmed release to site/public")
    mode.add_argument("--pages", action="store_true", help="Build the current version for GitHub Pages in site/public")
    args = parser.parse_args()

    directory = SITE / "dist"
    modinfo = (ROOT / "mod/modinfo.lua").read_text(encoding="utf8")
    version = re.search(r'^version\s*=\s*"([^"]+)"', modinfo, re.MULTILINE)
    if not version:
        parser.error("Missing version in mod/modinfo.lua")
    local_version = version[1]
    label = f"本地版 v{local_version}"
    if args.pages:
        label = f"v{local_version}"
    if args.local_labels:
        sync_labels(directory, label)
        from build_pages import build_pages
        build_pages(directory)
        raise SystemExit(0)
    if args.release:
        history = ReleaseHistory()
        history.feed((directory / "updates.html").read_text(encoding="utf8"))
        if not history.latest:
            parser.error("No confirmed release in updates.html")
        if history.latest != local_version:
            parser.error("Build the public guide from the matching released mod version")
        label = f"正式版 v{history.latest}"

    data = build()
    if args.release or args.pages:
        directory = Path(shutil.copytree(directory, SITE / "public", dirs_exist_ok=True))
    from PIL import Image
    with Image.open(ROOT / "assets_src/art_v1/runtime/nw_icons.png") as atlas:
        atlas.save(directory / "assets/spells.webp", lossless=True, exact=True)
    dest = directory / "catalog.json"
    dest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    (directory / "catalog.en.json").write_text(json.dumps(build("en"), ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    homepage = directory / "index.html"
    html = homepage.read_text(encoding="utf8")
    html = re.sub(r"<b>\d+</b><span>张可玩法术卡</span>",
                  f"<b>{len(data['cards'])}</b><span>张可玩法术卡</span>", html)
    homepage.write_text(html, encoding="utf8")
    sync_labels(directory, label)
    from build_pages import build_pages
    build_pages(directory)
    if args.pages:
        (directory / ".nojekyll").touch()
    print(f"Exported {len(data['cards'])} cards to {dest}")
