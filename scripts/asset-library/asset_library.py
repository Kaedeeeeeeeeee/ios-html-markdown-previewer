#!/usr/bin/env python3
"""GET-only ASC discovery/readback and offline screenshot upload planning.

There is deliberately no apply command and no authenticated write request path.
The ASC CLI's JWT is captured in memory; it is never logged or saved.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import struct
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zlib

API = "https://api.appstoreconnect.apple.com"
IMAGE_FIELDS = "category,fileName,fileSize,referenceName,specId,state,stateDetails,imageAsset"


class GetOnlyAPI:
    def __init__(self):
        process = subprocess.run(["asc", "auth", "token", "--confirm"],
                                 capture_output=True, text=True)
        if process.returncode:
            raise ValueError("ASC token generation failed; check asc auth status (credentials are not logged)")
        self.token = process.stdout.strip()
        if self.token.count(".") != 2:
            raise ValueError("asc auth token returned an unexpected format (output is not logged)")

    def request(self, method, path):
        if method != "GET":
            raise ValueError("This API client permits GET only")
        return self.get(path)

    def get(self, path):
        url = urllib.parse.urljoin(API, path)
        parts = urllib.parse.urlsplit(url)
        if parts.scheme != "https" or parts.netloc != "api.appstoreconnect.apple.com":
            raise ValueError("Refusing to send credentials outside the ASC API host")
        request = urllib.request.Request(url, method="GET", headers={
            "Authorization": "Bearer " + self.token, "Accept": "application/json"})
        # Disable redirects so bearer credentials cannot follow an unexpected host.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise ValueError(f"ASC GET failed: HTTP {error.code} at {parts.path}") from None

    def list(self, path):
        data, included, seen = [], {}, set()
        while path:
            if path in seen:
                raise ValueError("ASC pagination cycle")
            seen.add(path)
            response = self.get(path)
            if not isinstance(response["data"], list):
                raise ValueError("Expected a collection response")
            data.extend(response["data"])
            for item in response.get("included", []):
                included[(item["type"], item["id"])] = item
            path = response.get("links", {}).get("next")
        return {"data": data, "included": list(included.values())}


def query(path, **parameters):
    return path + "?" + urllib.parse.urlencode(parameters)


def load(path):
    return json.loads(pathlib.Path(path).read_text())


def emit(value, output=None):
    text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
    if output:
        pathlib.Path(output).write_text(text)
        print(f"Wrote {output}")
    else:
        print(text, end="")


def catalog_attributes(response):
    data = response["data"]
    if isinstance(data, list):
        if len(data) != 1:
            raise ValueError("Expected one reference data resource")
        data = data[0]
    return data["attributes"]


def group_specification(catalog, group, placement_type="APP_SCREENSHOT"):
    attributes = catalog_attributes(catalog)
    profile = next((p for p in attributes["placementProfileGroups"]
                    if p["placementProfileGroupId"] == group), None)
    placement = next((p for p in attributes["placementTypes"]
                      if p["placementTypeId"] == placement_type), None)
    if not profile or not placement:
        raise ValueError("Unknown placement group/type; refresh reference data")
    mapping = next((p for p in placement["specMappings"]
                    if p["placementGroupId"] == group), None)
    feature = next(p for p in attributes["features"] if p["featureId"] == "APP_STORE_VERSIONS")
    limits = [limit["maxCount"] for policy in feature["placementPolicies"]
              if policy["placementType"] == placement_type
              for limit in policy["groupLimits"] if group in limit["groupIds"]]
    if not mapping or not limits:
        raise ValueError("Group/type unsupported for APP_STORE_VERSIONS")
    specifications = [s for s in attributes["imageSpecs"] if s["specId"] in mapping["specs"]]
    if not specifications:
        raise ValueError("No image specifications for this group")
    display = next(p for p in attributes["displayClasses"]
                   if p["displayClassId"] == profile["displayClassId"])
    return {"profile": profile, "displayClass": display,
            "categories": placement["acceptsAssetCategories"],
            "maxCount": min(limits), "specifications": specifications}


def image_metadata(path):
    """Check file structure/metadata; ASC performs final image decoding/validation."""
    path = pathlib.Path(path).resolve()
    data = path.read_bytes()
    width = height = None
    alpha = False
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        mime, offset, end, image_data = "image/png", 8, False, False
        first = True
        while offset + 12 <= len(data):
            size = struct.unpack_from(">I", data, offset)[0]
            kind = data[offset + 4:offset + 8]
            if offset + size + 12 > len(data):
                raise ValueError(f"Truncated PNG: {path}")
            body = data[offset + 8:offset + 8 + size]
            crc = struct.unpack_from(">I", data, offset + 8 + size)[0]
            if zlib.crc32(kind + body) & 0xffffffff != crc:
                raise ValueError(f"Invalid PNG CRC: {path}")
            if first and (kind != b"IHDR" or size != 13):
                raise ValueError(f"Invalid PNG header: {path}")
            first = False
            if kind == b"IHDR":
                width, height, _, color = struct.unpack_from(">IIBB", body)
                alpha = color in (4, 6)
            elif kind == b"tRNS":
                alpha = True
            elif kind == b"IDAT":
                image_data = True
            elif kind == b"IEND":
                end = size == 0
                break
            offset += size + 12
        if not end or not image_data:
            raise ValueError(f"Incomplete PNG: {path}")
    elif data.startswith(b"\xff\xd8"):
        mime, offset = "image/jpeg", 2
        sof = {0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf}
        while offset + 4 <= len(data):
            if data[offset] != 0xff:
                raise ValueError(f"Invalid JPEG marker: {path}")
            while offset < len(data) and data[offset] == 0xff:
                offset += 1
            marker = data[offset]
            offset += 1
            if marker in (0xda, 0xd9):
                break
            size = struct.unpack_from(">H", data, offset)[0]
            if size < 2 or offset + size > len(data):
                raise ValueError(f"Truncated JPEG: {path}")
            if marker in sof:
                if size < 8:
                    raise ValueError(f"Invalid JPEG dimensions: {path}")
                height, width = struct.unpack_from(">HH", data, offset + 3)
                break
            offset += size
        if not data.endswith(b"\xff\xd9"):
            raise ValueError(f"Incomplete JPEG: {path}")
    else:
        raise ValueError(f"Only PNG/JPEG are supported: {path}")
    if not width or not height:
        raise ValueError(f"Missing image dimensions: {path}")
    return {"path": str(path), "fileName": path.name, "fileSize": len(data),
            "width": width, "height": height, "mimeType": mime, "hasAlpha": alpha,
            "sha256": hashlib.sha256(data).hexdigest()}


def matching_specs(image, specifications):
    matches = []
    for spec in specifications:
        d = spec["dimensions"]
        if (d["minWidth"] <= image["width"] <= d["maxWidth"] and
                d["minHeight"] <= image["height"] <= d["maxHeight"] and
                pathlib.Path(image["fileName"]).suffix.lower() in spec["fileExtensions"] and
                image["mimeType"] in spec["mimeTypes"] and
                image["fileSize"] <= spec["maxFileSize"] and
                (spec["alphaAllowed"] or not image["hasAlpha"])):
            # Exact screenshot dimensions are authoritative; Apple's aspectRatio
            # is a nominal class (2034/1398 is not literally 3/2).
            if d["minWidth"] != d["maxWidth"] or d["minHeight"] != d["maxHeight"]:
                raise ValueError("Variable-dimension specs require an explicit aspect-ratio policy")
            matches.append(spec["specId"])
    return matches


def discover(app_id, version_string):
    api = GetOnlyAPI()
    catalog = api.get("/v1/appAssetLibraryRefData")
    library = api.get(f"/v1/apps/{app_id}/assetLibrary")["data"]
    versions = api.list(query(f"/v1/apps/{app_id}/appStoreVersions", limit=200))["data"]
    matches = [v for v in versions if v["attributes"]["versionString"] == version_string
               and v["attributes"]["platform"] == "IOS"]
    if len(matches) > 1:
        raise ValueError("Ambiguous version")
    version = matches[0] if matches else None
    localizations = []
    if version:
        locs = api.list(query(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations", limit=200))
        for loc in locs["data"]:
            placements = api.list(query(f"/v1/appStoreVersionLocalizations/{loc['id']}/placements",
                                        limit=200, sort="placementGroupPosition", include="image",
                                        **{"fields[appAssetLibraryImages]": IMAGE_FIELDS}))
            localizations.append({"id": loc["id"], "locale": loc["attributes"]["locale"],
                                  "placements": placements})
    return {"capturedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "appId": app_id, "requestedVersion": version_string, "catalog": catalog,
            "libraryId": library["id"], "version": version,
            "versions": [{"id": v["id"], "attributes": v["attributes"]} for v in versions],
            "localizations": localizations}


def resource(kind, identity):
    return {"data": {"type": kind, "id": identity}}


def plan(snapshot, manifest):
    if manifest["appId"] != snapshot["appId"] or manifest["versionString"] != snapshot["requestedVersion"]:
        raise ValueError("Manifest app/version does not match snapshot")
    blocks = []
    version = snapshot["version"]
    if not version or version["attributes"]["appStoreState"] != "PREPARE_FOR_SUBMISSION":
        blocks.append("Target IOS version must exist in PREPARE_FOR_SUBMISSION; this tool never creates it")
    uploads, groups, seen = {}, [], set()
    for entry in manifest["groups"]:
        locale, group = entry["locale"], entry["placementGroup"]
        if (locale, group) in seen:
            raise ValueError("Duplicate locale/group")
        seen.add((locale, group))
        spec = group_specification(snapshot["catalog"], group)
        if spec["profile"]["platform"] not in ("IPHONE_APP_STORE", "IPAD_APP_STORE"):
            raise ValueError("This IOS screenshot planner supports iPhone/iPad App Store groups")
        category = "APP_SCREENSHOTS_AND_PREVIEWS"
        if category not in spec["categories"]:
            raise ValueError("Screenshot category is not accepted")
        loc = next((l for l in snapshot["localizations"] if l["locale"] == locale), None)
        if not loc:
            blocks.append(f"Missing target localization: {locale}")
        localization_id = loc["id"] if loc else "${localization:" + locale + "}"
        existing = [p for p in loc["placements"]["data"] if p["attributes"]["placementGroup"] == group] if loc else []
        # Exact ID order guards replacement intent and preserves other groups/media.
        if entry.get("existingPlacementIds", []) != [p["id"] for p in existing]:
            raise ValueError(f"Existing placement order differs from manifest: {locale}/{group}")
        mode = entry.get("mode", "append")
        if mode not in ("append", "replace"):
            raise ValueError("mode must be append or replace")
        removed = [p for p in existing if mode == "replace" and p["attributes"]["placementType"] == "APP_SCREENSHOT"]
        removed_ids = {p["id"] for p in removed}
        retained = [p for p in existing if p["id"] not in removed_ids]
        if not entry["files"]:
            raise ValueError("Empty screenshot set is not a supported plan")
        screenshot_count = sum(p["attributes"]["placementType"] == "APP_SCREENSHOT" for p in retained) + len(entry["files"])
        if screenshot_count > spec["maxCount"]:
            raise ValueError(f"Screenshot count exceeds live group limit {spec['maxCount']}: {locale}/{group}")
        creations, ordered = [], [p["id"] for p in retained]
        for position, path in enumerate(entry["files"]):
            image = image_metadata(path)
            allowed = matching_specs(image, spec["specifications"])
            if not allowed:
                raise ValueError(f"Image fails group specification: {path} ({image['width']}x{image['height']}, alpha={image['hasAlpha']})")
            digest = image["sha256"]
            image_id = "${image:" + digest + "}"
            if digest not in uploads:
                uploads[digest] = {"file": image, "allowedSpecIds": allowed,
                    "reserve": {"method": "POST", "path": "/v1/appAssetLibraryImages", "body": {"data": {
                        "type": "appAssetLibraryImages", "attributes": {"fileName": image["fileName"],
                        "fileSize": image["fileSize"], "category": category,
                        "referenceName": "release-" + manifest["versionString"] + "-" + digest[:16]},
                        "relationships": {"assetLibrary": resource("appAssetLibraries", snapshot["libraryId"])}}}},
                    "commit": {"method": "PATCH", "path": "/v1/appAssetLibraryImages/" + image_id,
                        "body": {"data": {"type": "appAssetLibraryImages", "id": image_id, "attributes": {"uploaded": True}}}}}
            else:
                intersection = [s for s in uploads[digest]["allowedSpecIds"] if s in allowed]
                if not intersection:
                    raise ValueError("Identical file cannot satisfy all requested placement groups")
                uploads[digest]["allowedSpecIds"] = intersection
            placement_id = "${placement:" + locale + ":" + group + ":" + str(position) + "}"
            ordered.append(placement_id)
            creations.append({"resultId": placement_id, "method": "POST", "path": "/v1/appAssetLibraryPlacements",
                "body": {"data": {"type": "appAssetLibraryPlacements", "attributes": {
                    "placementType": "APP_SCREENSHOT", "placementGroup": group}, "relationships": {
                    "image": resource("appAssetLibraryImages", image_id),
                    "appStoreVersionLocalization": resource("appStoreVersionLocalizations", localization_id)}}}})
        groups.append({"locale": locale, "placementGroup": group, "specification": spec,
            "expectedExistingPlacementIds": [p["id"] for p in existing],
            "deletePlacements": [{"method": "DELETE", "path": "/v1/appAssetLibraryPlacements/" + p["id"]} for p in removed],
            "createPlacements": creations,
            "order": {"method": "POST", "path": "/v1/appAssetLibraryPlacementOrderingRequests", "body": {
                "data": {"type": "appAssetLibraryPlacementOrderingRequests", "attributes": {"placementGroup": group},
                "relationships": {"appStoreVersionLocalization": resource("appStoreVersionLocalizations", localization_id),
                "orderedPlacements": {"data": [{"type": "appAssetLibraryPlacements", "id": p} for p in ordered]}}}}}})
    return {"dryRun": True, "remoteWritesPerformed": False, "readyForExecution": not blocks,
            "blockers": list(dict.fromkeys(blocks)), "appId": snapshot["appId"],
            "versionString": snapshot["requestedVersion"], "versionId": version["id"] if version else None,
            "snapshotCapturedAt": snapshot["capturedAt"],
            "uploads": list(uploads.values()), "groups": groups,
            "executionNotes": ["This program cannot execute the plan. Review/authorization is required separately.",
                "Refresh discovery and recheck editable parent and exact placement IDs immediately before any mutation.",
                "Reserve -> upload exact byte ranges using server methods/headers without ASC Authorization -> commit uploaded=true.",
                "Poll GET image with bounded deadline until PREPARE_FOR_SUBMISSION or usable reviewed state; FAILED stops.",
                "Compare server specId and imageAsset dimensions with plan before creating placements.",
                "Group replacement deletes only its APP_SCREENSHOT placements; existing previews are retained before new screenshots.",
                "After ordering, GET placements sorted by placementGroupPosition and verify exact IDs/image IDs/specs/dimensions.",
                "Never delete reusable library images as part of placement replacement."]}


def verify(snapshot, receipt):
    """Receipt contains final real IDs, not unresolved dry-run placeholders."""
    errors = []
    if snapshot["appId"] != receipt["appId"] or snapshot["requestedVersion"] != receipt["versionString"]:
        raise ValueError("Receipt app/version does not match fresh snapshot")
    if receipt.get("versionId") and (not snapshot["version"] or snapshot["version"]["id"] != receipt["versionId"]):
        raise ValueError("Receipt target version identity changed")
    if not receipt["groups"]:
        errors.append("Receipt has no completed placement groups")
    actual_groups = [(g["locale"], g["placementGroup"]) for g in receipt["groups"]]
    if len(set(actual_groups)) != len(actual_groups):
        errors.append("Duplicate receipt placement groups")
    if receipt.get("expectedGroups") and set(actual_groups) != {tuple(g) for g in receipt["expectedGroups"]}:
        errors.append("Receipt is missing expected placement groups")
    for group in receipt["groups"]:
        loc = next((l for l in snapshot["localizations"] if l["locale"] == group["locale"]), None)
        if not loc:
            errors.append(f"Missing locale {group['locale']}")
            continue
        actual = [p for p in loc["placements"]["data"] if p["attributes"]["placementGroup"] == group["placementGroup"]]
        if [p["id"] for p in actual] != group["orderedPlacementIds"]:
            errors.append(f"Order mismatch {group['locale']}/{group['placementGroup']}")
        images = {i["id"]: i for i in loc["placements"]["included"] if i["type"] == "appAssetLibraryImages"}
        for expected in group["images"]:
            placement = next((p for p in actual if p["id"] == expected["placementId"]), None)
            image = images.get(expected["imageId"])
            if not placement or placement.get("relationships", {}).get("image", {}).get("data", {}).get("id") != expected["imageId"]:
                errors.append(f"Placement/image mismatch {expected['placementId']}")
            if not image:
                errors.append(f"Missing image {expected['imageId']}")
                continue
            attrs = image["attributes"]
            pixels = attrs.get("imageAsset") or {}
            if attrs.get("specId") not in expected["allowedSpecIds"] or [pixels.get("width"), pixels.get("height")] != expected["dimensions"]:
                errors.append(f"Processed image specification mismatch {image['id']}")
            usable_states = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED", "APPROVED", "COMPLETE"}
            placement_states = {"PARENT_PREPARE_FOR_SUBMISSION", "PARENT_READY_FOR_REVIEW", "PARENT_WAITING_FOR_REVIEW", "PARENT_IN_REVIEW", "PARENT_APPROVED", "ACTIVE"}
            if attrs["state"] not in usable_states or placement["attributes"]["state"] not in placement_states:
                errors.append(f"Unusable asset/placement state {image['id']}")
    return {"verified": not errors, "errors": errors, "capturedAt": snapshot["capturedAt"]}


def material_manifest(snapshot, root, order, mappings):
    entries = []
    root = pathlib.Path(root).resolve()
    for locale in order["locales"]:
        loc = next((l for l in snapshot["localizations"] if l["locale"] == locale), None)
        for mapping in mappings:
            prefix, group = mapping.split("=", 1)
            group_specification(snapshot["catalog"], group)
            files = [str(root / locale / (prefix + "-" + suffix + ".png"))
                     for suffix in order["outputSuffixes"]]
            existing = [p["id"] for p in loc["placements"]["data"]
                        if p["attributes"]["placementGroup"] == group] if loc else []
            entries.append({"locale": locale, "placementGroup": group,
                            "mode": "replace" if existing else "append",
                            "existingPlacementIds": existing, "files": files})
    return {"appId": snapshot["appId"], "versionString": snapshot["requestedVersion"], "groups": entries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    discovery = commands.add_parser("discover", help="GET-only catalog, library, version, localization, sorted placement snapshot")
    discovery.add_argument("--app-id", required=True)
    discovery.add_argument("--version-string", required=True)
    discovery.add_argument("--output", required=True)
    inspect = commands.add_parser("specs", help="Resolve a group using the actual catalog")
    inspect.add_argument("--snapshot", required=True)
    inspect.add_argument("--group", required=True)
    materials = commands.add_parser("manifest", help="Build local manifest from explicit prefix=liveGroup mappings")
    materials.add_argument("--snapshot", required=True)
    materials.add_argument("--screenshots-root", required=True)
    materials.add_argument("--order-json", required=True)
    materials.add_argument("--map", action="append", required=True)
    materials.add_argument("--output", required=True)
    for name in ("plan", "verify"):
        p = commands.add_parser(name, help="Offline " + name + "; never writes to ASC")
        p.add_argument("--snapshot", required=True)
        p.add_argument("--" + ("manifest" if name == "plan" else "receipt"), required=True)
        p.add_argument("--output")
    args = parser.parse_args()
    if args.command == "discover":
        emit(discover(args.app_id, args.version_string), args.output)
    elif args.command == "specs":
        emit(group_specification(load(args.snapshot)["catalog"], args.group))
    elif args.command == "manifest":
        emit(material_manifest(load(args.snapshot), args.screenshots_root, load(args.order_json), args.map), args.output)
    elif args.command == "plan":
        emit(plan(load(args.snapshot), load(args.manifest)), args.output)
    else:
        result = verify(load(args.snapshot), load(args.receipt))
        emit(result, args.output)
        return 0 if result["verified"] else 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, KeyError, OSError, urllib.error.URLError) as error:
        print("Error: " + str(error), file=sys.stderr)
        sys.exit(1)
