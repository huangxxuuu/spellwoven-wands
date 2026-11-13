"""Rebuild the local field guide with the project's Lua 5.1 environment."""
import argparse
import json
import re
import shutil
from collections import defaultdict
from html import escape
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlencode, urlsplit
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
SITE = Path(__file__).resolve().parent
STATIONS = {"nw_workbench": "奥术台", "nw_engraver": "武器刻印台"}
MODES = ("fun", "balanced", "balanced_loot")
MATERIAL_GUIDES = {"nw_blank": "index.html#blank-cards", "nw_beast_core": "index.html#core-refining",
                   "nw_overlord_core": "index.html#core-refining", "nw_dust": "index.html#start"}

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
# Recipe material names verified by prefab against the installed native Chinese PO.
LABELS.update({
    "amulet": "重生护符",
    "armorsnurtleshell": "蜗壳护甲",
    "bearger_fur": "熊皮",
    "boards": "木板",
    "cactus_meat": "仙人掌肉",
    "deerclops_eyeball": "独眼巨鹿眼球",
    "dragon_scales": "鳞片",
    "fishmeat": "生鱼肉",
    "gnarwail_horn": "一角鲸的角",
    "lunarplant_husk": "亮茄外壳",
    "messagebottleempty": "空瓶子",
    "milkywhites": "乳白物",
    "minotaurhorn": "守护者之角",
    "moonglass": "月亮碎片",
    "oceanfishinglure_spinner_red": "日出旋转亮片",
    "pocketwatch_parts": "时间碎片",
    "reviver": "告密的心",
    "royal_jelly": "蜂王浆",
    "shadowheart": "暗影心房",
    "shadowheart_infused": "附身暗影心房",
    "spidergland": "蜘蛛腺",
    "thulecite": "铥矿",
    "townportaltalisman": "沙之石",
    "trunk_summer": "象鼻",
    "voidcloth": "暗影碎布",
    "waterballoon": "水球",
    "wormlight": "发光浆果"
})


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


