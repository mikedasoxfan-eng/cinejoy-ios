"""Collect unchanged native screenshots with their XCTest provenance."""
import argparse
import html
import json
import re
import shutil
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("inputs", nargs="+", type=Path)
parser.add_argument("--out", required=True, type=Path)
parser.add_argument("--note", required=True)
args = parser.parse_args()
images = args.out / "images"
images.mkdir(parents=True, exist_ok=True)
captures = []
for root in args.inputs:
    seen = set()
    for manifest in sorted(root.rglob("manifest.json")):
        for test in json.loads(manifest.read_text()):
            for attachment in test.get("attachments", []):
                exported = attachment.get("exportedFileName", "")
                if Path(exported).name != exported:
                    continue
                source = manifest.parent / exported
                if source.suffix.lower() != ".png" or not source.is_file():
                    continue
                seen.add(source.resolve())
                title = re.split(r"_\d+_[0-9A-Fa-f-]{36}", attachment.get("suggestedHumanReadableName", source.stem))[0]
                captures.append((source, title, test.get("testIdentifier", ""), attachment.get("deviceName", ""), attachment.get("isAssociatedWithFailure", False)))
    for source in sorted(root.rglob("*.png")):
        if source.resolve() not in seen and "named" not in source.parts:
            captures.append((source, source.stem, "Standalone Simulator capture", "", False))

records = []
cards = []
for index, (source, title, test, device, failed) in enumerate(captures, 1):
    filename = f"{index:02d}-{re.sub(r'[^A-Za-z0-9_-]+', '-', title)}.png"
    shutil.copy2(source, images / filename)
    records.append({"image": "images/" + filename, "title": title, "test": test, "device": device, "failure_attachment": failed, "source": str(source.resolve())})
    label = html.escape(title)
    provenance = html.escape(" · ".join(x for x in (device, test) if x))
    warning = "<strong>Failure attachment</strong>" if failed else ""
    cards.append(f'<article><h2>{label}</h2>{warning}<a href="images/{filename}"><img src="images/{filename}" loading="lazy" alt="{label}"></a><p>{provenance}</p></article>')

args.out.mkdir(parents=True, exist_ok=True)
(args.out / "captures.json").write_text(json.dumps(records, indent=2))
(args.out / "index.html").write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Cinejoy native review</title><style>body{margin:0;padding:28px;background:#101210;color:#f3f5f2;font:16px system-ui}header{max-width:1100px;margin:0 auto 28px}h1{font-size:30px}p{color:#aeb6ab;line-height:1.5;overflow-wrap:anywhere}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:24px;max-width:1500px;margin:auto}article{background:#1b201a;border:1px solid #30392e;border-radius:16px;padding:14px}h2{font-size:16px}img{display:block;width:100%;height:540px;object-fit:contain;background:#090b09;border-radius:8px}strong{color:#ffb6a4}</style><header><h1>Cinejoy · native Simulator review</h1><p>''' + html.escape(args.note) + f'</p><p>{len(records)} original captures. Click an image for full resolution. Capture provenance is recorded below each image.</p></header><main class="grid">' + "".join(cards) + "</main></html>")
print(f"Collected {len(records)} unchanged screenshots in {args.out}")
