#!/usr/bin/env python3
"""Check shipped YAML assets against their reviewed source and npm lockfile."""
import hashlib
import json
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
vendor = root / "scripts/vendor-yaml"
resources = root / "HTMLMarkdownPreviewer/Resources/YAML"
manifest = json.loads((resources / "manifest.json").read_text())
lock = json.loads((vendor / "package-lock.json").read_text())
package = json.loads((vendor / "package.json").read_text())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


assert manifest["sourceSHA256"] == digest(vendor / "runtime.mjs"), "Rebuild changed YAML source"
assert manifest["lockSHA256"] == digest(vendor / "package-lock.json"), "Rebuild changed YAML lockfile"
assert manifest["global"] == "YAMLRuntime"
assert {item["name"] for item in manifest["dependencies"]} == {"yaml", "highlight.js"}
for dependency in manifest["dependencies"]:
    name = dependency["name"]
    pinned = lock["packages"][f"node_modules/{name}"]
    assert dependency["version"] == package["dependencies"][name] == pinned["version"]
    assert dependency["tarball"] == pinned["resolved"]
    assert dependency["integrity"] == pinned["integrity"]
    assert dependency["license"]
for asset in manifest["assets"]:
    path = resources / asset["path"]
    assert path.resolve().parent == resources.resolve(), "Asset escaped resource directory"
    assert path.stat().st_size == asset["bytes"]
    assert digest(path) == asset["sha256"], f"Changed generated asset: {path.name}"
notices = (resources / "THIRD-PARTY-LICENSES.txt").read_text()
assert "yaml 2.9.1" in notices and "highlight.js 11.12.0" in notices

info = plistlib.loads((root / "HTMLMarkdownPreviewer/Info.plist").read_bytes())
assert any("public.yaml" in item["LSItemContentTypes"] for item in info["CFBundleDocumentTypes"])
yaml_type = next(item for item in info["UTImportedTypeDeclarations"] if item["UTTypeIdentifier"] == "public.yaml")
assert {"yaml", "yml"} <= set(yaml_type["UTTypeTagSpecification"]["public.filename-extension"])

baseline = None
for language in ["en", "zh-Hans", "zh-Hant", "ja"]:
    path = root / f"HTMLMarkdownPreviewer/{language}.lproj/YAML.strings"
    pairs = re.findall(r'^"([^"]+)"\s*=\s*"((?:\\.|[^"\\])*)";', path.read_text(), re.MULTILINE)
    strings = dict(pairs)
    assert len(strings) == len(pairs), f"Duplicate YAML strings in {language}"
    assert strings and all(value.strip() for value in strings.values())
    formats = {key: sorted(re.findall(r"%(?:\d+\$)?[@d]", value)) for key, value in strings.items()}
    if baseline is None:
        baseline = formats
    else:
        assert formats == baseline, f"YAML localization keys or placeholders differ in {language}"

print("YAML runtime source, asset hashes, pinned provenance, type declarations, and four localizations verified.")
