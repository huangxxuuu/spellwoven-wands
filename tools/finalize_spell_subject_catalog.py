"""Validate and index saved first-pass illustrations; never generate or edit images."""
from __future__ import annotations

import hashlib
import json
from collections import Counter
from pathlib import Path
from urllib.parse import unquote

from PIL import Image

from build_spell_subject_gallery import DEFAULT_CATALOG, collect_entries, read_json


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    root = DEFAULT_CATALOG
    roster = read_json(root / "roster.json")
    expected = {x["id"] for x in roster if x["status"] == "needs_generation"}
    entries, warnings = collect_entries(root, root)
    assert not warnings, warnings
    assert len(roster) == 182 and len(expected) == 103
    assert len({x["id"] for x in entries}) == len(entries)
    generated = [x for x in entries if x["origin"] == "needs_generation"]
    assert {x["id"] for x in generated} == expected
    assert all(x["status"] in {"candidate", "needs_retry"} for x in generated), "Reviews incomplete"
    records = list(root.glob("*/*.result.json"))
    assert {x.name.removesuffix(".result.json") for x in records} == expected
    checks = []
    for entry in generated:
        ident = entry["id"]
        folder = root / entry["group"]
        record = read_json(folder / f"{ident}.result.json")
        attempt = read_json(folder / f"{ident}.attempt.json")
        assert record["attempt_count"] == attempt["attempt_count"] == 1, ident
        png = (root / unquote(entry["image"])).resolve()
        prompt = (root / unquote(entry["prompt"])).resolve()
        assert prompt.is_file() and len(prompt.read_text(encoding="utf-8")) > 600, ident
        digest = hashlib.sha256(png.read_bytes()).hexdigest()
        source = Path(record["source"])
        assert source.is_file() and digest == hashlib.sha256(source.read_bytes()).hexdigest(), ident
        with Image.open(png) as im:
            im.load()
            assert im.mode == "RGBA", ident
            extrema = im.getchannel("A").getextrema()
            assert extrema[0] == 0 and extrema[1] > 128, ident
            check = {
                "id": ident, "attempt_count": 1, "mode": im.mode,
                "size": list(im.size), "alpha_extrema": list(extrema),
                "sha256": digest, "matches_source": True,
                "png": entry["image"], "prompt": entry["prompt"],
            }
        checks.append(check)
        entry["validation"] = check
        entry["source"] = source.as_posix()
        review = record.get("review", {})
        entry["issues"] = review.get("issues", record.get("issues", [])) if isinstance(review, dict) else record.get("issues", [])
        entry["retry_prompt_mode"] = record.get("retry_prompt_mode") or ("recommended" if entry["status"] == "needs_retry" else "optional_not_required" if entry["retry_prompt"] else None)
    counts = dict(Counter(x["status"] for x in generated))
    recommended = [x for x in generated if x["status"] == "needs_retry"]
    optional = [x for x in generated if x["status"] == "candidate" and x["retry_prompt"]]
    assert all(x["retry_prompt"] and (root / unquote(x["retry_prompt"])).is_file() for x in recommended)
    manifest = {
        "date": "2026-11-07", "public_cards": len(entries), "new_images": len(generated),
        "new_image_statuses": counts, "scope_counts": dict(Counter(x["origin"] for x in entries)),
        "generation_calls_this_batch": len(checks), "each_image_generated_once": True,
        "automatic_retries": 0, "image_postprocessing_performed": False,
        "all_new_pngs_match_tool_sources": True, "runtime_assets_installed": False,
        "items": entries,
    }
    write_json(root / "catalog.json", manifest)
    write_json(root / "validation.json", {"passed": True, "checks": checks})
    write_json(root / "retry_requests.json", {
        "no_retries_executed": True,
        "instructions": "原图保持不动。仅在用户后续明确安排时用完整重试 prompt 尝试；本批不再调用生成器。",
        "recommended": recommended, "optional": optional,
    })
    lines = [
        "# 主图重试建议", "",
        "本批103张均只生成一次。以下重试提示词已保存，但没有执行重绘或清理原图。", "",
        "## 建议重新尝试", "",
        "这些项目存在可见内容、边缘或构图问题，建议后续交给用户指定的 high 推理强度模型。", "",
        "| 法术卡 | 问题 | 原图与提示词 |", "| --- | --- | --- |",
    ]
    for item in recommended:
        reason = "；".join(item["issues"] or item["qa"])
        links = f"[原图]({item['image']}) · [原始 prompt]({item['prompt']}) · [完整重试 prompt]({item['retry_prompt']})"
        lines.append(f"| {item['name']}（{item['id']}） | {reason.replace('|', '/')} | {links} |")
    lines += ["", "## 可选改善", "", "以下保持候选：部分预览彩边只在低 alpha 像素中，另有完整横画布可在接入时等比适配。它们不计入建议重绘数量；只有实际合成后仍不满意时才需要尝试。", ""]
    for item in optional:
        lines.append(f"- {item['name']}（{item['id']}）：[原图]({item['image']}) · [可选重试 prompt]({item['retry_prompt']})。详见[逐图检查]({item['result']})。")
    lines += ["", "## 使用方式", "", "重试文件包含完整的首次约束与定向修正，可直接交给下一次生成任务使用。若配有 reference 字段，参考图路径保存在该卡 result.json 中。建议将新结果另存为 attempt2，保留本轮 PNG 与记录，以便对比。", ""]
    (root / "RETRY_REQUESTS.md").write_text("\n".join(lines), encoding="utf-8")
    groups = Counter(x["group"] for x in generated)
    readme = f"""# 全量法术卡主图 v3

日期：2026-11-07。已完成本批 **{len(generated)}张新主图**，每张只生成一次，完整 prompt 与生成器原始 PNG 均在本地保存。没有自动重试、修图或清理 PNG。

- [打开本地总览](index.html)：182张公开法术卡，可按名称、组别和审核状态筛选；支持浅灰/白/深灰底和64px查看。
- [建议重试清单](RETRY_REQUESTS.md)：{len(recommended)}张建议重新尝试，另有{len(optional)}张可选改善提示词；本轮均未执行。
- [全量索引](catalog.json)：逐卡选图、prompt、来源、审核意见和校验信息。
- [原始范围](roster.json) / [保存校验](validation.json) / [统一提示词约束](common_prompt.txt)。

## 覆盖范围

公开卡共182张：61张原版武器/道具直用；6张已完成主图继续使用（火焰弹、冰霜弹、重能量球、旋斧攻击、长矛戳击、玻璃刀砍）；12张碰撞/定时变体共享六种基础弹主图；本批补齐其余103张。园艺锄沿用此前选定的原版动画主体。

| 新绘分组 | 数量 | 目录 |
| --- | ---: | --- |
| 投射物与施法控制 | {groups['projectiles_controls']} | [projectiles_controls](projectiles_controls) |
| 场地、召唤与光环 | {groups['fields']} | [fields](fields) |
| 通用法术修饰 | {groups['modifiers']} | [modifiers](modifiers) |
| 音乐、目标与辅助 | {groups['music_targets']} | [music_targets](music_targets) |

本批结果为 **{counts.get('candidate', 0)}张候选、{counts.get('needs_retry', 0)}张建议重试、0张生成失败**。候选表示初步视觉检查通过，仍需在正式卡框下确认缩放与小尺寸识别。

## 文件约定

每张卡保存 `id.prompt.txt`（完整首次提示词）、`id.png`（未经修改的工具输出）、`id.attempt.json`（调用前记录）、`id.result.json`（完成结果与审核）。`attempt.json` 的 started 是历史开始记录，最终状态以 result.json / catalog.json 为准。需要时另附 `id.retry.prompt.txt`，仅供后续尝试。

103张均核验透明 RGBA、文件可读取、prompt完整、每张尝试次数为1，并逐一核对 PNG 与生成器源文件的 SHA-256 一致。接近透明的 RGB 彩色残留与真正可见污染分别记录，没有因预览彩边自动重绘。

当前交付是主图素材与浏览索引；尚未替换游戏运行时卡牌资源。入框时以主体边界做等比缩放，完整放在卡框内部并尽量大。共享变体的碰撞/定时角标在卡牌合成层添加，不烘焙进主图。

## 更新索引

```powershell
python tools/finalize_spell_subject_catalog.py
python tools/build_spell_subject_gallery.py
```

以上命令在仓库根目录执行，只核验并生成索引，不调用生图器或修改图片。
"""
    (root / "README.md").write_text(readme, encoding="utf-8")
    print(json.dumps({"generated": len(generated), "counts": counts, "recommended_retries": len(recommended), "optional_retries": len(optional), "checks_passed": True}))


if __name__ == "__main__":
    main()
