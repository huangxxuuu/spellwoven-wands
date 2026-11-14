"""Render actual Lua beam_visual output against the compiled animation banks.

This is a mathematical camera projection of compiled mip0, not game footage.
It does not emulate GPU depth, mip selection/LOD, or lighting.
The same Lua regression harness supplies snapshots and interpolated positions.
"""
from __future__ import annotations

import json
import math
import argparse
import struct
import zipfile
from collections import defaultdict
from pathlib import Path

from lupa.lua51 import LuaRuntime, lua_type
from PIL import Image, ImageDraw

from build_end_beam_head import ROOT, PREVIEW, draw_material, load_compiled


def plain(value):
    if lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys and all(isinstance(k, (int, float)) for k in keys):
        return [plain(value[k]) for k in sorted(keys)]
    return {str(k): plain(value[k]) for k in keys}


def capture():
    samples = []
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT/"mod/scripts/?.lua").as_posix()+";"+vm.globals().package.path
    vm.globals()._BEAM_TRACE = lambda sample: samples.append(plain(sample))
    harness=(ROOT/"tests/test_beam_visual.lua").read_text(encoding="utf-8")
    marker="-- Empty, attached roots also detach during world shutdown, even with no task."
    assert harness.count(marker)==1
    fixture=(ROOT/"tests/fixtures/end_beam_motion.lua").read_text(encoding="utf-8")
    vm.execute(harness.replace(marker,fixture+"\n"+marker))
    assert samples, "beam regression harness did not export any motion frames"
    return samples


def project(dx, dy, dz, heading, pitch):
    """Match nw/electric_visual.project; angles are in radians."""
    c, s = math.cos(heading), math.sin(heading)
    return dz*c-dx*s, (dx*c+dz*s)*math.sin(pitch)-dy*math.cos(pitch)


def projected_basis(fx, heading, pitch, pixels_per_unit=120):
    """Map native animation XY into the entity's captured facing plane."""
    sx, sy = fx["sx"]*pixels_per_unit/150, fx["sy"]*pixels_per_unit/150
    angle = math.radians(-fx.get("rotation", 0))
    c, s = math.cos(angle), math.sin(angle)
    if fx["orientation"] == "BillBoard":
        # A billboard's vertical axis stays screen vertical at every pitch.
        return sx*c, sx*s, -sy*s, sy*c
    if fx["orientation"] != "OnGround":
        raise ValueError(f"Unsupported captured orientation: {fx['orientation']!r}")
    ux, uy = project(c, 0, s, heading, pitch)
    vx, vy = project(-s, 0, c, heading, pitch)
    return sx*ux, sx*uy, sy*vx, sy*vy


class SymbolFrame:
    """Supply atlas pixels with the quad's exact floating-point origin."""
    def __init__(self, image, origin):
        self.frame = image, origin

    def render_frame(self, clip, index):
        return self.frame


def compiled_quads(material, key, frame):
    """Read original BILD quads without symbol()'s integer-bound expansion."""
    if not hasattr(material,"preview_quad_cache"):
        material.preview_quad_cache = {}
    row = next(row for row in material.build["frames"][key] if row[0]<=frame<row[0]+row[1])
    cache_key = key,row[0]
    if cache_key not in material.preview_quad_cache:
        vertices = material.build["vertices"][row[6]:row[6]+row[7]]
        quads = []
        for index in range(0,len(vertices),6):
            quad = vertices[index:index+6]
            x0,y0 = min(v[0] for v in quad),min(v[1] for v in quad)
            x1,y1 = max(v[0] for v in quad),max(v[1] for v in quad)
            u0,v0 = min(v[3] for v in quad),min(v[4] for v in quad)
            u1,v1 = max(v[3] for v in quad),max(v[4] for v in quad)
            atlas = material.atlases[round(quad[0][5])]
            image = atlas.crop((round(u0*atlas.width),round((1-v1)*atlas.height),
                                round(u1*atlas.width),round((1-v0)*atlas.height)))
            for x,y,z,u,v,sampler in quad:
                assert abs((x-x0)/max(.001,x1-x0)-(u-u0)/max(1e-9,u1-u0))<.001
                assert abs((y-y0)/max(.001,y1-y0)-(v1-v)/max(1e-9,v1-v0))<.001
            quads.append((image,x0,y0,(x1-x0)/image.width,(y1-y0)/image.height))
        material.preview_quad_cache[cache_key] = quads
    return material.preview_quad_cache[cache_key]


