#!/usr/bin/env python3
"""Extract the website's English source strings (data-i18n / data-i18n-attr in docs/*.html,
plus t("key", "fallback") calls in docs/assets/main.js) into scripts/l10n/site-en.json."""
import glob, json, os, re
from html.parser import HTMLParser

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DOCS = os.path.join(ROOT, "docs")
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}

class P(HTMLParser):
    def __init__(self, raw):
        super().__init__(convert_charrefs=False); self.raw = raw; self.out = {}; self.stack = []
        self.lines = raw.split("\n"); self.offsets = [0]
        for l in self.lines: self.offsets.append(self.offsets[-1] + len(l) + 1)
    def pos(self):
        line, col = self.getpos(); return self.offsets[line - 1] + col
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if "data-i18n-attr" in a:
            for pair in a["data-i18n-attr"].split(";"):
                if ":" in pair:
                    attr, key = [x.strip() for x in pair.split(":", 1)]
                    if a.get(attr) is not None: self.out.setdefault(key, a[attr])
        if tag in VOID: return
        start = self.pos() + len(self.get_starttag_text())
        self.stack.append((tag, a.get("data-i18n"), start))
    def handle_endtag(self, tag):
        while self.stack:
            t, key, start = self.stack.pop()
            if key: self.out.setdefault(key, self.raw[start:self.pos()].strip())
            if t == tag: break

out = {}
for f in sorted(glob.glob(os.path.join(DOCS, "*.html"))):
    raw = open(f).read(); p = P(raw); p.feed(raw); out.update({k: v for k, v in p.out.items() if k not in out})
js = open(os.path.join(DOCS, "assets", "main.js")).read()
for k, v in re.findall(r'\bt\("([\w.\-]+)",\s*"((?:[^"\\]|\\.)*)"\)', js):
    out.setdefault(k, v)
json.dump(out, open(os.path.join(ROOT, "scripts", "l10n", "site-en.json"), "w"), ensure_ascii=False, indent=1)
print(len(out), "keys")
