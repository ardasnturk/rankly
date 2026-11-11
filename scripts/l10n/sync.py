#!/usr/bin/env python3
"""Sync Rankly/Localizable.xcstrings with the strings the compiler extracted, then apply translations.

1. Build once (SWIFT_EMIT_LOC_STRINGS=YES writes *.stringsdata into build/…/Objects-normal).
2. python3 scripts/l10n/sync.py            -> adds new keys, drops keys no longer in code,
                                              writes scripts/l10n/keys.json (sorted key list)
3. Translations live in scripts/l10n/<lang>.json as {"<key>": "<translation>"}; this script merges
   them into the catalog. Missing translations fall back to English at runtime.
"""
import glob, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(ROOT, "Rankly", "Localizable.xcstrings")
LANGS = ["de", "es", "fr", "it", "ja", "ko", "pt-BR", "tr", "zh-Hans"]

keys = {}
for f in glob.glob(os.path.join(ROOT, "build/Build/Intermediates.noindex/Rankly.build/Debug/Rankly.build/Objects-normal/arm64/*.stringsdata")):
    data = json.load(open(f))
    for table, entries in data.get("tables", {}).items():
        if table != "Localizable":
            continue
        for e in entries:
            keys.setdefault(e["key"], e.get("comment"))
if not keys:
    sys.exit("No .stringsdata found — build the Debug configuration first.")
swift = glob.glob(os.path.join(ROOT, "Rankly", "*.swift"))
data = glob.glob(os.path.join(ROOT, "build/Build/Intermediates.noindex/Rankly.build/Debug/Rankly.build/Objects-normal/arm64/*.stringsdata"))
if len(data) < len(swift) and "--force" not in sys.argv:
    sys.exit(f"Only {len(data)} .stringsdata files for {len(swift)} Swift files (incremental build?). "
             "Do a clean Debug build first, or pass --force.")

cat = json.load(open(CATALOG))
old = cat.get("strings", {})
strings = {}
for k in sorted(keys):
    entry = old.get(k, {})
    if keys[k]:
        entry["comment"] = keys[k]
    entry.setdefault("extractionState", "manual")
    strings[k] = entry

missing = {}
for lang in LANGS:
    path = os.path.join(ROOT, "scripts", "l10n", f"{lang}.json")
    tr = json.load(open(path)) if os.path.exists(path) else {}
    for k, entry in strings.items():
        v = tr.get(k)
        if v is None:
            # Strings with no letters (e.g. "%@ %@", "#%lld") need no translation.
            if any(ch.isalpha() for ch in k.replace("%lld", "").replace("%@", "").replace("%.1f", "")):
                missing.setdefault(lang, []).append(k)
            continue
        entry.setdefault("localizations", {})[lang] = {"stringUnit": {"state": "translated", "value": v}}

cat["strings"] = strings
json.dump(cat, open(CATALOG, "w"), ensure_ascii=False, indent=2, sort_keys=True)
json.dump(sorted(keys), open(os.path.join(ROOT, "scripts", "l10n", "keys.json"), "w"), ensure_ascii=False, indent=1)
print(f"{len(strings)} keys; removed {len(set(old) - set(strings))} stale")
for lang in LANGS:
    print(f"  {lang}: {len(missing.get(lang, []))} missing")
