#!/usr/bin/env python3
"""Execute a separately reviewed asset-library plan only with its exact SHA-256.

Remote writes require --confirm-remote-writes and --approved-plan-sha256.
The explicit --prepare-resume mode performs GET-only recovery verification.
Never use this against a published version. A receipt journals remote intent;
on failure stop and review it instead of blindly running the whole plan again.
"""
import argparse
import hashlib
import io
import json
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import asset_library as library


class WriteAPI(library.GetOnlyAPI):
    def __init__(self):
        super().__init__()
        self.token_at = time.monotonic()

    def request(self, method, path, body=None):
        if time.monotonic() - self.token_at > 540:
            super().__init__()
            self.token_at = time.monotonic()
        if method == "GET":
            return self.get(path)
        parts = urllib.parse.urlsplit(urllib.parse.urljoin(library.API, path))
        if parts.scheme != "https" or parts.netloc != "api.appstoreconnect.apple.com":
            raise ValueError("Invalid ASC mutation host")
        payload = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(parts.geturl(), data=payload, method=method,
            headers={"Authorization": "Bearer " + self.token, "Content-Type": "application/json"})
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        try:
            with urllib.request.build_opener(NoRedirect).open(request, timeout=60) as response:
                data = response.read()
                return json.loads(data) if data else None
        except urllib.error.HTTPError as error:
            # Error response can contain upload URLs: only expose status/path.
            raise ValueError(f"ASC {method} failed: HTTP {error.code} at {parts.path}; review receipt, do not blindly retry") from None


def substitute(value, identifiers):
    if isinstance(value, str):
        for placeholder, identity in identifiers.items():
            value = value.replace(placeholder, identity)
        return value
    if isinstance(value, list):
        return [substitute(v, identifiers) for v in value]
    if isinstance(value, dict):
        return {k: substitute(v, identifiers) for k, v in value.items()}
    return value


def perform(api, action, identifiers):
    action = substitute(action, identifiers)
    payload = {k: v for k, v in action.items() if k in ("method", "path", "body")}
    if "${" in json.dumps(payload):
        raise ValueError("Unresolved plan identifier")
    return api.request(action["method"], action["path"], action.get("body"))


def upload_ranges(operations, file):
    # Upload URLs are credentials. Keep them in memory and never include them in
    # the receipt or diagnostics; never send the ASC JWT to the blob host.
    data = pathlib.Path(file["path"]).read_bytes()
    if len(data) != file["fileSize"] or hashlib.sha256(data).hexdigest() != file["sha256"]:
        raise ValueError("Upload bytes changed after plan approval")
    coverage = sorted((op["offset"], op["length"]) for op in operations)
    cursor = 0
    for offset, length in coverage:
        if offset != cursor or length <= 0 or offset + length > len(data):
            raise ValueError("Invalid/overlapping/incomplete server upload byte ranges")
        cursor += length
    if cursor != len(data):
        raise ValueError("Server upload operations do not cover file")
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None
    for op in operations:
        if urllib.parse.urlsplit(op["url"]).scheme != "https" or op["method"] not in ("PUT", "POST"):
            raise ValueError("Unexpected upload operation; inspect server documentation before continuing")
        headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
        payload = data[op["offset"]:op["offset"] + op["length"]]
        try:
            req = urllib.request.Request(op["url"], data=payload, method=op["method"], headers=headers)
            with urllib.request.build_opener(NoRedirect).open(req, timeout=90) as response:
                response.read()
        except (urllib.error.URLError, OSError):
            raise ValueError("Blob upload failed (signed URL redacted); inspect receipt before retry") from None


