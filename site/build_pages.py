"""Generate English pages from the maintained Chinese pages and reviewed text."""
import json
import re
from html import escape
from html.parser import HTMLParser
from pathlib import Path

SITE = Path(__file__).resolve().parent

def build_pages(directory):
    translations = json.loads((SITE / 'page_translations.en.json').read_text(encoding='utf8'))

    def translate(text):
        if text in translations:
            return translations[text]
        if text.startswith('本地版 v'):
            return text.replace('本地版', 'Local build', 1)
        if text.startswith('正式版 v'):
            return text.replace('正式版', 'Release', 1)
        assert not re.search(r'[\u4e00-\u9fff]', text), f'Missing page translation: {text}'
        return text

    class EnglishPage(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=False)
            self.parts = []

        def handle_decl(self, decl): self.parts.append('<!' + decl + '>')
        def handle_comment(self, text): self.parts.append('<!--' + text + '-->')
        def handle_entityref(self, name): self.parts.append('&' + name + ';')
        def handle_charref(self, name): self.parts.append('&#' + name + ';')
        def handle_data(self, data): self.parts.append(escape(translate(data), quote=False))
        def handle_endtag(self, tag): self.parts.append('</' + tag + '>')
        def handle_starttag(self, tag, attrs):
            out = []
            for key, value in attrs:
                if value is not None:
                    value = translate(value)
                    if key == 'lang': value = 'en'
                    if key in ('href', 'src') and (value.startswith('assets/') or value.endswith(('.css', '.js'))):
                        value = '../' + value
                out.append(key if value is None else key + '="' + escape(value, quote=True) + '"')
            self.parts.append('<' + tag + (' ' + ' '.join(out) if out else '') + '>')

    dest = directory / 'en'
    dest.mkdir(exist_ok=True)
    for page in directory.glob('*.html'):
        content = page.read_text(encoding='utf8')
        if 'src="language.js"' not in content:
            content = content.replace('</head>', '<script src="language.js"></script></head>')
            page.write_text(content, encoding='utf8')
        parser = EnglishPage()
        parser.feed(content)
        (dest / page.name).write_text(''.join(parser.parts), encoding='utf8')

if __name__ == '__main__':
    build_pages(SITE / 'dist')
