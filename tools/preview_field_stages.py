"""Offline review of the actual field XML and production local-member module.

Field phase inputs follow gameplay deadlines. The independent mushrooms,
glow motes and shields run the production Lua world-coordinate scheduler.
"""
from __future__ import annotations

import argparse
import math
from functools import lru_cache

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw

from build_field_stages import BANK, KINDS, ROOT, build_bank
from native_animation import NativeAnimation
from preview_basic_flight import BG, FONT, INK, MOCK_RUNTIME, PROJECTION, SMALL
from preview_insect_motion import SWARM_ADAPTER

OUT = ROOT / "docs/previews/field-stages-v1"
LABELS = {key: key.replace("_", " ").upper() for key in KINDS}


class Review:
    def __init__(self):
        self.bank = build_bank()
        self.animations = {clip.get("name"): clip for clip in self.bank.animations}
        self.shadow = NativeAnimation("meteor_shadow")

    @lru_cache(maxsize=2000)
    def frame(self, clip, index):
        root = self.animations[clip]
        pose = root[index % len(root)]
        if not len(pose):
            return Image.new("RGBA", (1, 1)), (0, 0)
        left = math.floor(float(pose.get("x")) - float(pose.get("w"))/2)
        top = math.floor(float(pose.get("y")) - float(pose.get("h"))/2)
        size = (math.ceil(float(pose.get("w")))+1, math.ceil(float(pose.get("h")))+1)
        image = Image.new("RGBA", size)
        for part in pose:
            key = part.get("name")
            source = self.bank.images[f"{key}_{part.get('frame')}"]
            a, b, c, d, x, y = [float(part.get("m_"+name)) for name in ("a", "b", "c", "d", "tx", "ty")]
            det = a*d-b*c
            transform = (d/det, -c/det, (d*(left-x)-c*(top-y))/det+source.width/2,
                         -b/det, a/det, (-b*(left-x)+a*(top-y))/det+source.height/2)
            image.alpha_composite(source.transform(size, Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC))
        if clip.startswith(("vortex_", "shock_ring_")):
            # These two clips are now actual OnGround circles. Apply the fixed
            # review camera's projection after their production transforms.
            image = image.resize((image.width, max(1, round(image.height*PROJECTION))), Image.Resampling.LANCZOS)
            top *= PROJECTION
        return image, (left, top)

    def stamp(self, canvas, clip, time, anchor, scale=1, alpha=1):
        metadata = self.bank.clips[clip]
        index = int(time*metadata["fps"])
        if metadata["loop"]:
            index %= len(metadata["poses"])
        else:
            index = min(len(metadata["poses"])-1, max(0, index))
        image, offset = self.frame(clip, index)
        if alpha < 1:
            image = image.copy()
            image.putalpha(image.getchannel("A").point(lambda a: round(a*alpha)))
        image = image.resize((max(1, round(image.width*scale)), max(1, round(image.height*scale))), Image.Resampling.LANCZOS)
        canvas.alpha_composite(image, (round(anchor[0]+offset[0]*scale), round(anchor[1]+offset[1]*scale)))

    def moon_shadow(self, canvas, anchor, scale):
        image, _ = self.shadow.render_frame("idle", 0)
        width = 2*2*.6*150*scale
        image = image.resize((max(1, round(width)), max(1, round(width*PROJECTION))), Image.Resampling.LANCZOS)
        image.putalpha(image.getchannel("A").point(lambda a: round(a*.45)))
        canvas.alpha_composite(image, (round(anchor[0]-image.width/2), round(anchor[1]-image.height/2)))


def footprint_scale(kind):
    return {"moon_fall": 2*2*150*.6/100, "shock_ring": 2*2*150/191,
            "vortex": 2*2.5*150/220, "deer_decoy": 2}.get(kind, 1)


def save_gif(frames, name, fps=15):
    frames[0].convert("RGB").save(OUT/name, save_all=True,
                                  append_images=[frame.convert("RGB") for frame in frames[1:]],
                                  duration=round(1000/fps), loop=0, disposal=2)


