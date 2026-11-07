"""Extend the existing labelled music-icon system with the missing F/B cards."""
import json
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[1]
SUBJECTS = ROOT / 'assets_src/spell_card_subjects'
DEST = SUBJECTS / 'v9_music_octave'
DEST.mkdir(parents=True, exist_ok=True)
CATALOG = SUBJECTS / 'v3_full_catalog/music_targets'
master = Image.open(CATALOG / 'kantele_e.png').convert('RGBA')
# The E sits on transparent space, separate from both the lyre and blue note.
# Reuse painted F/B glyphs from the same icon family instead of a typeset font.
letter_box = (880, 65, 1150, 345)
glyph_boxes = {'F': (912, 115, 1200, 445), 'B': (945, 150, 1200, 445)}
reference = master.crop(letter_box).getchannel('A').getbbox()
cx = letter_box[0] + (reference[0] + reference[2]) / 2
cy = letter_box[1] + (reference[1] + reference[3]) / 2
overrides = json.loads((SUBJECTS / 'selected_overrides.json').read_text(encoding='utf8'))
cards = []
for label in ('F', 'B'):
    ident = 'kantele_' + label.lower()
    art = master.copy()
    art.paste((0, 0, 0, 0), letter_box)
    glyph = Image.open(CATALOG / ('ocarina_' + label.lower() + '.png')).convert('RGBA').crop(glyph_boxes[label])
    glyph = glyph.crop(glyph.getchannel('A').getbbox())
    height = reference[3] - reference[1]
    glyph = glyph.resize((round(glyph.width * height / glyph.height), height), Image.Resampling.LANCZOS)
    art.alpha_composite(glyph, (round(cx - glyph.width / 2), round(cy - glyph.height / 2)))
    unchanged = ImageChops.difference(master, art)
    unchanged.paste((0, 0, 0, 0), letter_box)
    assert all(channel.getbbox() is None for channel in unchanged.split()), 'Only the letter may change'
    art.save(DEST / (ident + '.png'))
    overrides[ident] = 'v9_music_octave/' + ident + '.png'
    cards.append(dict(id=ident, name='弦琴 ' + label, kind='note'))
(DEST / 'cards.json').write_text(json.dumps({'runtime_registered': True, 'cards': cards}, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
(SUBJECTS / 'selected_overrides.json').write_text(json.dumps(overrides, ensure_ascii=False, indent=2)+'\n', encoding='utf8')
