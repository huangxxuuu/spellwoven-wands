"""Registered, hand-drawn spore sentry poses for the shared field bank.

The generated 4x4 sheet is an authored set of silhouettes, not sixteen
independently fitted icons. A shared root foot and a fixed cell origin keep
the sentry planted while pose silhouettes move at the game's 30 Hz.
"""
from __future__ import annotations

import math
from pathlib import Path

from PIL import Image


CELL_SIZE = 208
GROUND_Y = 191
ROOT_TOP = 178
DURATIONS = {"grow": .6, "idle": 1.2, "fire": .4, "wilt": .3}


def _smooth(t):
    t = min(1, max(0, t))
    return t*t*(3-2*t)


def add_spore_stages(bank, source: Path):
    """Register the v2 sheet and the four production ``spore_*`` clips.

    ``source`` is the PNG path. The existing bank owns packing and alpha
    pruning; this helper never writes files or changes another field.
    """
    source = Path(source)
    source_label = source.resolve().relative_to(Path(__file__).resolve().parents[1]).as_posix()
    sheet = Image.open(source).convert("RGBA")
    poses = []
    for index in range(16):
        col, row = index % 4, index // 4
        bounds = (round(col*sheet.width/4), round(row*sheet.height/4),
                  round((col+1)*sheet.width/4), round((row+1)*sheet.height/4))
        pose = sheet.crop(bounds).resize((CELL_SIZE, CELL_SIZE), Image.Resampling.LANCZOS)
        pose.putalpha(pose.getchannel("A").point(lambda a: a if a > 8 else 0))
        visible = pose.getchannel("A").point(lambda a: 255 if a > 32 else 0).getbbox()
        if visible is None:
            raise ValueError(f"Empty spore sentry cell {index}")
        # Correct only the sheet's one-pixel baseline rounding. Never fit,
        # rescale or centre a pose by its changing silhouette.
        registered = Image.new("RGBA", pose.size)
        registered.alpha_composite(pose, (0, GROUND_Y-visible[3]))
        poses.append(registered)

    registration = {}
    silhouette_sizes = {}

    def sprite(key, image, origin, label):
        bounds = image.getchannel("A").getbbox()
        if bounds is None:
            raise ValueError(f"Empty spore sentry layer {key}")
        left, top, right, bottom = bounds
        bank.sprite(key, image.crop(bounds), f"{source_label}: {label}")
        registration[key] = (origin[0]+(left+right)/2-CELL_SIZE/2,
                             origin[1]+(top+bottom)/2-GROUND_Y)
        solid = image.getchannel("A").point(lambda a: 255 if a > 32 else 0).getbbox()
        silhouette_sizes[key] = (solid[2]-solid[0], solid[3]-solid[1])

    # All clips share the exact same bottom root pixels. No crossfade, bob,
    # recoil or independent bounding-box fit can move the contact patch.
    sprite("spore_root_v2", poses[5].crop((0, ROOT_TOP, CELL_SIZE, CELL_SIZE)),
           (0, ROOT_TOP), "fixed root foot from mature pose")
    used_poses = (0, 1, 2, 3, 4, 5, 7, 8, 9, 11, 12, 13, 14, 15)
    for index in used_poses:
        sprite(f"spore_pose_{index}", poses[index].crop((0, 0, CELL_SIZE, ROOT_TOP)),
               (0, 0), f"row {index//4+1}, column {index%4+1}, registered upper body")

    def layer(key, opacity=1, angle=0, sx=1, sy=1):
        x, y = registration[key]
        # Upper poses stretch around the fixed root/stem junction rather
        # than the sprite centre. This keeps the seam on the root foot.
        x *= sx
        joint_y = ROOT_TOP-GROUND_Y
        y = joint_y+(y-joint_y)*sy
        return bank.layer(key, x=x*math.cos(angle)-y*math.sin(angle),
                          y=x*math.sin(angle)+y*math.cos(angle),
                          angle=angle, sx=sx, sy=sy, opacity=opacity)

    def inbetweens(sequence, positions, frame, opacity=1):
        for i in range(len(sequence)-1):
            if frame < positions[i+1]:
                progress = _smooth((frame-positions[i])/(positions[i+1]-positions[i]))
                current = f"spore_pose_{sequence[i]}"
                following = f"spore_pose_{sequence[i+1]}"
                a, b = silhouette_sizes[current], silhouette_sizes[following]
                # One fully inked silhouette per frame. Alpha crossfading
                # different nozzle positions creates two translucent mouths;
                # rooted scale inbetweens keep a clean solid outline instead.
                return [layer(current, opacity,
                              sx=1+(b[0]/a[0]-1)*progress,
                              sy=1+(b[1]/a[1]-1)*progress)]
        return [layer(f"spore_pose_{sequence[-1]}", opacity)]

    def posed(phase, t, frame):
        if phase == "idle":
            # A tiny upper-body breath around the planted foot, with no
            # periodic sprite swap or pulse in the contact patch.
            return [layer("spore_root_v2"),
                    layer("spore_pose_5", angle=.007*math.sin(t*math.tau))]
        if phase == "grow":
            alpha = .2+.8*_smooth(frame/3)
            return [layer("spore_root_v2", alpha)] + inbetweens(
                (0, 1, 2, 3, 4, 5), (0, 3, 6, 9, 13, 17), frame, alpha)
        if phase == "fire":
            # Twelve 30 Hz frames. Frame 6 begins at .2 s, exactly when the
            # garden component emits the projectile. Both ends reuse idle.
            return [layer("spore_root_v2")] + inbetweens(
                (5, 7, 8, 9, 5), (0, 3, 6, 9, 11), frame)
        alpha = 1-_smooth((t-.5)/.5)
        return [layer("spore_root_v2", alpha)] + inbetweens(
            (5, 11, 12, 13, 14, 15), (0, 1.6, 3.2, 4.8, 6.4, 8), frame, alpha)

    for phase, seconds in DURATIONS.items():
        bank.clip("spore_"+phase, seconds,
                  lambda t, index, phase=phase: posed(phase, t, index), phase == "idle")

    return {"source": source_label, "grid": [4, 4], "authored_poses": 16,
            "registered_cell_pixels": CELL_SIZE, "ground_y": GROUND_Y,
            "shared_root_top": ROOT_TOP, "durations": DURATIONS,
            "fire_release_frame": 6, "fire_release_seconds": .2,
            "notes": ["Fixed root pixels shared across all stages",
                      "Single opaque silhouettes use rooted 30 Hz inbetweens",
                      "Fire and wilt start from the same mature idle pose"]}
