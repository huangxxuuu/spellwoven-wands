"""Check the generated guide's local links under a GitHub Pages project path."""
import argparse
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--directory', type=Path, default=Path('site/public'))
args = parser.parse_args()
root = args.directory.resolve()
checked = 0

def check(source, value):
    global checked
    url = urlsplit(value)
    if url.scheme or url.netloc or not url.path:
        return
    assert not url.path.startswith('/'), f'Host-root URL breaks project hosting: {source}: {value}'
    target = (source.parent / unquote(url.path)).resolve()
    assert target.is_relative_to(root), f'Link escapes published site: {source}: {value}'
    if target.is_dir():
        target = target / 'index.html'
    assert target.is_file(), f'Missing local resource: {source}: {value}'
    checked += 1

class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('href', 'src') and value:
                check(self.source, value)

for source in root.rglob('*.html'):
    links = Links()
    links.source = source
    links.feed(source.read_text('utf8'))
for source in root.rglob('*.css'):
    for value in re.findall(r'url\([\s\"\']*([^\)\"\']+)', source.read_text('utf8')):
        check(source, value.strip())
for filename in ('index.html', 'en/index.html', 'spells.html', 'en/spells.html', 'catalog.json', 'catalog.en.json'):
    assert (root / filename).is_file(), filename
print(f'PASS: {checked} local references and both language entry points under a project subpath')
