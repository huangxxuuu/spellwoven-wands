"""Slice generated lamp artwork and assemble registered animation deliverables.

All drawing comes from the saved image_gen masters. This script only separates
existing parts, normalizes near-zero alpha, registers, resizes and packs them.
It never writes to mod/ or changes gameplay.
"""
from __future__ import annotations

import json
import hashlib
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

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


OUT = asset_directory('emberlamp')
ORIGINAL = OUT / 'originals'
CANVAS = (256, 320)
ANCHOR = (128, 302)
SOURCE_ANCHOR = (577, 1206)
SCALE = .25


def cleaned(im):
    """Discard invisible generator alpha noise; preserve authored edge coverage."""
    im = im.convert('RGBA').copy()
    a = im.getchannel('A').point(lambda v: 0 if v <= 8 else (255 if v >= 247 else v))
    im.putalpha(a)
    return im


def world(im):
    out = Image.new('RGBA', CANVAS)
    im = im.resize((round(im.width*SCALE), round(im.height*SCALE)), Image.Resampling.LANCZOS)
    out.alpha_composite(im, (round(ANCHOR[0]-SOURCE_ANCHOR[0]*SCALE),
                              round(ANCHOR[1]-SOURCE_ANCHOR[1]*SCALE)))
    return out


def fuel(name, outlined=False):
    im = cleaned(Image.open(ORIGINAL/name))
    arr = np.asarray(im).astype(np.int16)
    r,g,b,a = arr.transpose(2,0,1)
    select = (b > g+8) & (r > g+6) & (b > r-15) & (r > 85) & (a > 8)
    select[:680] = False
    select[791:] = False
    select[:,:620] = False
    select[:,885:] = False
    mask = Image.fromarray((select*255).astype('uint8')).filter(ImageFilter.MaxFilter(17 if outlined else 3))
    # Preserve the selected full mound's actual black ink outline as well as its
    # colored interior. This is extraction of the generated drawing, not a new
    # outline synthesized by the exporter.
    al = np.minimum(np.asarray(mask), np.asarray(im.getchannel('A')))
    im.putalpha(Image.fromarray(al.astype('uint8')))
    return world(im)


def contact_shadow(body_source):
    """Separate the generated ground-contact and soil pass from its lamp."""
    im = cleaned(Image.open(ORIGINAL/'r2_ground_contact.png'))
    body_mask = body_source.getchannel('A').point(lambda v: 255 if v>8 else 0)
    body_mask = body_mask.filter(ImageFilter.MaxFilter(3))
    alpha = ImageChops.subtract(im.getchannel('A'),body_mask)
    # Only the ground pass is used; unchanged hardware in its input is discarded.
    alpha.paste(0,(0,0,alpha.width,1080))
    im.putalpha(alpha)
    im.save(OUT/'layers/r2_ground_contact_source.png')
    return world(im)


def fire_cells(name, columns, count):
    sheet = cleaned(Image.open(ORIGINAL/name))
    cells = []
    for i in range(count):
        x,y = i % columns, i // columns
        box = (round(x*sheet.width/columns), round(y*sheet.height/2),
               round((x+1)*sheet.width/columns), round((y+1)*sheet.height/2))
        cell = sheet.crop(box)
        # Use meaningful opacity to find the root rather than sparse alpha specks.
        bounds = cell.getchannel('A').point(lambda v:255 if v>40 else 0).getbbox()
        assert bounds, (name, i)
        bounds = (max(0,bounds[0]-2), max(0,bounds[1]-2),
                  min(cell.width,bounds[2]+2), min(cell.height,bounds[3]+2))
        cut = cell.crop(bounds)
        cut.save(OUT/'layers'/f'{Path(name).stem}_{i:02}_source.png')
        cells.append(cut)
    return cells


def sized_fire(sprite, width, height, root):
    sprite = sprite.resize((max(1,round(width)),max(1,round(height))), Image.Resampling.LANCZOS)
    out = Image.new('RGBA', CANVAS)
    out.alpha_composite(sprite,(round(root[0]-sprite.width/2), round(root[1]-sprite.height)))
    return out


