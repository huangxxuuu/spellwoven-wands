#!/usr/bin/env python3
"""Build a dependency-free file:// gallery without modifying any source art.

Usage: python tools/build_spell_subject_gallery.py
       python tools/build_spell_subject_gallery.py --check
"""

from __future__ import annotations

import argparse
import json
import os
from collections import Counter
from pathlib import Path
from urllib.parse import quote


DEFAULT_CATALOG = (
    Path(__file__).resolve().parents[1]
    / "assets_src/spell_card_subjects/v3_full_catalog"
)
REUSE_STATUSES = {"native_reuse", "existing_selected", "shared_base"}
GROUP_LABELS = {
    "projectiles_controls": "投射物与施法控制",
    "fields": "场地、召唤与光环",
    "modifiers": "修饰法术",
    "music_targets": "音乐、目标与辅助",
    "native_reuse": "原版武器 / 道具复用",
    "existing_selected": "此前已选主图",
    "shared_base": "共享基础主图",
}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def text_values(value):
    """Extract review prose, deliberately excluding numeric validation metadata."""
    if isinstance(value, str):
        return [value] if value.strip() else []
    if isinstance(value, list):
        return [item for part in value for item in text_values(part)]
    if isinstance(value, dict):
        return [
            item
            for key in (
                "issues", "reasons", "reason", "notes", "warnings", "summary",
                "message", "description", "visual_review", "recommendation",
                "failure_reason", "error",
            )
            for item in text_values(value.get(key))
        ]
    return []


def review_status(record: dict) -> str:
    values = [record.get("status"), record.get("review_status"), record.get("qa_status")]
    for key in ("review", "qa", "visual_review"):
        nested = record.get(key)
        if isinstance(nested, dict):
            values.extend([nested.get("status"), nested.get("review_status")])
    states = {str(value).strip().lower() for value in values if value}
    if states & {"needs_retry", "retry", "rejected", "needs_regeneration", "needs_revision"}:
        return "needs_retry"
    if states & {"failed", "error", "generation_failed"}:
        return "failed"
    if states & {"candidate", "approved", "accepted", "passed", "pass", "ok"}:
        return "candidate"
    return "pending"


def resolve_asset(value, owner_dir: Path, catalog: Path) -> Path | None:
    if not isinstance(value, str) or not value.strip():
        return None
    path = Path(value.replace("\\", "/"))
    if path.is_absolute():
        return path
    choices = [owner_dir / path, catalog / path, DEFAULT_CATALOG.parents[2] / path]
    return next((choice.resolve() for choice in choices if choice.is_file()), choices[0].resolve())


def local_link(path: Path | None, output_dir: Path) -> str | None:
    if path is None or not path.is_file():
        return None
    try:
        return quote(Path(os.path.relpath(path, output_dir)).as_posix(), safe="/:")
    except ValueError:  # A custom output file may live on another Windows drive.
        return path.resolve().as_uri()