def draw_compiled(canvas, material, animation, index, px, py, basis, opacity):
    # Fractional native lengths (the 18.75-unit micro clips) otherwise become
    # intermediate rasters with transparent rounded borders. Compose the
    # actual compiled element matrix directly to avoid artificial seam lines.
    a,b,c,d = basis
    elements = material.clip(animation)["frames"][index]["elements"]
    for key,frame,layer,ea,eb,ec,ed,tx,ty,depth in sorted(elements,key=lambda e:e[-1],reverse=True):
        if key not in material.build["frames"]:
            continue
        matrix = (a*ea+c*eb,b*ea+d*eb,a*ec+c*ed,b*ec+d*ed)
        ma,mb,mc,md = matrix
        for image,x0,y0,qx,qy in compiled_quads(material,key,frame):
            # Pixel (0,0) maps to the exact BILD corner, e.g. -10.5 rather
            # than -11 for a 21px micro source. Geometry is never inflated.
            draw_material(canvas,SymbolFrame(image,(0,0)),animation,index,
                          px+a*tx+c*ty+ma*x0+mc*y0,py+b*tx+d*ty+mb*x0+md*y0,1,1,
                          opacity=opacity,matrix=(ma*qx,mb*qx,mc*qy,md*qy))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,default=PREVIEW)
    parser.add_argument("--camera-pitch",type=float,default=35,
                        help="DST camera pitch in degrees (default: 35)")
    parser.add_argument("--camera-heading",type=float,default=-90,
                        help="DST camera heading in degrees; -90 puts +X screen right")
    args=parser.parse_args()
    pitch, heading = math.radians(args.camera_pitch), math.radians(args.camera_heading)
    output=args.output_dir
    samples = capture()
    output.mkdir(parents=True,exist_ok=True)
    (output/"runtime-trace.json").write_text(json.dumps(samples,indent=2)+"\n",encoding="utf-8")
    banks = {name:load_compiled(name) for name in ("nw_end_beam","nw_end_beam_head")}
    texture_mips = {}
    for name in banks:
        with zipfile.ZipFile(ROOT/f"mod/anim/{name}.zip") as archive:
            texture_mips[name] = {
                member: (struct.unpack_from("<I",archive.read(member),4)[0] >> 13) & 31
                for member in archive.namelist() if member.endswith(".tex")}
    single_mip = all(levels == 1 for textures in texture_mips.values() for levels in textures.values())
    groups = defaultdict(list)
    for sample in samples:
        groups[sample["kind"]].append(sample)
    for kind, points in groups.items():
        frames = []
        for point in points:
            canvas = Image.new("RGBA",(1000,380),"#353d37")
            label=ImageDraw.Draw(canvas)
            label.text((20,14),f"Actual Lua renderer trace / {kind} / frame {len(frames):02d}",fill="#ede1cc")
            label.text((20,32),f"Camera pitch {args.camera_pitch:g} / heading {args.camera_heading:g} deg; 120 px/world unit",fill="#b8bcb5")
            planes = sorted({(fx["finaloffset"],fx["orientation"]) for fx in point["fx"]})
            label.text((20,50),"Captured FinalOffset/facing: "+"; ".join(f"{offset:g} {plane}" for offset,plane in planes),fill="#b8bcb5")
            head_rates = sorted({fx.get("rate",1) for fx in point["fx"] if fx["role"] == "head"})
            label.text((20,68),"16 native micro clips/span; captured overlap; star rate: "+", ".join(f"{rate:g}x" for rate in head_rates),fill="#b8bcb5")
            label.text((20,312),"Texture archive: "+("single mip0, lower mips removed" if single_mip else "multiple mip levels present"),fill="#b8bcb5")
            label.text((20,330),"30 Hz movement + 10 Hz snapshots; mathematical projection + compiled mip0",fill="#b8bcb5")
            label.text((20,350),"Offline preview, not game footage; no GPU depth, mip/LOD selection, or lighting",fill="#b8bcb5")
            for fx in sorted(point["fx"],key=lambda f:(f["finaloffset"],f.get("id",0))):
                if fx.get("hidden") or fx["sx"]<=0 or fx["sy"]<=0:
                    continue
                material=banks[fx["bank"]]
                clip=material.clip(fx["animation"])
                elapsed=fx["time"]+(point["now"]-fx["timeset"])*fx.get("rate",1)
                index=math.floor(elapsed*clip["fps"]+1e-7)%len(clip["frames"])
                # Camera tracks the captured head height, not just ground X/Z.
                dx,dy=project(fx["x"]-point["x"],fx["y"]-point["y"],
                              fx["z"]-point["z"],heading,pitch)
                px,py=760+dx*120,190+dy*120
                draw_compiled(canvas,material,fx["animation"],index,px,py,
                              projected_basis(fx,heading,pitch),fx.get("alpha",1))
            frames.append(canvas.convert("RGB"))
        frames[0].save(output/f"motion-{kind}.gif",save_all=True,append_images=frames[1:],
                       duration=[33,33,34]*(len(frames)//3)+[33]*(len(frames)%3),loop=0,disposal=2)
        board=Image.new("RGB",(1000,380*6),"#353d37")
        indices=(0,24,45,60,68,78) if kind=="terminal" else (0,12,24,36,48,60) if kind=="gentle-curve" else (0,10,20,30,40,len(frames)-1)
        for row,index in enumerate(indices):
            board.paste(frames[index],(0,row*380))
        board.save(output/f"motion-{kind}-contact.png")
    (output/"README.txt").write_text(
        f"Camera pitch: {args.camera_pitch:g} degrees; heading: {args.camera_heading:g} degrees.\n"
        "Projection matches nw/electric_visual.project; camera tracks captured head XYZ.\n"
        "OnGround sprite axes use projected ground X/Z; BillBoard axes stay screen XY.\n"
        "Draw order uses captured actual FinalOffset, then entity id.\n"
        "Captured sortoffset is recorded, but GPU world/depth sorting is not simulated.\n"
        "Animation time advances using captured playback rate; 16 micro clips/span retain native dimensions.\n"
        "Captured quad transforms include overlap; terminal beam/connector outer endpoints are asserted.\n"
        "Gentle-curve scenario changes heading smoothly, peaking at 9.9 degrees per logical span.\n"
        "Compiled element matrices project atlas UV quads at exact floating-point BILD boundaries.\n"
        "No intermediate integer raster: a 21px micro source stays 21px / 18.75 native units, not 22px.\n"
        f"Single mip0 texture archives (lower mip levels removed): {single_mip}.\n"
        "Compiled animation mip0 only, resampled by Pillow; mathematical preview, not game footage.\n"
        "No actual GPU depth, mip/LOD selection, lighting, or multiplayer verification.\n"
        "This preview cannot establish a fix for short-span mip sampling blur.\n",
        encoding="utf-8")
    (output/"manifest.json").write_text(json.dumps({
        "camera_pitch_degrees": args.camera_pitch,
        "camera_heading_degrees": args.camera_heading,
        "pixels_per_world_unit": 120,
        "projection": "nw/electric_visual.project mathematical projection",
        "material": "compiled mip0 atlas UV quads at exact float BILD boundaries; composed element/camera matrices; Pillow sampling",
        "offline_geometry_correction": "avoid integer symbol raster expansion of odd 21px sources to 22px; preserve native 18.75 units",
        "texture_mip_levels": texture_mips,
        "lower_mip_levels_removed": single_mip,
        "animation_time": "time + (now - timeset) * captured rate",
        "micro_clips_per_span": 16,
        "micro_native_length": 18.75,
        "overlap": "captured runtime quad transforms, no preview-only enlargement",
        "gentle_curve": "S bend; heading = 55*sin(frame*0.18) degrees; peak adjacent change 9.9 degrees",
        "star_rates": sorted({fx.get("rate",1) for sample in samples for fx in sample["fx"] if fx["role"] == "head"}),
        "beam_clips": sorted({fx["animation"] for sample in samples for fx in sample["fx"] if fx["bank"] == "nw_end_beam"}),
        "layer_order": "captured actual FinalOffset, then entity id",
        "trace_frames": len(samples),
        "scenarios": {k:len(v) for k,v in groups.items()},
        "engine_verified": False,
        "limitations": ["no GPU depth or world sorting / sortoffset simulation", "no mip/LOD selection", "no lighting",
                        "cannot establish short-span mip blur fix"],
    },indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"trace_frames":len(samples),"scenarios":{k:len(v) for k,v in groups.items()}}))


if __name__ == "__main__":
    main()
