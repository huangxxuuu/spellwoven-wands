"""Export recipe inventory icons from installed DST art without changing Mod files.

Run with the project virtualenv; requires Pillow and lupa (Lua 5.1).
The normal site build consumes the checked-in manifest and exported WebP files,
so a game installation is required only when rebuilding these source assets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree

from PIL import Image, ImageDraw

from native_animation import GAME, texture

ROOT = Path(__file__).resolve().parents[1]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def recipe_materials():
    """Evaluate the same Lua recipes as the game, including generated engravings."""
    from lupa.lua51 import LuaRuntime

    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.globals().package.path = (ROOT / "mod/scripts/?.lua").as_posix() + ";" + vm.globals().package.path
    rows = vm.eval('require("nw/acquisition").recipes')
    materials = {row.ingredients[i][1] for row in rows.values()
                 for i in range(1, len(row.ingredients) + 1)}
    weapons = vm.eval('require("nw/weapon_catalog")')
    overrides = {row[1]: row[6] for row in weapons.values() if row[6]}
    return sorted(materials), overrides, len(rows)


def build(game, output, manifest, contact_sheet=None):
    prefabs, overrides, recipe_count = recipe_materials()
    bundle_path = game / "data/databundles"
    with zipfile.ZipFile(bundle_path / "scripts.zip") as scripts:
        scrapbook_path = "scripts/screens/redux/scrapbookdata.lua"
        scrapbook_bytes = scripts.read(scrapbook_path)
    scrapbook = {}
    for line in scrapbook_bytes.decode("utf8").splitlines():
        prefab = re.search(r'prefab="([^"]+)"', line)
        tex = re.search(r'tex="([^"]+)"', line)
        if prefab and tex:
            scrapbook[prefab[1]] = tex[1]

    native = {}
    atlas_images = {}
    atlas_sources = {}
    with zipfile.ZipFile(bundle_path / "images.zip") as images:
        for path in sorted(images.namelist()):
            if not re.fullmatch(r"images/inventoryimages\d*\.xml", path):
                continue
            atlas_bytes = images.read(path)
            atlas = ElementTree.fromstring(atlas_bytes)
            texture_path = str(Path(path).with_name(atlas.find("Texture").get("filename"))).replace("\\", "/")
            if texture_path not in images.namelist():
                # Legacy unnumbered XML can ship without its retired texture.
                continue
            texture_bytes = images.read(texture_path)
            atlas_sources[path] = dict(texture=texture_path, sourceSha256=sha256(texture_bytes),
                                       atlasSha256=sha256(atlas_bytes))
            for element in atlas.findall("./Elements/Element"):
                attrs = element.attrib
                # The game can contain legacy entries in inventoryimages.xml;
                # numbered atlases contain the current inventory artwork.
                native[attrs["name"]] = (path, attrs)
            atlas_images[path] = texture(texture_bytes)

    selected = {}
    missing = []
    for prefab in prefabs:
        if prefab.startswith("nw_"):
            source = ROOT / "assets_src/art_v1/runtime/nw_supplies" / (prefab + ".png")
            if not source.is_file():
                missing.append(prefab)
                continue
            raw = source.read_bytes()
            icon = Image.open(source).convert("RGBA")
            details = dict(source=source.relative_to(ROOT).as_posix(), sourceSha256=sha256(raw),
                           reference="nw/acquisition.materials; nw_supplies runtime PNG")
        else:
            tex = overrides.get(prefab, scrapbook.get(prefab, prefab + ".tex"))
            if tex not in native:
                missing.append(f"{prefab}: {tex}")
                continue
            atlas_path, attrs = native[tex]
            atlas = atlas_images[atlas_path]
            uv = {key: float(attrs[key]) for key in ("u1", "v1", "u2", "v2")}
            rect = tuple(round(n) for n in (uv["u1"] * atlas.width,
                         (1 - uv["v2"]) * atlas.height, uv["u2"] * atlas.width,
                         (1 - uv["v1"]) * atlas.height))
            icon = atlas.crop(rect)
            details = dict(source=f"data/databundles/images.zip!{atlas_sources[atlas_path]['texture']}",
                           atlas=f"data/databundles/images.zip!{atlas_path}", tex=tex,
                           uv=uv, crop=list(rect), **atlas_sources[atlas_path])
            if prefab in overrides:
                details["reference"] = "mod/scripts/nw/weapon_catalog.lua field 6"
            elif prefab in scrapbook:
                details["reference"] = f"data/databundles/scripts.zip!{scrapbook_path} prefab={prefab}"
            else:
                details["reference"] = "Exact prefab.tex inventory atlas element"
        if not icon.getchannel("A").getbbox():
            raise ValueError(f"Empty icon for {prefab}")
        details["size"] = list(icon.size)
        selected[prefab] = (icon, details)
    if missing:
        raise ValueError("Missing exact inventory icons: " + ", ".join(missing))

    output.mkdir(parents=True, exist_ok=True)
    result = {}
    for prefab, (icon, details) in selected.items():
        destination = output / (prefab + ".webp")
        # Lossless encoding preserves original colours and alpha; no fit/crop,
        # background painting, or per-item rescaling is applied to the artwork.
        icon.save(destination, "WEBP", lossless=True, method=6, exact=True)
        result[prefab] = dict(icon="assets/materials/" + destination.name,
                              iconSha256=sha256(destination.read_bytes()), **details)
    data = dict(schemaVersion=1, recipeCount=recipe_count, materialCount=len(result),
                source="Locally installed Don't Starve Together inventory atlases and Mod runtime PNGs",
                materials=result)
    manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    if contact_sheet:
        columns, cell_width, cell_height = 8, 168, 176
        sheet = Image.new("RGB", (columns * cell_width, ((len(result) + columns - 1) // columns) * cell_height), "#c9bba7")
        draw = ImageDraw.Draw(sheet)
        for index, (prefab, (icon, _)) in enumerate(selected.items()):
            x, y = index % columns * cell_width, index // columns * cell_height
            # Preview at a common UI canvas size, preserving the full source
            # canvas and its whitespace (exported files retain native pixels).
            preview = icon.copy()
            scale = 128 / max(preview.size)
            preview = preview.resize((round(preview.width * scale), round(preview.height * scale)), Image.Resampling.LANCZOS)
            sheet.paste(preview, (x + (cell_width - preview.width) // 2, y), preview)
            # Long prefab IDs wrap instead of hiding their identifying suffix.
            label = prefab if len(prefab) <= 25 else prefab[:25] + "\n" + prefab[25:]
            draw.text((x + 4, y + 145), label, fill="#211b16")
        contact_sheet.parent.mkdir(parents=True, exist_ok=True)
        sheet.save(contact_sheet)
    print(f"Exported {len(result)} exact icons for {recipe_count} recipes to {output}")
    print(f"Manifest: {manifest}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=GAME)
    parser.add_argument("--output", type=Path, default=ROOT / "site/dist/assets/materials")
    parser.add_argument("--manifest", type=Path, default=ROOT / "site/recipe_material_icons.json")
    parser.add_argument("--contact-sheet", type=Path, help="Optional labeled PNG preview (not a site asset)")
    args = parser.parse_args()
    build(args.game, args.output, args.manifest, args.contact_sheet)


if __name__ == "__main__":
    main()