def wait_image(api, image_id, allowed, dimensions, on_mismatch=None):
    deadline = time.monotonic() + 300
    ready_states = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW", "ACCEPTED", "APPROVED", "COMPLETE"}
    last_mismatch = None
    while time.monotonic() < deadline:
        response = api.request("GET", "/v1/appAssetLibraryImages/" + image_id)
        attrs = response["data"]["attributes"]
        if attrs["state"] in ("FAILED", "REJECTED", "ARCHIVED"):
            raise ValueError(f"Image validation failed for {image_id}: {attrs['state']}")
        if attrs["state"] in ready_states:
            asset = attrs.get("imageAsset") or {}
            if attrs.get("specId") in allowed and [asset.get("width"), asset.get("height")] == dimensions:
                return attrs
            # The state can reach ready before the classification/delivery fields
            # converge. Keep GET polling within the same deadline; never accept a
            # permanently incompatible specification or reserve a second image.
            last_mismatch = {"imageId": image_id, "state": attrs["state"],
                             "specId": attrs.get("specId"), "width": asset.get("width"),
                             "height": asset.get("height"), "fileSize": attrs.get("fileSize")}
            if on_mismatch:
                on_mismatch(last_mismatch)
        time.sleep(2)
    detail = " Last ready mismatch: " + json.dumps(last_mismatch, sort_keys=True) if last_mismatch else ""
    raise ValueError("Bounded image-processing timeout; do not blindly reserve another asset." + detail)


def delivery_check(attrs, file):
    # Pixel comparison survives metadata stripping/recompression. Pillow is a
    # deliberate dependency for this executable; discovery/plan use stdlib only.
    from PIL import Image
    source_bytes = pathlib.Path(file["path"]).read_bytes()
    if len(source_bytes) != file["fileSize"] or hashlib.sha256(source_bytes).hexdigest() != file["sha256"]:
        raise ValueError("Delivery comparison source changed after plan approval")
    asset = attrs["imageAsset"]
    url = asset["templateUrl"].replace("{w}", str(asset["width"])).replace("{h}", str(asset["height"])).replace("{f}", "png")
    if re.search(r"\{[^}]+\}", url) or urllib.parse.urlsplit(url).scheme != "https":
        raise ValueError("Unrecognized delivery URL template")
    try:
        with urllib.request.urlopen(url, timeout=90) as response:
            data = response.read()
    except (urllib.error.URLError, OSError):
        raise ValueError("Image delivery download failed (URL redacted)") from None
    with Image.open(io.BytesIO(source_bytes)) as original, Image.open(io.BytesIO(data)) as delivered:
        original.load()
        delivered.load()
        if delivered.size != original.size:
            raise ValueError("Delivered dimensions differ from original")
        if delivered.mode in ("RGBA", "LA") and delivered.getchannel("A").getextrema() != (255, 255):
            raise ValueError("Delivered image has transparency")
        original_pixels = hashlib.sha256(original.convert("RGB").tobytes()).hexdigest()
        delivered_pixels = hashlib.sha256(delivered.convert("RGB").tobytes()).hexdigest()
        if file["mimeType"] == "image/png" and original_pixels != delivered_pixels:
            raise ValueError("PNG delivered pixels differ from local source")
    return {"deliveredBytesSha256": hashlib.sha256(data).hexdigest(),
            "sourcePixelsSha256": original_pixels, "deliveredPixelsSha256": delivered_pixels,
            "pixelExact": original_pixels == delivered_pixels, "dimensions": [asset["width"], asset["height"]]}


def validate_scope(plan, app_id, version_id, locales, groups, images_per_group):
    if plan["appId"] != app_id or plan["versionId"] != version_id:
        raise ValueError("Plan app/version differs from separately specified execution scope")
    expected = {(locale, group) for locale in locales for group in groups}
    actual = [(g["locale"], g["placementGroup"]) for g in plan["groups"]]
    if len(actual) != len(set(actual)) or set(actual) != expected:
        raise ValueError("Plan locale/group set differs from separately specified execution scope")
    if any(len(g["createPlacements"]) != images_per_group for g in plan["groups"]):
        raise ValueError("Plan screenshot count differs from separately specified execution scope")


