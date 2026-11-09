"""Pack generated jewellery-case art into an anchored, two-sided lid animation.

No illustration is drawn here: masks split generated surfaces, geometry animates
the rigid lid, and generated content layers are composited behind the rim.
Original imagegen files stay unchanged. No mod runtime files are touched.
"""
from __future__ import annotations
import json
import math
import shutil
from pathlib import Path
import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]


def asset_directory(name):
    """Support both this repository and the top-level folders in the ZIP."""
    for base in (ROOT / 'assets_src/arcane_storage_final', ROOT):
        directory = base / name
        if (directory / 'originals').is_dir():
            return directory
    raise FileNotFoundError(
        f'Cannot find {name}/originals beside tools/ or under assets_src/arcane_storage_final. '
        'Extract the complete art bundle before running this builder.')


DEST = asset_directory('dustbox')
SOURCE = DEST / 'originals'
SIZE = (1254, 1254)
CANVAS = (160, 160)
ANCHOR = (80, 148)
SCALE = 0.125
SOURCE_ANCHOR = (627, 1048)
LEVELS = ('empty', 'half', 'full')


def cleaned(im):
    """Remove only sub-visible alpha noise outside generated silhouettes."""
    im = im.convert('RGBA')
    a = np.array(im)
    a[a[:, :, 3] <= 8] = 0
    a[:, :, 3][a[:, :, 3] >= 250] = 255
    return Image.fromarray(a)


def polygon_mask(points):
    mask = Image.new('L', SIZE)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask


def part(im, mask):
    result = im.copy()
    result.putalpha(ImageChops.multiply(im.getchannel('A'), mask))
    return result


def rear_visibility(lid, angle):
    """Occlude the stationary rear rim behind the nearly closed lid.

    R3 splits the original open-body back edge from the front body. The two
    independent generated mother images disagree by up to 22 source pixels
    at the rear outline. Hide only this protruding strip at 0/4 degrees; all
    poses from 11 degrees retain their original artwork and projection.
    Two source pixels of inset keep the brass out of the cap's alpha fringe.
    """
    visible = np.full((SIZE[1], SIZE[0]), 255, dtype=np.uint8)
    if angle <= 4:
        alpha = np.asarray(lid.getchannel('A'))
        solid = alpha > 224
        top = np.argmax(solid, axis=0)
        top[~solid.any(axis=0)] = SIZE[1]
        yy = np.arange(SIZE[1])[:, None]
        visible[(yy < 800) & (yy < top[None, :] + 2)] = 0
    return Image.fromarray(visible)


def hinged(surface, factor, mode='inside', thickness_factor=1):
    """Project the planar face and extruded edge independently.

    R2: the old whole-image affine transform collapsed the material edge when
    the lid crossed the camera plane. This is a texture warp of generated art,
    with a distinct side-wall depth that survives at that critical angle.
    """
    pixels = np.asarray(surface).astype(np.float32)
    yy, xx = np.mgrid[:SIZE[1], :SIZE[0]]
    # Slight perspective change of the free edge; zero at the accepted open pose.
    sx = xx.astype(np.float32) - (30*(1-factor) if mode == 'inside' else 0)
    axis = 700.0-.085*sx
    if mode == 'outside':
        bottom = np.interp(sx, [0,150,200,335,995,1108,1254],
                           [770,823,872,916,875,811,740])
        depth = 70.0
        dest_bottom = axis + factor*(bottom-axis)
        dest_seam = dest_bottom-depth*thickness_factor
        sy = np.where(yy >= dest_seam,
                      bottom+(yy-dest_bottom)/thickness_factor,
                      axis+(yy+depth*thickness_factor-axis)/factor-depth)
    else:
        alpha = np.asarray(surface.getchannel('A'))
        edge = np.argmax(alpha > 8, axis=0).astype(np.float32)
        edge[~(alpha > 8).any(axis=0)] = 600
        top = np.interp(sx, np.arange(SIZE[0]), edge)
        depth = 60.0
        dest_seam = axis+factor*(top+depth-axis)
        sy = np.where(yy <= dest_seam,
                      top+depth+(yy-dest_seam)/thickness_factor,
                      axis+(yy-axis)/factor)
    x0, y0 = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = sx-x0, sy-y0
    # Premultiplied bilinear sampling avoids black/colored alpha-edge fringes.
    pixels[:,:,:3] *= pixels[:,:,3:4]/255
    result = np.zeros_like(pixels)
    for dx,dy,weight in ((0,0,(1-fx)*(1-fy)),(1,0,fx*(1-fy)),
                         (0,1,(1-fx)*fy),(1,1,fx*fy)):
        px,py=x0+dx,y0+dy
        valid=(px>=0)&(px<SIZE[0])&(py>=0)&(py<SIZE[1])
        result[valid] += pixels[py[valid],px[valid]]*weight[valid,None]
    result[:,:,:3] = np.divide(result[:,:,:3]*255,result[:,:,3:4],
                               out=np.zeros_like(result[:,:,:3]),where=result[:,:,3:4]>0)
    return Image.fromarray(np.clip(result,0,255).astype('uint8'))


