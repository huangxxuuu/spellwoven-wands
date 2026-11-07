"""Review visual size changes and upright insects using production transforms.

The resident-swarm adapter below executes the production Lua module. Images
are offline renderings of runtime sprites, not captures of the DST client.
"""
from __future__ import annotations

import math

from PIL import Image, ImageDraw

from build_elemental_flight import BANK, DISPLAY_SIZES, ROOT, RUNTIME
from preview_special_flight import COLORS, LABELS, OUT, SpecialReview, lua_environment
from preview_basic_flight import BG, FONT, INK, MOCK_RUNTIME, PROJECTION, SMALL

SIZE_FACTORS = {"slime": 1.5, "tri_electric": 1.5, "soundwave": 1.5, "land_hook": 2.8}

SWARM_ADAPTER = r'''
local original_create=CreateEntity
local function events(entity)
    entity.listeners={}
    function entity:ListenForEvent(name,fn,source)
        source=source or self
        source.listeners[name]=source.listeners[name] or {}
        source.listeners[name][fn]=true
    end
    function entity:RemoveEventCallback(name,fn,source)
        source=source or self
        if source.listeners[name] then source.listeners[name][fn]=nil end
    end
    function entity:PushEvent(name,data)
        local callbacks={}
        for callback in pairs(self.listeners[name] or {}) do callbacks[#callbacks+1]=callback end
        for _,callback in ipairs(callbacks) do callback(self,data) end
    end
end
function CreateEntity()
    local entity=original_create()
    events(entity)
    entity.Show=function() entity.visible=true end
    entity.entity.GetWorldPosition=function() return entity.x,entity.y,entity.z end
    entity.entity.GetParent=function() return nil end
    function entity:Remove()
        if not self.valid then return end
        self.valid=false
        self:PushEvent("onremove")
    end
    return entity
end
events(TheWorld)
return function(guid,scale,x,y,z)
    local field=CreateEntity()
    field.GUID,field.scale=guid,scale
    field.Transform:SetPosition(x,y,z)
    field._nw_insect_size={value=function() return field.scale end}
    return field
end
'''


class SwarmScene:
    """Run insect_swarm_visual.lua; Python only supplies the field anchors."""

    def __init__(self):
        self.lua = lua_environment()
        self.harness = self.lua.execute(MOCK_RUNTIME)
        self.make_field = self.lua.execute(SWARM_ADAPTER)
        flight = self.lua.execute((ROOT / "mod/scripts/nw/elemental_flight.lua").read_text(encoding="utf8"))
        self.lua.globals().preview_flight = flight
        self.lua.execute('package.loaded["nw/elemental_flight"]=preview_flight')
        self.swarm = self.lua.execute((ROOT / "mod/scripts/nw/insect_swarm_visual.lua").read_text(encoding="utf8"))
        self.fields = []
        for index, kind in enumerate(("bee_swarm", "fireflies")):
            x, y, z = self.anchor(kind, 0)
            field = self.make_field(41 + index, 1, x, y, z)
            state = self.swarm.attach(field, kind)
            self.fields.append((kind, field, state))

    @staticmethod
    def anchor(kind, now):
        if kind == "bee_swarm":
            return 0, 0, 0
        # Illustrative motion of the owner anchor only. Member orbits, bob,
        # headings and animation phases all come from the production module.
        return .2 * math.sin(now * .9), 1, .35 * math.sin(now * .7)

    def snapshot(self, now):
        for kind, field, _ in self.fields:
            field.Transform.SetPosition(field.Transform, *self.anchor(kind, now))
            if now >= 2.6 and field.valid:
                field.Remove(field)
        self.harness.update(now)
        result = []
        for kind, field, state in self.fields:
            members = []
            for member in state.members.values():
                fx = member.fx
                if fx.valid and fx.visible:
                    members.append({"x": fx.x, "y": fx.y, "z": fx.z, "scale": fx.sx,
                                    "direction": int(member.direction),
                                    "frame": min(5, int(self.harness.clock(fx) * 30))})
            result.append({"kind": kind, "anchor": (field.x, field.y, field.z), "members": members,
                           "alive": field.valid})
        return result