def preflight(plan, fresh):
    from PIL import Image
    if not plan["readyForExecution"] or plan["blockers"]:
        raise ValueError("Plan has unresolved blockers")
    version = fresh["version"]
    if not version or version["id"] != plan["versionId"] or version["attributes"]["appStoreState"] != "PREPARE_FOR_SUBMISSION":
        raise ValueError("Target version identity/editable state changed")
    if any(v["attributes"]["appStoreState"] == "READY_FOR_SALE" and v["id"] == plan["versionId"] for v in fresh["versions"]):
        raise ValueError("Refusing to mutate a published version")
    upload_placeholders = {"${image:" + u["file"]["sha256"] + "}" for u in plan["uploads"]}
    # Complete all local/remote preflight before the first write.
    for group in plan["groups"]:
        fresh_spec = library.group_specification(fresh["catalog"], group["placementGroup"])
        if fresh_spec != group["specification"]:
            raise ValueError("Reference specification changed; regenerate plan")
        loc = next((l for l in fresh["localizations"] if l["locale"] == group["locale"]), None)
        actual = [p["id"] for p in loc["placements"]["data"] if p["attributes"]["placementGroup"] == group["placementGroup"]] if loc else None
        if actual != group["expectedExistingPlacementIds"]:
            raise ValueError("Target localization/placement order changed; regenerate plan")
        expected_loc = group["order"]["body"]["data"]["relationships"]["appStoreVersionLocalization"]["data"]["id"]
        if expected_loc != loc["id"]:
            raise ValueError("Target localization ID changed")
        deletes = [a["path"].removeprefix("/v1/appAssetLibraryPlacements/") for a in group["deletePlacements"]]
        removable = {p["id"] for p in loc["placements"]["data"]
                     if p["attributes"]["placementGroup"] == group["placementGroup"] and
                     p["attributes"]["placementType"] == "APP_SCREENSHOT"}
        if len(deletes) != len(set(deletes)) or not set(deletes).issubset(removable):
            raise ValueError("Plan deletes an unrelated or duplicate placement")
        if any(a != {"method": "DELETE", "path": "/v1/appAssetLibraryPlacements/" + identity}
               for a, identity in zip(group["deletePlacements"], deletes)):
            raise ValueError("Unexpected delete action")
        new_ids = []
        for index, action in enumerate(group["createPlacements"]):
            body = action["body"]["data"]
            expected_result = "${placement:" + group["locale"] + ":" + group["placementGroup"] + ":" + str(index) + "}"
            if (action["method"] != "POST" or action["path"] != "/v1/appAssetLibraryPlacements" or
                    action["resultId"] != expected_result or
                    body["type"] != "appAssetLibraryPlacements" or
                    body["attributes"] != {"placementType": "APP_SCREENSHOT", "placementGroup": group["placementGroup"]} or
                    set(body["relationships"]) != {"image", "appStoreVersionLocalization"} or
                    body["relationships"]["appStoreVersionLocalization"] != library.resource("appStoreVersionLocalizations", loc["id"]) or
                    body["relationships"]["image"]["data"]["id"] not in upload_placeholders or
                    body["relationships"]["image"] != library.resource("appAssetLibraryImages", body["relationships"]["image"]["data"]["id"])):
                raise ValueError("Plan creates a placement outside the approved screenshot surface")
            new_ids.append(action["resultId"])
        order = group["order"]
        ordered = [p["id"] for p in order["body"]["data"]["relationships"]["orderedPlacements"]["data"]]
        expected = [p for p in actual if p not in set(deletes)] + new_ids
        if (ordered != expected or len(set(ordered)) != len(ordered) or
                order["method"] != "POST" or order["path"] != "/v1/appAssetLibraryPlacementOrderingRequests" or
                order["body"]["data"]["type"] != "appAssetLibraryPlacementOrderingRequests" or
                order["body"]["data"]["attributes"] != {"placementGroup": group["placementGroup"]} or
                set(order["body"]["data"]["relationships"]) != {"orderedPlacements", "appStoreVersionLocalization"} or
                order["body"]["data"]["relationships"]["appStoreVersionLocalization"] != library.resource("appStoreVersionLocalizations", loc["id"]) or
                order["body"]["data"]["relationships"]["orderedPlacements"] != {"data": [{"type": "appAssetLibraryPlacements", "id": p} for p in ordered]}):
            raise ValueError("Plan ordering does not preserve the approved group membership/order")
    for upload in plan["uploads"]:
        file = upload["file"]
        current = library.image_metadata(file["path"])
        if current != file:
            raise ValueError("Local upload file changed since plan approval")
        reservation = upload["reserve"]
        expected_attributes = {"fileName": file["fileName"], "fileSize": file["fileSize"],
                               "category": "APP_SCREENSHOTS_AND_PREVIEWS",
                               "referenceName": "release-" + plan["versionString"] + "-" + file["sha256"][:16]}
        if (reservation["method"] != "POST" or reservation["path"] != "/v1/appAssetLibraryImages" or
                reservation["body"]["data"]["type"] != "appAssetLibraryImages" or
                reservation["body"]["data"]["attributes"] != expected_attributes or
                reservation["body"]["data"]["relationships"] != {"assetLibrary": library.resource("appAssetLibraries", fresh["libraryId"])}):
            raise ValueError("Plan reserves an asset outside the approved app library")
        placeholder = "${image:" + file["sha256"] + "}"
        expected_commit = {"method": "PATCH", "path": "/v1/appAssetLibraryImages/" + placeholder,
                           "body": {"data": {"type": "appAssetLibraryImages", "id": placeholder, "attributes": {"uploaded": True}}}}
        if upload["commit"] != expected_commit:
            raise ValueError("Plan commit is not the exact image-upload completion action")
        with Image.open(file["path"]) as image:
            image.verify()


