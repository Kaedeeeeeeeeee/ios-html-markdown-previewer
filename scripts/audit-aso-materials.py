#!/usr/bin/env python3
"""Validate the local release-material packet without accessing App Store Connect."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--packet", type=Path, default=ROOT / "docs/aso/2026-10-03/materials")
args = parser.parse_args()
packet = args.packet
order = json.loads((packet / "order.json").read_text())
candidate = json.loads((packet.parent / "metadata-candidate.json").read_text())
copy = json.loads((packet / "copy.json").read_text())
errors, files, metadata = [], [], {}

for locale in order["locales"]:
    metadata[locale] = {}
    for field, limit in {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000}.items():
        path = packet / "metadata" / locale / (field + ".txt")
        value = path.read_text().rstrip("\n")
        metadata[locale][field] = {"characters": len(value), "limit": limit}
        if value != candidate["locales"][locale][field] or not 0 < len(value) <= limit:
            errors.append(f"Invalid metadata: {locale}/{field}")
    if set(copy[locale]["screenshots"]) != set(order["sourceKeys"]):
        errors.append(f"Invalid screenshot copy keys: {locale}")
    expected = {f"{family}-{suffix}.png" for family in ["iphone", "ipad"] for suffix in order["outputSuffixes"]}
    found = {p.name for p in (packet / "screenshots" / locale).glob("*.png")}
    if found != expected:
        errors.append(f"Invalid final inventory: {locale}: missing={sorted(expected-found)}, extra={sorted(found-expected)}")
    for family, size in [("iphone", (1320, 2868)), ("ipad", (2064, 2752))]:
        for source, suffix in zip(order["sourceKeys"], order["outputSuffixes"]):
            source_path = packet / "sources" / locale / f"{family}-{source}.png"
            path = packet / "screenshots" / locale / f"{family}-{suffix}.png"
            if not source_path.is_file() or not path.is_file():
                errors.append(f"Missing source or screenshot: {locale}/{family}/{suffix}")
                continue
            with Image.open(path) as im:
                im.load()
                if im.size != size or "A" in im.getbands() or "transparency" in im.info:
                    errors.append(f"Invalid size or transparency: {path}")
                files.append({"path": str(path.relative_to(packet)), "pixels": list(im.size), "mode": im.mode,
                              "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                              "source": str(source_path.relative_to(packet)),
                              "sourceSHA256": hashlib.sha256(source_path.read_bytes()).hexdigest()})
    preview = packet / "previews" / f"{locale}-iphone.png"
    if not preview.is_file():
        errors.append(f"Missing contact sheet: {locale}")

result = {"status": "PASS" if not errors else "FAIL", "scope": "Local metadata, PNG dimensions, opacity, inventory, source pairing and checksums. Does not prove final-build equivalence, App Store acceptance, upload, review, or release.",
          "expectedScreenshotCount": 48, "actualScreenshotCount": len(files), "metadata": metadata, "screenshots": files, "errors": errors}
(packet / "validation.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"status": result["status"], "screenshots": len(files), "errors": errors}, ensure_ascii=False))
raise SystemExit(bool(errors))
