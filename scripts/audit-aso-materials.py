#!/usr/bin/env python3
"""Validate a local ASO packet; never access or change App Store Connect."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--packet", type=Path, default=ROOT / "docs/aso/2026-10-03/materials")
parser.add_argument("--locales", help="Comma-separated subset for staged capture validation")
parser.add_argument("--families", help="Comma-separated subset for staged capture validation")
parser.add_argument("--sources-only", action="store_true")
parser.add_argument("--output", type=Path, help="Write a staged audit separately from the complete packet validation")
args = parser.parse_args()
packet = args.packet
order = json.loads((packet / "order.json").read_text())
candidate = json.loads((packet.parent / "metadata-candidate.json").read_text())
copy = json.loads((packet / "copy.json").read_text())
devices = [{"prefix": "iphone", "width": 1320, "height": 2868, "isPhone": True},
           {"prefix": "ipad", "width": 2064, "height": 2752, "isPhone": False}]
if order.get("deviceConfig"):
    devices = json.loads((packet / order["deviceConfig"]).read_text())["devices"]
configured_families = {d["prefix"] for d in devices}
locales = args.locales.split(",") if args.locales else order["locales"]
families = args.families.split(",") if args.families else [d["prefix"] for d in devices]
if not set(locales) <= set(order["locales"]) or not set(families) <= {d["prefix"] for d in devices}:
    parser.error("Unknown locale or family")
devices = [d for d in devices if d["prefix"] in families]
if len(order["sourceKeys"]) != len(order["outputSuffixes"]) or len(set(order["sourceKeys"])) != 6 or len(set(order["outputSuffixes"])) != 6:
    parser.error("Order must pair six distinct source keys with six outputs")
errors, files, sources, metadata = [], [], [], {}
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()

for locale in locales:
    metadata[locale] = {}
    for field, limit in {"name": 30, "subtitle": 30, "keywords": 100, "promotional_text": 170, "description": 4000}.items():
        path = packet / "metadata" / locale / (field + ".txt")
        value = path.read_text().rstrip("\n") if path.exists() else ""
        metadata[locale][field] = {"characters": len(value), "limit": limit}
        if value != candidate["locales"][locale][field] or not 0 < len(value) <= limit:
            errors.append(f"Invalid metadata: {locale}/{field}")
    if set(copy[locale]["screenshots"]) != set(order["sourceKeys"]):
        errors.append(f"Invalid screenshot copy keys: {locale}")
    for device in devices:
        family = device["prefix"]
        device_copy = copy[locale].get("deviceScreenshots", {}).get(family, copy[locale]["screenshots"])
        if set(device_copy) != set(order["sourceKeys"]) or any(not entry.get(f, "").strip() for entry in device_copy.values() for f in ["eyebrow", "title", "subtitle"]):
            errors.append(f"Invalid screenshot copy: {locale}/{family}")
        expected = {f"{family}-{suffix}.png" for suffix in order["outputSuffixes"]}
        found = {p.name for p in (packet / "screenshots" / locale).glob(f"{family}-*.png")}
        if not args.sources_only and found != expected:
            errors.append(f"Invalid final inventory: {locale}/{family}: missing={sorted(expected-found)}, extra={sorted(found-expected)}")
        for source, suffix in zip(order["sourceKeys"], order["outputSuffixes"]):
            source_path = packet / "sources" / locale / f"{family}-{source}.png"
            path = packet / "screenshots" / locale / f"{family}-{suffix}.png"
            frame = device.get("frames", {}).get(source, device)
            size = (frame["width"], frame["height"])
            if not source_path.is_file():
                errors.append(f"Missing source: {locale}/{family}/{source}")
                continue
            with Image.open(source_path) as im:
                native = im.size
                if family == "duo":
                    expected_source = (frame.get("sourceWidth", frame["width"]), frame.get("sourceHeight", frame["height"]))
                    if native != expected_source:
                        errors.append(f"Wrong Duo display/orientation: {source_path}: {native}, expected {expected_source}")
                else:
                    limits = (.43, .50) if device["isPhone"] else (.65, .80)
                    if native[0] >= native[1] or not limits[0] <= native[0] / native[1] <= limits[1]:
                        errors.append(f"Unsupported native aspect: {source_path}: {native}")
                sources.append({"path": str(source_path.relative_to(packet)), "pixels": list(native), "mode": im.mode, "sha256": sha(source_path)})
            record_path = packet / "capture-records" / locale / f"{family}-{source}.json"
            if order.get("deviceConfig"):
                if not record_path.exists():
                    errors.append(f"Missing capture identity: {record_path}")
                else:
                    record = json.loads(record_path.read_text())
                    if record.get("sha256") != sha(source_path) or record.get("pixels") != list(native) or record.get("locale") != locale:
                        errors.append(f"Capture identity mismatch: {record_path}")
                    if record.get("appVersion") != "1.8" or record.get("buildNumber") != "13":
                        errors.append(f"Capture is not target 1.8(13): {record_path}")
                    if family == "duo" and record.get("displayId") != frame["displayId"]:
                        errors.append(f"Capture display mismatch: {record_path}")
            if args.sources_only:
                continue
            if not path.is_file():
                errors.append(f"Missing final screenshot: {locale}/{family}/{suffix}")
                continue
            with Image.open(path) as im:
                im.load()
                if im.size != size or im.mode != "RGB" or "transparency" in im.info:
                    errors.append(f"Invalid canvas or opacity: {path}: {im.size}/{im.mode}")
                files.append({"path": str(path.relative_to(packet)), "pixels": list(im.size), "mode": im.mode,
                              "sha256": sha(path), "source": str(source_path.relative_to(packet)), "sourceSHA256": sha(source_path)})
        if not args.sources_only and not (packet / "previews" / f"{locale}-{family}.png").is_file():
            errors.append(f"Missing contact sheet: {locale}/{family}")

expected_count = len(locales) * len(devices) * len(order["sourceKeys"])
result = {"status": "PASS" if not errors else "FAIL", "scope": "Local metadata, native source aspect/identity, exact PNG canvas, RGB opacity, per-group inventory and hashes. Does not prove visual review, App Store acceptance, upload or release.",
          "sourcesOnly": args.sources_only, "locales": locales, "families": families,
          "expectedScreenshotCount": expected_count, "actualScreenshotCount": len(files), "actualSourceCount": len(sources),
          "metadata": metadata, "sources": sources, "screenshots": files, "errors": errors}
output = args.output or packet / ("source-validation.json" if args.sources_only else "validation.json")
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
if not args.sources_only and not errors and set(locales) == set(order["locales"]) and set(families) == configured_families:
    (packet / "checksums-sha256.txt").write_text("".join(f'{entry["sha256"]}  {entry["path"]}\n' for entry in files))
print(json.dumps({"status": result["status"], "sources": len(sources), "screenshots": len(files), "expected": expected_count, "errors": errors}, ensure_ascii=False))
raise SystemExit(bool(errors))