def collect_entries(catalog: Path, output_dir: Path):
    roster_data = read_json(catalog / "roster.json")
    roster = roster_data if isinstance(roster_data, list) else roster_data.get("items", roster_data.get("cards", []))
    by_id = {str(row["id"]): row for row in roster}
    results = {}
    warnings = []
    for result_file in sorted(catalog.glob("*/*.result.json")):
        try:
            record = read_json(result_file)
            ident = str(record.get("id") or result_file.name.removesuffix(".result.json"))
            if ident in results:
                warnings.append(f"Duplicate result ID: {ident}; using {result_file.relative_to(catalog)}")
            results[ident] = (record, result_file)
        except (OSError, ValueError, TypeError) as exc:
            warnings.append(f"Cannot read {result_file.name}: {exc}")

    def resolve_subject(ident: str, seen=()):
        if ident in seen:
            return None, None, None, None
        row = by_id.get(ident, {})
        kind = row.get("status")
        if kind == "shared_base":
            base = str(row.get("base") or row.get("selected") or "")
            return resolve_subject(base, (*seen, ident))
        if kind in REUSE_STATUSES:
            image = resolve_asset(row.get("selected") or row.get("source_image"), catalog, catalog)
            prompt = image.with_suffix(".prompt.txt") if image and kind == "existing_selected" else None
            return image, prompt, None, None
        record, result_file = results.get(ident, ({}, catalog / str(row.get("group", "")) / f"{ident}.result.json"))
        owner = result_file.parent
        image = resolve_asset(record.get("output") or record.get("image") or record.get("image_path") or f"{ident}.png", owner, catalog)
        prompt = resolve_asset(record.get("prompt") or record.get("prompt_path") or f"{ident}.prompt.txt", owner, catalog)
        retry = resolve_asset(record.get("retry_prompt") or record.get("retry_prompt_path") or f"{ident}.retry.prompt.txt", owner, catalog)
        return image, prompt, retry, result_file

    entries = []
    for row in roster:
        ident = str(row["id"])
        origin = str(row.get("status", "needs_generation"))
        group = str(row.get("group") or (origin if origin in REUSE_STATUSES else "ungrouped"))
        record, result_file = results.get(ident, ({}, None))
        image, prompt, retry, resolved_result = resolve_subject(ident)
        base = str(row.get("base") or row.get("selected") or "") if origin == "shared_base" else None
        base_record = results.get(base, ({}, None))[0] if base else {}
        status = "reused" if origin in REUSE_STATUSES else review_status(record)
        qa = []
        for key in ("review", "qa", "visual_review", "issues", "reasons", "reason", "notes", "warnings", "error"):
            qa.extend(text_values(record.get(key)))
        if origin == "shared_base":
            base_name = by_id.get(base, {}).get("name", base)
            qa.append(f"复用基础卡「{base_name}」的主图，非本次单独生成；基础图状态：{review_status(base_record) if base_record else by_id.get(base, {}).get('status', 'unknown')}。")
        elif origin == "native_reuse":
            qa.append("直接使用原版武器 / 道具图，非本次生成。")
        elif origin == "existing_selected":
            qa.append("使用此前已选定的主图，非本次生成。")
        if row.get("note"):
            qa.extend(text_values(row["note"]))
        image_url = local_link(image, output_dir)
        if not image_url:
            qa.append("主图文件尚未就绪或路径不存在。")
            warnings.append(f"Missing image: {ident}")
        entries.append({
            "id": ident, "name": row.get("name", ident), "group": group,
            "group_label": GROUP_LABELS.get(group, group), "origin": origin,
            "status": status, "kind": row.get("kind", ""), "effect": row.get("effect", ""),
            "base": base, "badge": row.get("badge") or row.get("event"),
            "source_weapon": row.get("source_weapon"),
            "image": image_url, "prompt": local_link(prompt, output_dir),
            "retry_prompt": local_link(retry, output_dir),
            "retry_prompt_mode": (base_record if base else record).get("retry_prompt_mode"),
            "result": local_link(result_file or resolved_result, output_dir),
            "attempt_count": record.get("attempt_count"),
            "qa": list(dict.fromkeys(qa)),
        })
    return entries, warnings


