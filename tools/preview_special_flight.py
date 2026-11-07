"""Review special projectile assets through the production Lua trail scheduler.

The camera, input paths, and contact times are illustrative. Particle births,
aging, positions, facing, and retirement come from elemental_flight.lua. This
does not emulate DST physics or claim to be an in-game capture.
"""
from __future__ import annotations

import json
import math
import re
from functools import lru_cache

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw

from build_elemental_flight import BANK, DISPLAY_SIZES, ROOT, RUNTIME, direction_transform
from preview_basic_flight import BG, FONT, INK, MOCK_RUNTIME, PROJECTION, SMALL, Review, TrailScene

OUT = ROOT / "docs/previews/special-v1"
KINDS = (
    "gust", "spore_ball", "flint_lance", "slime", "grow_orb", "heal_bolt",
    "star_vortex", "glass_disc", "land_hook", "tri_electric", "end_beam",
    "soundwave", "bee_swarm", "fireflies",
)
LABELS = {
    "gust": "WIND PRESSURE", "spore_ball": "MUSHROOM SPORE", "flint_lance": "FLINT LANCE",
    "slime": "SLIME", "grow_orb": "CHARGING ORB", "heal_bolt": "HEALING BOLT",
    "star_vortex": "VORTEX STAR", "glass_disc": "MOON GLASS DISC", "land_hook": "LAND HOOK",
    "tri_electric": "TRIPLE ELECTRIC", "end_beam": "TERMINAL BEAM", "soundwave": "OCARINA WAVE",
    "bee_swarm": "BEE PROJECTILE", "fireflies": "FIREFLY PROJECTILE",
}
SPEED = {
    "gust": 16, "spore_ball": 3, "flint_lance": 24, "slime": 12, "grow_orb": 14,
    "heal_bolt": 18, "star_vortex": 9, "glass_disc": 15, "land_hook": 18,
    "tri_electric": 16, "end_beam": 26, "soundwave": 14, "bee_swarm": 16, "fireflies": 16,
}
COLORS = {
    "gust": (221, 216, 195), "spore_ball": (225, 193, 122), "flint_lance": (205, 195, 170),
    "slime": (173, 208, 72), "grow_orb": (241, 211, 101), "heal_bolt": (179, 223, 173),
    "star_vortex": (201, 198, 249), "glass_disc": (172, 214, 230), "land_hook": (212, 187, 138),
    "tri_electric": (218, 161, 248), "end_beam": (248, 162, 141), "soundwave": (184, 216, 240),
    "bee_swarm": (239, 195, 91), "fireflies": (201, 238, 117),
}
NOTES = ("note_a", "ocarina_b", "note_c", "ocarina_d", "ocarina_e", "ocarina_f",
         "ocarina_gsharp", "ocarina_a2", "ocarina_g")


def animation_groups():
    manifest = json.loads((RUNTIME / BANK / "manifest.json").read_text(encoding="utf8"))
    fps = manifest["fps"]
    result = {}
    for kind in KINDS:
        groups = manifest["sources"][kind]["groups"]
        result[kind] = {}
        for group in ("head", "tail", "hit"):
            frames = groups[group].get("frames", manifest["frames"])
            result[kind][group] = {"frames": frames, "period": groups[group].get("period", frames / fps)}
    return result


def lua_environment():
    lua = LuaRuntime(unpack_returned_tuples=True)
    # The renderer only consults instrument metadata. Do not load unrelated
    # weapon, locale, or gameplay modules to make this offline display work.
    notes = lua.table_from({name: lua.table_from({"instrument": "ocarina"}) for name in NOTES})
    notes["kantele_a"] = lua.table_from({"instrument": "kantele"})
    lua.globals().preview_notes = notes
    lua.execute('''
        package.preload["nw/arsenal"]=function() return {notes=preview_notes} end
        package.preload["nw/spell_effects"]=function() return {} end
        package.preload["nw/targeting"]=function() return {} end
    ''')
    return lua