def stage_sheet(review):
    # Member rings are reviewed in world space below; this sheet deliberately
    # shows their single members rather than pretending an atlas is a ring.
    for page in range(3):
        kinds = KINDS[page*5:(page+1)*5]
        canvas = Image.new("RGBA", (1680, 110+len(kinds)*300), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((20, 15), "FIELD STAGES - production component art / NORMAL and GIANT x2.5", font=FONT, fill=INK)
        draw.text((20, 45), "Runtime footprint scales; native moon shadow; spirit deer body and spin use the actual compiled clips.", font=SMALL, fill=INK)
        for row, kind in enumerate(kinds):
            top = 88+row*300
            draw.line((20, top-6, 1660, top-6), fill=(70, 79, 83))
            label = LABELS[kind]
            if kind in ("guard_ring", "vital_ring"):
                label += " / SINGLE WORLD MEMBER"
            draw.text((20, top), label, font=FONT, fill=(176, 215, 200))
            for column, phase in enumerate(("spawn", "idle", "pulse", "end")):
                cx = 210+column*415
                draw.text((cx-160, top+30), phase.upper(), font=SMALL, fill=INK)
                clip = kind+"_"+phase
                if kind in ("guard_ring", "vital_ring"):
                    clip = ("guard" if kind=="guard_ring" else "vital")+"_member_"+phase
                if kind=="spore_sentry":
                    clip = "spore_"+{"spawn":"grow", "idle":"idle", "pulse":"fire", "end":"wilt"}[phase]
                if kind=="moon_fall" and phase=="pulse":
                    clip = "moon_fall_fall"
                    draw.text((cx-160, top+50), "ONE FALL, BEFORE 0.8 s DEADLINE", font=SMALL, fill=(188, 188, 194))
                seconds = review.bank.clips[clip]["seconds"]
                when = seconds*.55 if phase!="idle" else .5
                scale = .20 if kind in ("rain_cloud", "storm_cloud") else .15 if kind in ("moon_fall", "shock_ring", "vortex") else .30 if kind=="deer_decoy" else .48
                if kind=="guard_ring":
                    scale *= 2
                for factor, ax in ((1, cx-80), (2.5, cx+85)):
                    anchor = (ax, top+(185 if kind in ("guard_ring", "shock_ring", "vortex") else 240))
                    draw.line((ax-8, anchor[1], ax+8, anchor[1]), fill=(100, 112, 115))
                    if kind=="moon_fall" and phase!="end":
                        review.moon_shadow(canvas, anchor, scale*factor)
                    review.stamp(canvas, clip, when, anchor, scale*factor*footprint_scale(kind))
                    draw.text((ax-23, top+267), "x1" if factor==1 else "x2.5", font=SMALL, fill=INK)
        canvas.convert("RGB").save(OUT/f"stages-{page+1}.png")


def field_timeline(kind, now):
    """Only test scenario/event inputs live here; render clips remain production."""
    ends = {"moon_fall": .8, "delay_seal": .75, "detonate": .22, "vortex": .4,
            "storm_cloud": 2.55, "rain_cloud": 3, "shock_ring": 2, "deer_decoy": 3,
            "crystal_mine": 2.3, "sleep_crystal": 2.3, "payload_egg": 2.3, "spore_sentry": 3}
    end = ends[kind]
    if now >= end:
        return ("spore_wilt" if kind=="spore_sentry" else kind+"_end", now-end, now < end+(.5 if kind=="deer_decoy" else .3))
    if kind=="spore_sentry":
        if now < .6: return "spore_grow", now, True
        for start in (1, 1.9, 2.6):
            if start <= now < start+.4: return "spore_fire", now-start, True
        return "spore_idle", now, True
    if kind=="moon_fall":
        return (kind+"_fall", now-.56, True) if now >= .56 else (kind+"_warning", now, True)
    if now < .2:
        return kind+"_spawn", now, True
    pulses = {"rain_cloud": (.3, 1.8), "storm_cloud": (.8, 1.6, 2.4), "shock_ring": (.85, 1.85)}
    for at in pulses.get(kind, ()):
        if at <= now < at+.2:
            return kind+"_pulse", now-at, True
        if kind=="storm_cloud" and at-.3 <= now < at:
            return kind+"_warning", now-(at-.3), True
    return kind+"_idle", now, True


MEMBER_ADAPTER = r'''
local make_field=...
local timers={}
local original_update=preview_harness.update
local original_time=GetTime
local original_create=CreateEntity
local wall_entities={}
local last_time=0
TheSim={GetTimeScale=function() return 1 end}
TheNet.IsServerPaused=function() return false end
-- Match the game's quantized simulation clock. Orbit interpolation must come
-- from the actual production wall callback, not a smoother mock GetTime().
GetTime=function() return math.floor(original_time()*30+.000001)/30 end
function CreateEntity()
    local e=original_create()
    e.components={}
    function e:AddComponent(name)
        assert(name=="updatelooper")
        local component={wallfns={}}
        function component:AddOnWallUpdateFn(fn) self.wallfns[fn]=true;wall_entities[e]=true end
        function component:RemoveOnWallUpdateFn(fn) self.wallfns[fn]=nil end
        self.components[name]=component
        return component
    end
    local remove=e.Remove
    function e:Remove()
        remove(self)
        wall_entities[self]=nil
        if self.components.updatelooper then self.components.updatelooper.wallfns={} end
    end
    return e
end
local function wallframe(dt)
    if TheNet:IsServerPaused() then return end
    local entities={};for e in pairs(wall_entities) do entities[#entities+1]=e end
    for _,e in ipairs(entities) do
        if e:IsValid() then
            local fns={}
            for fn in pairs(e.components.updatelooper.wallfns) do fns[#fns+1]=fn end
            for _,fn in ipairs(fns) do if e:IsValid() then fn(e,dt) end end
        end
    end
end
local function net()
    local n={v=0}
    function n:value() return self.v end
    function n:set(value) self.v=value end
    return n
end
net_float=net;net_tinybyte=net;net_ushortint=net;net_smallbyte=net
local function anchor(guid)
    local e=make_field(guid,1,0,0,0)
    function e:DoTaskInTime(delay,fn)
        local task={at=GetTime()+delay,fn=fn,owner=e}
        function task:Cancel() self.cancelled=true end
        timers[#timers+1]=task
        return task
    end
    return e
end
function SpawnPrefab(name)
    local e=anchor(199)
    local id=name=="nw_guard_stage_fx" and "guard_ring" or "vital_ring"
    preview_stages.setup(e,id);preview_stages.attach(e,id)
    function e:SetStage(id,phase,size,radius,count,age,seed)
        preview_stages.effect_state(e,id,phase,size,radius,count,age,seed)
        self:DoTaskInTime(.3,self.Remove)
    end
    return e
end
local function step(now,dt)
        original_update(now)
        for i=#timers,1,-1 do
            local task=timers[i]
            if task.at<=now+.00001 then
                table.remove(timers,i)
                if not task.cancelled and task.owner:IsValid() then task.fn(task.owner) end
            end
        end
        wallframe(dt)
end
return {
    anchor=anchor,
    update=function(now)
        -- Render output may be 15 fps, but every member is simulated through
        -- the real 60 Hz wall callback and its scaled-dt visual clock.
        while last_time+1/60<now-.000001 do
            local next_time=last_time+1/60
            step(next_time,next_time-last_time);last_time=next_time
        end
        step(now,math.max(0,now-last_time));last_time=now
    end,
}
'''


class MemberScene:
    def __init__(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().package.path = str(ROOT/"mod/scripts/?.lua").replace("\\", "/")+";"+self.lua.globals().package.path
        self.harness = self.lua.execute(MOCK_RUNTIME)
        self.lua.globals().preview_harness = self.harness
        make_field = self.lua.execute(SWARM_ADAPTER)
        self.stages = self.lua.eval('require("nw/field_stages")')
        self.lua.globals().preview_stages = self.stages
        self.adapter = self.lua.execute(MEMBER_ADAPTER, make_field)
        self.fields = []
        for row, kind in enumerate(("guard_ring", "vital_ring")):
            for factor in (1, 2.5):
                field = self.adapter.anchor(len(self.fields)+30)
                radius = (2.5 if kind=="guard_ring" else 3)*factor
                self.stages.setup(field, kind)
                self.stages.attach(field, kind)
                self.stages.start(field, kind, self.lua.table_from({"size_mult": factor, "radius": radius}), False)
                self.fields.append((kind, factor, field, {"pulse": 0, "consumed": False}))

    def snapshot(self, now):
        self.adapter.update(now)
        for kind, factor, field, flags in self.fields:
            if not field.valid:
                continue
            if kind=="guard_ring" and now>=1.1 and not flags["consumed"]:
                self.stages.guard(field, 1)
                flags["consumed"] = True
            if kind=="vital_ring" and 1<=now<3.1 and int(now)>flags["pulse"]:
                self.stages.pulse(field)
                flags["pulse"] = int(now)
            end = 2 if kind=="guard_ring" else 3.1
            if now>=end:
                self.stages.finish(field)
                field.Remove(field)
        self.adapter.update(now)
        result = []
        pool = self.lua.globals().TheWorld._nw_field_members
        if pool:
            for state in pool.fields.values():
                members = []
                for part in state.members.values():
                    fx = part.fx
                    if fx.valid and fx.visible:
                        age = fx.clock+(now-fx.clock_start)*fx.playback
                        members.append({"x":fx.x, "y":fx.y, "z":fx.z, "scale":fx.sx,"index":part.index,"kind":part.kind,
                                        "alpha":fx.alpha, "clip":fx.anim, "age":age})
                result.append({"kind":state.id, "size":state.size, "members":members})
        return result


def member_preview(review):
    scene = MemberScene()
    frames = []
    for index in range(53):
        now = index/15
        canvas = Image.new("RGBA", (1500, 1020), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((20, 16), f"INDEPENDENT WORLD MEMBERS - production Lua / {now:.2f} s", font=FONT, fill=INK)
        draw.text((20, 47), "Wall-update shields, one consumed at 1.1 s; mushrooms: 8 large + 12 small fixed feet + 6 motes; heal at 1/2/3 s.", font=SMALL, fill=INK)
        for row, kind in enumerate(("guard_ring", "vital_ring")):
            for factor, cx in ((1, 370), (2.5, 1120)):
                origin = (cx, 315+row*480)
                draw.text((cx-160, origin[1]-220), f"{LABELS[kind]} / x{factor:g}", font=FONT, fill=INK)
                view = .25
                radius = (2.5 if kind=="guard_ring" else 3)*factor*150*view
                draw.ellipse((cx-radius, origin[1]-radius*PROJECTION, cx+radius, origin[1]+radius*PROJECTION),
                             outline=(74, 87, 91), width=1)
                draw.line((cx-5, origin[1], cx+5, origin[1]), fill=(100, 120, 123))
        states = scene.snapshot(now)
        for state in states:
            row = 0 if state["kind"]=="guard_ring" else 1
            origin = (370 if state["size"]<2 else 1120, 315+row*480)
            view = .25
            for part in sorted(state["members"], key=lambda p:p["z"]):
                pos = (origin[0]+part["x"]*150*view,
                       origin[1]+part["z"]*150*view*PROJECTION-part["y"]*150*view)
                review.stamp(canvas, part["clip"], part["age"], pos, part["scale"]*view, part["alpha"])
        frames.append(canvas)
    save_gif(frames, "members.gif")
    frames[23].convert("RGB").save(OUT/"members.png")
    frames[16].convert("RGB").save(OUT/"members-heal.png")


def member_camera_review(review):
    scene = MemberScene()
    states = None
    for index in range(25):
        states = scene.snapshot(index/30)
    canvas = Image.new("RGBA", (1600, 1230), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 15), "SAME WORLD MEMBERS, TWO CAMERAS - fixed feet / individual Billboard sprites", font=FONT, fill=INK)
    draw.text((20, 46), "Production Lua positions at 0.80 s, before shield consumption. Numbers identify the same mushroom across views.", font=SMALL, fill=INK)
    for camera, cx in ((0, 400), (60, 1200)):
        theta = math.radians(camera)
        draw.text((cx-100, 81), f"CAMERA {camera} DEGREES", font=FONT, fill=INK)
        for row, (kind, factor) in enumerate((("guard_ring", 1), ("guard_ring", 2.5), ("vital_ring", 1), ("vital_ring", 2.5))):
            origin = (cx, 230+row*275)
            view = .22
            draw.text((cx-365, origin[1]-90), f"{LABELS[kind]} x{factor:g}", font=SMALL, fill=INK)
            state = next(s for s in states if s["kind"]==kind and s["size"]==factor)
            projected = []
            for part in state["members"]:
                x = part["x"]*math.cos(theta)-part["z"]*math.sin(theta)
                z = part["x"]*math.sin(theta)+part["z"]*math.cos(theta)
                projected.append((z, part, x))
            for z, part, x in sorted(projected, key=lambda row:row[0]):
                pos = (origin[0]+x*150*view, origin[1]+z*150*view*PROJECTION-part["y"]*150*view)
                review.stamp(canvas, part["clip"], part["age"], pos, part["scale"]*view, part["alpha"])
                if part["kind"]=="vital":
                    draw.text((pos[0]-4, pos[1]+3), str(part["index"]), font=SMALL, fill=(153, 176, 167))
    canvas.convert("RGB").save(OUT/"members-cameras.png")


def lifecycle_preview(review):
    kinds = [kind for kind in KINDS if kind not in ("guard_ring", "vital_ring")]
    for page in range(3):
        subset = kinds[page*4:(page+1)*4]
        frames = []
        for index in range(53):
            now = index/15
            canvas = Image.new("RGBA", (1420, 85+len(subset)*330), BG)
            draw = ImageDraw.Draw(canvas)
            draw.text((20, 16), f"FIELD LIFECYCLES - x1 / x2.5, real event deadlines / {now:.2f} s", font=FONT, fill=INK)
            draw.text((20, 45), "Permanent crystals/egg are manually triggered at 2.3 s for this preview; they have no expiry timer.", font=SMALL, fill=INK)
            for row, kind in enumerate(subset):
                top = 85+row*330
                draw.line((20, top, 1400, top), fill=(61, 75, 79))
                draw.text((20, top+8), LABELS[kind], font=FONT, fill=(176, 215, 200))
                clip, age, active = field_timeline(kind, now)
                scale = .24 if kind in ("rain_cloud", "storm_cloud") else .14 if kind=="moon_fall" else .37 if kind=="deer_decoy" else .20 if kind in ("shock_ring", "vortex") else .65
                for factor, x in ((1, 450), (2.5, 1090)):
                    anchor = (x, top+275)
                    draw.line((x-30, anchor[1], x+30, anchor[1]), fill=(89, 107, 109))
                    if active:
                        if kind=="moon_fall" and now<.8:
                            review.moon_shadow(canvas, anchor, scale*factor)
                        review.stamp(canvas, clip, age, anchor, scale*factor*footprint_scale(kind))
                    draw.text((x-90, top+305), f"x{factor:g} / {clip.rsplit('_',1)[-1]}", font=SMALL, fill=INK)
            frames.append(canvas)
        save_gif(frames, f"lifecycle-{page+1}.gif")
        frames[11].convert("RGB").save(OUT/f"lifecycle-{page+1}.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--members-only", action="store_true", help="Refresh only the independent shield/mushroom previews")
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    review = Review()
    if not args.members_only:
        stage_sheet(review)
    member_preview(review)
    member_camera_review(review)
    if not args.members_only:
        lifecycle_preview(review)
    print(f"Saved stage sheets and lifecycle/member previews to {OUT}")


if __name__=="__main__":
    main()
