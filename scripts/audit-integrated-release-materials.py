#!/usr/bin/env python3
"""Check that the next-release upload paths contain the approved local ASO packet."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, help="Optional JSON evidence path")
args = parser.parse_args()
packet = ROOT / "docs/aso/2026-10-03/materials"
order = json.loads((packet / "order.json").read_text())
candidate = json.loads((packet.parent / "metadata-candidate.json").read_text())
errors, screenshots, metadata = [], [], {}


def check(condition, message):
    if not condition:
        errors.append(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def value(path):
    return path.read_text().rstrip("\n") if path.is_file() else ""


project = (ROOT / "project.yml").read_text()
def project_setting(key):
    match = re.search(r'^\s*' + key + r':\s*"?([^"\s#]+)"?\s*$', project, re.M)
    if not match:
        raise SystemExit(f"Missing {key} in project.yml")
    return match.group(1)


version = project_setting("MARKETING_VERSION")
build = project_setting("CURRENT_PROJECT_VERSION")
workflow = (ROOT / ".github/workflows/app-store-upload.yml").read_text()
backend = (ROOT / ".github/scripts/submit-app-store-review.rb").read_text()
check(f'APP_STORE_CONNECT_VERSION_STRING: "{version}"' in workflow, "Upload workflow version mismatch")
check(f'APP_STORE_CONNECT_BUILD_NUMBER: "{build}"' in workflow, "Upload workflow build mismatch")
locales = order["locales"]
check(f'for locale in {" ".join(locales)}; do' in workflow, "Upload workflow locale mismatch")
check(f'EXPECTED_SCREENSHOT_LOCALES = %w[{" ".join(locales)}]' in backend, "Backend locale mismatch")
check('"48"' in workflow, "Upload workflow must require 48 screenshots")
check(json.loads((ROOT / "docs/app-store-screenshots/copy.json").read_text()) ==
      json.loads((packet / "copy.json").read_text()), "Integrated screenshot copy differs from packet")

for family, display_type, dimensions in [("iphone", "APP_IPHONE_67", (1320, 2868)),
                                         ("ipad", "APP_IPAD_PRO_3GEN_129", (2064, 2752))]:
    names = [f"{family}-{suffix}.png" for suffix in order["outputSuffixes"]]
    found = re.search(r'"' + display_type + r'"\s*=>\s*%w\[([^\]]+)\]', backend)
    check(found is not None and found.group(1).split() == names, f"Backend order differs: {family}")
    for locale in locales:
        folder = ROOT / "docs/app-store-screenshots" / locale
        expected_inventory = {f"{f}-{s}.png" for f in ["iphone", "ipad"] for s in order["outputSuffixes"]}
        check({p.name for p in folder.glob("*.png")} == expected_inventory, f"Screenshot inventory differs: {locale}")
        for name in names:
            path, source = folder / name, packet / "screenshots" / locale / name
            if not path.is_file() or not source.is_file():
                errors.append(f"Missing integrated or packet screenshot: {locale}/{name}")
                continue
            raw = path.read_bytes()
            check(raw[:8] == b"\x89PNG\r\n\x1a\n", f"Not PNG: {locale}/{name}")
            width, height, depth, color = struct.unpack(">IIBB", raw[16:26])
            check((width, height) == dimensions and depth == 8 and color == 2,
                  f"Invalid dimensions or opaque RGB encoding: {locale}/{name}")
            offset, has_transparency = 8, False
            while offset + 12 <= len(raw):
                length = struct.unpack(">I", raw[offset:offset + 4])[0]
                chunk = raw[offset + 4:offset + 8]
                has_transparency |= chunk == b"tRNS"
                offset += length + 12
                if chunk == b"IEND":
                    break
            check(not has_transparency, f"Transparent PNG: {locale}/{name}")
            digest = sha(path)
            check(digest == sha(source), f"Integrated screenshot differs from packet: {locale}/{name}")
            if locale == "en-US":
                compatibility_copy = ROOT / "docs/app-store-screenshots" / name
                check(compatibility_copy.is_file() and sha(compatibility_copy) == digest,
                      f"English compatibility copy differs: {name}")
            screenshots.append({"path": str(path.relative_to(ROOT)), "sha256": digest,
                                "pixels": [width, height]})

for locale in locales:
    metadata[locale] = {}
    for field, limit in {"name": 30, "subtitle": 30, "keywords": 100,
                         "promotional_text": 170, "description": 4000}.items():
        path = ROOT / "fastlane/metadata" / locale / f"{field}.txt"
        text = value(path)
        check(text == candidate["locales"][locale][field], f"Integrated metadata differs: {locale}/{field}")
        check(0 < len(text) <= limit, f"Metadata length invalid: {locale}/{field}")
        metadata[locale][field] = {"characters": len(text), "limit": limit,
                                   "sha256": sha(path) if path.is_file() else None}
    release = value(ROOT / "fastlane/metadata" / locale / "release_notes.txt")
    check(0 < len(release) <= 4000, f"Release notes missing or too long: {locale}")
    check(release == value(ROOT / "docs/updates" / f"{version}-release-notes-{locale}.txt"),
          f"Release notes handoff differs: {locale}")
    for field in ["privacy_url", "support_url"]:
        check(value(ROOT / "fastlane/metadata" / locale / f"{field}.txt").startswith("https://"),
              f"Missing HTTPS URL: {locale}/{field}")

check(len(screenshots) == 48, f"Expected 48 integrated screenshots, found {len(screenshots)}")
result = {"status": "PASS" if not errors else "FAIL", "version": version, "build": build,
          "scope": "Local upload-path identity, metadata limits, release-note identity, PNG inventory, encoding and backend order. No upload, Apple acceptance, review or release is verified.",
          "locales": locales, "screenshotCount": len(screenshots), "metadata": metadata,
          "screenshots": screenshots, "errors": errors}
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({k: result[k] for k in ["status", "version", "build", "screenshotCount", "errors"]}))
raise SystemExit(bool(errors))
