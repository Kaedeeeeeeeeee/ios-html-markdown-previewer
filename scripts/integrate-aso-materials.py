#!/usr/bin/env python3
"""Mirror a validated 72-image packet into the canonical local upload inputs.

Dry-run by default. --apply changes only local screenshots and copy.json,
preserves old bytes in a unique /tmp backup, and never accesses App Store Connect.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--packet", type=Path, default=ROOT / "docs/aso/2026-10-07-duo/materials")
parser.add_argument("--apply", action="store_true")
args = parser.parse_args()
packet = args.packet.resolve()
target = ROOT / "docs/app-store-screenshots"
order = json.loads((packet / "order.json").read_text())
devices = json.loads((packet / order["deviceConfig"]).read_text())["devices"]
validation = json.loads((packet / "validation.json").read_text())
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
families = {d["prefix"] for d in devices}
if (set(order["locales"]) != {"en-US", "zh-Hans", "ja", "zh-Hant"} or
        families != {"iphone", "ipad", "duo"} or len(order["outputSuffixes"]) != 6 or len(set(order["outputSuffixes"])) != 6):
    raise SystemExit("Refusing a different locale/family/scene matrix")
if validation.get("status") != "PASS" or validation.get("actualScreenshotCount") != 72 or validation.get("errors"):
    raise SystemExit("Full 72-image packet validation must pass before integration")
validated = {entry["path"]: entry for entry in validation["screenshots"]}
copies = []
for locale in order["locales"]:
    for device in devices:
        for suffix in order["outputSuffixes"]:
            name = f'{device["prefix"]}-{suffix}.png'
            source = packet / "screenshots" / locale / name
            entry = validated.get(str(source.relative_to(packet)), {})
            native = packet / entry.get("source", "missing-source")
            if not source.is_file() or sha(source) != entry.get("sha256") or not native.is_file() or sha(native) != entry.get("sourceSHA256"):
                raise SystemExit(f"Validation is stale: {source}")
            copies.append((source, target / locale / name))
            if locale == "en-US":
                copies.append((source, target / name))
copies.append((packet / "copy.json", target / "copy.json"))
old_files = [p for folder in [target, *(target / locale for locale in order["locales"])] for p in folder.glob("*.png")]
if any(not any(p.name.startswith(family + "-") for family in families) for p in old_files):
    raise SystemExit("Unrecognized existing PNG; inspect it before integration")
if (target / "copy.json").is_file():
    old_files.append(target / "copy.json")
if any(p.is_symlink() for p in old_files) or target.is_symlink() or any((target / locale).is_symlink() for locale in order["locales"]):
    raise SystemExit("Refusing symlink upload inputs")
result = {"status":"DRY_RUN", "packet":str(packet), "target":str(target),
          "localizedScreenshotCount":72, "englishCompatibilityCount":18,
          "scope":"Local exact-byte screenshot/copy integration only; no metadata mutation, upload, archive equivalence, or publication.",
          "oldFileCount":len(old_files)}
if args.apply:
    backup = Path(tempfile.mkdtemp(prefix="html-aso-formal-before-integration-", dir="/tmp"))
    prior = []
    for old in old_files:
        relative, digest = old.relative_to(target), sha(old)
        saved = backup / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(old, saved)
        if sha(saved) != digest or sha(old) != digest:
            raise SystemExit(f"Backup identity changed: {old}")
        prior.append({"path":str(relative), "sha256":digest})
    destinations = {destination for _, destination in copies}
    for source, destination in copies:
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name("." + destination.name + ".integrating")
        shutil.copy2(source, temporary)
        if sha(temporary) != sha(source):
            raise SystemExit(f"Copy identity changed: {source}")
        temporary.replace(destination)
    for old in old_files:
        if old not in destinations:
            old.unlink()
    if any(sha(source) != sha(destination) for source, destination in copies):
        raise SystemExit("Integrated copies differ; old bytes are retained in backup")
    result.update(status="PASS", integratedAtUTC=datetime.now(timezone.utc).isoformat(),
                  oldInputsBackup=str(backup), previousInputs=prior,
                  files=[{"path":str(destination.relative_to(ROOT)), "sha256":sha(destination)} for _, destination in copies])
    (packet / "local-integration.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({k:v for k,v in result.items() if k not in {"files", "previousInputs"}}, ensure_ascii=False))
