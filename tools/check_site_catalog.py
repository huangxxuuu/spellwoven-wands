"""Check exported guide data against fresh Lua state and shipped atlas assets.

Does not import the catalog generator. Source PNG / WebP equality is lossless;
compiled KTEX comparisons allow block-compression error and cannot certify art.
"""
import argparse
import hashlib
import json
import re
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from xml.etree import ElementTree as ET

import numpy as np
from PIL import Image
from lupa.lua51 import LuaRuntime
from native_animation import texture

ROOT = Path(__file__).resolve().parents[1]
MODES = ("fun", "balanced", "balanced_loot")
MATERIAL_GUIDES = {"nw_blank": "index.html#blank-cards", "nw_beast_core": "index.html#core-refining",
                   "nw_overlord_core": "index.html#core-refining", "nw_dust": "index.html#start"}


class PageIds(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        self.ids.update(value for key, value in attrs if key == "id")


def check_materials(data, language, directory):
    """Check prefab-bound local pixels and curated links, without claiming live HTTP validity."""
    manifest = json.loads((ROOT / "site/recipe_material_icons.json").read_text(encoding="utf8"))
    materials = manifest["materials"]
    wikis = json.loads((ROOT / "site/material_wiki.json").read_text(encoding="utf8"))
    assert manifest["materialCount"] == len(materials), "Material manifest count differs"
    # Validate all exported assets, including materials used only in non-card recipes.
    for prefab, record in materials.items():
        expected_icon = f"assets/materials/{prefab}.webp"
        assert record["icon"] == expected_icon, (prefab, "manifest icon identity")
        path = directory / expected_icon
        assert path.is_file(), (prefab, "missing material icon")
        assert hashlib.sha256(path.read_bytes()).hexdigest() == record["iconSha256"], (prefab, "material icon hash")
        with Image.open(path) as image:
            assert image.mode == "RGBA", (prefab, "material icon must be RGBA")
            assert list(image.size) == record["size"], (prefab, "material icon size")
            assert image.getchannel("A").getbbox(), (prefab, "blank material icon")
    page = PageIds()
    page_path = directory / ("en/index.html" if language == "en" else "index.html")
    page.feed(page_path.read_text(encoding="utf8"))
    domains = {"zh": {"dontstarve.huijiwiki.com"},
               "en": {"dontstarve.fandom.com", "dontstarve.wiki.gg"}}[language]
    used = set()
    for card in data["cards"]:
        for recipe in card["recipes"]:
            for ingredient in recipe["ingredients"]:
                prefab = ingredient["prefab"]
                used.add(prefab)
                assert prefab in materials, (prefab, "missing material coverage")
                assert ingredient.get("icon") == materials[prefab]["icon"], (prefab, "material icon identity")
                if prefab in MATERIAL_GUIDES:
                    assert ingredient.get("wiki") is False, (prefab, "Mod material must use local guide")
                    assert ingredient.get("href") == MATERIAL_GUIDES[prefab], (prefab, "Mod material local href")
                    assert urlsplit(ingredient["href"]).fragment in page.ids, (language, prefab, "missing local material anchor")
                    continue
                assert ingredient.get("wiki") is True, (prefab, "native material wiki flag")
                assert prefab in wikis and language in wikis[prefab], (prefab, "missing material wiki metadata")
                article = wikis[prefab][language]
                assert article["title"].strip() and type(article["verified"]) is bool, (prefab, "invalid material wiki metadata")
                origin = urlsplit(article["url"])
                href = urlsplit(ingredient.get("href", ""))
                for link in (origin, href):
                    assert link.scheme == "https" and link.netloc in domains, (prefab, "material wiki domain")
                assert href.netloc == origin.netloc, (prefab, "material wiki identity")
                if article["verified"]:
                    assert ingredient["href"] == article["url"], (prefab, "material wiki identity")
                else:
                    assert href.path == "/wiki/Special:Search" and not href.fragment, (prefab, "unverified material must use wiki search")
                    assert parse_qs(href.query) == {"search": [article["title"]], "go": ["Go"]}, (prefab, "material wiki identity")
    return len(used), len(materials)


def runtime(language, mode="fun"):
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
    vm.eval('require("nw/locale").configure')(language, language)
    vm.eval('require("nw/balance").configure')(mode)
    return vm


def array(value):
    return [value[i] for i in range(1, len(value) + 1)]


def recipe_data(vm, card_id):
    rows = [r for r in vm.eval('require("nw/acquisition").recipes').values() if r.card == card_id]
    result = []
    for row in rows:
        available = []
        for mode in MODES:
            vm.eval('require("nw/balance").configure')(mode)
            if vm.eval('require("nw/crafting").recipe_enabled')(row):
                available.append(mode)
        result.append({"name": row.name, "station": row.station, "product": row.product,
                       "count": row.count, "ingredients": [
                           {"prefab": ingredient[1], "count": ingredient[2]}
                           for ingredient in array(row.ingredients)], "availableModes": available})
    vm.eval('require("nw/balance").configure')("fun")
    return result


def check_cards(data, language, icon_tiles):
    vm = runtime(language)
    defs = vm.eval('require("nw/definitions").spells')
    rarity = vm.eval('require("nw/card_rarity")')
    info = vm.eval('require("nw/spell_info")')
    cards = data["cards"]
    ids = [card["id"] for card in cards]
    assert len(ids) == len(set(ids)), "Duplicate public card IDs"
    assert set(ids) == set(rarity.pool.values()), (language, "public pool differs")
    recipe_count = 0
    # Probe the runtime boundary, including eligibility exclusions, rather than
    # duplicating the drop-rate constants in this check.
    probe = vm.eval('''function(hp, card, wand, multiplier, roll)
        return require("nw/sources").finish_card(hp, card, wand, multiplier,
            function(n) return n and 1 or roll end)
    end''')
    for mode in MODES:
        vm.eval('require("nw/balance").configure')(mode)
        low, high = 0., 1.
        for _ in range(50):
            middle = (low + high) / 2
            if probe(201, None, False, 1, middle):
                low = middle
            else:
                high = middle
        assert abs(data["fallbackDropChance"][mode] - (low + high) / 2) < 1e-10, (language, mode, "fallback drop chance")
        assert probe(200, None, False, 1, 0) is None
        assert probe(201, None, True, 1, 0) is None
        assert probe(201, None, False, 0, 0) is None
        assert probe(201, "spark", False, 1, 0) == "spark"
    vm.eval('require("nw/balance").configure')("fun")
    for card in cards:
        card_id = card["id"]
        for mode in MODES:
            vm.eval('require("nw/balance").configure')(mode)
            for key in ("mana", "delay", "recharge"):
                actual = round(defs[card_id][key], 5)
                assert card["modeValues"][mode][key] == actual, (language, card_id, mode, key)
                if mode == "fun":
                    assert card[key] == actual, (language, card_id, key, "default value")
        vm.eval('require("nw/balance").configure')("fun")
        expected = recipe_data(vm, card_id)
        exported = []
        for row in card["recipes"]:
            exported.append({**row, "ingredients": [
                {"prefab": ingredient["prefab"], "count": ingredient["count"]}
                for ingredient in row["ingredients"]]})
            assert all(i["name"].strip() for i in row["ingredients"]), (card_id, "empty ingredient name")
        assert exported == expected, (language, card_id, "recipe or mode eligibility differs", exported, expected)
        recipe_count += len(expected)
        station = expected[-1]["station"] if expected else None
        station_names = {"nw_workbench": "奥术台", "nw_engraver": "武器刻印台"}
        assert card["station"] == (vm.eval('require("nw/locale").t')(station_names[station]) if station else None), (card_id, "station filter")
        inscription = "刻写" if language == "zh" else " inscription"
        displayed_recipes = [source for source in card["sources"] if inscription in source]
        assert len(displayed_recipes) == len(expected), (card_id, "displayed recipe count")
        for recipe, source in zip(card["recipes"], displayed_recipes):
            station_label = vm.eval('require("nw/locale").t')(station_names[recipe["station"]])
            quantities = " + ".join(f'{ingredient["name"]} ×{ingredient["count"]}'
                                    for ingredient in recipe["ingredients"])
            # Compare the complete ordered quantity list, not isolated digit
            # substrings (which could accidentally accept ×1 as part of ×10).
            assert source.startswith(station_label + inscription), (card_id, "displayed recipe station")
            assert source.split(" · ")[-1] == quantities, (card_id, "displayed recipe ingredients")
            unavailable = "掉落限定不可制作" if language == "zh" else "unavailable in Loot Only"
            assert unavailable in source, (card_id, "displayed recipe mode restriction")
        fallback_label = "极稀有随机掉落" if language == "zh" else "Very rare random drop"
        fallback_sources = [source for source in card["sources"] if source.startswith(fallback_label)]
        if card_id == "edge_propsign":
            assert not fallback_sources, (card_id, "excluded card displays fallback route")
        else:
            assert len(fallback_sources) == 1, (card_id, "displayed fallback route count")
            source = fallback_sources[0]
            percentages = set(re.findall(r"\d+(?:\.\d+)?%", source))
            expected_percentages = {f"{chance * 100:.3g}%" for chance in data["fallbackDropChance"].values()}
            assert percentages == expected_percentages, (card_id, "displayed fallback probability")
            conditions = (("超过 200", "无散卡", "无携卡法杖") if language == "zh" else
                          ("over 200 maximum health", "neither a loose card nor a loaded wand"))
            assert all(condition in source for condition in conditions), (card_id, "displayed fallback eligibility")
        assert card["rarity"] == rarity.names[rarity.tiers[card_id]], (card_id, "rarity")
        icon = info.icon(card_id)
        assert icon in icon_tiles, (card_id, "icon absent from shipped XML", icon)
        assert card["iconIndex"] == icon_tiles[icon][0], (card_id, "icon index")
    return len(cards), recipe_count


def check_atlas(directory):
    atlas = ET.parse(ROOT / "mod/images/inventoryimages/nw_icons.xml")
    source = Image.open(ROOT / "assets_src/art_v1/runtime/nw_icons.png").convert("RGBA")
    web = Image.open(directory / "assets/spells.webp").convert("RGBA")
    assert web.size == source.size and web.tobytes() == source.tobytes(), "Website atlas differs from current runtime PNG"
    compiled = texture((ROOT / "mod/images/inventoryimages/nw_icons.tex").read_bytes())
    assert compiled.size == source.size, "Compiled atlas size differs"
    tiles = {}
    occupied = set()
    for element in atlas.findall(".//Element"):
        name = element.get("name")
        if not name.startswith("nw_spell_"):
            continue
        u1, u2, v1, v2 = (float(element.get(k)) for k in ("u1", "u2", "v1", "v2"))
        col, row = u1 * 16, (1 - v2) * 16
        assert col.is_integer() and row.is_integer() and abs(u2 - u1 - 1 / 16) < 1e-9 and abs(v2 - v1 - 1 / 16) < 1e-9, (name, "non-grid UV")
        index = int(row * 16 + col)
        assert 0 <= index < 256 and index not in occupied, (name, "duplicate/out-of-range UV")
        occupied.add(index)
        w, h = source.size
        box = tuple(round(v) for v in (u1 * w, (1 - v2) * h, u2 * w, (1 - v1) * h))
        pixels = np.array(source.crop(box)).astype(float)
        decoded = np.array(compiled.crop(box)).astype(float)
        visible = pixels[:, :, 3] > 32
        assert visible.any(), (name, "blank icon")
        difference = abs(pixels - decoded)
        assert difference[:, :, :3][visible].mean() < 15, (name, "compiled texture content differs")
        assert difference[:, :, 3].mean() < 2, (name, "compiled texture alpha differs")
        tiles[name] = (index, box)
    return tiles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=ROOT / "site/dist")
    args = parser.parse_args()
    tiles = check_atlas(args.directory)
    for language, filename in (("zh", "catalog.json"), ("en", "catalog.en.json")):
        data = json.loads((args.directory / filename).read_text(encoding="utf8"))
        count, recipes = check_cards(data, language, tiles)
        used, assets = check_materials(data, language, args.directory)
        print(f"PASS: {language}: {count} current cards, {recipes} exact recipes, 3 mode values/recipe eligibility/drop rates, displayed recipe/drop sources, rarity, stations and atlas indices")
        print(f"PASS: {language}: {used} recipe materials, {assets} prefab-bound RGBA assets/hashes, curated wiki URLs and existing local guide anchors (offline)")
    print(f"PASS: {len(tiles)} shipped atlas tiles; exact website/source pixels; compressed KTEX content within tolerance")


if __name__ == "__main__":
    main()
