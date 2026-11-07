"""Continuous billowing poses using the painted lobes and DST electric art.

The strike callbacks still own gameplay timing. Each clip is a window onto
the same rolling cycle so warning, discharge and recovery never freeze it.
"""
from __future__ import annotations

import math
import json
from PIL import ImageOps, Image
from native_animation import NativeAnimation

PERIOD = .8
PERIODS = {"spawn": .5, "idle": PERIOD, "warning": .3, "pulse": .2, "end": .8}
HEIGHT_LIFT = 35  # Billboard pixels; match field_stages.storm_strike_pixels.
STRIKE_PIXELS = 310+HEIGHT_LIFT


def add_cloud_art(bank, source):
    """Registered dark/light paintings; three overlapping illumination zones."""
    sheet = Image.open(source / "storm_volumes_v5.png").convert("RGBA")
    registration = json.loads((source / "storm_volumes_v5.json").read_text(encoding="utf-8"))
    # Row heights were authored, not inferred from an assumed equal grid.
    rows = registration["row_edges"]
    columns = registration["columns"]
    for row, (key, size) in enumerate((("storm_back",(214,84)),("storm_crown",(184,140)),
                                      ("storm_left",(134,66)),("storm_right",(128,64)))):
        box = registration["rows"][row]["pair_crop_in_cell"]
        pieces = []
        for col in (0,1):
            image = sheet.crop((box[0]+columns[col],box[1]+rows[row],box[2]+columns[col],box[3]+rows[row]))
            image.putalpha(image.getchannel("A").point(lambda a:a if a>8 else 0))
            pieces.append(ImageOps.contain(image,size,Image.Resampling.LANCZOS))
        dark, lit = pieces
        bank.sprite(key,dark,f"storm_volumes_v5.png: registered row {row+1}, dark")
        for zone, centre in enumerate((.2,.5,.8)):
            glow = lit.copy()
            alpha = []
            for y in range(lit.height):
                for x in range(lit.width):
                    dr,dg,db,da = dark.getpixel((x,y))
                    r,g,b,a = lit.getpixel((x,y))
                    # Only the painted transmitted light is composited; the
                    # opaque ink silhouette remains owned by the dark body.
                    gain = max(0,min(1,(max(r,g,b)-max(dr,dg,db))/65))
                    falloff = math.exp(-.5*((x/lit.width-centre)/.27)**2)
                    alpha.append(round(min(a,da)*gain*falloff))
            mask = Image.new("L",lit.size);mask.putdata(alpha);glow.putalpha(mask)
            bank.sprite(f"{key}_light_{zone}",glow,
                        f"storm_volumes_v5.png: registered row {row+1}, transmitted light zone {zone}")


# (x,y,arrival,strength) along three different branching discharges. Timings
# remain relative to the warning start; the real gameplay strike is at .30.
ROUTES = (
    ((-72,-345,.025,.38),(-43,-359,.08,.6),(-12,-377,.14,.85),(18,-363,.20,1),
     (43,-342,.26,1),(4,-319,.30,1), (1,-399,.19,.7),(34,-392,.24,.9),(70,-356,.29,.7)),
    ((66,-369,.02,.4),(34,-381,.07,.65),(4,-361,.13,.9),(-26,-340,.19,1),
     (-59,-346,.25,1),(-5,-320,.30,1),(-16,-392,.18,.75),(-48,-380,.23,.9),(44,-327,.27,.8)),
    ((-7,-326,.02,.4),(-33,-350,.07,.6),(-11,-373,.13,.9),(20,-397,.19,1),
     (51,-370,.25,1),(9,-341,.30,1),(-43,-390,.18,.75),(-69,-365,.24,.9),(61,-334,.28,.8)),
)
EDGES = ((0,1),(1,2),(2,3),(3,4),(4,5),(2,6),(6,7),(4,8))


def energy(clock, birth, tail=.12):
    """Fast rise and slower afterlight; no global strobe or uniform cloud flash."""
    age = (clock-birth) % PERIOD
    if age > .035+tail:
        return 0
    return smooth(age/.035)*(1-smooth(max(0,age-.035)/tail))


def local_light(clock, x, y, variant=1):
    value = 0
    for nx,ny,birth,strength in ROUTES[variant-1]:
        distance = ((x-nx)/43)**2+((y-ny)/38)**2
        value += strength*energy(clock,birth)*math.exp(-distance/2)
    return min(1,value)


def arc_layers(bank, clock, variant, depth, opacity):
    route = ROUTES[variant-1]
    result = []
    for number,(a,b) in enumerate(EDGES):
        x0,y0,_,_ = route[a];x1,y1,birth,strength = route[b]
        y = (y0+y1)/2
        # The first leader and a deep upper branch stay behind the crown: their
        # light is visible through paint, while later branches emerge in gaps.
        lane = 1 if number in (0,5) else 2 if y < -355 else 4
        if lane != depth:
            continue
        # One to three frames expose a traveling branch; adjacent clouds retain
        # light after it vanishes. A weaker restrike follows irregularly.
        age = (clock-birth) % PERIOD
        core = max(0,1-age/.075) if age<.075 else .45*max(0,1-abs(age-.115)/.028)
        if core <= .02:
            continue
        length = math.hypot(x1-x0,y1-y0)
        shape = (number+variant+math.floor(age*30))%3
        key = f"storm_inner_arc_bolt_c_{shape}"
        result.append(bank.layer(key,(x0+x1)/2,y,angle=math.atan2(y1-y0,x1-x0),
                                sx=length/bank.sprites[key].width*1.15,sy=.7,
                                opacity=opacity*core*strength))
    return result