def validate_resume_receipt(plan, digest, receipt):
    if (receipt["approvedPlanSha256"] != digest or receipt["appId"] != plan["appId"] or
            receipt["versionId"] != plan["versionId"] or receipt["versionString"] != plan["versionString"] or
            receipt["expectedGroups"] != [[g["locale"], g["placementGroup"]] for g in plan["groups"]]):
        raise ValueError("Resume receipt plan identity/scope differs")
    if receipt["completed"] or receipt["groups"]:
        raise ValueError("Only an incomplete upload-phase receipt can be resumed automatically")
    uploads, operations = receipt["uploads"], receipt["operations"]
    if not uploads or len(uploads) > len(plan["uploads"]):
        raise ValueError("Resume receipt upload prefix is invalid")
    if len(operations) != len(uploads) * 2:
        raise ValueError("Ambiguous mutation history; GET reconciliation required before resume")
    identities = [u["imageId"] for u in uploads]
    if len(set(identities)) != len(identities):
        raise ValueError("Duplicate image identities in resume receipt")
    for index, record in enumerate(uploads):
        planned = plan["uploads"][index]
        if record["source"] != planned["file"] or record["allowedSpecIds"] != planned["allowedSpecIds"]:
            raise ValueError("Receipt source/hash/spec differs from approved upload prefix")
        if record.get("resultUnknown") or record["stage"] not in ("validated", "committed"):
            raise ValueError("Unknown/incomplete upload outcome must be reconciled before resume")
        identity = record["imageId"]
        placeholder = "${image:" + record["source"]["sha256"] + "}"
        expected = [planned["reserve"], substitute(planned["commit"], {placeholder: identity})]
        for operation, action in zip(operations[index * 2:index * 2 + 2], expected):
            if (operation["status"] != "completed" or operation.get("resultUnknown") or
                    operation.get("resultId") != identity or operation["action"] != action):
                raise ValueError("Unknown/ambiguous mutation result must be reconciled before resume")


