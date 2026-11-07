"""Render production sprites with the actual Lua trail scheduler.

Only the input trajectories and renderer are illustrative. Tail births,
positions, directions, animation clocks and cleanup run through production
elemental_flight.lua. This is not a screenshot of the DST renderer.
"""
import math
from functools import lru_cache

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw, ImageFont

from build_elemental_flight import BANK, DISPLAY_SIZES, ROOT, RUNTIME

OUT = ROOT / 'docs/previews/basic-v1'
KINDS = ('arrow', 'heavy', 'scatter')
LABELS = {'arrow': 'MAGIC ARROW', 'heavy': 'HEAVY ENERGY ORB', 'scatter': 'SCATTER / THREE INDEPENDENT PELLETS'}
COLORS = {'arrow': (132, 224, 220), 'heavy': (205, 166, 243), 'scatter': (231, 190, 116)}
HIT_SCALE = {'arrow': .7, 'heavy': .85, 'scatter': .55}
SPRITE_SCALE = .6
PROJECTION = math.sin(math.radians(35))
BG = (26, 32, 35, 255)
INK = (229, 230, 224, 255)
FONT = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 20)
SMALL = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 14)


MOCK_RUNTIME = r'''
local now,tick=0,nil
ANIM_ORIENTATION={BillBoard=2}
TheCamera={heading=0,pitch=35}
TheNet={IsDedicated=function() return false end}
GetTime=function() return now end
TheWorld={DoPeriodicTask=function(_,_,fn)
    tick=fn;return {Cancel=function() tick=nil end}
end}
local noop=function() end
function CreateEntity()
    local e={valid=true,visible=true,x=0,y=0,z=0,sx=1,sy=1,sz=1,
        anim_sx=1,anim_sy=1,alpha=1,clock=0,clock_start=now,playback=1}
    e.entity={AddTransform=noop,AddAnimState=noop,SetCanSleep=noop,
        IsVisible=function() return e.visible end}
    e.Transform={SetPosition=function(_,x,y,z) e.x,e.y,e.z=x,y,z end,
        GetWorldPosition=function() return e.x,e.y,e.z end,
        GetRotation=function() return e.rotation or 0 end,
        SetScale=function(_,x,y,z) e.sx,e.sy,e.sz=x,y,z end}
    e.AnimState={SetBank=noop,SetBuild=noop,SetOrientation=noop,SetLightOverride=noop,
        PlayAnimation=function(_,name,loop)
            e.anim,e.loop,e.clock,e.clock_start=name,loop,0,now
        end,
        SetDeltaTimeMultiplier=function(_,rate) e.playback=rate end,
        SetTime=function(_,age) e.clock,e.clock_start=age,now end,
        SetScale=function(_,x,y) e.anim_sx,e.anim_sy=x,y end,
        SetMultColour=function(_,_,_,_,a) e.alpha=a end}
    e.AddTag=noop
    e.IsValid=function() return e.valid end
    e.Remove=function() e.valid=false end
    e.Hide=function() e.visible=false end
    return e
end
return {
    shot=function(flight,id,guid,scale,x,z,vx,vz)
        local e=CreateEntity()
        e.GUID,e.x,e.z,e.vx,e.vz,e.scale=guid,x,z,vx,vz,scale
        e.rotation=-math.atan2(vz,vx)*180/math.pi
        e._visual=CreateEntity()
        e._height={value=function() return 1.4 end}
        e._size={value=function() return e.scale end}
        e.Physics={GetVelocity=function() return e.vx,0,e.vz end}
        flight.attach(e,id)
        return e
    end,
    update=function(time) now=time;if tick then tick(TheWorld) end end,
    clock=function(e)
        local age=e.clock+(now-e.clock_start)*e.playback
        return e.loop and age%.2 or math.min(.199999,age)
    end,
}
'''