def actual_bounds(review, kind, group="head", frame=0):
    sprite = review.art[kind, group, frame]
    box = sprite.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    if not box:
        return 0, 0
    width, height = DISPLAY_SIZES[kind][group]
    return (box[2] - box[0]) * width / sprite.width, (box[3] - box[1]) * height / sprite.height


def size_review(review):
    # Fire is an unchanged, existing projectile used as an in-project scale
    # reference. Old sizes use the exact inverse of this visual-only update.
    for frame in range(6):
        review.art["fire", "head", frame] = Image.open(RUNTIME / BANK / f"fire_head_{frame}.png").convert("RGBA")
    canvas = Image.new("RGBA", (1640, 1110), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((25, 18), "PROJECTILE SIZE - unchanged fire reference / previous size / updated size", font=FONT, fill=INK)
    draw.text((25, 49), "Same view scale for every column. Head, trail, and contact receive the same visual factor; gameplay size is unchanged.", font=SMALL, fill=INK)
    centers = (200, 650, 1350)
    view_scale = .7
    for row, (kind, factor) in enumerate(SIZE_FACTORS.items()):
        top = 90 + row * 250
        draw.line((25, top - 7, 1615, top - 7), fill=(53, 66, 72))
        draw.text((25, top + 4), f"{LABELS[kind]} / visual x{factor:g}", font=FONT, fill=COLORS[kind])
        y = top + 119
        for x, label in zip(centers, ("FIRE REFERENCE", "PREVIOUS", "UPDATED")):
            draw.text((x - 65, top + 40), label, font=SMALL, fill=INK)
            draw.line((x - 7, y, x + 7, y), fill=(71, 85, 91))
            draw.line((x, y - 7, x, y + 7), fill=(71, 85, 91))
        review.stamp(canvas, "fire", "head", 1, (centers[0], y), scale=view_scale)
        review.stamp(canvas, kind, "head", 1, (centers[1], y), scale=view_scale / factor)
        review.stamp(canvas, kind, "head", 1, (centers[2], y), scale=view_scale)
        new_width, new_height = actual_bounds(review, kind, frame=1)
        draw.text((centers[1] - 140, top + 212), f"Visible head {new_width / factor:.0f} x {new_height / factor:.0f} animation pixels", font=SMALL, fill=INK)
        draw.text((centers[2] - 165, top + 212), f"Visible head {new_width:.0f} x {new_height:.0f} animation pixels", font=SMALL, fill=INK)
    draw.text((25, 1080), "Offline asset review. Canvas bounds are not collision bounds; giant_shot remains an independent gameplay modifier.", font=SMALL, fill=(158, 174, 178))
    canvas.convert("RGB").save(OUT / "size-adjustment.png")


def direction_review(review):
    kinds = ("bee_swarm", "fireflies")
    angles = (0, -45, -135, 180, 135, 45)
    names = ("RIGHT", "UP-RIGHT", "UP-LEFT", "LEFT", "DOWN-LEFT", "DOWN-RIGHT")
    frames = []
    for frame in range(6):
        canvas = Image.new("RGBA", (1680, 710), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((25, 18), "INSECT HEADS - actual compiled direction matrices", font=FONT, fill=INK)
        draw.text((25, 49), "Left-facing heads mirror horizontally and keep their upper side up. Tail and contact rotation rules stay unchanged.", font=SMALL, fill=INK)
        for row, kind in enumerate(kinds):
            top = 90 + row * 295
            draw.line((25, top - 7, 1655, top - 7), fill=(53, 66, 72))
            draw.text((25, top), LABELS[kind], font=FONT, fill=COLORS[kind])
            for column, (angle, name) in enumerate(zip(angles, names)):
                center = (140 + column * 280, top + 137)
                heading = math.radians(angle)
                dx, dy = math.cos(heading), math.sin(heading)
                end = (center[0] + dx * 108, center[1] + dy * 108)
                draw.line((center[0] - dx * 105, center[1] - dy * 105, *end), fill=(58, 73, 80), width=1)
                draw.polygon((end, (end[0] - dx * 10 - dy * 4, end[1] - dy * 10 + dx * 4),
                              (end[0] - dx * 10 + dy * 4, end[1] - dy * 10 - dx * 4)), fill=(91, 108, 115))
                review.stamp(canvas, kind, "head", frame, center, heading, 1.25)
                draw.text((center[0] - 63, top + 255), f"{name} / {angle} deg", font=SMALL, fill=INK)
        draw.text((25, 680), "Offline sprite review, not a game capture. Six wing poses at the production 30 fps rate.", font=SMALL, fill=(158, 174, 178))
        frames.append(canvas)
    review.save_gif(frames, "insect-directions.gif", kinds)
    frames[1].convert("RGB").save(OUT / "insect-directions.png")


def resident_review(review):
    scene = SwarmScene()
    frames = []
    view_scale = 1.2
    unit = review.layout.pixels_per_unit * view_scale
    for step in range(90):
        now = step / 30
        snapshot = scene.snapshot(now)
        canvas = Image.new("RGBA", (1120, 650), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((25, 18), "RESIDENT INSECTS - independent members from the production Lua module", font=FONT, fill=INK)
        draw.text((25, 49), "Enlarged offline review. Bee field is stationary; the firefly owner anchor moves. Only anchor paths are illustrative.", font=SMALL, fill=INK)
        for column, shot in enumerate(snapshot):
            kind = shot["kind"]
            left = column * 560
            origin = (left + 270, 470)
            draw.text((left + 25, 90), LABELS[kind].replace("PROJECTILE", "FIELD"), font=FONT, fill=COLORS[kind])
            draw.text((left + 25, 122), f"{len(shot['members'])} visible members / individual orbit, height and wing phase", font=SMALL, fill=INK)
            ax, ay, az = shot["anchor"]
            anchor = (origin[0] + az * unit, origin[1] + ax * unit * PROJECTION)
            draw.ellipse((anchor[0] - 105, anchor[1] - 28, anchor[0] + 105, anchor[1] + 28), outline=(45, 60, 67), width=1)
            draw.line((anchor[0] - 7, anchor[1], anchor[0] + 7, anchor[1]), fill=(110, 128, 134))
            draw.line((anchor[0], anchor[1] - 7, anchor[0], anchor[1] + 7), fill=(110, 128, 134))
            draw.text((anchor[0] - 42, anchor[1] + 38), "field / owner", font=SMALL, fill=(158, 174, 178))
            # Ground-order sorting is only the offline drawing convention;
            # every member's actual world position is provided by Lua.
            for part in sorted(shot["members"], key=lambda p: p["x"]):
                x = origin[0] + part["z"] * unit
                y = origin[1] + part["x"] * unit * PROJECTION - part["y"] * unit
                sprite = review.sprite(kind, "head", part["frame"], part["direction"], part["scale"] * view_scale)
                canvas.alpha_composite(sprite, (round(x - sprite.width / 2), round(y - sprite.height / 2)))
            if not shot["alive"]:
                draw.text((left + 126, 285), "Anchor removed; members cleared", font=FONT, fill=INK)
        draw.text((25, 586), f"Preview time {now:.2f} s. Anchors are kept for 2.6 s here to inspect motion, then removed through the actual lifecycle.", font=SMALL, fill=INK)
        draw.text((25, 620), "Sprites are local visuals. Existing field attacks, targeting, lifetime and emitted projectile count are not simulated or changed.", font=SMALL, fill=(158, 174, 178))
        frames.append(canvas)
    review.save_gif(frames, "resident-insects.gif", ("bee_swarm", "fireflies"))
    frames[45].convert("RGB").save(OUT / "resident-insects.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    review = SpecialReview()
    size_review(review)
    direction_review(review)
    resident_review(review)
    print(OUT)