HTML = r'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>法术卡主图 · 本地总览</title>
<style>
:root{color-scheme:light;--thumb:192px;--canvas:#e5e7eb;--ink:#172033}
*{box-sizing:border-box}body{margin:0;background:#f7f8fa;color:var(--ink);font:14px/1.5 system-ui,"Microsoft YaHei",sans-serif}
header{padding:22px 24px 12px}h1{margin:0;font-size:25px}header p{margin:7px 0;color:#526071}
.controls{position:sticky;top:0;z-index:2;padding:12px 24px;background:#fffef7f2;border-block:1px solid #d6dce4;backdrop-filter:blur(8px);display:flex;gap:12px;flex-wrap:wrap;align-items:center}
label{display:flex;align-items:center;gap:6px}input,select,button{font:inherit;border:1px solid #b6bfce;border-radius:5px;padding:6px 8px;background:white;color:inherit}input[type=search]{width:230px}input[type=range]{padding:0;width:130px}button{cursor:pointer}button:hover{background:#e7eef8}
#count{padding:12px 24px;color:#526071}#grid{padding:0 24px 28px;display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:16px;align-items:start}
.card{background:white;border:1px solid #d6dce4;border-radius:10px;overflow:hidden;min-width:0}.preview{display:flex;align-items:center;justify-content:center;height:calc(var(--thumb) + 28px);min-height:92px;background:var(--canvas);padding:14px;text-decoration:none;color:#526071;overflow:auto}.preview img{display:block;width:var(--thumb);height:var(--thumb);object-fit:contain;flex-shrink:0}.missing{padding:16px;color:#763b32}
.info{padding:12px}.title{font-size:17px;font-weight:650;margin:0}.id{font:12px ui-monospace,Consolas,monospace;color:#66758a;word-break:break-all}.badges{display:flex;gap:6px;flex-wrap:wrap;margin:8px 0}.tag{padding:2px 7px;border-radius:4px;background:#edf0f4;font-size:12px}.candidate{background:#e2f2e8;color:#155c37}.needs_retry,.failed{background:#ffe8dc;color:#8b390c}.pending{background:#fff3c8;color:#755900}.reused{background:#e8ebf6;color:#4d5680}.links{display:flex;gap:12px;flex-wrap:wrap;margin:9px 0}a{color:#1557ac}.qa{padding-left:18px;margin:8px 0;color:#566275;font-size:12px}.qa li+li{margin-top:5px}.effect{font-size:12px;color:#566275;margin-top:8px}details summary{cursor:pointer}#empty{padding:32px;text-align:center;color:#526071}noscript{display:block;padding:24px}
</style></head><body>
<header><h1>法术卡主图 · 本地总览</h1><p>查看生成候选与复用素材。图片、prompt 均为本地链接；切换预览不会修改原图。复用卡明确标为“非本次生成”。</p></header>
<div class="controls">
<label>搜索 <input id="query" type="search" placeholder="中文名称 / id" autocomplete="off"></label>
<label>组别 <select id="group"><option value="all">全部组别</option></select></label>
<label>状态 <select id="status"><option value="all">全部状态</option><option value="candidate">候选</option><option value="needs_retry">建议重试</option><option value="pending">待审核</option><option value="failed">生成失败</option><option value="reused">复用（非本次生成）</option></select></label>
<label>底色 <select id="background"><option value="#e5e7eb">浅灰</option><option value="#ffffff">白色</option><option value="#292d34">深灰</option></select></label>
<label>缩略图 <input id="size" type="range" min="64" max="320" step="8" value="192"><output id="size-label">192 px</output></label>
<button id="actual-size" type="button">看 64px</button><button id="reset" type="button">重置筛选</button>
</div><div id="count" role="status" aria-live="polite"></div><main id="grid"></main><p id="empty" hidden>没有符合筛选条件的主图。</p>
<noscript>请启用 JavaScript。所有清单数据已内嵌于本文件，无需本地服务器或网络。</noscript>
<script type="application/json" id="catalog-data">__CATALOG_DATA__</script>
<script>
"use strict";
const data=JSON.parse(document.getElementById("catalog-data").textContent);
const q=document.getElementById("query"),g=document.getElementById("group"),s=document.getElementById("status");
const statusNames={candidate:"候选",needs_retry:"建议重试",pending:"待审核",failed:"生成失败",reused:"非本次生成"};
const originNames={native_reuse:"原版武器 / 道具",existing_selected:"此前已选主图",shared_base:"共享基础主图"};
const groups=new Map();for(const item of data)groups.set(item.group,item.group_label);
for(const [value,label] of groups){const option=document.createElement("option");option.value=value;option.textContent=label;g.append(option)}
function node(tag,cls,text){const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e}
function link(href,label){const a=node("a",null,label);a.href=href;a.target="_blank";a.rel="noopener";return a}
function render(){
 const query=q.value.trim().toLowerCase();
 const visible=data.filter(x=>(g.value==="all"||x.group===g.value)&&(s.value==="all"||x.status===s.value)&&(!query||(x.id+" "+x.name).toLowerCase().includes(query)));
 const grid=document.getElementById("grid");const fragment=document.createDocumentFragment();
 for(const item of visible){
  const card=node("article","card");card.id="card-"+item.id;
  const preview=item.image?link(item.image,""):node("div");preview.className="preview";
  if(item.image){const img=node("img");img.src=item.image;img.alt=item.name+"主图";img.loading="lazy";img.decoding="async";img.addEventListener("error",()=>{preview.replaceChildren(node("span","missing","图片无法读取，请检查本地文件。"))},{once:true});preview.append(img)}else preview.append(node("span","missing","主图尚未就绪"));
  const info=node("div","info");info.append(node("h2","title",item.name),node("div","id",item.id));
  const badges=node("div","badges");badges.append(node("span","tag "+item.status,statusNames[item.status]),node("span","tag",item.group_label));
  if(originNames[item.origin])badges.append(node("span","tag",originNames[item.origin]));
  if(item.badge)badges.append(node("span","tag",item.badge==="hit"?"碰撞变体":item.badge==="timer"?"定时变体":item.badge));
  info.append(badges);const links=node("nav","links");
  if(item.image)links.append(link(item.image,"PNG 原图"));if(item.prompt)links.append(link(item.prompt,item.origin==="shared_base"?"基础图 prompt":"原始 prompt"));if(item.retry_prompt)links.append(link(item.retry_prompt,item.retry_prompt_mode==="optional_not_required"?"可选重试 prompt":"重试 prompt"));if(item.result)links.append(link(item.result,"记录"));info.append(links);
  if(item.qa.length){const list=node("ul","qa");for(const note of item.qa)list.append(node("li",null,note));info.append(list)}
  if(item.effect){const details=node("details","effect");details.append(node("summary",null,"法术机制"),node("p",null,item.effect));info.append(details)}
  card.append(preview,info);fragment.append(card);
 }
 grid.replaceChildren(fragment);document.getElementById("empty").hidden=visible.length>0;
 const counts={};for(const item of data)counts[item.status]=(counts[item.status]||0)+1;
 document.getElementById("count").textContent="显示 "+visible.length+" / "+data.length+" 张 · "+Object.entries(counts).map(([key,value])=>statusNames[key]+" "+value).join(" · ");
}
q.addEventListener("input",render);g.addEventListener("change",render);s.addEventListener("change",render);
document.getElementById("background").addEventListener("change",e=>document.documentElement.style.setProperty("--canvas",e.target.value));
function setSize(value){document.getElementById("size").value=value;document.documentElement.style.setProperty("--thumb",value+"px");document.getElementById("size-label").textContent=value+" px"}
document.getElementById("size").addEventListener("input",e=>setSize(e.target.value));document.getElementById("actual-size").addEventListener("click",()=>setSize(64));
document.getElementById("reset").addEventListener("click",()=>{q.value="";g.value="all";s.value="all";render()});render();
</script></body></html>'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG, help="Directory containing roster.json")
    parser.add_argument("--output", type=Path, help="HTML output path (default: CATALOG/index.html)")
    parser.add_argument("--check", action="store_true", help="Read and validate inputs; do not write HTML")
    args = parser.parse_args()
    catalog = args.catalog.resolve()
    output = (args.output or catalog / "index.html").resolve()
    entries, warnings = collect_entries(catalog, output.parent)
    print(f"Cards: {len(entries)}; states: {dict(Counter(item['status'] for item in entries))}")
    for warning in warnings:
        print(f"Warning: {warning}")
    if args.check:
        return 0
    payload = json.dumps(entries, ensure_ascii=False, separators=(",", ":"))
    for char, replacement in (("<", "\\u003c"), (">", "\\u003e"), ("&", "\\u0026"), ("\u2028", "\\u2028"), ("\u2029", "\\u2029")):
        payload = payload.replace(char, replacement)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(HTML.replace("__CATALOG_DATA__", payload), encoding="utf-8")
    print(f"Wrote: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