class TrailScene:
    """Tiny rendering adapter; particle sampling stays entirely inside Lua."""

    def __init__(self, shots):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.harness = self.lua.execute(MOCK_RUNTIME)
        self.flight = self.lua.execute((ROOT / 'mod/scripts/nw/elemental_flight.lua').read_text(encoding='utf8'))
        self.shots = []
        for guid, spec in enumerate(shots, 1):
            x, z, vx, vz = spec['path'](0)
            entity = self.harness.shot(self.flight, spec['kind'], guid, spec.get('scale', 1), x, z, vx, vz)
            self.shots.append((spec, entity))

    def snapshot(self, now):
        result = []
        for spec, entity in self.shots:
            contact = spec.get('contact', math.inf)
            x, z, vx, vz = spec['path'](min(now, contact))
            entity.x, entity.z, entity.vx, entity.vz = x, z, vx, vz
            entity.rotation = -math.degrees(math.atan2(vz, vx))
            entity.valid = now < contact
        self.harness.update(now)
        for spec, entity in self.shots:
            particles = []
            state = entity._nw_elemental_flight
            if state:
                for part in state.parts.values():
                    fx = part.fx
                    if fx.valid and fx.visible:
                        particles.append(self.capture(fx, now, part.born))
            particles.sort(key=lambda part: part['born'])
            head = self.capture(entity._visual, now)
            head.update(x=entity.x, z=entity.z, scale=entity.scale)
            result.append({'kind': spec['kind'], 'head': head, 'alive': entity.valid,
                           'particles': particles, 'contact': spec.get('contact', math.inf),
                           'direction': self.flight.direction(math.atan2(entity.vz, entity.vx), spec['kind'])})
        return result

    def capture(self, entity, now, born=0):
        direction = int(entity.anim.rsplit('_', 1)[1])
        return {'x': entity.x, 'z': entity.z, 'scale': entity.sx,
                'direction': direction, 'frame': min(5, int(self.harness.clock(entity) * 30)),
                'alpha': entity.alpha, 'born': born, 'age': now - born}

    def sample(self, frames):
        return [self.snapshot(step / 30) for step in range(frames)]


def load_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    module = lua.execute((ROOT / 'mod/scripts/nw/elemental_flight.lua').read_text(encoding='utf8'))
    layout = lua.execute((ROOT / 'mod/scripts/nw/fx_layout.lua').read_text(encoding='utf8'))
    art = {(kind, group, frame): Image.open(RUNTIME / BANK / f'{kind}_{group}_{frame}.png').convert('RGBA')
           for kind in KINDS for group in ('head', 'tail', 'hit') for frame in range(6)}
    return lua, module, layout, art


