"""Snapshot the Chinese Wiki's spell index, infobox data and 16px icons.

Run with Python 3.10+, requests, beautifulsoup4 and Pillow. This reads data
literals only; it does not execute the Wiki's Lua or JavaScript.
"""
import argparse
import csv
import io
import json
import re
from collections import Counter
from datetime import datetime, timezone
from hashlib import sha256
from html import escape
from pathlib import Path
from urllib.parse import quote, urljoin

import requests
from bs4 import BeautifulSoup
from PIL import Image
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

ROOT = Path(__file__).resolve().parents[1]
SITE = "https://noita.wiki.gg"
API = SITE + "/zh/api.php"
INDEX = SITE + "/zh/wiki/" + quote("法术")
GROUPS = ("投射物", "静态投射物", "投射修正", "多重释放", "材料", "其他", "实用", "被动")


def data_rows(source):
    body = re.search(r"local all_spells\s*=\s*\{(.*?)\n\}\s*\n---", source, re.S)[1]
    rows = {}
    for block in re.findall(r"^\{\s*\n(.*?)^\},", body, re.M | re.S):
        row = {}
        for line in block.splitlines():
            key, value = re.fullmatch(r'\s*(\w+)\s*=\s*(".*"),\s*', line).groups()
            row[key] = json.loads(value)
        key = row["gameID"]
        if key in rows:
            raise ValueError(f"Duplicate infobox ID: {key}")
        rows[key] = row
    return rows


def catalog(records):
    rows=[]
    for r in records:
        props=" · ".join(f"{escape(k)}={escape(v)}" for k,v in r["properties"].items())
        rows.append('<tr><td><img loading="lazy" width="32" height="32" src="'+r["icon"]+'"></td>'
                    f'<td>{escape(r["group"])}</td><td><a href="{escape(r["url"])}">{escape(r["name"])}</a>'
                    f'<br><code>{r["id"]}</code></td><td>{escape(r["description"])}'
                    f'<details><summary>原始属性</summary>{props}</details></td></tr>')
    return '''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>Noita 法术图鉴</title>
<style>body{font:16px system-ui;background:#202325;color:#efe6d5;margin:2rem}a{color:#eac888}td{padding:.6rem;border-bottom:1px solid #514f48}td:nth-child(2){white-space:nowrap}img{image-rendering:pixelated}details{color:#bbb}input{padding:.5rem;width:25rem}</style>
<h1>Noita 法术图鉴</h1><p>中文 Wiki 快照。点卡名看来源，展开可看非空原始字段。</p>
<input id="q" placeholder="按类型、卡名、ID 或效果筛选"> <span id="count"></span><table><tbody>'''+"".join(rows)+'''</tbody></table>
<script>const q=document.getElementById('q');function filter(){let n=0;for(const r of document.querySelectorAll('tr')){r.hidden=!r.textContent.toLowerCase().includes(q.value.trim().toLowerCase());if(!r.hidden)n++}document.getElementById('count').textContent=n+' 张'}q.oninput=filter;filter()</script></html>'''