class SpecialScene(TrailScene):
    def __init__(self, shots):
        self.animations = animation_groups()
        self.lua = lua_environment()
        # The basic harness has six-frame clips. Respect each production
        # group's real length for the electric orb's twelve-frame loop.
        old_clock = "return e.loop and age%.2 or math.min(.199999,age)"
        if old_clock not in MOCK_RUNTIME:
            raise ValueError("Basic preview harness clock changed; update the variable-clip adapter")
        harness = MOCK_RUNTIME.replace(old_clock,
                                       "return e.loop and age%(e.clip_time or .2) or math.min((e.clip_time or .2)-.000001,age)")
        self.harness = self.lua.execute(harness)
        self.flight = self.lua.execute((ROOT / "mod/scripts/nw/elemental_flight.lua").read_text(encoding="utf8"))
        self.shots = []
        for guid, spec in enumerate(shots, 1):
            x, z, vx, vz = spec["path"](0)
            entity = self.harness.shot(self.flight, spec["kind"], guid, spec.get("scale", 1), x, z, vx, vz)
            kind = self.flight.resolve(spec["kind"])
            entity._visual.clip_time = self.animations[kind]["head"]["period"]
            self.shots.append((spec, entity))

    def capture(self, entity, now, born=0):
        prefix, direction = entity.anim.rsplit("_dir_", 1)
        group = "tail" if prefix.endswith("_tail") else "hit" if prefix.endswith("_hit") else "head"
        kind = prefix if group == "head" else prefix[:-(len(group) + 1)]
        frames = self.animations[kind][group]["frames"]
        return {"x": entity.x, "z": entity.z, "scale": entity.sx,
                "direction": int(direction), "frame": min(frames - 1, int(self.harness.clock(entity) * 30)),
                "alpha": entity.alpha, "born": born, "age": now - born}