def fallback_probability(sources):
    """Read the eligible 1x chance through the same decision used by the mod."""
    low, high = 0.0, 1.0
    for _ in range(40):
        roll = (low + high) / 2
        rng = lambda count=None: 1 if count is not None else roll
        if sources.finish_card(201, None, False, 1, rng) is not None:
            low = roll
        else:
            high = roll
    return round((low + high) / 2, 10)


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
    balance = require("nw/balance")
    crafting = require("nw/crafting")
    mode_values = defaultdict(dict)
    recipe_modes = defaultdict(list)
    fallback_chances = {}
    for mode in MODES:
        balance.configure(mode)
        fallback_chances[mode] = fallback_probability(sources)
        for card_id in array(rarity.pool):
            d = defs.spells[card_id]
            mode_values[card_id][mode] = dict(mana=d.mana, delay=round(d.delay, 5),
                                             recharge=round(d.recharge, 5))
        for row in array(rules.recipes):
            if crafting.recipe_enabled(row):
                recipe_modes[row.name].append(mode)
    balance.configure("fun")
    natural = require("nw/natural_loot")
    hover = require("nw/hover_data")
    tags = require("nw/card_tags")
    identities = require("nw/card_visuals").cards
    classes = {}
    for station in STATIONS:
        for option in array(require("nw/crafting_filter").class_options(station)):
            classes[option.data] = option.text
    class_order = {"basic": 1, "modifier": 2, "control": 3}
    icons = icon_indices()
    labels = LABELS | {row[1]: row[2] for row in array(require("nw/weapon_catalog"))}
    for c in array(require("nw/arsenal").cards):
        if c.source_weapon and c.source_weapon not in labels:
            labels[c.source_weapon] = c.name
    labels.update({key: row[1] for key, row in rules.materials.items()})
    material_icons = json.loads((SITE / "recipe_material_icons.json").read_text(encoding="utf8"))["materials"]
    material_wikis = json.loads((SITE / "material_wiki.json").read_text(encoding="utf8"))

    recipes = defaultdict(list)
    recipe_data = defaultdict(list)
    stations = {}
    recipe_order = {}
    for index, row in enumerate(array(rules.recipes)):
        if row.card:
            recipe_order.setdefault(row.card, index)
            costs = " + ".join(f"{labels[item[1]]} ×{item[2]}" for item in array(row.ingredients))
            stations[row.card] = STATIONS[row.station]
            recipes[row.card].append(f"{STATIONS[row.station]}刻写（爽快/平衡；掉落限定不可制作） · {costs}")
            ingredients = [dict(prefab=item[1], count=item[2], name=labels[item[1]])
                           for item in array(row.ingredients)]
            if language == "en":
                from catalog_locale import translate_tree
                ingredients = translate_tree(ingredients)
            for material in ingredients:
                prefab = material["prefab"]
                material["icon"] = material_icons[prefab]["icon"]
                material["wiki"] = prefab not in MATERIAL_GUIDES
                if material["wiki"]:
                    article = material_wikis[prefab][language]
                    if article["verified"]:
                        material["href"] = article["url"]
                    else:
                        # MediaWiki's Go form opens an exact title when it exists,
                        # or offers search results instead of a guessed missing page.
                        origin = urlsplit(article["url"])
                        material["href"] = f"{origin.scheme}://{origin.netloc}/wiki/Special:Search?" + urlencode(
                            {"search": article["title"], "go": "Go"})
                else:
                    material["href"] = MATERIAL_GUIDES[prefab]
            recipe_data[row.card].append(dict(name=row.name, station=row.station,
                                             product=row.product, count=row.count,
                                             ingredients=ingredients,
                                             availableModes=recipe_modes[row.name]))

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
            routes.append("极稀有随机掉落 · 最大生命超过 200 的合资格生物，此次既无散卡也无携卡法杖时，从全卡池（道具招牌除外）等概率抽一张。默认掉率倍率下，爽快/平衡为 "
                          f"{100 * fallback_chances['fun']:.3g}%"
                          "，平衡·掉落限定为 "
                          f"{100 * fallback_chances['balanced_loot']:.3g}%"
                          "；实际概率再乘法术卡掉率倍率。")

        # Render the exact same fields and descriptions as the in-game panel.
        detail = hover.card_details(card_id, False)
        primary = identities[card_id].primary_class
        tag_options = array(tags.options(tags.for_card(card_id)))
        if language == "en":
            from catalog_locale import translate_tree
            routes = translate_tree(routes)
        guide.append(dict(id=card_id, name=detail.title, category=classes[primary],
                          categoryId=primary, groupOrder=class_order[primary], rarity=rarity.names[tier],
                          tags=[tag.text for tag in tag_options], tagIds=[tag.id for tag in tag_options],
                          effect=info.brief(card_id), detailedEffect=detail.effect,
                          mana=d.mana, delay=round(d.delay, 5), recharge=round(d.recharge, 5),
                          modeValues=mode_values[card_id], recipes=recipe_data[card_id],
                          fields=[[row[1], vm.globals().tostring(row[2])] for row in array(detail.fields)],
                          sources=routes, station=(require("nw/locale").t(stations[card_id])
                          if card_id in stations else None), iconIndex=icons[info.icon(card_id)]))

    assert {card["id"] for card in guide} == set(public_ids)
    assert all(card["name"] and card["effect"] and card["sources"] for card in guide)
    guide.sort(key=lambda card: (card["groupOrder"], recipe_order.get(card["id"], float("inf"))))
    present = vm.table_from({tag: True for card in guide for tag in card["tagIds"]})
    return {"cards": guide, "fallbackDropChance": fallback_chances,
            "tags": [{"id": tag.id, "text": tag.text}
                                     for tag in array(tags.options(present))]}


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