def registered_fire(sprite, anchor, scale, root):
    """One fixed transform for an entire handdrawn sequence, keeping rising FX."""
    size = tuple(round(v*scale) for v in sprite.size)
    result = Image.new('RGBA',CANVAS)
    result.alpha_composite(sprite.resize(size,Image.Resampling.LANCZOS),
        (round(root[0]-anchor[0]*scale),round(root[1]-anchor[1]*scale)))
    return result


def registered_part(im, anchor, scale, target):
    """Place an extracted authored part using one fixed anatomical anchor."""
    bounds = im.getchannel('A').getbbox()
    assert bounds, 'Empty authored part'
    cut = im.crop(bounds)
    size = (round(cut.width*scale), round(cut.height*scale))
    out = Image.new('RGBA', CANVAS)
    out.alpha_composite(cut.resize(size, Image.Resampling.LANCZOS),
        (round(target[0]+(bounds[0]-anchor[0])*scale),
         round(target[1]+(bounds[1]-anchor[1])*scale)))
    return cleaned(out)


def wick_and_full_fuel():
    """Extract the approved wick and surrounding powder, never draw substitutes."""
    source = cleaned(Image.open(ORIGINAL/'r3_unlit_wick_fuel.png'))
    # This mask follows the generated cord and its small fixing ring. It is a
    # selection, not a drawn replacement for the source artwork.
    mask = Image.new('L', source.size)
    ImageDraw.Draw(mask).polygon([(599,498),(610,496),(622,506),(617,518),
        (610,538),(609,546),(620,547),(627,553),(626,560),(619,564),
        (589,564),(579,560),(577,554),(582,549),(590,547),(592,526)], fill=255)
    wick_source = source.copy()
    wick_source.putalpha(ImageChops.multiply(source.getchannel('A'),mask))
    wick_source.save(OUT/'layers/r3_wick_source.png')
    wick = registered_part(wick_source,(602,556),.27,(174,195))

    arr = np.asarray(source).astype(np.int16)
    r,g,b,a = arr.transpose(2,0,1)
    purple = (b>g+14)&(r>g+12)&(b>r-25)&(r>65)&(a>8)
    purple[:518] = False
    purple[565:] = False
    purple[:,:1288] = False
    purple[:,1472:] = False
    # Include the authored black perimeter, with the front slope passing in
    # front of the wick foot. The separate short wick in this source is excluded.
    selection = Image.fromarray((purple*255).astype('uint8')).filter(ImageFilter.MaxFilter(5))
    alpha = np.minimum(np.asarray(selection),np.asarray(source.getchannel('A'))).copy()
    alpha[(g>b+18)&(r>g+12)] = 0  # Gold bowl hardware is not part of the powder.
    alpha[:518] = 0
    alpha[566:] = 0
    powder_source = source.copy()
    powder_source.putalpha(Image.fromarray(alpha.astype('uint8')))
    powder_source.save(OUT/'layers/r3_full_fuel_source.png')
    full = registered_part(powder_source,(1380,556),.315,(174,195))
    return wick, full


def lit_wick(wick, heat):
    """Render authored cord under moving fire, with local light/softness only."""
    if heat <= 0:
        return wick.copy()
    pixels = np.asarray(wick).astype(np.float32).copy()
    # Purple-gray reflected firelight softens the charred cord; no new geometry.
    amount = .40*heat
    pixels[:,:,:3] = pixels[:,:,:3]*(1-amount)+np.array([126,99,145])*amount
    result = Image.fromarray(np.clip(pixels,0,255).astype('uint8'))
    return result.filter(ImageFilter.GaussianBlur(.20+.30*heat))


def front_fire(flame, wick, heat):
    """Keep fire in front; transmit only a faint hint of wick inside its core."""
    pixels = np.asarray(flame).astype(np.float32).copy()
    influence = np.asarray(wick.getchannel('A').filter(ImageFilter.GaussianBlur(.45)))/255
    # All flame pixels outside this tiny internal wick footprint are untouched.
    pixels[:,:,3] *= 1-influence*(.10+.12*heat)
    return Image.fromarray(np.clip(pixels,0,255).astype('uint8'))


