#!/usr/bin/env python3
"""Record source-to-final identities after local geometry and visual review."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--packet", type=Path, default=Path(__file__).resolve().parents[1] / "docs/aso/2026-10-07-duo/materials")
packet = parser.parse_args().packet
order = json.loads((packet / "order.json").read_text())
validation = json.loads((packet / "validation.json").read_text())
if validation.get("status") != "PASS" or validation.get("actualScreenshotCount") != 72:
    raise SystemExit("A completed 72-image structural audit is required")
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
reviews, groups, images = {}, {}, []
for family in validation["families"]:
    path = packet / f"visual-review-{family}.json"
    review = json.loads(path.read_text())
    if review.get("status") != "PASS" or len(review.get("images", [])) != 24:
        raise SystemExit(f"Incomplete visual review: {family}")
    reviews[family] = {entry["path"]:entry for entry in review["images"]}
for entry in validation["screenshots"]:
    final, source = packet / entry["path"], packet / entry["source"]
    if sha(final) != entry["sha256"] or sha(source) != entry["sourceSHA256"]:
        raise SystemExit(f"Stale structural audit: {final}")
    locale, name = Path(entry["source"]).parts[-2:]
    family, source_key = name[:-4].split("-", 1)
    capture_path = packet / "capture-records" / locale / f"{family}-{source_key}.json"
    capture = json.loads(capture_path.read_text())
    review = reviews[family].get(entry["path"], {})
    if (review.get("status") != "PASS" or review.get("finalSHA256") != sha(final) or
            review.get("sourceSHA256") != sha(source) or capture.get("sha256") != sha(source)):
        raise SystemExit(f"Stale capture or visual review: {final}")
    binaries = capture["installedExecutableSHA256"]
    group_key = json.dumps(binaries, sort_keys=True)
    groups.setdefault(group_key, {"installedExecutables":binaries, "sources":[]})["sources"].append(entry["source"])
    images.append({"locale":locale, "family":family, "source":entry["source"], "sourceSHA256":sha(source),
                   "final":entry["path"], "finalSHA256":sha(final), "nativePixels":capture["pixels"],
                   "canvasPixels":entry["pixels"], "capturedAtUTC":capture["capturedAtUTC"],
                   "deviceId":capture["deviceId"], "displayId":capture.get("displayId"),
                   "developerDirectory":capture["developerDirectory"], "appVersion":capture["appVersion"],
                   "buildNumber":capture["buildNumber"], "captureRecord":str(capture_path.relative_to(packet)),
                   "installedExecutableSHA256":binaries, "visualReview":f"visual-review-{family}.json"})
result = {"status":"LOCAL_VALIDATED", "recordedAtUTC":datetime.now(timezone.utc).isoformat(),
          "count":len(images), "locales":order["locales"], "families":validation["families"],
          "scope":"Actual simulator Debug source captures plus localized opaque RGB marketing canvases. Complete native source frames are embedded proportionally; source bytes are retained. Separate local geometry and visual reviews passed. No archive equivalence, remote asset acceptance, submission or public release is asserted.",
          "binaryScope":"Actual installed executable/debug dylib identities are recorded per capture; mixed source binaries remain separate groups. No single-binary or Release-archive provenance is inferred.",
          "captureIsolation":"HTML_PREVIEWER_UI_TESTS=1, isolated UITestLibrary/preferences, synthetic local templates and built-in samples; 9:41 status override during capture only.",
          "duoScope":"One six-image group, three actual Open inner-display captures and three Closed outer-display captures per locale. Automatic device-pose-specific storefront selection is not claimed.",
          "pipelineHashes":{path.name:sha(path) for path in [packet/"copy.json", packet/"devices.json", packet/"order.json", Path(__file__).parent/"generate-app-store-screenshots.swift"]},
          "binaryGroups":[dict(group, sourceCount=len(group["sources"])) for group in groups.values()],
          "images":images}
history = packet / "post-capture-source-changes.json"
if history.is_file():
    result["postCaptureSourceChanges"] = json.loads(history.read_text())
(packet / "provenance.json").write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
print(json.dumps({"status":result["status"], "count":len(images), "binaryGroups":len(groups)}))