def add_electric_art(bank):
    native = NativeAnimation("shock_fx")
    # electrocute_fx (including hounds) uses white, jagged bolt_b/c symbols.
    # Keep their natural thickness and frame registration instead of flattening
    # a long attack arc. The registered lit paintings supply the diffuse flash.
    for symbol, fit in (("bolt_b", (64, 68)), ("bolt_c", (108, 58))):
        frames = [(frame, *native.symbol(symbol, frame)) for frame in (0, 3, 4)]
        left = min(offset[0] for _, _, offset in frames)
        top = min(offset[1] for _, _, offset in frames)
        right = max(offset[0]+image.width for _, image, offset in frames)
        bottom = max(offset[1]+image.height for _, image, offset in frames)
        for index, (frame, image, offset) in enumerate(frames):
            registered = Image.new("RGBA", (right-left, bottom-top))
            registered.alpha_composite(image, (offset[0]-left, offset[1]-top))
            registered = ImageOps.contain(registered, fit, Image.Resampling.LANCZOS)
            bank.sprite(f"storm_inner_arc_{symbol}_{index}", registered,
                        f"DST shock_fx: {symbol} frame {frame}, native electrocute silhouette")


def smooth(value):
    value = max(0, min(1, value))
    return value*value*(3-2*value)


def pose(bank, phase, t, index=None, variant=1):
    # Normal live deadlines: .5 spawn, .8/1.6/2.4 strikes, 2.55 expiry.
    # The .3 s recovery uses the first .3 s of the idle loop. Longer-life
    # storms keep rolling through the rest of that loop while waiting.
    start = {"spawn": -.5, "warning": 0, "pulse": .3, "idle": .5, "end": .45}[phase]
    clock = start+(index/30 if index is not None else t*PERIODS[phase])
    theta = clock/PERIOD*math.tau
    incoming = smooth(t) if phase == "spawn" else 1
    outgoing = smooth(t) if phase == "end" else 0
    # These are successive depth layers of one cloud, not separated puffs.
    # Counter-moving fronts uncover the lit fissures in the deeper bank.
    lobes = (
        ("storm_back", 0, -332, 1.05, 1.0, 0.0, -1, .04),
        ("storm_right", 55, -365, .77, .80, 1.4, 1, .15),
        ("storm_crown", -8, -370, 1., .94, 2.2, -1, .24),
        ("storm_left", -57, -322, 1.05, 1., .4, -1, .08),
        ("storm_right", 56, -315, 1.04, 1., 3.4, 1, 0),
        ("storm_back", -1, -310, .65, .59, 4.5, 1, .18),
    )
    layers = []
    envelope = incoming*(1-outgoing)
    if phase == "end":
        envelope *= 1-smooth(t*3)  # Dissipating clouds cannot start a new burst.
    for index, (key, bx, by, base_x, base_y, offset, side, departure) in enumerate(lobes):
        turn = theta+offset
        x = bx+math.sin(turn)*(10 if index < 3 else 13)
        y = by+math.cos(turn)*(6 if index < 3 else 5)
        angle = .045*math.sin(turn+.7)*side
        sx = base_x*(1+.045*math.sin(turn+.4))
        sy = base_y*(1+.05*math.cos(turn-.3))
        alpha = 1
        if phase == "spawn":
            gather = smooth((t-index*.035)/(1-index*.035))
            x += side*(48+index*4)*(1-gather)
            y += (8+index*2)*(1-gather)
            angle += side*.12*(1-gather)
            sx *= .72+.28*gather
            sy *= .73+.27*gather
            alpha = smooth((t-index*.035)/.62)
        elif phase == "end":
            scatter = smooth((t-departure)/(1-departure))
            x += side*(65+index*9)*scatter
            y -= (16+index*4)*scatter
            angle += side*.15*scatter
            sx *= 1+.24*scatter
            sy *= 1-.22*scatter
            alpha = 1-scatter
        layers.append(bank.layer(key, x, y, angle=angle, sx=sx, sy=sy, opacity=alpha))
        for zone, centre in enumerate((.2,.5,.8)):
            lx=x+(centre-.5)*bank.sprites[key].width*sx
            light=local_light(clock,lx,y,variant)
            # A dark foreground silhouette remains in front of the hot cavity.
            light *= .18 if index==5 else .72 if index in (3,4) else 1
            layers.append(bank.layer(f"{key}_light_{zone}",x,y,angle=angle,sx=sx,sy=sy,
                                     opacity=alpha*envelope*light))
        if index in (1,2,4):
            layers.extend(arc_layers(bank,clock,variant,index,envelope))
    # Translate the entire weather scene, including buried lightning and shine.
    return [None if part is None else (part[0],part[1],part[2]-HEIGHT_LIFT,*part[3:])
            for part in layers]