def inspect_resume_images(api, plan, fresh, receipt):
    identities = [record["imageId"] for record in receipt["uploads"]]
    members = api.list(library.query(f"/v1/appAssetLibraries/{fresh['libraryId']}/images", limit=200,
        **{"filter[id]": ",".join(identities), "fields[appAssetLibraryImages]": library.IMAGE_FIELDS}))["data"]
    if ({m["id"] for m in members} != set(identities) or len(members) != len(identities) or
            any(m["type"] != "appAssetLibraryImages" for m in members)):
        raise ValueError("Reserved IDs are missing/ambiguous in the approved app library")
    results = []
    for index, record in enumerate(receipt["uploads"]):
        file = record["source"]
        attrs = next(m["attributes"] for m in members if m["id"] == record["imageId"])
        expected = plan["uploads"][index]["reserve"]["body"]["data"]["attributes"]
        if any(attrs.get(key) != expected[key] for key in ("fileName", "fileSize", "category", "referenceName")):
            raise ValueError("Remote reserved image metadata does not match the approved local source")
        mismatches = []
        attrs = wait_image(api, record["imageId"], record["allowedSpecIds"],
                           [file["width"], file["height"]], on_mismatch=mismatches.append)
        if any(attrs.get(key) != expected[key] for key in ("fileName", "fileSize", "category", "referenceName")):
            raise ValueError("Fresh image metadata differs after processing")
        delivery = delivery_check(attrs, file)
        results.append({"imageId": record["imageId"], "sourceSha256": file["sha256"],
                        "fileName": file["fileName"], "fileSize": file["fileSize"],
                        "referenceName": attrs["referenceName"], "state": attrs["state"],
                        "specId": attrs["specId"], "dimensions": [file["width"], file["height"]],
                        "delivery": delivery, "readyMismatchObservations": mismatches})
    return results


def prepare_resume(plan, digest, receipt_path):
    receipt_bytes = receipt_path.read_bytes()
    receipt = json.loads(receipt_bytes)
    validate_resume_receipt(plan, digest, receipt)
    fresh = library.discover(plan["appId"], plan["versionString"])
    preflight(plan, fresh)
    images = inspect_resume_images(library.GetOnlyAPI(), plan, fresh, receipt)
    if receipt_path.read_bytes() != receipt_bytes:
        raise ValueError("Receipt changed during read-only resume preparation")
    return {"dryRun": True, "remoteWritesPerformed": False, "planSha256": digest,
            "receiptSha256": hashlib.sha256(receipt_bytes).hexdigest(),
            "appId": plan["appId"], "versionId": plan["versionId"], "versionString": plan["versionString"],
            "capturedAt": fresh["capturedAt"], "reusedImages": images,
            "remainingUploads": [u["file"] for u in plan["uploads"][len(images):]],
            "groups": [{"locale": g["locale"], "placementGroup": g["placementGroup"],
                        "createCount": len(g["createPlacements"]), "expectedExistingPlacementIds": g["expectedExistingPlacementIds"]}
                       for g in plan["groups"]],
            "deleteCount": sum(len(g["deletePlacements"]) for g in plan["groups"]),
            "orderCount": len(plan["groups"])}


