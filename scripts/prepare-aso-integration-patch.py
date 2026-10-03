#!/usr/bin/env python3
"""Prepare, but do not apply, the next-release ASO pipeline changes."""
import difflib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
packet = ROOT / "docs/aso/2026-10-03/materials"
order = json.loads((packet / "order.json").read_text())
renames = dict(zip(order["sourceKeys"], order["outputSuffixes"]))
patch = []
paths = [".github/workflows/app-store-upload.yml", ".github/scripts/submit-app-store-review.rb",
         "scripts/portable-release-materials-audit.sh", "scripts/release-audit.sh",
         "scripts/capture-release-screenshots.sh"]
for name in paths:
    old = (ROOT / name).read_text()
    new = old
    for key in renames:
        new = new.replace(key, "ASO_TEMP_" + key)
    for key, value in renames.items():
        new = new.replace("ASO_TEMP_" + key, value)
    for opening, closing in [("[", "]"), ("{", "}"), ("(", ")")]:
        new = new.replace(opening + '"en-US", "zh-Hans", "ja"' + closing,
                          opening + '"en-US", "zh-Hans", "ja", "zh-Hant"' + closing)
    new = new.replace("en-US zh-Hans ja", "en-US zh-Hans ja zh-Hant")
    if name.endswith("capture-release-screenshots.sh"):
        # Capture source keys are stable. Only defaults for final composition change.
        new = old.replace("en-US zh-Hans ja", "en-US zh-Hans ja zh-Hant")
        new = new.replace('SCREENSHOT_ORDER="${SCREENSHOT_ORDER:-}"',
                          'SCREENSHOT_ORDER="${SCREENSHOT_ORDER:-' + ','.join(order["sourceKeys"]) + '}"')
    if name.endswith(".yml"):
        new = new.replace('"36"', '"48"').replace("Expected 36 localized", "Expected 48 localized")
    if name.endswith("submit-app-store-review.rb"):
        for family in ["iphone", "ipad"]:
            pattern = rf'{family}-01-html-report\.png\n(?:    {family}-[^\n]+\.png\n){{5}}'
            block = "\n".join("    " + family + "-" + suffix + ".png" for suffix in order["outputSuffixes"]) + "\n"
            new, count = re.subn(pattern, block.lstrip(), new)
            if count != 1:
                raise SystemExit(f"Review script changed; inspect {family} inventory before preparing patch")
    if name.endswith("audit.sh"):
        # Marketing copy and raw captures deliberately retain their old source keys.
        for pattern in [r"required_copy_keys = \{[^}]+\}", r"required_screenshots = \{[^}]+\}"]:
            match = re.search(pattern, old)
            if match:
                new = re.sub(pattern, lambda _: match.group(), new)
        new = new.replace("copy covers en-US, zh-Hans, and ja", "copy covers en-US, zh-Hans, ja, and zh-Hant")
    patch.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile="a/" + name, tofile="b/" + name))
(packet / "next-release-integration.patch").write_text("".join(patch))
print("Prepared next-release integration patch; not applied.")
