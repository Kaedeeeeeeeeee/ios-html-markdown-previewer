#!/usr/bin/env python3
"""Verify that actual upload inputs match the new local release packet.

No App Store write, device operation, or release action is performed. The older
36/48-image materials cannot satisfy the new 72-image gate.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--packet", type=Path, default=ROOT / "docs/aso/2026-10-07-duo/materials")
parser.add_argument("--screenshots-path", type=Path, default=ROOT / "docs/app-store-screenshots")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
packet, upload = args.packet, args.screenshots_path
order = json.loads((packet / "order.json").read_text())
candidate = json.loads((packet.parent / "metadata-candidate.json").read_text())
devices = json.loads((packet / order["deviceConfig"]).read_text())["devices"]
errors, screenshots, metadata = [], [], {}
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
value = lambda path: path.read_text().rstrip("\n") if path.is_file() else ""

def check(condition, message):
    if not condition:
        errors.append(message)

def project_setting(key):
    match = re.search(r'^\s*' + key + r':\s*"?([^"\s#]+)"?\s*$', (ROOT / "project.yml").read_text(), re.M)
    if not match:
        raise SystemExit(f"Missing {key} in project.yml")
    return match.group(1)

def png_geometry(path):
    raw = path.read_bytes()
    if raw[:8] != b"\x89PNG\r\n\x1a\n" or len(raw) < 33:
        return None
    width, height, depth, color = struct.unpack(">IIBB", raw[16:26])
    offset, transparent = 8, False
    while offset + 12 <= len(raw):
        length = struct.unpack(">I", raw[offset:offset+4])[0]
        chunk = raw[offset+4:offset+8]
        transparent |= chunk == b"tRNS"
        offset += length + 12
        if chunk == b"IEND":
            break
    return width, height, depth, color, transparent

version, build = project_setting("MARKETING_VERSION"), project_setting("CURRENT_PROJECT_VERSION")
workflow = (ROOT / ".github/workflows/app-store-upload.yml").read_text()
check(f'APP_STORE_CONNECT_VERSION_STRING: "{version}"' in workflow, "Upload workflow version mismatch")
check(f'APP_STORE_CONNECT_BUILD_NUMBER: "{build}"' in workflow, "Upload workflow build mismatch")
locales = order["locales"]
expected_count = len(locales) * len(devices) * len(order["outputSuffixes"])
check(expected_count == 72, "Expected the approved four-locale, three-family, six-scene matrix")
check(len(set(order["sourceKeys"])) == 6 and len(set(order["outputSuffixes"])) == 6,
      "All six source scenes and final filenames must be distinct")
check(set(locales) == {"en-US", "zh-Hans", "ja", "zh-Hant"}, "Four-language inventory missing")
check({d["prefix"] for d in devices} == {"iphone", "ipad", "duo"}, "New Duo family missing")
# Distribution must verify the same canonical files with the modern GET-only
# gate. A stale legacy screenshot-sync step must not consume a different pack.
check('APP_STORE_CONNECT_SCREENSHOTS_PATH: ${{ github.workspace }}/docs/app-store-screenshots' in workflow,
      "Modern store-assets gate must use the integrated screenshot directory")
check('FASTLANE_METADATA_PATH: ${{ github.workspace }}/fastlane/metadata' in workflow,
      "Modern store-assets gate must use the integrated metadata directory")
check('APP_STORE_CONNECT_CHECK_STORE_ASSETS_ONLY: "true"' in workflow and
      'ruby .github/scripts/submit-app-store-review.rb' in workflow,
      "Upload workflow is missing the read-only modern store-assets gate")
check('cp -R "docs/app-store-screenshots/$locale"' not in workflow,
      "Obsolete screenshot staging remains in upload workflow")
store_gate = (ROOT / ".github/scripts/submit-app-store-review.rb").read_text()
for profile, family in {"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE":"iphone", "IPAD_13_PROFILE":"ipad", "IPHONE_DUO_PROFILE":"duo"}.items():
    check(re.search(r'[\"\']' + profile + r'[\"\']\s*=>\s*[\"\']' + family + r'[\"\']', store_gate),
          f"Modern store-assets gate profile mismatch: {profile}/{family}")
validation_path = packet / "validation.json"
validation = json.loads(validation_path.read_text()) if validation_path.exists() else {}
validated_images = {entry["path"]: entry for entry in validation.get("screenshots", [])}
check(validation.get("status") == "PASS" and validation.get("actualScreenshotCount") == 72,
      "New packet requires completed 72-image validation; old packet is not a substitute")
check((upload / "copy.json").is_file() and json.loads((upload / "copy.json").read_text()) == json.loads((packet / "copy.json").read_text()),
      "Integrated screenshot copy differs from new packet")
release_handoff = ROOT / "docs/updates" / f"{version}-release-notes.md"
check(release_handoff.is_file(), "Current release-note handoff is missing")
check("fastlane/metadata/{en-US,zh-Hans,ja,zh-Hant}/release_notes.txt" in value(release_handoff),
      "Release-note handoff must identify the four actual active metadata files")

for locale in locales:
    folder = upload / locale
    expected = {f'{d["prefix"]}-{s}.png' for d in devices for s in order["outputSuffixes"]}
    check({p.name for p in folder.glob("*.png")} == expected, f"Exact 18-image upload inventory differs: {locale}")
    for device in devices:
        family = device["prefix"]
        for source_key, suffix in zip(order["sourceKeys"], order["outputSuffixes"]):
            name = f"{family}-{suffix}.png"
            path, reference = folder / name, packet / "screenshots" / locale / name
            if not path.is_file() or not reference.is_file():
                errors.append(f"Missing integrated or packet screenshot: {locale}/{name}")
                continue
            frame = device.get("frames", {}).get(source_key, device)
            geometry = png_geometry(path)
            check(geometry == (frame["width"], frame["height"], 8, 2, False), f"Wrong size or opaque RGB encoding: {locale}/{name}")
            digest = sha(path)
            check(digest == sha(reference), f"Upload screenshot differs from packet: {locale}/{name}")
            validated = validated_images.get(f"screenshots/{locale}/{name}", {})
            check(validated.get("sha256") == digest, f"Packet validation is stale: {locale}/{name}")
            source_path = packet / "sources" / locale / f"{family}-{source_key}.png"
            check(source_path.is_file() and validated.get("sourceSHA256") == sha(source_path),
                  f"Source changed since packet validation: {locale}/{name}")
            capture_path = packet / "capture-records" / locale / f"{family}-{source_key}.json"
            capture = json.loads(capture_path.read_text()) if capture_path.exists() else {}
            check(capture.get("appVersion") == version and capture.get("buildNumber") == build,
                  f"Capture version differs from upload target: {locale}/{name}")
            check(capture.get("sha256") == validated.get("sourceSHA256") and bool(capture.get("installedExecutableSHA256")),
                  f"Capture identity missing or stale: {locale}/{name}")
            if upload.resolve() != (packet / "screenshots").resolve() and locale == "en-US":
                compatibility = upload / name
                check(compatibility.is_file() and sha(compatibility) == digest, f"English compatibility image differs: {name}")
            screenshots.append({"path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
                                "sha256": digest, "pixels": list(geometry[:2]) if geometry else None})
    metadata[locale] = {}
    for field, limit in {"name":30, "subtitle":30, "keywords":100, "promotional_text":170, "description":4000}.items():
        path = ROOT / "fastlane/metadata" / locale / f"{field}.txt"
        text = value(path)
        check(text == candidate["locales"][locale][field], f"Integrated metadata differs: {locale}/{field}")
        check(0 < len(text) <= limit, f"Metadata length invalid: {locale}/{field}")
        metadata[locale][field] = {"characters":len(text), "limit":limit, "sha256":sha(path) if path.exists() else None}
    release_path = ROOT / "fastlane/metadata" / locale / "release_notes.txt"
    release = value(release_path)
    check(0 < len(release) <= 4000, f"Missing or long release notes: {locale}")
    metadata[locale]["release_notes"] = {"characters":len(release), "limit":4000,
                                          "sha256":sha(release_path) if release_path.is_file() else None}
    for field in ["privacy_url", "support_url"]:
        path = ROOT / "fastlane/metadata" / locale / f"{field}.txt"
        text = value(path)
        check(text.startswith("https://"), f"Missing HTTPS URL: {locale}/{field}")
        check(text == value(packet / "metadata" / locale / f"{field}.txt"),
              f"Integrated URL differs from packet: {locale}/{field}")
        metadata[locale][field] = {"characters":len(text), "sha256":sha(path) if path.is_file() else None}

check(len(screenshots) == expected_count, f"Expected {expected_count} integrated images, found {len(screenshots)}")
result = {"status":"PASS" if not errors else "FAIL", "version":version, "build":build,
          "scope":"Local identity of actual upload inputs, new 72-image inventory, opaque PNG geometry, metadata and release-note handoff. No API enum, upload, Apple acceptance, review or release is asserted.",
          "packet":str(packet), "uploadPath":str(upload), "locales":locales, "families":[d["prefix"] for d in devices],
          "screenshotCount":len(screenshots), "metadata":metadata, "screenshots":screenshots, "errors":errors}
if args.output:
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
print(json.dumps({k:result[k] for k in ["status","version","build","screenshotCount","errors"]}))
raise SystemExit(bool(errors))