class Review:
    def __init__(self):
        self.lua, self.runtime, self.layout, self.art = load_runtime()
        self.world_pixels = self.layout.pixels_per_unit * SPRITE_SCALE

    @lru_cache(maxsize=1024)
    def sprite(self, kind, group, frame, direction, scale):
        size = tuple(max(1, round(v * scale)) for v in DISPLAY_SIZES[kind][group])
        sprite = self.art[kind, group, frame].resize(size, Image.Resampling.LANCZOS)
        count = self.runtime.direction_count(kind)
        return sprite.rotate(-direction * 360 / count, Image.Resampling.BICUBIC, expand=True)

    def stamp(self, canvas, kind, group, frame, position, heading=0, scale=1):
        # Paths below already use screen coordinates. Without TheCamera, the
        # runtime applies its actual per-kind direction rounding directly.
        direction = self.runtime.direction(heading, kind)
        sprite = self.sprite(kind, group, frame, direction, scale)
        x, y = position
        canvas.alpha_composite(sprite, (round(x - sprite.width / 2), round(y - sprite.height / 2)))

    def stamp_snapshot(self, canvas, kind, group, part, origin, view_scale):
        unit = self.layout.pixels_per_unit * view_scale
        x, y = origin[0] + part['z'] * unit, origin[1] + part['x'] * unit * PROJECTION
        sprite = self.sprite(kind, group, part['frame'], part['direction'], part['scale'] * view_scale)
        if part['alpha'] < 1:
            sprite = sprite.copy()
            sprite.putalpha(sprite.getchannel('A').point(lambda alpha: round(alpha * part['alpha'])))
        canvas.alpha_composite(sprite, (round(x - sprite.width / 2), round(y - sprite.height / 2)))

    def render_shot(self, canvas, shot, now, origin, view_scale):
        kind = shot['kind']
        for part in shot['particles']:
            self.stamp_snapshot(canvas, kind, 'tail', part, origin, view_scale)
        if shot['alive']:
            self.stamp_snapshot(canvas, kind, 'head', shot['head'], origin, view_scale)
        elif now < shot['contact'] + .2:
            part = dict(shot['head'], frame=min(5, int((now - shot['contact']) / .2 * 6)),
                        direction=shot['direction'], scale=shot['head']['scale'] * HIT_SCALE[kind])
            self.stamp_snapshot(canvas, kind, 'hit', part, origin, view_scale)

    def contact_sheet(self):
        canvas = Image.new('RGBA', (1470, 1260), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((28, 20), 'ARROW / HEAVY / SCATTER - production sprite frames', font=FONT, fill=INK)
        draw.text((28, 52), 'Shared pivots and head size ratios | contact thumbnails reduced | offline asset review', font=SMALL, fill=INK)
        for row, kind in enumerate(KINDS):
            top = 88 + row * 380
            period = self.runtime.head_period(kind)
            draw.text((28, top), LABELS[kind], font=FONT, fill=COLORS[kind])
            for frame in range(6):
                x = 145 + frame * 235
                self.stamp(canvas, kind, 'head', frame, (x, top + 110))
                draw.text((x - 23, top + 202), f'{round(frame * period / 6 * 1000)} ms', font=SMALL, fill=INK)
            draw.text((28, top + 242), 'TRAIL', font=SMALL, fill=INK)
            draw.text((774, top + 242), 'CONTACT', font=SMALL, fill=INK)
            for index, frame in enumerate((0, 2, 4)):
                self.stamp(canvas, kind, 'tail', frame, (150 + index * 230, top + 300))
                self.stamp(canvas, kind, 'hit', frame, (880 + index * 195, top + 300), scale=HIT_SCALE[kind] * .7)
        canvas.convert('RGB').save(OUT / 'frames.png')

    def direction_review(self):
        canvas = Image.new('RGBA', (1440, 690), BG)
        draw = ImageDraw.Draw(canvas)
        count = self.runtime.direction_count('arrow')
        draw.text((28, 20), f'MAGIC ARROW - {count} direction clips', font=FONT, fill=INK)
        draw.text((28, 52), 'Grey line: actual path. Head and new trail share the sampled heading. Offline sprite review.',
                  font=SMALL, fill=INK)
        for index in range(8):
            heading = math.radians(17.5 + index * 45)
            dx, dy = math.cos(heading), math.sin(heading)
            cx, cy = 180 + index % 4 * 360, 238 + index // 4 * 295
            draw.line((cx - 147 * dx, cy - 147 * dy, cx + 147 * dx, cy + 147 * dy),
                      fill=(87, 102, 108), width=1)
            self.stamp(canvas, 'arrow', 'tail', 0, (cx - 54 * dx, cy - 54 * dy), heading, .7)
            self.stamp(canvas, 'arrow', 'head', 2, (cx + 38 * dx, cy + 38 * dy), heading, .7)
            direction = self.runtime.direction(heading, 'arrow')
            label = f'{math.degrees(heading):.1f} deg | clip {direction}'
            draw.text((cx - 82, cy + 126), label, font=SMALL, fill=COLORS['arrow'])
        canvas.convert('RGB').save(OUT / 'directions.png')

    @staticmethod
    def path(kind, age, pellet=0):
        if kind == 'arrow':
            phase = age * math.tau / .8
            return .5 * math.sin(phase), 25 * age, .5 * math.tau / .8 * math.cos(phase), 25
        if kind == 'heavy':
            phase = age * math.tau / 1.4
            return .4 * math.sin(phase), 8.75 * age, .4 * math.tau / 1.4 * math.cos(phase), 8.75
        angle = pellet * math.radians(10)
        vx, vz = 15 * math.sin(angle), 15 * math.cos(angle)
        return pellet * .35 + vx * age, vz * age, vx, vz

    def motion_frame(self, now, snapshots):
        canvas = Image.new('RGBA', (1120, 770), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((26, 18), 'ARROW / HEAVY / SCATTER - flight, turns and contact', font=FONT, fill=INK)
        draw.text((26, 48), 'Particle births, positions and animation ages run through the production Lua scheduler.', font=SMALL, fill=INK)
        for row, kind in enumerate(KINDS):
            top = 82 + row * 220
            center = top + 123
            draw.line((26, top - 8, 1094, top - 8), fill=(55, 69, 75))
            draw.text((26, top), LABELS[kind], font=FONT, fill=COLORS[kind])
            life, interval = self.runtime.trail_timing(1, kind)
            period = self.runtime.head_period(kind)
            count = self.runtime.direction_count(kind)
            sampling = 'distance sampled' if kind == 'arrow' else f'{1 / interval:.0f} particles/s'
            caption = f'Head {period:.2f} s | trail {life:.2f} s | {sampling} | {count} directions'
            draw.text((26, top + 30), caption, font=SMALL, fill=INK)
            for shot in snapshots:
                if shot['kind'] == kind:
                    self.render_shot(canvas, shot, now, (140, center), SPRITE_SCALE)
        draw.text((26, 745), 'Offline sprite review, not a game capture. Contact ends the head; existing trails finish independently.', font=SMALL, fill=(158, 174, 178))
        return canvas

    def save_gif(self, frames, name):
        palette_source = Image.new('RGB', (96 * 18, 96 * 3), BG[:3])
        for row, kind in enumerate(KINDS):
            for group_index, group in enumerate(('head', 'tail', 'hit')):
                for frame in range(6):
                    sprite = self.art[kind, group, frame]
                    palette_source.paste(sprite, ((frame + group_index * 6) * 96, row * 96), sprite)
        palette = palette_source.quantize(colors=255)
        quantized = [frame.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
        durations = [30, 30, 40] * (len(frames) // 3 + 1)
        quantized[0].save(OUT / name, save_all=True, append_images=quantized[1:],
                          duration=durations[:len(frames)], loop=0, disposal=2, optimize=False)

    def motion_review(self):
        shots = []
        for kind in KINDS:
            for pellet in ((-1, 0, 1) if kind == 'scatter' else (0,)):
                shots.append({'kind': kind, 'contact': {'arrow': .35, 'heavy': .95, 'scatter': .6}[kind],
                              'path': lambda age, k=kind, p=pellet: self.path(k, age, p)})
        snapshots = TrailScene(shots).sample(48)
        frames = [self.motion_frame(step / 30, snapshot) for step, snapshot in enumerate(snapshots)]
        self.save_gif(frames, 'flight.gif')
        frames[8].convert('RGB').save(OUT / 'flight.png')
        frames[31].convert('RGB').save(OUT / 'after-contact.png')

    def orbit_review(self):
        snapshots, radii = [], []
        for scale in (1, 2.5):
            radius = min(8, max(2.5, 3.2 * math.sqrt(scale)))
            rate = min(25 / radius, math.radians(210))
            def path(age, r=radius, omega=rate):
                phase = age * omega
                return r * math.sin(phase), r * math.cos(phase), r * omega * math.cos(phase), -r * omega * math.sin(phase)
            snapshots.append(TrailScene([{'kind': 'arrow', 'scale': scale, 'contact': 2.4, 'path': path}]).sample(96))
            radii.append(radius)
        frames = []
        view_scale = .34
        unit = self.layout.pixels_per_unit * view_scale
        for step in range(96):
            now = step / 30
            canvas = Image.new('RGBA', (1440, 680), BG)
            draw = ImageDraw.Draw(canvas)
            draw.text((28, 20), 'MAGIC ARROW - short segments around a curve', font=FONT, fill=INK)
            draw.text((28, 52), 'Real Lua trail scheduler | 150 animation pixels per world unit | input path is a steady orbit', font=SMALL, fill=INK)
            for column, scale in enumerate((1, 2.5)):
                origin = (360 + column * 720, 370)
                radius = radii[column] * unit
                draw.text((28 + column * 720, 90), f'{scale:g}x size | radius {radii[column]:.2f}', font=FONT, fill=COLORS['arrow'])
                draw.ellipse((origin[0] - radius, origin[1] - radius * PROJECTION,
                              origin[0] + radius, origin[1] + radius * PROJECTION), outline=(50, 64, 69), width=1)
                draw.ellipse((origin[0] - 7, origin[1] - 7, origin[0] + 7, origin[1] + 7), fill=(100, 115, 118))
                draw.text((origin[0] - 18, origin[1] + 18), 'owner', font=SMALL, fill=(158, 174, 178))
                shot = snapshots[column][step][0]
                self.render_shot(canvas, shot, now, origin, view_scale)
                draw.text((28 + column * 720, 610), f'{len(shot["particles"])} live segments; older segments stay at their birth positions', font=SMALL, fill=INK)
            draw.text((28, 648), 'Offline sprite review, not a game capture. The arrow ends at 2.4 s; the remaining trail fades independently.', font=SMALL, fill=(158, 174, 178))
            frames.append(canvas)
        self.save_gif(frames, 'arrow-orbit.gif')
        frames[45].convert('RGB').save(OUT / 'arrow-orbit.png')

    def heavy_giant_review(self):
        canvas = Image.new('RGBA', (1200, 520), BG)
        draw = ImageDraw.Draw(canvas)
        draw.text((28, 20), 'HEAVY ENERGY ORB - tail volume at ordinary and giant size', font=FONT, fill=INK)
        draw.text((28, 52), 'Same view scale and real Lua particle ages; no relative enlargement of the tail.', font=SMALL, fill=INK)
        for column, scale in enumerate((1, 2.5)):
            scene = TrailScene([{'kind': 'heavy', 'scale': scale,
                                 'path': lambda age: (0, 8.75 * age, 0, 8.75)}])
            shot = scene.sample(20)[-1][0]
            draw.text((28 + column * 600, 90), f'{scale:g}x size', font=FONT, fill=COLORS['heavy'])
            origin = (440 + column * 600 - shot['head']['z'] * self.layout.pixels_per_unit * .5, 290)
            self.render_shot(canvas, shot, 19 / 30, origin, .5)
        canvas.convert('RGB').save(OUT / 'heavy-giant.png')


if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    review = Review()
    review.contact_sheet()
    review.direction_review()
    review.motion_review()
    review.orbit_review()
    review.heavy_giant_review()
    print(OUT)
