"""Check English coverage, format arguments, generated names and gameplay parity."""
import json
import re
from pathlib import Path
from xml.etree import ElementTree
from lupa.lua51 import LuaRuntime, lua_type
from build_localized_names import names

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
        suffix = '_en' if language == 'en' else ''
        atlas = ElementTree.parse(ROOT / f'mod/images/nw_sections{suffix}.xml')
        icons = {row.get('name') for row in atlas.findall('.//Element')}
        rows = runtime(language).eval('require("nw/acquisition").menu_entries')
        assert all(not row.section_icon or row.section_icon + '.tex' in icons for row in rows.values())
    a = json.loads((ROOT / 'site/dist/catalog.json').read_text(encoding='utf8'))['cards']
    b = json.loads((ROOT / 'site/dist/catalog.en.json').read_text(encoding='utf8'))['cards']
    assert [c['id'] for c in a] == [c['id'] for c in b]
    for left, right in zip(a, b):
        for key in ('mana', 'delay', 'recharge', 'iconIndex', 'groupOrder'):
            assert left[key] == right[key], (left['id'], key)
        assert not re.search(r'[\u4e00-\u9fff]', json.dumps(right, ensure_ascii=False))
    print(f'PASS: {len(dictionary)} translations, format arguments, both icon atlases, gameplay/ID parity, {len(a)} bilingual catalog cards')
