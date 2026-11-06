"""Copy publishable source into a separate checkout without local history or saves.

Run before reviewing/committing an update in dist/github-public. Existing .git
metadata is preserved. Removed files are reported, never silently deleted.
"""
import argparse
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=ROOT / 'dist/github-public')
args = parser.parse_args()
dest = args.output.resolve()
assert dest != ROOT and not ROOT.is_relative_to(dest), 'Destination must not contain the workspace'
marker = dest / '.nw_public_export'
if dest.exists() and any(dest.iterdir()):
    assert marker.is_file() and json.loads(marker.read_text('utf8'))['workspace'] == str(ROOT), 'Unowned export directory'
dest.mkdir(parents=True, exist_ok=True)
files = [ROOT / n for n in ('.gitignore', '.gitattributes', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.txt')]
for folder in ('.github', 'mod', 'site', 'assets_src', 'docs', 'tests', 'tools'):
    for source in (ROOT / folder).rglob('*'):
        if not source.is_file() or source.is_symlink() or '__pycache__' in source.parts or source.suffix == '.pyc':
            continue
        relative = source.relative_to(ROOT)
        if relative.parts[:2] == ('site', 'public'):
            continue
        files.append(source)
files.extend((ROOT / 'test_reports').glob('*.md'))
old = set(json.loads(marker.read_text('utf8'))['files']) if marker.exists() else set()
paths = {p.relative_to(ROOT).as_posix() for p in files}
for relative in sorted(old - paths):
    print('REVIEW removed source still present in checkout:', relative)
for source in files:
    target = dest / source.relative_to(ROOT)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)
marker.write_text(json.dumps({'workspace': str(ROOT), 'files': sorted(paths)}, indent=2), 'utf8')
print(f'Exported {len(files)} files ({sum(p.stat().st_size for p in files)/1048576:.1f} MiB) to {dest}')
