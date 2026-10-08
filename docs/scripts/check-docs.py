#!/usr/bin/env python3
"""Validate local documentation references and immutable audit evidence."""
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
errors = []
checked = 0
sources = [*sorted(ROOT.glob('README*.md')), ROOT / 'CONTRIBUTING.md',
           *sorted((ROOT / 'docs').rglob('*.md'))]
for source in sources:
    if not source.exists():
        continue
    body = source.read_text()
    for target in re.findall(r'\]\(([^)]+)\)', body):
        target = target.split('#')[0].split(' "')[0]
        if not target or re.match(r'^[a-zA-Z]+:', target) or target.startswith('//'):
            continue
        path = (source.parent / target).resolve()
        if not path.exists():
            errors.append(f'{source.relative_to(ROOT)}: missing {target}')
        checked += 1
catalog = json.loads((ROOT / 'docs/api/cursor-web-endpoints.json').read_text())
assert catalog['bundleCount'] == 428
assert catalog['routeCount'] == len(catalog['endpoints']) == 857
assert sum('observed-response' in item['evidence'] for item in catalog['endpoints']) == 120
assert sum(any(e.startswith('observed-') for e in item['evidence'])
           for item in catalog['endpoints']) == 123
json.loads((ROOT / 'docs/api/cursor-web-services.json').read_text())
for svg in (ROOT / 'docs/assets').glob('*.svg'):
    ET.parse(svg)

class Prototype(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = set()
        self.inline = False
        self.scripts = []
        self.lang = None
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'html':
            self.lang = attrs.get('lang')
        if 'id' in attrs:
            if attrs['id'] in self.ids:
                errors.append(f'duplicate prototype id: {attrs["id"]}')
            self.ids.add(attrs['id'])
        if tag == 'script':
            self.inline = 'src' not in attrs
    def handle_endtag(self, tag):
        if tag == 'script':
            self.inline = False
    def handle_data(self, data):
        if self.inline:
            self.scripts.append(data)

parser = Prototype()
parser.feed((ROOT / 'docs/design/cursor-android-prototype.html').read_text())
assert parser.lang == 'en', 'Canonical prototype must default to English'
with tempfile.NamedTemporaryFile(mode='w', suffix='.js') as script:
    script.write('\n'.join(parser.scripts))
    script.flush()
    subprocess.run(['node', '--check', script.name], check=True)
if errors:
    raise SystemExit('\n'.join(errors))
print(f'Passed: {checked} local Markdown links; 857 routes / 123 observed / 120 responses; '
      'JSON, SVG, prototype IDs and JavaScript syntax.')