def main():
    for directory in ('layers','world','previews'):
        (OUT/directory).mkdir(parents=True,exist_ok=True)
    body_source = cleaned(Image.open(ORIGINAL/'r2_empty_grounded.png'))
    body = world(body_source)
    body.save(OUT/'layers/body.png')
    wick, full_fuel = wick_and_full_fuel()
    wick.save(OUT/'layers/wick.png')
    dust = {'empty':Image.new('RGBA',CANVAS),
            'half':fuel('half_world.png'),'full':full_fuel}
    for state,im in dust.items(): im.save(OUT/'layers'/f'fuel_{state}.png')
    shadow = contact_shadow(body_source)
    shadow.save(OUT/'layers/ground_shadow.png')
    loops = fire_cells('flame_loop.png',4,8)
    ignition = fire_cells('ignite.png',3,6)
    extinction_spec = json.loads((OUT/'r2_extinguish_clip.json').read_text(encoding='utf8'))
    # Earlier Windows-authored manifests contain backslashes; normalize them
    # before passing paths to pathlib on macOS or Linux.
    extinction = [Image.open(OUT/row['path'].replace('\\','/')).convert('RGBA')
                  for row in extinction_spec['frames']]
    clips = {}
    images = {}
    fx_area = np.zeros((CANVAS[1],CANVAS[0]),dtype=bool)
    heat_records = {}
    loop_bounds = {}

    def save(state, stem, flame=None, heat=0):
        name = f'{stem}_{state}'
        im = shadow.copy()
        im.alpha_composite(body)
        cord = lit_wick(wick,heat)
        im.alpha_composite(cord)
        # Fuel encloses the foot on all sides, including the foreground. Full
        # powder hides the fixing ring and leaves only the small wick tip.
        im.alpha_composite(dust[state])
        fx_area[:] |= np.asarray(cord.getchannel('A'))>0
        fx_area[:] |= np.asarray(dust[state].getchannel('A'))>0
        if flame is not None:
            front = front_fire(flame,cord,heat)
            im.alpha_composite(front)
            fx_area[:] |= np.asarray(front.getchannel('A'))>0
        path = f'world/{name}.png'
        im.save(OUT/path)
        images[path] = im
        heat_records[name] = round(heat,3)
        return path

    for state in ('empty','half','full'):
        off = save(state,'off')
        clips[f'off_{state}'] = {'fps':30,'frames':[off]}
        if state == 'empty': continue
        # The full dust surface is higher, leaving less space below the canopy.
        root = (175,194 if state=='half' else 185)
        scale = 1 if state=='half' else .82
        burn = []
        for i,sprite in enumerate(loops):
            height = [44,47,50,52,51,48,45,43][i]*scale
            flame = sized_fire(sprite,40,height,root)
            flame.save(OUT/'layers'/f'flame_{state}_{i:02}.png')
            bounds = flame.getchannel('A').point(lambda a:255 if a>40 else 0).getbbox()
            loop_bounds[f'{state}_{i:02}'] = list(bounds)
            burn.append(save(state,f'burn_{i:02}',flame,
                             [.82,.93,1,.88,.76,.91,.98,.86][i]))
        clips[f'burn_{state}'] = {'fps':30,'frames':[p for p in burn for _ in range(2)]}
        clips[f'on_{state}'] = {'fps':30,'frames':[burn[0]]}
        pre = [off]
        for i,sprite in enumerate(ignition):
            width = [5,15,19,32,34,40][i]
            height = [8,13,24,36,49,44][i]*scale
            # The first spark is at the fixed wick TIP. As the flame grows,
            # its enclosing lower shell reaches down to the powder surface.
            ignition_root = (root[0],round(181+(root[1]-181)*[0,.20,.48,.76,1,1][i]))
            pre.append(save(state,f'ignite_{i:02}',sized_fire(sprite,width,height,ignition_root),
                            [.12,.28,.45,.64,.82,.82][i]))
        # Finish on the exact first loop pose, without a seam or anchor change.
        pre.append(burn[0])
        clips[f'ignite_{state}'] = {'fps':30,'frames':[p for p in pre for _ in range(2)]}
        post = [burn[0]]
        for i,sprite in enumerate(extinction):
            # All 9 cells have identical canvas, anchor and uniform scale. The
            # drawings themselves pinch, separate, rise and dissipate; nothing
            # is resized to a progressively shorter height or bottom-aligned.
            flame = registered_fire(sprite,extinction_spec['anchor'],.42*scale,root)
            flame.save(OUT/'layers'/f'extinguish_{state}_{i:02}.png')
            post.append(save(state,f'extinguish_{i:02}',flame,
                             [.82,.72,.46,.25,.10,.04,0,0,0][i]))
        clips[f'extinguish_{state}'] = {'fps':30,'frames':[p for p in post for _ in range(2)]}

    icons = {n:f'inventory/{n}.png' for n in ('nw_emberlamp','nw_emberlamp_empty',
             'nw_emberlamp_half','nw_emberlamp_full','nw_emberlamp_half_lit','nw_emberlamp_full_lit')}
    manifest = {'version':1,'art_revision':'r3','bank':'nw_emberlamp','canvas':list(CANVAS),'anchor':list(ANCHOR),
        'clips':clips,'aliases':{'idle':'off_empty','on':'burn_full','off':'off_full',
          'turn_on':'ignite_full','turn_off':'extinguish_full'},'icons':icons,
        'shadow':{'mode':'baked_handdrawn_contact','layer':'layers/ground_shadow.png',
          'source':'originals/r2_ground_contact.png',
          'reference':'test_reports/arcane_storage_native/r2_bearger/reference_board.png',
          'dynamic_shadow':False},
        'notes':['Empty state is unlit; no burning animation for empty fuel.',
          'Fixed body reused bit-for-bit. Powder, permanent wick and flame are independent layers.',
          'Full fuel uses the approved surrounding mound with its black ink perimeter; fixing ring is buried.',
          'Central and corner stones share the ground plane; no elevated central rock or arch gap.',
          'Extinguish uses fixed-scale handdrawn detach/rise/dissolve cells, never per-frame compression.',
          'Native nightlight movement reference: eight distinct drawings held two frames at 30fps.',
          'Draw order: ground, body, wick, enclosing foreground powder, front flame.',
          'Wick tip is inside fire; only its local footprint receives light softness and partial transmission.',
          'Wick lighting varies with eight loop poses and returns to the exact unlit state after extinction.',
          'Ignition begins at the fixed wick tip, then the growing flame wraps down to the fuel surface.',
          'Fire root is registered on the visible powder surface; full pile has less headroom.',
          'World export is 0.25 source scale, independent from dedicated 64px UI artwork.',
          'Alpha <=8 discarded and >=247 normalized for export only; generated sources unchanged.',
          'Fuel visual thresholds and consumption mechanics are not implemented by this art package.']}
    (OUT/'clip_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')

    names = ['off_empty','off_half','off_full','on_half','on_full']
    contact = Image.new('RGBA',(CANVAS[0]*len(names),CANVAS[1]+36),'#77766f')
    draw = ImageDraw.Draw(contact)
    for i,name in enumerate(names):
        draw.text((i*CANVAS[0]+12,10),name,fill='white')
        contact.alpha_composite(images[clips[name]['frames'][0]],(i*CANVAS[0],32))
    contact.convert('RGB').save(OUT/'previews/states.png')
    contact.convert('RGB').save(OUT/'previews/r3_states.png')
    details = Image.new('RGB',(320*len(names),320),'#77766f')
    for i,name in enumerate(names):
        tile = Image.new('RGBA',CANVAS,'#77766f')
        tile.alpha_composite(images[clips[name]['frames'][0]])
        details.paste(tile.crop((135,131,215,205)).resize((320,296),Image.Resampling.NEAREST).convert('RGB'),(i*320,24))
        ImageDraw.Draw(details).text((i*320+12,8),name,fill='white')
    details.save(OUT/'previews/r3_wick_detail.png')
    for state in ('half','full'):
        timeline = ([clips[f'off_{state}']['frames'][0]]*20 + clips[f'ignite_{state}']['frames'] +
                    clips[f'burn_{state}']['frames']*4 + clips[f'extinguish_{state}']['frames'] +
                    [clips[f'off_{state}']['frames'][0]]*20)
        animation = []
        for path in timeline:
            im = Image.new('RGBA',CANVAS,'#77766f')
            im.alpha_composite(images[path])
            animation.append(im.convert('RGB'))
        animation[0].save(OUT/'previews'/f'ignite_burn_extinguish_{state}.gif',
            save_all=True,append_images=animation[1:],
            duration=[[30,30,40][i%3] for i in range(len(animation))],loop=0)
        animation[0].save(OUT/'previews'/f'r3_ignite_burn_extinguish_{state}.gif',
            save_all=True,append_images=animation[1:],
            duration=[[30,30,40][i%3] for i in range(len(animation))],loop=0)
    # R3 preview uses the final grounded body, enclosing fuel and permanent wick.
    sequence = clips['extinguish_half']['frames'][2::2]
    board = Image.new('RGBA',(CANVAS[0]*5,(CANVAS[1]+28)*2),'#77766f')
    drawing = ImageDraw.Draw(board)
    for i,path in enumerate(sequence):
        x,y = i%5*CANVAS[0],i//5*(CANVAS[1]+28)
        drawing.text((x+12,y+8),f'R3 extinguish {i:02}',fill='white')
        board.alpha_composite(images[path],(x,y+28))
    board.convert('RGB').save(OUT/'previews/r3_extinguish_lamp_contact.png')
    timeline = ([clips['burn_half']['frames'][0]]*20 + clips['extinguish_half']['frames'] +
                [clips['off_half']['frames'][0]]*25)
    gif = []
    for path in timeline:
        im = Image.new('RGBA',CANVAS,'#77766f')
        im.alpha_composite(images[path])
        gif.append(im.convert('RGB'))
    gif[0].save(OUT/'previews/r3_extinguish_lamp.gif',save_all=True,append_images=gif[1:],
                duration=[[30,30,40][i%3] for i in range(len(gif))],loop=0)
    # Compare actual exported pixels in every fixed-body region. Only the fuel
    # and open flame cavity are excluded from this stability check.
    # A rising flame may legitimately contribute through antialiased canopy
    # edge pixels. Compare only fully opaque body pixels for registration.
    fixed = np.asarray(body.getchannel('A')) == 255
    fixed &= ~fx_area
    reference_pixels = np.asarray(images['world/off_empty.png'])
    stable = all(np.array_equal(np.asarray(im)[fixed],reference_pixels[fixed]) for im in images.values())
    assert stable, 'Lamp structure moved or changed between frames'
    body_alpha = np.asarray(body.getchannel('A'))
    contact_bottoms = [int(np.where(body_alpha[:,x]>40)[0].max()) for x in range(105,151)]
    assert max(contact_bottoms)-min(contact_bottoms) <= 5, 'Central stone is not on a shared ground line'
    endpoints = all(np.array_equal(np.asarray(images[clips[f'extinguish_{s}']['frames'][-1]]),
                       np.asarray(images[clips[f'off_{s}']['frames'][0]])) for s in ('half','full'))
    assert endpoints, 'Extinction must return to the exact off-state wick and fuel'
    visible_wick = {s:int(((np.asarray(wick.getchannel('A'))>40)&
                        (np.asarray(dust[s].getchannel('A'))<100)).sum()) for s in dust}
    assert visible_wick['empty']>visible_wick['half']>visible_wick['full']>0, visible_wick
    assert all(bounds[1]>=140 for bounds in loop_bounds.values()), 'Loop flame touches the canopy'
    checks = {'art_revision':'r3','canvas':CANVAS,'anchor':ANCHOR,'world_frames':len(images),'clips':len(clips),
              'loop_drawings':len(loops),'ignition_drawings':len(ignition),
              'extinguish_drawings':len(extinction)-1,'extinguish_terminal_empty':True,
              'extinguish_fixed_transform':True,'body_static':stable,
              'permanent_wick':True,'wick_visible_pixels_by_fuel':visible_wick,
              'draw_order':['ground','body','wick','foreground_fuel','front_fire'],
              'extinguish_matches_off':endpoints,'loop_flame_bounds':loop_bounds,
              'wick_heat_by_frame':heat_records,
              'central_stone_bottom_range':[min(contact_bottoms),max(contact_bottoms)],
              'checked_fixed_body_pixels':int(fixed.sum())}
    (OUT/'art_export_report.json').write_text(json.dumps(checks,indent=2),encoding='utf8')
    generated = [
        ('empty_world.png','01_empty_world.txt','c0f97faa-d55d-497c-b5b9-fc46b0213d55','superseded_ground_contact_revision'),
        ('half_world.png','02_half_world.txt','a9b41db1-3cd3-4912-802c-69aa8386399e','fuel_only'),
        ('full_world.png','03_full_world.txt','d7d18ca0-7eec-4038-9f56-76e18ebd2b4b','superseded_r3_surrounding_mound'),
        ('flame_loop_glow_rejected.png','04_flame_loop.txt','8a6a3322-d24e-4b8a-9458-16b19c040683','superseded'),
        ('flame_loop.png','05_flame_cleanup.txt','adc469ff-0520-44dd-aac4-b652662773f6','selected'),
        ('ignite.png','07_ignite.txt','a0f2198a-246c-4d9d-96f4-206136067493','selected'),
        ('extinguish.png','08_extinguish.txt','aa20eb81-a931-4c1f-8cab-06b4a0d87afa','superseded_compressed_motion'),
        ('full_world_powder.png','09_full_dust_surface.txt','e2b56014-99d8-4a84-bdf3-c26882858062','superseded_user_prefers_black_outline'),
        ('r2_empty_grounded.png','r2_grounded_base.txt','923c5f0d-eb19-4549-8dc9-e5f96bf171fc','selected_grounded_body'),
        ('r2_ground_contact.png','r2_ground_contact.txt','b726b77c-2b03-4ef4-b29c-b889bf44c603','selected_contact_shadow_and_soil'),
        ('r2_extinguish.png','r2_extinguish.txt','aa4d399f-6847-4a9f-8e19-c6320bb56f11','selected_rising_extinguish'),
        ('r3_unlit_wick_fuel.png','r3_full_unlit_parts.txt','6425fdb1-aa51-428d-ab06-d48c2ae2e8e9','selected_permanent_wick_and_surrounding_full_fuel'),
    ]
    records = []
    for filename,prompt,source,status in generated:
        path = ORIGINAL/filename
        record = {'file':'originals/'+filename,'prompt':'prompts/'+prompt,
                  'source':'exec-'+source+'.png','status':status}
        if path.is_file():
            record.update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                          size=list(Image.open(path).size))
        elif status.startswith('superseded'):
            # The distributable deliberately omits rejected drafts. They are
            # provenance only, and are not required to reproduce selected art.
            record.update(available_in_this_bundle=False,
                          note='Superseded draft omitted from the standalone bundle.')
        else:
            raise FileNotFoundError(f'Missing selected artwork source: {path}')
        records.append(record)
    provenance = {'date':'2026-11-09','revision':3,'method':'built-in image_gen','category':'world_building_and_animation',
        'approved_identity':'assets_src/arcane_storage_v2/originals/emberlamp_appearance.png',
        'style_priority':['local art specifications','native DST references','approved identity and existing stations'],
        'read_specs':['AGENTS.md','docs/26_饥荒原版画风与生图基础规范.md','docs/DST生图基础提示词.txt',
                     'docs/art/02_游戏内建筑规范.md','docs/art/03_游戏内物品栏贴图规范.md'],
        'reference_roles':{'approved_lamp':'identity, palette and proportions',
                           'nightlight_flame_contact':'motion silhouette and timing only',
                           'approved_jewellery_box':'fine powder surface only'},
        'generated':records,'inventory':'inventory_manifest.json','export':'clip_manifest.json',
        'approved_wick_design':'concepts/wick_r4/wick_comparison_full.png',
        'separation':'Canonical grounded body. Generated cord with socket reused at one fixed position; foreground powder buries its foot. Existing generated fire drawings render in front with local wick light transmission.',
        'part_registration':{'wick':{'source_anchor':[602,556],'scale':.27,'world_anchor':[174,195]},
                             'full_fuel':{'source_anchor':[1380,556],'scale':.315,'world_anchor':[174,195]}},
        'native_reference':'test_reports/arcane_storage_native/manifest.json',
        'ground_reference':'test_reports/arcane_storage_native/r2_bearger/manifest.json',
        'extinguish_registration':'r2_extinguish_clip.json'}
    (OUT/'generation_manifest.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps(checks))


if __name__ == '__main__':
    main()
