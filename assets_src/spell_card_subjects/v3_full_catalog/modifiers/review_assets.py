"""Record the first-pass visual review. Read PNGs only; never edit or generate art."""
import hashlib
import json
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
NOTES = {
    "speed_up": "魔弹与两条加速笔触清楚。",
    "speed_down": "前方阻力弧线表达减速；小尺寸时需与声波类区分。",
    "damage_up": "魔弹与粗上箭头表达伤害提升。",
    "precision": "三条线路收束到同一瞄准点。",
    "sine": "双波峰波谷形成正弦线路；构图较宽，入框时统一等比缩放。",
    "spiral": "连续螺旋围绕前进轴，能与正弦弹道区分。",
    "homing": "长弯曲路线和敌方目标明确，附推进笔触。",
    "bounce": "完整墙面与入射、反射路径表达反弹。",
    "pierce": "同一路径贯穿三个目标。",
    "explosion": "橙白实心爆裂形状清楚，无铺底烟云。",
    "knockback": "魔弹、木靶与推离箭头能表达击退，但冲击边缘出现半透明雾。",
    "orbit": "施法者剪影与环绕的单条椭圆弹道。",
    "pierce_all": "四个目标与无穷符号表达持续穿透。",
    "phase_wall": "完整墙体与贯穿轨迹，局部透明用于穿墙表达。",
    "heavy_shot": "石壳、紫芯与下压箭头表达沉重一击；红色杂边只存在 alpha<8 区域。",
    "wild_charge": "法杖、三条散开弹道与回充箭头表达散放快充。",
    "long_life": "上半部剩余沙量较多，长箭头表达续航。",
    "reverse_path": "U形折返线路表达向原方向返回。",
    "return_path": "弯曲回路终止于施法者，和固定折返区分。",
    "light_shot": "羽毛与轻型魔弹清楚；青绿色高饱和边缘残留仅在 alpha<8 区域。",
    "accelerate": "沿同一直线的三个位置逐渐拉开间距；位置影像也被画成逐渐增大，需结合牌名避免误读巨化。",
    "melee_mark": "短刃、缺口和弱点目标表达近战破绽。",
    "harmless": "空心载体包裹紫色能量点。",
    "near_homing": "短而紧的弯曲路径指向近处目标，保留推进笔触。",
    "crit_rune": "晶石上的红色切口与白色冲击形状表达暴击。",
    "giant_shot": "相同菱形魔弹从小到大，膨胀箭头清楚。",
    "short_life": "沙量集中下部，短轨迹逐段消散。",
    "homing_rotate": "弹头转向目标的角度变化，没有持续推进尾焰。",
}


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    rows = []
    for ident, note in NOTES.items():
        path = ROOT / f"{ident}.result.json"
        row = json.loads(path.read_text(encoding="utf-8"))
        image_path = ROOT / f"{ident}.png"
        with Image.open(image_path) as im:
            assert im.mode == "RGBA"
            arr = np.asarray(im)
            alpha = arr[:, :, 3]
            bounds = Image.fromarray(np.where(alpha >= 8, 255, 0).astype("uint8")).getbbox()
            edge = np.concatenate([alpha[0], alpha[-1], alpha[:, 0], alpha[:, -1]])
            digest = hashlib.sha256(image_path.read_bytes()).hexdigest()
            validation = {
                "mode": im.mode,
                "size": list(im.size),
                "alpha_extrema": [int(alpha.min()), int(alpha.max())],
                "bbox_alpha8": list(bounds),
                "visible_edge_pixels": int(np.count_nonzero(edge >= 8)),
                "minimum_visible_margin_px": min(bounds[0], bounds[1], im.width - bounds[2], im.height - bounds[3]),
                "sha256": digest,
                "matches_source": digest == hashlib.sha256(Path(row["source"]).read_bytes()).hexdigest(),
            }
        assert validation["matches_source"] and row["attempt_count"] == 1
        issues = []
        if ident == "knockback":
            issues.append("冲击尖角之间出现带颗粒的半透明青灰雾，边界不够干净，不符合仅用实心运动笔触的要求。")
            retry = (ROOT / f"{ident}.prompt.txt").read_text(encoding="utf-8")
            retry += "\n下一次尝试的重点修正（本轮未执行）：\n保留单枚魔弹、被推离的木制练习靶及向右箭头的概念。魔弹外侧仅画三到五个边界清晰、完全实心的青白冲击尖角，尖角之间必须是完全透明的空隙。彻底取消外发光、柔光、灰雾、烟尘、半透明晕圈、颗粒和喷溅。仅物体边缘可有一至两像素正常抗锯齿。用轮廓与实心色块表达受击，确保所有主体完整，四边留足10%透明空白。\n"
            (ROOT / f"{ident}.retry.prompt.txt").write_text(retry, encoding="utf-8")
            row["retry_prompt"] = f"{ident}.retry.prompt.txt"
        notes = [note]
        if validation["minimum_visible_margin_px"] < 100:
            notes.append("生成图安全留白偏紧，但可见主体未触边；接入卡牌时按主体边界等比缩小至卡框内部。")
        row.update(
            status="needs_retry" if issues else "candidate",
            output=f"{ident}.png",
            review={"visual_checked": True, "issues": issues, "notes": notes, "card_frame_fitting_required": True},
            validation=validation,
            raw_png_modified=False,
        )
        row.pop("visual_review", None)
        dump(path, row)
        rows.append(row)
    dump(ROOT.parent / "modifiers_summary.json", {
        "group": "modifiers", "requested": 28, "generated": len(rows),
        "counts": dict(Counter(row["status"] for row in rows)),
        "each_attempted_once": True, "raw_png_modified": False,
        "items": rows,
    })
    print(json.dumps({"reviewed": len(rows), "counts": dict(Counter(row["status"] for row in rows))}))


if __name__ == "__main__":
    main()
