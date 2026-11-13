"""Check English coverage, format arguments, generated names and gameplay parity."""
import json
import re
from pathlib import Path
from lupa.lua51 import LuaRuntime, lua_type
from build_localized_names import names
from check_site_catalog import check_atlas, check_cards, check_materials

ROOT = Path(__file__).resolve().parents[1]

def runtime(language):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().package.path = (ROOT / 'mod/scripts/?.lua').as_posix() + ';' + lua.globals().package.path
    lua.eval('require("nw/locale").configure')(language, language)
    return lua

def plain(value):
    if lua_type(value) == 'table':
        return {k: plain(v) for k, v in value.items() if k not in ('name', 'effect', 'title')}
    return value

if __name__ == '__main__':
    zh, en = runtime('zh'), runtime('en')
    dictionary = dict(en.eval('require("nw/locales/en")').items())
    placeholder = re.compile(r'%(?:[-+#0]*\d*(?:\.\d+)?)?[cdiouxXeEfgGqs]')
    for source, target in dictionary.items():
        assert not re.search(r'[\u4e00-\u9fff]', target), source
        assert placeholder.findall(source) == placeholder.findall(target), f'Format mismatch: {source}'
    literals = re.compile(r'T\(("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')\)')
    for path in (ROOT / 'mod').rglob('*.lua'):
        if 'locales' in path.parts:
            continue
        for match in literals.finditer(path.read_text(encoding='utf8')):
            key = zh.eval(match[1])
            assert key in dictionary, f'Missing translation: {path}: {key}'
    defs_zh = plain(zh.eval('require("nw/definitions").spells'))
    defs_en = plain(en.eval('require("nw/definitions").spells'))
    assert defs_zh == defs_en, 'Language changed gameplay values'
    assert plain(zh.eval('require("nw/cards").codes')) == plain(en.eval('require("nw/cards").codes'))
    actual = dict(en.eval('require("nw/locales/names")').items())
    expected_en = names('en')
    for key, source in names('zh').items():
        assert actual[source] == expected_en[key], f'Stale generated name: {source}'
    for language in ('zh', 'en'):
        rows = runtime(language).eval('require("nw/acquisition").menu_entries')
        assert all(not row.section_icon for row in rows.values()), 'Retired crafting headings still registered'
    zh_catalog = json.loads((ROOT / 'site/dist/catalog.json').read_text(encoding='utf8'))
    en_catalog = json.loads((ROOT / 'site/dist/catalog.en.json').read_text(encoding='utf8'))
    a, b = zh_catalog['cards'], en_catalog['cards']
    assert [c['id'] for c in a] == [c['id'] for c in b]
    for left, right in zip(a, b):
        for key in ('mana', 'delay', 'recharge', 'iconIndex', 'groupOrder'):
            assert left[key] == right[key], (left['id'], key)
        assert not re.search(r'[\u4e00-\u9fff]', json.dumps(right, ensure_ascii=False))
    # Compare every public card against the actual in-game presentation model.
    for language, cards in (("zh", a), ("en", b)):
        vm = runtime(language)
        hover = vm.eval('require("nw/hover_data")')
        info = vm.eval('require("nw/spell_info")')
        visuals = vm.eval('require("nw/card_visuals").cards')
        tags = vm.eval('require("nw/card_tags")')
        rarity = vm.eval('require("nw/card_rarity")')
        classes = {}
        for station in ("nw_workbench", "nw_engraver"):
            for option in vm.eval('require("nw/crafting_filter").class_options')(station).values():
                classes[option.data] = option.text
        assert {c["id"] for c in cards} == set(rarity.pool.values())
        for card in cards:
            card_id = card["id"]
            detail = hover.card_details(card_id, False)
            fields = [[detail.fields[i][1], vm.globals().tostring(detail.fields[i][2])]
                      for i in range(1, len(detail.fields) + 1)]
            own = tags.options(tags.for_card(card_id))
            expected = {"name": detail.title, "effect": info.brief(card_id),
                        "detailedEffect": detail.effect, "fields": fields,
                        "categoryId": visuals[card_id].primary_class,
                        "category": classes[visuals[card_id].primary_class],
                        "rarity": rarity.names[rarity.tiers[card_id]],
                        "tags": [own[i].text for i in range(1, len(own) + 1)],
                        "tagIds": [own[i].id for i in range(1, len(own) + 1)]}
            for key, value in expected.items():
                assert card[key] == value, (language, card_id, key, "website differs from mod")
    tiles = check_atlas(ROOT / 'site/dist')
    for language, catalog in (("zh", zh_catalog), ("en", en_catalog)):
        _, recipe_count = check_cards(catalog, language, tiles)
        check_materials(catalog, language, ROOT / 'site/dist')
    print(f'PASS: {len(dictionary)} translations, format arguments, gameplay/ID parity, {len(a)} bilingual catalog cards, '
          f'{recipe_count} current recipes, 3 difficulty modes and {len(tiles)} atlas tiles')
