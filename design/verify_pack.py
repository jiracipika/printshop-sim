"""Offline structural verification; writes no files and performs no network calls."""
from html.parser import HTMLParser
from pathlib import Path
import importlib.util
import json
import shutil

ROOT = Path(__file__).resolve().parent
HTML_FILES = ['cover.html', 'menu-main.html', 'menu-contracts.html', 'hud.html', 'screenshot-workshop.html']
DOC_FILES = ['language.md', 'implementation-plan.md', 'README.md']

class Check(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.errors = []
        self.tags = []
        self.links = []
        self.ids = []
    def handle_starttag(self, tag, attrs):
        self.tags.append(tag)
        a = dict(attrs)
        if tag not in {'meta', 'link', 'img', 'br', 'hr', 'input', 'source', 'wbr', 'area', 'base', 'embed', 'param', 'track', 'col'}:
            self.stack.append(tag)
        if 'id' in a:
            self.ids.append(a['id'])
        for k in ('src', 'href'):
            if k in a:
                self.links.append(a[k])
        if tag == 'svg' and (a.get('role') != 'img' or not a.get('aria-label')):
            self.errors.append('SVG missing accessible image label')
    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()
    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1] != tag:
            self.errors.append('Mismatched closing tag: ' + tag)
        else:
            self.stack.pop()

results = []
for name in HTML_FILES:
    text = (ROOT / name).read_text()
    p = Check()
    p.feed(text)
    errors = p.errors
    if p.stack:
        errors.append('Unclosed tags: ' + str(p.stack))
    for required in ('html', 'title', 'style', 'svg', 'main'):
        if required not in p.tags:
            errors.append('Missing ' + required)
    if len(set(p.ids)) != len(p.ids):
        errors.append('Duplicate IDs')
    for link in p.links:
        if '://' in link or link.startswith('//'):
            errors.append('External asset/link: ' + link)
        elif not link.startswith('#') and not (ROOT / link).is_file():
            errors.append('Broken local link: ' + link)
    if '@import' in text or '<script' in text or 'http://' in text or 'https://' in text:
        errors.append('Remote dependency or script found')
    if 'concept' not in text.lower() or 'mockup' not in text.lower():
        errors.append('Missing concept/mockup provenance')
    results.append({'file': name, 'bytes': (ROOT / name).stat().st_size, 'errors': errors})
for name in DOC_FILES:
    p = ROOT / name
    results.append({'file': name, 'bytes': p.stat().st_size if p.exists() else 0,
                    'errors': [] if p.exists() and p.stat().st_size else ['Missing or empty']})
print(json.dumps({'checks': results, 'browser_tools': {
    'python_playwright': bool(importlib.util.find_spec('playwright')),
    'node': shutil.which('node'),
    'chrome': Path('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome').exists(),
    'chromium': Path('/Applications/Chromium.app/Contents/MacOS/Chromium').exists()
}}, indent=2))
raise SystemExit(1 if any(r['errors'] for r in results) else 0)