class SpecialReview(Review):
    def __init__(self):
        self.animations = animation_groups()
        self.lua = lua_environment()
        self.runtime = self.lua.execute((ROOT / "mod/scripts/nw/elemental_flight.lua").read_text(encoding="utf8"))
        self.layout = self.lua.execute((ROOT / "mod/scripts/nw/fx_layout.lua").read_text(encoding="utf8"))
        self.motion = self.lua.execute((ROOT / "mod/scripts/nw/flight.lua").read_text(encoding="utf8"))
        self.art = {(kind, group, frame): Image.open(RUNTIME / BANK / f"{kind}_{group}_{frame}.png").convert("RGBA")
                    for kind in KINDS for group in ("head", "tail", "hit")
                    for frame in range(self.animations[kind][group]["frames"])}
        # Read the production contact scale table rather than maintaining a
        # second set of impact sizes in the preview.
        hit_source = (ROOT / "mod/scripts/prefabs/nw_elemental_hit_fx.lua").read_text(encoding="utf8")
        match = re.search(r"local scale\s*=\s*\{([^}]+)\}", hit_source)
        if not match:
            raise ValueError("Cannot find the production contact scale table")
        self.hit_scale = {key: float(value) for key, value in re.findall(r"(\w+)\s*=\s*([.\d]+)", match.group(1))}
        for kind in KINDS:
            if not self.runtime.supports(kind) or kind not in self.hit_scale:
                raise ValueError(f"Missing runtime visual configuration: {kind}")

    def visual_kind(self, kind):
        return self.runtime.resolve(kind)

    @lru_cache(maxsize=1536)
    def sprite(self, kind, group, frame, direction, scale):
        """Render the same affine matrix compiled into the direction clip.

        Insect heads can have a negative determinant on the left side; a
        plain rotate() would incorrectly show those production clips upside
        down. Transform the authored canvas around its fixed source pivot.
        """
        source = self.art[kind, group, frame]
        a, b, c, d = (value * scale for value in direction_transform(kind, group, direction))
        width = max(1, math.ceil(abs(a) * source.width + abs(c) * source.height))
        height = max(1, math.ceil(abs(b) * source.width + abs(d) * source.height))
        determinant = a * d - b * c
        ia, ib, ic, id_ = d / determinant, -c / determinant, -b / determinant, a / determinant
        transform = (ia, ib, source.width / 2 - ia * width / 2 - ib * height / 2,
                     ic, id_, source.height / 2 - ic * width / 2 - id_ * height / 2)
        return source.transform((width, height), Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC)

    def sampling_caption(self, kind, scale):
        if kind == "flint_lance":
            spacing, _ = self.runtime.trail_spacing(scale, kind)
            return f"distance sampled / {spacing:.3g} world-unit step"
        _, interval = self.runtime.trail_timing(scale, kind)
        return f"{1 / interval:.1f} births per second"

    def render_shot(self, canvas, shot, now, origin, view_scale):
        kind = self.visual_kind(shot["kind"])
        for part in shot["particles"]:
            self.stamp_snapshot(canvas, kind, "tail", part, origin, view_scale)
        if shot["alive"]:
            self.stamp_snapshot(canvas, kind, "head", shot["head"], origin, view_scale)
        elif now < shot["contact"] + .2:
            part = dict(shot["head"], frame=min(5, int((now - shot["contact"]) * 30)),
                        direction=shot["direction"], scale=shot["head"]["scale"] * self.hit_scale[kind])
            self.stamp_snapshot(canvas, kind, "hit", part, origin, view_scale)

    @lru_cache(maxsize=4)
    def gif_palette(self, kinds=KINDS):
        columns = max(sum(config["frames"] for config in self.animations[kind].values()) for kind in kinds)
        palette_source = Image.new("RGB", (96 * columns, 96 * len(kinds)), BG[:3])
        for row, kind in enumerate(kinds):
            column = 0
            for group in ("head", "tail", "hit"):
                for frame in range(self.animations[kind][group]["frames"]):
                    sprite = self.art[kind, group, frame]
                    palette_source.paste(sprite, (column * 96, row * 96), sprite)
                    column += 1
        return palette_source.quantize(colors=255)

    def save_gif(self, frames, name, kinds=KINDS):
        palette = self.gif_palette(kinds)
        quantized = [frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
        durations = ([30, 30, 40] * (len(frames) // 3 + 1))[:len(frames)]
        quantized[0].save(OUT / name, save_all=True, append_images=quantized[1:],
                          duration=durations, loop=0, disposal=2, optimize=False)

    def contact_sheet(self):
        canvas = Image.new("RGBA", (1500, 100 + len(KINDS) * 195), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((25, 18), "SPECIAL PROJECTILES / OCARINA / INSECTS - production sprite frames", font=FONT, fill=INK)
        draw.text((25, 48), "Six sampled head poses | three trail ages | three contact ages. Electric orb has a separate full twelve-pose review.", font=SMALL, fill=INK)
        for row, kind in enumerate(KINDS):
            top = 86 + row * 195
            draw.line((25, top - 7, 1475, top - 7), fill=(53, 66, 72))
            draw.text((25, top), LABELS[kind], font=FONT, fill=COLORS[kind])
            period = self.runtime.head_period(kind)
            directions = self.runtime.direction_count(kind)
            draw.text((340, top + 4), f"{period:.2f} s loop / {directions} directions", font=SMALL, fill=INK)
            draw.text((875, top + 4), "TRAIL", font=SMALL, fill=INK)
            draw.text((1180, top + 4), "CONTACT", font=SMALL, fill=INK)
            for index in range(6):
                frame = index * self.animations[kind]["head"]["frames"] // 6
                # Keep the long rope within its thumbnail cell. Proportions
                # are reviewed separately at one shared view scale below.
                scale = .45 * 400 / DISPLAY_SIZES[kind]["head"][0] if kind == "land_hook" else .68
                self.stamp(canvas, kind, "head", frame, (80 + index * 135, top + 111), scale=scale)
            for index, frame in enumerate((0, 2, 4)):
                self.stamp(canvas, kind, "tail", frame, (900 + index * 93, top + 111), scale=.76)
                self.stamp(canvas, kind, "hit", frame, (1215 + index * 105, top + 111), scale=self.hit_scale[kind] * .72)
        canvas.convert("RGB").save(OUT / "frames.png")

    @staticmethod
    def straight_path(kind, lane=0):
        speed = SPEED[kind]
        def path(age):
            phase = age * math.tau / 1.4 + lane * .35
            lateral = lane * 1.25 + .24 * math.sin(phase)
            return lateral, speed * age, .24 * math.tau / 1.4 * math.cos(phase), speed
        return path

    def flight_review(self):
        shots = [{"kind": kind, "contact": .75, "path": self.straight_path(kind)} for kind in KINDS]
        snapshots = SpecialScene(shots).sample(42)
        frames = []
        view_scale = .68
        unit = self.layout.pixels_per_unit * view_scale
        for step, snapshot in enumerate(snapshots):
            now = step / 30
            canvas = Image.new("RGBA", (1440, 1660), BG)
            draw = ImageDraw.Draw(canvas)
            draw.text((25, 18), "FOURTEEN VISUAL FAMILIES - production Lua trails and contact poses", font=FONT, fill=INK)
            draw.text((25, 49), "Camera follows each head. Uniform illustrative contact at 0.75 s; gameplay speed and lifetime are not simulated.", font=SMALL, fill=INK)
            for index, shot in enumerate(snapshot):
                kind = shot["kind"]
                left, top = (index % 2) * 720, 85 + index // 2 * 220
                draw.line((left + 20, top - 6, left + 700, top - 6), fill=(53, 66, 72))
                draw.text((left + 25, top), LABELS[kind], font=FONT, fill=COLORS[kind])
                life, _ = self.runtime.trail_timing(1, kind)
                draw.text((left + 25, top + 28), f"Trail {life:.2f} s | {self.sampling_caption(kind, 1)} | {len(shot['particles'])} live", font=SMALL, fill=INK)
                center = top + 126
                origin = (left + 530 - shot["head"]["z"] * unit, center)
                self.render_shot(canvas, shot, now, origin, view_scale)
            draw.text((25, 1630), "Offline asset review, not a game capture. Only the emitted insect projectile is shown; source fields remain unchanged.", font=SMALL, fill=(158, 174, 178))
            frames.append(canvas)
        self.save_gif(frames, "flight.gif")
        frames[15].convert("RGB").save(OUT / "flight.png")
        frames[25].convert("RGB").save(OUT / "after-contact.png")

    def orbit_review(self, kinds=("flint_lance", "end_beam", "land_hook"), name="long-orbit"):
        cases = [(kind, scale) for kind in kinds for scale in (1, 2.5)]
        scenes = []
        for kind, scale in cases:
            radius = self.motion.orbit_radius(self.lua.table_from({"size_mult": scale}), SPEED[kind])
            omega = min(SPEED[kind] / radius, math.radians(210))
            def path(age, r=radius, w=omega):
                phase = age * w
                return r * math.sin(phase), r * math.cos(phase), r * w * math.cos(phase), -r * w * math.sin(phase)
            scene = SpecialScene([{"kind": kind, "scale": scale, "contact": 1.6, "path": path}])
            scenes.append((radius, scene.sample(66)))
        frames = []
        view_scale = .42 if len(kinds) == 1 else .32
        unit = self.layout.pixels_per_unit * view_scale
        for step in range(66):
            now = step / 30
            height = 130 + len(kinds) * 460
            canvas = Image.new("RGBA", (1440, height), BG)
            draw = ImageDraw.Draw(canvas)
            title = "FLINT LANCE - connected short dust segments" if len(kinds) == 1 else "LONG PROJECTILES - standard and giant turns"
            draw.text((25, 18), title, font=FONT, fill=INK)
            draw.text((25, 49), "Radius reads Flight.orbit_radius. Input path is a steady circle; this does not simulate entry or owner following.", font=SMALL, fill=INK)
            for index, (kind, scale) in enumerate(cases):
                radius, snapshots = scenes[index]
                left, top = index % 2 * 720, 85 + index // 2 * 460
                origin = (left + 360, top + 232)
                r = radius * unit
                draw.text((left + 25, top), f"{LABELS[kind]} / {scale:g}x size / radius {radius:.2f}", font=FONT, fill=COLORS[kind])
                draw.ellipse((origin[0] - r, origin[1] - r * PROJECTION,
                              origin[0] + r, origin[1] + r * PROJECTION), outline=(56, 70, 76), width=1)
                draw.ellipse((origin[0] - 6, origin[1] - 6, origin[0] + 6, origin[1] + 6), fill=(99, 111, 116))
                shot = snapshots[step][0]
                self.render_shot(canvas, shot, now, origin, view_scale)
                directions = self.runtime.direction_count(kind)
                caption = f"{directions} directions / {len(shot['particles'])} detached particles"
                if kind == "flint_lance":
                    spacing, _ = self.runtime.trail_spacing(scale, kind)
                    caption += f" / {spacing:.3g} world-unit step"
                draw.text((left + 25, top + 417), caption, font=SMALL, fill=INK)
            draw.text((25, height - 30), "Offline sprite review. Head stops at 1.6 s; already emitted trails finish independently.", font=SMALL, fill=(158, 174, 178))
            frames.append(canvas)
        self.save_gif(frames, f"{name}.gif", kinds)
        frames[31].convert("RGB").save(OUT / f"{name}.png")

    def voices_and_insects(self):
        cases = (("soundwave", ("note_a", "note_c", "ocarina_g")),
                 ("bee_swarm", ("bee_swarm",) * 3), ("fireflies", ("fireflies",) * 3))
        scenes = []
        for kind, ids in cases:
            shots = [{"kind": actual_id, "contact": .75, "path": self.straight_path(kind, index - 1)}
                     for index, actual_id in enumerate(ids)]
            scenes.append(SpecialScene(shots).sample(42))
        frames = []
        view_scale = .7
        unit = self.layout.pixels_per_unit * view_scale
        for step in range(42):
            now = step / 30
            canvas = Image.new("RGBA", (1120, 940), BG)
            draw = ImageDraw.Draw(canvas)
            draw.text((25, 18), "OCARINA ALIASES / BEE / FIREFLY - concurrent projectile trails", font=FONT, fill=INK)
            draw.text((25, 49), "Three illustrative paths per family. Actual emission counts and timing are still controlled by gameplay.", font=SMALL, fill=INK)
            for row, (kind, ids) in enumerate(cases):
                top = 90 + row * 270
                draw.line((25, top - 8, 1095, top - 8), fill=(53, 66, 72))
                draw.text((25, top), LABELS[kind], font=FONT, fill=COLORS[kind])
                caption = "note_a / note_c / ocarina_g -> shared soundwave art" if row == 0 else "Independent wing cycle and particle ages; parent field is not replaced"
                draw.text((25, top + 30), caption, font=SMALL, fill=INK)
                snapshot = scenes[row][step]
                origin = (850 - snapshot[0]["head"]["z"] * unit, top + (145 if kind == "bee_swarm" else 160))
                for shot in snapshot:
                    self.render_shot(canvas, shot, now, origin, view_scale)
            draw.text((25, 910), "Offline sprite review. Ocarina sound/mark behavior and swarm targeting are outside this visual preview.", font=SMALL, fill=(158, 174, 178))
            frames.append(canvas)
        self.save_gif(frames, "voices-insects.gif", ("soundwave", "bee_swarm", "fireflies"))
        frames[15].convert("RGB").save(OUT / "voices-insects.png")

    def electric_cycle(self):
        kind = "tri_electric"
        count = self.animations[kind]["head"]["frames"]
        period = self.animations[kind]["head"]["period"]
        rows = math.ceil(count / 6)
        sheet = Image.new("RGBA", (1440, 100 + rows * 245), BG)
        draw = ImageDraw.Draw(sheet)
        draw.text((25, 18), f"ELECTRIC ORB - all {count} authored discharge poses", font=FONT, fill=INK)
        draw.text((25, 49), f"{period:.2f} s loop. Branches appear and disappear at different positions around a fixed orb core.", font=SMALL, fill=INK)
        for frame in range(count):
            x, y = 120 + frame % 6 * 240, 200 + frame // 6 * 245
            self.stamp(sheet, kind, "head", frame, (x, y), scale=1.6)
            draw.text((x - 48, y + 95), f"{frame:02d} / {round(frame / 30 * 1000)} ms", font=SMALL, fill=INK)
        sheet.convert("RGB").save(OUT / "electric-cycle.png")
        frames = []
        for frame in range(count):
            canvas = Image.new("RGBA", (1120, 530), BG)
            draw = ImageDraw.Draw(canvas)
            draw.text((25, 18), "ELECTRIC ORB - changing discharge branches", font=FONT, fill=INK)
            draw.text((25, 49), f"Production head poses at 30 fps / {count} frames / {period:.2f} s. Enlarged asset review, not a game capture.", font=SMALL, fill=INK)
            for column, scale in enumerate((1, 2.5)):
                draw.text((25 + column * 560, 90), f"{scale:g}x size", font=FONT, fill=COLORS[kind])
                self.stamp(canvas, kind, "head", frame, (280 + column * 560, 300), scale=scale * 1.15)
            draw.text((25, 497), f"Head pose {frame + 1}/{count}. Trail and contact clips retain their independent six-frame timelines.", font=SMALL, fill=INK)
            frames.append(canvas)
        self.save_gif(frames, "electric-cycle.gif", (kind,))

    def proportions_review(self):
        """Compare fresh-tail volume and the real coexistence of tail ages."""
        canvas = Image.new("RGBA", (1800, 100 + len(KINDS) * 300), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((25, 18), "HEAD / TAIL PROPORTIONS - standard and 2.5x giant at the same view scale", font=FONT, fill=INK)
        draw.text((25, 49), "Production Lua particles at 1.0 s. No independent resizing of heads, tails, or giant views. Offline asset review.", font=SMALL, fill=INK)
        metrics = {"alpha_threshold": 8, "measurement": "whole painted silhouette bounds in animation pixels; not root-only thickness", "kinds": {}}
        view_scale = .5
        for row, kind in enumerate(KINDS):
            top = 90 + row * 300
            boxes = {}
            for group in ("head", "tail"):
                values = []
                for frame in range(self.animations[kind][group]["frames"]):
                    sprite = self.art[kind, group, frame]
                    box = sprite.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
                    if not box:
                        values.append({"frame": frame, "width": 0, "height": 0})
                        continue
                    width, height = DISPLAY_SIZES[kind][group]
                    values.append({"frame": frame, "width": round((box[2] - box[0]) * width / sprite.width, 2),
                                   "height": round((box[3] - box[1]) * height / sprite.height, 2)})
                boxes[group] = values
            head_height = max(value["height"] for value in boxes["head"])
            tail_height = boxes["tail"][0]["height"]
            metric = {**boxes, "fresh_tail_to_max_head_height": round(tail_height / head_height, 3), "snapshots": {}}
            for column, scale in enumerate((1, 2.5)):
                panel = Image.new("RGBA", (900, 300), BG)
                panel_draw = ImageDraw.Draw(panel)
                panel_draw.line((20, 0, 880, 0), fill=(53, 66, 72))
                panel_draw.text((25, 12), f"{LABELS[kind]} / {scale:g}x size", font=FONT, fill=COLORS[kind])
                speed = SPEED[kind]
                scene = SpecialScene([{"kind": kind, "scale": scale,
                                       "path": lambda age, v=speed: (0, v * age, 0, v)}])
                shot = scene.sample(31)[-1][0]
                unit = self.layout.pixels_per_unit * view_scale
                origin = (680 - shot["head"]["z"] * unit, 169)
                panel_draw.line((28, 169, 850, 169), fill=(40, 49, 53))
                self.render_shot(panel, shot, 1, origin, view_scale)
                ages = sorted(round(part["age"], 4) for part in shot["particles"])
                life, interval = self.runtime.trail_timing(scale, kind)
                caption = f"{len(ages)} live tail parts / {life:.2f} s lifetime / {self.sampling_caption(kind, scale)}"
                panel_draw.text((25, 270), caption, font=SMALL, fill=INK)
                canvas.alpha_composite(panel, (column * 900, top))
                metric["snapshots"][str(scale)] = {"live_particles": len(ages), "ages_seconds": ages,
                                                  "lifetime_seconds": life, "birth_interval_seconds": interval}
                if kind == "flint_lance":
                    spacing, coverage = self.runtime.trail_spacing(scale, kind)
                    record = metric["snapshots"][str(scale)]
                    record.pop("birth_interval_seconds")
                    record.update(sampling="distance", spacing_world=spacing, coverage_world=coverage,
                                  reference_interval_at_speed25=interval)
            metrics["kinds"][kind] = metric
        canvas.convert("RGB").save(OUT / "giant-trails.png")
        focus_kinds = ("gust", "grow_orb", "heal_bolt", "end_beam", "soundwave")
        focused = Image.new("RGBA", (1800, 100 + len(focus_kinds) * 300), BG)
        focused_draw = ImageDraw.Draw(focused)
        focused_draw.text((25, 18), "ENERGY AND WAVE TAILS - standard and 2.5x giant at the same view scale", font=FONT, fill=INK)
        focused_draw.text((25, 49), "Production silhouettes and real Lua particle ages. Root connection should be judged visually, not from a whole-sprite bounding box.", font=SMALL, fill=INK)
        for row, kind in enumerate(focus_kinds):
            source_top = 90 + KINDS.index(kind) * 300
            focused.alpha_composite(canvas.crop((0, source_top, 1800, source_top + 300)), (0, 90 + row * 300))
        focused.convert("RGB").save(OUT / "energy-tails.png")
        (OUT / "proportions.json").write_text(json.dumps(metrics, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    review = SpecialReview()
    review.contact_sheet()
    review.flight_review()
    review.orbit_review()
    review.orbit_review(("flint_lance",), "flint-tail-v2")
    review.voices_and_insects()
    review.electric_cycle()
    review.proportions_review()
    print(OUT)