def execute(plan, digest, receipt_path, resume_review=None):
    if receipt_path.exists() and resume_review is None:
        raise ValueError("Receipt already exists; review/resume explicitly instead of blind reexecution")
    fresh = library.discover(plan["appId"], plan["versionString"])
    preflight(plan, fresh)
    if resume_review:
        receipt_bytes = receipt_path.read_bytes()
        if (resume_review["planSha256"] != digest or resume_review["receiptSha256"] != hashlib.sha256(receipt_bytes).hexdigest()):
            raise ValueError("Receipt/plan changed since resume review approval")
        receipt = json.loads(receipt_bytes)
        validate_resume_receipt(plan, digest, receipt)
        approved_ids = [i["imageId"] for i in resume_review["reusedImages"]]
        if approved_ids != [i["imageId"] for i in receipt["uploads"]]:
            raise ValueError("Approved resume IDs differ from receipt")
    else:
        receipt = {"appId": plan["appId"], "versionString": plan["versionString"], "versionId": plan["versionId"],
               "approvedPlanSha256": digest, "completed": False, "uploads": [], "operations": [], "groups": [],
               "expectedGroups": [[g["locale"], g["placementGroup"]] for g in plan["groups"]]}
    def save():
        # Atomic local checkpoint; no JWT, signed upload URL, or blob headers.
        tmp = receipt_path.with_suffix(receipt_path.suffix + ".tmp")
        tmp.write_text(json.dumps(receipt, indent=2) + "\n")
        tmp.replace(receipt_path)
    save()
    api, ids, image_receipts = WriteAPI(), {}, {}
    if resume_review:
        inspections = inspect_resume_images(api, plan, fresh, receipt)
        for record, inspection in zip(receipt["uploads"], inspections):
            record.update({"stage": "validated", "state": inspection["state"], "specId": inspection["specId"],
                           "delivery": inspection["delivery"], "resumeReadyMismatchObservations": inspection["readyMismatchObservations"]})
            ids["${image:" + record["source"]["sha256"] + "}"] = record["imageId"]
            image_receipts[record["imageId"]] = record
        receipt.setdefault("resumeHistory", []).append({"approvedReceiptSha256": resume_review["receiptSha256"],
            "reusedImageIds": [r["imageId"] for r in receipt["uploads"]]})
        save()
        print(f"Revalidated and reused {len(inspections)} existing images; no duplicate reservations", flush=True)
    def journaled(action, context=None):
        # Record sanitized intent *before* a mutation. A timeout can mean the
        # server applied it; retain the exact scope for GET-only reconciliation.
        resolved = substitute(action, ids)
        event = {"action": {k: v for k, v in resolved.items() if k in ("method", "path", "body")},
                 "context": context or {}, "status": "pending"}
        receipt["operations"].append(event)
        save()
        try:
            response = perform(api, resolved, ids)
        except Exception:
            event.update({"status": "failed", "resultUnknown": True})
            save()
            raise
        event["status"] = "completed"
        if response and isinstance(response.get("data"), dict):
            event["resultId"] = response["data"]["id"]
        save()
        return response
    remaining = plan["uploads"][len(receipt["uploads"]):]
    for upload in remaining:
        file = upload["file"]
        response = journaled(upload["reserve"], {"sourceSha256": file["sha256"]})["data"]
        image_id = response["id"]
        ids["${image:" + file["sha256"] + "}"] = image_id
        record = {"imageId": image_id, "source": file, "allowedSpecIds": upload["allowedSpecIds"], "stage": "reserved"}
        receipt["uploads"].append(record)
        save()
        record["stage"] = "upload_started"
        save()
        try:
            upload_ranges(response["attributes"]["uploadOperations"], file)
        except Exception:
            record.update({"stage": "upload_failed", "resultUnknown": True})
            save()
            raise
        record["stage"] = "uploaded"
        save()
        journaled(upload["commit"])
        record["stage"] = "committed"
        save()
        def observed_mismatch(observation):
            record.setdefault("readyMismatchObservations", []).append(observation)
            save()
        attrs = wait_image(api, image_id, upload["allowedSpecIds"], [file["width"], file["height"]],
                           on_mismatch=observed_mismatch)
        record.update({"stage": "validated", "state": attrs["state"], "specId": attrs["specId"],
                       "delivery": delivery_check(attrs, file)})
        image_receipts[image_id] = record
        save()
        print(f"Validated image {len(receipt['uploads'])}/{len(plan['uploads'])}: {file['fileName']}", flush=True)
    # All images must be validated/delivered before any old placement is removed.
    # Recheck the parent and group order after uploads, which can take minutes.
    post_upload = library.discover(plan["appId"], plan["versionString"])
    if (not post_upload["version"] or post_upload["version"]["id"] != plan["versionId"] or
            post_upload["version"]["attributes"]["appStoreState"] != "PREPARE_FOR_SUBMISSION"):
        raise ValueError("Parent became noneditable after uploads; no placements were changed")
    for group in plan["groups"]:
        loc = next((l for l in post_upload["localizations"] if l["locale"] == group["locale"]), None)
        actual = [p["id"] for p in loc["placements"]["data"] if p["attributes"]["placementGroup"] == group["placementGroup"]] if loc else None
        if actual != group["expectedExistingPlacementIds"]:
            raise ValueError("Placement order changed during uploads; no placements were changed")
    for group in plan["groups"]:
        for action in group["deletePlacements"]:
            journaled(action, {"locale": group["locale"], "placementGroup": group["placementGroup"]})
        images = []
        for action in group["createPlacements"]:
            actual = journaled(action, {"locale": group["locale"], "placementGroup": group["placementGroup"]})["data"]
            ids[action["resultId"]] = actual["id"]
            image_id = substitute(action["body"], ids)["data"]["relationships"]["image"]["data"]["id"]
            record = image_receipts[image_id]
            images.append({"placementId": actual["id"], "imageId": image_id,
                           "allowedSpecIds": record["allowedSpecIds"],
                           "dimensions": [record["source"]["width"], record["source"]["height"]]})
            save()
        order = substitute(group["order"], ids)
        journaled(order, {"locale": group["locale"], "placementGroup": group["placementGroup"]})
        receipt["groups"].append({"locale": group["locale"], "placementGroup": group["placementGroup"],
            "orderedPlacementIds": [p["id"] for p in order["body"]["data"]["relationships"]["orderedPlacements"]["data"]], "images": images})
        save()
    receipt["verification"] = library.verify(library.discover(plan["appId"], plan["versionString"]), receipt)
    receipt["completed"] = receipt["verification"]["verified"]
    save()
    if not receipt["completed"]:
        raise ValueError("Final placement/spec/order readback failed; inspect receipt")
    print("Completed and independently read back all image placements and ordering")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plan", required=True)
    parser.add_argument("--receipt", required=True)
    parser.add_argument("--approved-plan-sha256", required=True)
    parser.add_argument("--expected-app-id", required=True)
    parser.add_argument("--expected-version-id", required=True)
    parser.add_argument("--expected-locales", required=True, help="Comma-separated approved locale set")
    parser.add_argument("--expected-groups", required=True, help="Comma-separated approved live profile group set")
    parser.add_argument("--expected-images-per-group", required=True, type=int)
    parser.add_argument("--confirm-remote-writes", action="store_true")
    recovery = parser.add_mutually_exclusive_group()
    recovery.add_argument("--prepare-resume", action="store_true", help="GET-only verify existing IDs and write a review artifact")
    recovery.add_argument("--resume", action="store_true", help="Resume only the reviewed unambiguous upload-phase receipt")
    parser.add_argument("--resume-review", help="Path for the generated/approved resume review JSON")
    parser.add_argument("--approved-resume-review-sha256")
    args = parser.parse_args()
    if not args.confirm_remote_writes and not args.prepare_resume:
        parser.error("Remote writes require separate authorization and --confirm-remote-writes")
    digest = hashlib.sha256(pathlib.Path(args.plan).read_bytes()).hexdigest()
    if digest != args.approved_plan_sha256:
        raise ValueError("Plan SHA-256 differs from approved review artifact")
    plan = library.load(args.plan)
    validate_scope(plan, args.expected_app_id, args.expected_version_id,
                   args.expected_locales.split(","), args.expected_groups.split(","), args.expected_images_per_group)
    receipt_path = pathlib.Path(args.receipt).resolve()
    if args.prepare_resume:
        if not args.resume_review or args.confirm_remote_writes:
            parser.error("Preparation requires --resume-review and excludes --confirm-remote-writes")
        library.emit(prepare_resume(plan, digest, receipt_path), args.resume_review)
    elif args.resume:
        if not args.resume_review or not args.approved_resume_review_sha256:
            parser.error("Resume requires the separate reviewed artifact path and SHA-256")
        review_path = pathlib.Path(args.resume_review)
        if hashlib.sha256(review_path.read_bytes()).hexdigest() != args.approved_resume_review_sha256:
            raise ValueError("Resume review SHA-256 differs from authorization")
        execute(plan, digest, receipt_path, resume_review=library.load(review_path))
    else:
        if args.resume_review or args.approved_resume_review_sha256:
            parser.error("Resume review flags require --resume or --prepare-resume")
        execute(plan, digest, receipt_path)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, urllib.error.URLError) as error:
        print("Error: " + str(error), file=sys.stderr)
        sys.exit(1)