def snapshot(out):
    session = requests.Session()
    session.headers["User-Agent"] = "DST-spell-research/1.0 (local design reference)"
    session.mount("https://", HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1,
                  status_forcelist=(429, 500, 502, 503, 504))))

    def get(url, **params):
        response = session.get(url, params=params, timeout=(10, 45))
        response.raise_for_status()
        return response

    def api(**params):
        result = get(API, format="json", formatversion=2, **params).json()
        if "error" in result:
            raise ValueError(result["error"])
        return result

    page = api(action="parse", page="法术", prop="text|revid")["parse"]
    html = BeautifulSoup(page["text"], "html.parser")
    revs = {}
    def module(title):
        rev = api(action="query", titles=title, prop="revisions", rvslots="main",
                  rvprop="ids|content")["query"]["pages"][0]["revisions"][0]
        revs[title] = rev["revid"]
        return rev["slots"]["main"]["content"]

    db = data_rows(module("Module:DataQuery/Spells"))
    language = module("Module:Lang_zh_cn/data")
    text = re.search(r"local data_base\s*=\s*\[\[(.*?)\]\]", language, re.S)[1].strip()
    translations = {row["id"]: row for row in csv.DictReader(io.StringIO(text))}
    css = get(SITE+"/zh/load.php", modules="site.styles", only="styles", skin="vector", lang="zh").text
    sprite_url = urljoin(INDEX,re.search(r"\.sprite-spell-bg-16px\s*\{[^}]*?url\(([^)]+)\)", css)[1].strip("'\""))
    texture = get(sprite_url).content
    sheet = Image.open(io.BytesIO(texture)).convert("RGBA")
    records, icons, used_offsets = {}, {}, set()
    for group in GROUPS:
        heading = next((h for h in html.select("h3") if h.find(id=group) or h.get("id")==group),None)
        if not heading:
            raise ValueError(f"Missing index heading {group}")
        entries = heading.find_next("table").select("[data-spell-name]")
        if not entries:
            raise ValueError(f"Empty category {group}")
        for el in entries:
            key = el["data-spell-name"]
            row = db[key]
            if key in records or row["type"] != group or not re.fullmatch(r"[A-Z0-9_]+", key):
                raise ValueError(f"Index mismatch: {key}")
            tag = el.select_one(".sprite-spell-bg-16px")
            offset = -int(re.search(r"background-position-x:\s*(-?\d+)px", tag["style"])[1])
            if offset%16 or offset<0 or offset+16>sheet.width or offset in used_offsets:
                raise ValueError(f"Invalid icon offset for {key}: {offset}")
            used_offsets.add(offset)
            icon = sheet.crop((offset,0,offset+16,16))
            if not icon.getchannel("A").getbbox():
                raise ValueError(f"Empty icon: {key}")
            icons[key] = icon
            name = translations.get(row["nameKey"], {}).get("zh-cn") or row["nameOcn"]
            tr = translations.get(row["descriptionKey"], {})
            description = (tr.get("zh-cn") or tr.get("en") or "").strip().replace(r"\n", "\n")
            description_source="Wiki 中文词条" if tr.get("zh-cn") else "Wiki 英文词条"
            if not description:
                detail=api(action="parse",page=row["pageName"],prop="text|revid")["parse"]
                paras=BeautifulSoup(detail["text"],"html.parser").select(".mw-parser-output > p")
                description=next((p.get_text("",strip=True) for p in paras if p.get_text(strip=True)),"")
                description_source=f"Wiki 正文首段（修订 {detail['revid']}）"
            if not name or not description:
                raise ValueError(f"Missing translation: {key}")
            records[key] = dict(id=key, group=group, name=name, description=description,description_source=description_source,
                    url=urljoin(INDEX,el.a["href"].split("#")[0]), icon=f"icons/{key}.png",
                    icon_offset=offset, properties={k:v for k,v in row.items() if v!=""})
    if set(records)!=set(db):
        raise ValueError("Index/infobox coverage differs; review the upstream changes before publishing.")
    out.mkdir(parents=True,exist_ok=True)
    (out/"icons").mkdir(exist_ok=True)
    for key,icon in icons.items():
        icon.save(out/records[key]["icon"])
    def save(name,obj):
        dest=out/name
        tmp=dest.with_suffix(".tmp")
        tmp.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
        tmp.replace(dest)
    save("spells.json",list(records.values()))
    (out/"法术图鉴.html").write_text(catalog(records.values()),encoding="utf-8")
    save("sources.json",dict(index=INDEX+"#"+quote("投射物"),index_revision=page["revid"],
            modules=revs, sprite=sprite_url, sprite_sha256=sha256(texture).hexdigest(), acquired_utc=datetime.now(timezone.utc).isoformat(),
            counts=Counter(r["group"] for r in records.values()), total=len(records),
            wiki_license="https://creativecommons.org/licenses/by-nc-sa/3.0/deed.zh-hans"))
    print(f"{len(records)} unique spells and icons -> {out}")


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out",type=Path,default=ROOT/"research/noita-spells")
    snapshot(parser.parse_args().out)