def world(image, shadow=None):
    out = shadow.copy() if shadow is not None else Image.new('RGBA', CANVAS)
    resized = image.resize((round(SIZE[0]*SCALE), round(SIZE[1]*SCALE)), Image.Resampling.LANCZOS)
    xy = (round(ANCHOR[0]-SOURCE_ANCHOR[0]*SCALE), round(ANCHOR[1]-SOURCE_ANCHOR[1]*SCALE))
    out.alpha_composite(resized, xy)
    return cleaned(out)


def icon(image):
    image = cleaned(image)
    bounds = image.getchannel('A').point(lambda a: 255 if a > 16 else 0).getbbox()
    item = ImageOps.contain(image.crop(bounds), (60, 60), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', (64,64))
    out.alpha_composite(item, ((64-item.width)//2, (64-item.height)//2))
    return cleaned(out)


def preview_sprite(im, size=320, background=(190,184,170,255)):
    im = im.resize((size, size), Image.Resampling.NEAREST)
    bg = Image.new('RGBA', im.size, background)
    # R2 runtime frames already contain the single ink contact-shadow layer.
    bg.alpha_composite(im)
    return bg.convert('RGB')


def main():
    for folder in ('parts', 'world', 'inventory', 'review'):
        (DEST/folder).mkdir(parents=True, exist_ok=True)
    empty = cleaned(Image.open(SOURCE/'open_empty.png'))
    outer = cleaned(Image.open(SOURCE/'r2_closed_volume.png'))
    shadow_source = cleaned(Image.open(SOURCE/'r2_ground_ink_shadow.png'))
    shadow_bounds = shadow_source.getchannel('A').point(lambda a:255 if a>16 else 0).getbbox()
    shadow = Image.new('RGBA', CANVAS)
    shadow.alpha_composite(shadow_source.crop(shadow_bounds).resize((144,24),Image.Resampling.LANCZOS),(8,132))
    shadow = cleaned(shadow)
    shadow.save(DEST/'parts/r2_ground_shadow.png')
    # Follow the actual back-rim separation, including the clipped corners;
    # a straight split would leave a sliver of the open lid on the fixed body.
    body_mask = polygon_mask([(0,735),(228,697),(286,677),(430,664),
                              (705,641),(831,623),(875,622),(1254,595),
                              (1254,1254),(0,1254)])
    lid_mask = ImageChops.invert(body_mask)
    lid_inside = part(empty, lid_mask)
    body = part(empty, ImageChops.invert(lid_mask))
    rear_mask = polygon_mask([(0,0),(1253,0),(1253,799),(0,799)])
    body_rear = part(body, rear_mask)
    body_front = part(body, ImageChops.invert(rear_mask))
    # Cover the split line with original generated hinge artwork; no repainted seam.
    hinges_mask = polygon_mask([(326,650),(334,646),(412,639),(422,645),
                                (426,660),(422,678),(333,684),(326,677)])
    hinges_mask = ImageChops.lighter(hinges_mask, polygon_mask(
        [(718,616),(725,610),(802,607),(811,614),(813,631),(807,642),(725,648),(717,638)]))
    hinges = part(empty, hinges_mask)
    # The front thumb clasp belongs to the fixed body.
    clasp = part(empty, polygon_mask([(673,861),(744,855),(755,885),(774,920),
                                    (754,938),(714,971),(683,948),(656,928),(657,908),(676,891)]))
    lid_outside = part(outer, polygon_mask([(0,0),(1254,0),(1254,800),(1109,812),
                                         (1001,877),(367,922),(200,872),(142,819),(0,790)]))
    cavity_mask = polygon_mask([(187,770),(291,683),(838,645),(1032,698),(1072,766),
                                (983,831),(749,853),(670,864),(366,882),(226,833)])
    contents = {'empty': Image.new('RGBA', SIZE)}
    for level in ('half','full'):
        contents[level] = part(cleaned(Image.open(SOURCE/f'open_{level}.png')), cavity_mask)
    for name, im in {'body':body,'lid_inside':lid_inside,'lid_outside':lid_outside,
                     'hinges':hinges,'clasp':clasp,
                     'r3_body_front':body_front,'r3_rear_rim':body_rear,
                     **{f'contents_{k}':v for k,v in contents.items()}}.items():
        im.save(DEST/'parts'/f'{name}.png')

    # Acceleration, ease-out and a restrained one-degree settling motion.
    angles = [0,4,11,22,36,51,65,78,88,95,98,97,96]
    frames = {}
    volume_review = Image.new('RGB',(6*360,350),(190,184,170))
    volume_indices = (0,1,2,3,4,12)
    alignment_review = Image.new('RGB',(3*400,660),(190,184,170))
    occlusion_qa = {}
    for level in LEVELS:
        frames[level] = []
        for index, angle in enumerate(angles):
            theta = math.radians(angle)
            signed_projection = math.cos(theta) - 1.9*math.sin(theta)
            if signed_projection >= 0:
                lid = hinged(lid_outside, max(.035, signed_projection), 'outside', max(.85, math.cos(theta)))
            else:
                denominator = 1.9*math.sin(math.radians(96))-math.cos(math.radians(96))
                factor = max(.035, -signed_projection/denominator)
                lid = hinged(lid_inside, factor, 'inside', 1+.05*(1-factor))
            visibility = rear_visibility(lid, angle)
            if angle <= 4:
                rear = part(body_rear, visibility)
                im = body_front.copy()
                im.alpha_composite(rear)
                # Contents share the same occlusion boundary behind the cap.
                im.alpha_composite(part(contents[level], visibility))
                if level == 'empty':
                    cleaned(rear).save(DEST/'parts'/f'r3_rear_visible_{angle:02}.png')
                    rejected = np.asarray(visibility) == 0
                    occlusion_qa[str(angle)] = {
                        'rear_pixels_hidden':int(np.count_nonzero(rejected & (np.asarray(body_rear.getchannel('A')) > 16))),
                        'rear_pixels_remaining_outside_cap':int(np.count_nonzero(rejected & (np.asarray(rear.getchannel('A')) > 16)))}
            else:
                im = body.copy()
                im.alpha_composite(contents[level])
            im.alpha_composite(lid)
            if angle >= 36:
                im.alpha_composite(hinges)
            im.alpha_composite(clasp)
            if level == 'half' and index in volume_indices:
                cleaned(im).save(DEST/'review'/f'r3_source_pose_{angle:02}.png')
                tile = Image.new('RGBA',(1080,940),(190,184,170,255))
                tile.alpha_composite(im.crop((80,140,1160,1080)))
                column = volume_indices.index(index)
                volume_review.paste(tile.resize((360,313),Image.Resampling.LANCZOS).convert('RGB'),(column*360,0))
                ImageDraw.Draw(volume_review).text((column*360+130,325),f'{angle} deg',fill=(35,30,40))
                if index <= 2:
                    # Top: the high-resolution current composite. Bottom: the
                    # actual exported 160px sprite plus enlarged rear edge.
                    column = index*400
                    tile = Image.new('RGBA',(1080,620),(190,184,170,255))
                    tile.alpha_composite(im.crop((80,500,1160,1120)))
                    alignment_review.paste(tile.resize((400,230),Image.Resampling.LANCZOS).convert('RGB'),(column,30))
                    edge = Image.new('RGBA',(720,190),(190,184,170,255))
                    edge.alpha_composite(im.crop((340,570,1060,760)))
                    alignment_review.paste(edge.resize((400,106),Image.Resampling.LANCZOS).convert('RGB'),(column,280))
                    alignment_review.paste(preview_sprite(world(im,shadow),240),(column+80,410))
                    ImageDraw.Draw(alignment_review).text((column+160,10),f'{angle} deg',fill=(35,30,40))
            output = world(im, shadow)
            name = f'open_{level}_{index:02}.png'
            output.save(DEST/'world'/name)
            frames[level].append(output)
        # The three closed frames are deliberately identical: the opaque lid
        # cannot reveal contents; only open states have fill differences.
        if level == 'empty':
            closed = frames[level][0].copy()
        else:
            frames[level][0] = closed.copy()
            closed.save(DEST/'world'/f'open_{level}_00.png')
        frames[level][-1].save(DEST/'world'/f'opened_{level}.png')
        closed.save(DEST/'world'/f'closed_{level}.png')
    volume_review.save(DEST/'review/r3_lid_volume.png')
    alignment_review.save(DEST/'review/r3_rear_alignment.png')

    icon_names = {'nw_dustbox':'r2_icon_closed_volume.png',
                  **{f'nw_dustbox_open_{level}':f'icon_open_{level}.png' for level in LEVELS}}
    icons = {}
    for name, src in icon_names.items():
        im = icon(Image.open(SOURCE/src))
        im.save(DEST/'inventory'/f'{name}.png')
        icons[name] = f'inventory/{name}.png'
    Image.open(DEST/'inventory/nw_dustbox_open_half.png').save(DEST/'inventory/nw_dustbox_open.png')
    icons['nw_dustbox_open'] = 'inventory/nw_dustbox_open.png'

    clips = {}
    for level in LEVELS:
        sequence = [f'world/open_{level}_{i:02}.png' for i in range(len(angles))]
        clips[f'closed_{level}'] = {'fps':30, 'frames':[f'world/closed_{level}.png']}
        clips[f'opened_{level}'] = {'fps':30, 'frames':[f'world/opened_{level}.png']}
        clips[f'open_{level}'] = {'fps':30, 'frames':sequence}
        clips[f'close_{level}'] = {'fps':30, 'frames':list(reversed(sequence))}
    manifest = {'version':1,'bank':'nw_dustbox','canvas':list(CANVAS),'anchor':list(ANCHOR),
                'clips':clips,'aliases':{'closed':'closed_empty','open':'open_half',
                                        'opened':'opened_half','close':'close_half'},
                'icons':icons,'shadow':{'mode':'baked','layer':'parts/r2_ground_shadow.png',
                   'engine_dynamic_shadow':False,
                   'reference':'test_reports/arcane_storage_native/r2_bearger/ground_world_pose.png',
                   'note':'Single generated ink-contact layer in world frames; disable DynamicShadow on integration. Icons contain no ground shadow.'},
                'source_canvas':list(SIZE),'source_anchor':list(SOURCE_ANCHOR),
                'runtime_scale_from_source':SCALE,'lid_angles_degrees':angles,
                'revision':'r3_closed_rear_rim_occlusion',
                'approved_closed_reference':'concepts/lid_alignment_r3/closed_aligned.png',
                'rear_occlusion':{'affected_angles':[0,4],'restored_from_angle':11,
                    'parts':['parts/r3_body_front.png','parts/r3_rear_rim.png'],
                    'method':'Clip the rear body/contents behind the projected cap silhouette; preserve face and edge geometry.'},
                'lid_volume':'Face foreshortening and physical edge depth are sampled separately; depth does not collapse at camera-plane crossing.',
                'fill_semantics':'Empty/half/full are illustrative content-depth states, not finite storage capacity.',
                'integration':'Staged art only; no gameplay thresholds or prefab changes.'}
    (DEST/'clip_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')

    # Actual runtime sprites are used in every review, including fill-state comparisons.
    contact = Image.new('RGB',(1280,350),(190,184,170))
    for i,(label,im) in enumerate([('CLOSED',closed)]+[(level.upper(),frames[level][-1]) for level in LEVELS]):
        contact.paste(preview_sprite(im),(i*320,0))
        ImageDraw.Draw(contact).text((i*320+120,327),label,fill=(35,30,40))
    contact.save(DEST/'review/states.png')
    contact.save(DEST/'review/r3_states.png')
    poses = Image.new('RGB',(8*240,275),(190,184,170))
    for i,index in enumerate((0,1,2,3,4,6,8,12)):
        poses.paste(preview_sprite(frames['half'][index],240),(i*240,0))
        ImageDraw.Draw(poses).text((i*240+80,250),f'{angles[index]} deg',fill=(35,30,40))
    poses.save(DEST/'review/lid_keyframes.png')
    poses.save(DEST/'review/r3_lid_keyframes.png')
    animation = []
    for level in LEVELS:
        sequence = [closed]*14 + frames[level] + [frames[level][-1]]*22 + list(reversed(frames[level])) + [closed]*7
        for im in sequence:
            bg = preview_sprite(im)
            ImageDraw.Draw(bg).text((12,12),level.upper(),fill=(35,30,40))
            animation.append(bg)
    animation[0].save(DEST/'review/open_close.gif',save_all=True,append_images=animation[1:],duration=33,loop=0)
    shutil.copyfile(DEST/'review/open_close.gif',DEST/'review/r3_open_close.gif')
    iconboard = Image.new('RGB',(640,240),(230,226,213))
    draw = ImageDraw.Draw(iconboard)
    for col,name in enumerate(icon_names):
        im = Image.open(DEST/'inventory'/f'{name}.png')
        for row,bgcolor in enumerate(((230,226,213),(50,46,55))):
            tile = Image.new('RGBA',(160,100),bgcolor+(255,))
            tile.alpha_composite(im,(16,12))
            tile.alpha_composite(im.resize((32,32),Image.Resampling.LANCZOS),(104,28))
            iconboard.paste(tile.convert('RGB'),(col*160,row*100))
        draw.text((col*160+14,215),['CLOSED','EMPTY','HALF','FULL'][col],fill=(35,30,40))
    iconboard.save(DEST/'review/inventory_64_32.png')
    iconboard.save(DEST/'review/r3_inventory_64_32.png')
    qa = {'alpha_noise_cleanup':'Runtime only: A<=8 -> transparent; A>=250 -> opaque; source untouched.',
          'world_canvas':list(CANVAS),'world_anchor':list(ANCHOR),'runtime_max_width':max(im.getbbox()[2]-im.getbbox()[0] for im in frames['empty']),
          'world_rgba_frames':sum(len(v) for v in frames.values())+6,
          'clips_with_aliases':len(clips)+4,'inventory_icons':len(icons),
          'closed_equal_all_levels':all(np.array_equal(np.array(frames['empty'][0]),np.array(frames[level][0])) for level in LEVELS),
          'fixed_lower_body_rows_135_to_159':all(np.array_equal(np.array(frames['empty'][0])[135:],np.array(im)[135:]) for im in frames['empty']),
          'source_parts':13,'shadow_mode':'single baked ink layer; no ellipse',
          'shadow_alpha_bounds':list(shadow.getbbox()),
          'lid_edge_depth_source_pixels':{'outside':70,'inside':60},
          'revision':'r3_closed_rear_rim_occlusion','rear_occlusion':occlusion_qa,
          'artwork_origin':'All visible surfaces generated with built-in image_gen; masks and transforms only in this build.'}
    (DEST/'qa.json').write_text(json.dumps(qa,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(qa,indent=2))


if __name__ == '__main__':
    main()
