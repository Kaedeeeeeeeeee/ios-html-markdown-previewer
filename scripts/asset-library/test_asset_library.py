import copy
import json
import pathlib
import struct
import tempfile
import unittest
from unittest import mock
import zlib

import asset_library as library
import upload_assets as uploader


def png(width, height, alpha=False, shade=0):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xffffffff)
    pixel = bytes([shade, 0, 0, 255]) if alpha else bytes([shade, 0, 0])
    pixels = (b"\0" + pixel * width) * height
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6 if alpha else 2, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))


def snapshot():
    group = "FUTURE_GROUP_FROM_SERVER"
    spec = {"specId": "dynamic-spec", "shortName": "future", "dimensions": {
        "minWidth": 4, "maxWidth": 4, "minHeight": 3, "maxHeight": 3},
        "aspectRatio": "3:2", "compatiblePlacementTypes": ["APP_SCREENSHOT"],
        "alphaAllowed": False, "fileExtensions": [".png"], "maxFileSize": 1000,
        "mimeTypes": ["image/png"], "universalAsset": False}
    attributes = {"features": [{"featureId": "APP_STORE_VERSIONS", "placementPolicies": [{
        "placementType": "APP_SCREENSHOT", "groupLimits": [{"groupIds": [group], "maxCount": 2}]}]}],
        "placementProfileGroups": [{"placementProfileGroupId": group, "platform": "IPHONE_APP_STORE", "displayClassId": "FUTURE_DISPLAY"}],
        "placementTypes": [{"placementTypeId": "APP_SCREENSHOT", "acceptsAssetCategories": ["APP_SCREENSHOTS_AND_PREVIEWS"],
                            "specMappings": [{"placementGroupId": group, "specs": ["dynamic-spec"]}]}],
        "imageSpecs": [spec], "displayClasses": [{"displayClassId": "FUTURE_DISPLAY", "deviceFamily": "IPHONE", "screenDimensions": ["4x3"]}]}
    return {"appId": "app", "requestedVersion": "1.8", "capturedAt": "now", "libraryId": "library",
            "catalog": {"data": {"id": "1", "attributes": attributes}},
            "version": {"id": "new-version", "attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}},
            "versions": [{"id": "new-version", "attributes": {"appStoreState": "PREPARE_FOR_SUBMISSION"}}],
            "localizations": [{"id": "locale", "locale": "en-US", "placements": {"data": [], "included": []}}]}


class PlanningTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = pathlib.Path(self.directory.name) / "one.png"
        self.path.write_bytes(png(4, 3))
        self.snapshot = snapshot()
        self.manifest = {"appId": "app", "versionString": "1.8", "groups": [{"locale": "en-US",
            "placementGroup": "FUTURE_GROUP_FROM_SERVER", "files": [str(self.path)], "existingPlacementIds": []}]}

    def test_dynamic_group_nominal_ratio_and_commit_schema(self):
        plan = library.plan(self.snapshot, self.manifest)
        self.assertTrue(plan["readyForExecution"])
        self.assertEqual(plan["uploads"][0]["allowedSpecIds"], ["dynamic-spec"])
        self.assertEqual(plan["uploads"][0]["commit"]["body"]["data"]["attributes"], {"uploaded": True})
        self.assertNotIn("sourceFileChecksum", json.dumps(plan))
        self.assertNotIn("specId", plan["uploads"][0]["reserve"]["body"]["data"]["attributes"])

    def test_wrong_dimension_and_alpha_rejected(self):
        for content in (png(3, 4), png(4, 3, alpha=True)):
            self.path.write_bytes(content)
            with self.assertRaisesRegex(ValueError, "fails group specification"):
                library.plan(self.snapshot, self.manifest)

    def test_invalid_png_crc_rejected(self):
        content = bytearray(png(4, 3))
        content[20] ^= 1
        self.path.write_bytes(content)
        with self.assertRaisesRegex(ValueError, "CRC"):
            library.image_metadata(self.path)

    def test_live_limit_rejected(self):
        self.manifest["groups"][0]["files"] *= 3
        with self.assertRaisesRegex(ValueError, "limit 2"):
            library.plan(self.snapshot, self.manifest)

    def test_missing_and_published_version_blocked(self):
        for version in (None, {"id": "published", "attributes": {"appStoreState": "READY_FOR_SALE"}}):
            self.snapshot["version"] = version
            plan = library.plan(self.snapshot, self.manifest)
            self.assertFalse(plan["readyForExecution"])

    def test_replace_preserves_preview_and_other_groups(self):
        target = self.manifest["groups"][0]["placementGroup"]
        placements = [{"id": "preview", "attributes": {"placementGroup": target, "placementType": "APP_PREVIEW"}},
                      {"id": "old", "attributes": {"placementGroup": target, "placementType": "APP_SCREENSHOT"}},
                      {"id": "other", "attributes": {"placementGroup": "other", "placementType": "APP_SCREENSHOT"}}]
        self.snapshot["localizations"][0]["placements"]["data"] = placements
        group = self.manifest["groups"][0]
        group.update({"mode": "replace", "existingPlacementIds": ["preview", "old"]})
        plan = library.plan(self.snapshot, self.manifest)["groups"][0]
        self.assertEqual(plan["deletePlacements"], [{"method": "DELETE", "path": "/v1/appAssetLibraryPlacements/old"}])
        order = plan["order"]["body"]["data"]["relationships"]["orderedPlacements"]["data"]
        self.assertEqual(order[0]["id"], "preview")
        self.assertEqual(len(order), 2)
        group["existingPlacementIds"] = ["old", "preview"]
        with self.assertRaisesRegex(ValueError, "order differs"):
            library.plan(self.snapshot, self.manifest)

    def test_same_asset_reused_across_locales(self):
        self.snapshot["localizations"].append({"id": "locale-ja", "locale": "ja", "placements": {"data": [], "included": []}})
        entry = copy.deepcopy(self.manifest["groups"][0])
        entry["locale"] = "ja"
        self.manifest["groups"].append(entry)
        plan = library.plan(self.snapshot, self.manifest)
        self.assertEqual(len(plan["uploads"]), 1)
        self.assertEqual(len(plan["groups"]), 2)

    def test_readback_checks_real_order_spec_and_geometry(self):
        group = self.manifest["groups"][0]["placementGroup"]
        self.snapshot["localizations"][0]["placements"] = {"data": [{"id": "p", "attributes": {"placementGroup": group, "state": "PARENT_PREPARE_FOR_SUBMISSION"},
            "relationships": {"image": {"data": {"id": "i"}}}}], "included": [{"type": "appAssetLibraryImages", "id": "i", "attributes": {
                "state": "PREPARE_FOR_SUBMISSION", "specId": "dynamic-spec", "imageAsset": {"width": 4, "height": 3}}}]}
        receipt = {"appId": "app", "versionString": "1.8", "groups": [{"locale": "en-US", "placementGroup": group,
            "orderedPlacementIds": ["p"], "images": [{"placementId": "p", "imageId": "i", "allowedSpecIds": ["dynamic-spec"], "dimensions": [4, 3]}]}]}
        self.assertTrue(library.verify(self.snapshot, receipt)["verified"])
        receipt["groups"][0]["orderedPlacementIds"] = ["wrong"]
        self.assertFalse(library.verify(self.snapshot, receipt)["verified"])
        receipt["groups"][0]["orderedPlacementIds"] = ["p"]
        receipt["groups"][0]["images"][0]["dimensions"] = [3, 4]
        self.assertFalse(library.verify(self.snapshot, receipt)["verified"])


class FakeWriteAPI:
    calls = []
    fail_reservation = False

    def request(self, method, path, body=None):
        self.calls.append((method, path, body))
        if path == "/v1/appAssetLibraryImages" and self.fail_reservation:
            raise ValueError("Simulated reservation timeout; result unknown")
        if path == "/v1/appAssetLibraryImages":
            return {"data": {"id": "image", "attributes": {"uploadOperations": []}}}
        if path == "/v1/appAssetLibraryPlacements":
            return {"data": {"id": "placement"}}
        if method == "PATCH":
            return {"data": {"id": body["data"]["id"]}}
        return {"data": {"id": "result"}}


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        PlanningTests.setUp(self)
        FakeWriteAPI.calls = []
        FakeWriteAPI.fail_reservation = False
        self.receipt_path = pathlib.Path(self.directory.name) / "receipt.json"
        self.plan = library.plan(self.snapshot, self.manifest)
        for patch in (mock.patch.object(library, "discover", return_value=self.snapshot),
                      mock.patch.object(uploader, "WriteAPI", FakeWriteAPI)):
            patch.start()
            self.addCleanup(patch.stop)

    def test_bad_commit_rejected_before_first_write(self):
        self.plan["uploads"][0]["commit"] = {"method": "DELETE", "path": "/v1/appAssetLibraryPlacements/published"}
        with self.assertRaisesRegex(ValueError, "exact image-upload"):
            uploader.execute(self.plan, "digest", self.receipt_path)
        self.assertEqual(FakeWriteAPI.calls, [])

    def test_other_surface_delete_rejected_before_first_write(self):
        self.plan["groups"][0]["deletePlacements"] = [{"method": "DELETE", "path": "/v1/appAssetLibraryPlacements/published"}]
        with self.assertRaisesRegex(ValueError, "unrelated"):
            uploader.execute(self.plan, "digest", self.receipt_path)
        self.assertEqual(FakeWriteAPI.calls, [])

    def test_image_placeholder_collision_rejected_before_first_write(self):
        group = self.plan["groups"][0]
        old = group["createPlacements"][0]["resultId"]
        replacement = "${image:" + self.plan["uploads"][0]["file"]["sha256"] + "}"
        group["createPlacements"][0]["resultId"] = replacement
        group["order"] = uploader.substitute(group["order"], {old: replacement})
        with self.assertRaisesRegex(ValueError, "outside the approved"):
            uploader.execute(self.plan, "digest", self.receipt_path)
        self.assertEqual(FakeWriteAPI.calls, [])

    def test_execution_scope_is_independent_of_plan(self):
        group = self.plan["groups"][0]["placementGroup"]
        uploader.validate_scope(self.plan, "app", "new-version", ["en-US"], [group], 1)
        with self.assertRaisesRegex(ValueError, "execution scope"):
            uploader.validate_scope(self.plan, "app", "published", ["en-US"], [group], 1)
        with self.assertRaisesRegex(ValueError, "execution scope"):
            uploader.validate_scope(self.plan, "app", "new-version", ["en-US", "ja"], [group], 1)

    def test_payload_change_rejected_before_blob_request(self):
        file = self.plan["uploads"][0]["file"]
        self.path.write_bytes(png(4, 3, alpha=True))
        with self.assertRaisesRegex(ValueError, "bytes changed"):
            uploader.upload_ranges([], file)
        with self.assertRaisesRegex(ValueError, "source changed"):
            uploader.delivery_check({}, file)

    def test_unknown_reservation_result_journaled_before_request(self):
        FakeWriteAPI.fail_reservation = True
        with self.assertRaisesRegex(ValueError, "timeout"):
            uploader.execute(self.plan, "digest", self.receipt_path)
        receipt = library.load(self.receipt_path)
        self.assertFalse(receipt["completed"])
        self.assertTrue(receipt["operations"][0]["resultUnknown"])
        self.assertEqual(receipt["operations"][0]["action"]["path"], "/v1/appAssetLibraryImages")
        self.assertEqual(receipt["operations"][0]["context"]["sourceSha256"], self.plan["uploads"][0]["file"]["sha256"])
        self.assertEqual(len(FakeWriteAPI.calls), 1)

    def test_mocked_upload_commit_place_order_and_readback(self):
        attrs = {"state": "PREPARE_FOR_SUBMISSION", "specId": "dynamic-spec", "imageAsset": {"width": 4, "height": 3}}
        with mock.patch.object(uploader, "upload_ranges"), mock.patch.object(uploader, "wait_image", return_value=attrs), \
                mock.patch.object(uploader, "delivery_check", return_value={"pixelExact": True}), \
                mock.patch.object(library, "verify", return_value={"verified": True, "errors": []}):
            uploader.execute(self.plan, "digest", self.receipt_path)
        receipt = library.load(self.receipt_path)
        self.assertTrue(receipt["completed"])
        self.assertEqual(receipt["groups"][0]["orderedPlacementIds"], ["placement"])
        self.assertEqual([c[:2] for c in FakeWriteAPI.calls], [("POST", "/v1/appAssetLibraryImages"),
            ("PATCH", "/v1/appAssetLibraryImages/image"), ("POST", "/v1/appAssetLibraryPlacements"),
            ("POST", "/v1/appAssetLibraryPlacementOrderingRequests")])
        self.assertTrue(all(o["status"] == "completed" for o in receipt["operations"]))
        with self.assertRaisesRegex(ValueError, "already exists"):
            uploader.execute(self.plan, "digest", self.receipt_path)


class ReadinessTests(unittest.TestCase):
    def test_transient_ready_mismatch_polls_until_spec_and_dimensions_match(self):
        incomplete = {"state": "PREPARE_FOR_SUBMISSION", "specId": None,
                      "imageAsset": {"width": None, "height": None, "templateUrl": "DO_NOT_LOG"}}
        ready = {"state": "PREPARE_FOR_SUBMISSION", "specId": "expected", "imageAsset": {"width": 4, "height": 3}}
        api = mock.Mock()
        api.request.side_effect = [{"data": {"attributes": incomplete}}, {"data": {"attributes": ready}}]
        observations = []
        with mock.patch.object(uploader.time, "monotonic", return_value=0), mock.patch.object(uploader.time, "sleep"):
            result = uploader.wait_image(api, "image", ["expected"], [4, 3], observations.append)
        self.assertEqual(result, ready)
        self.assertEqual(api.request.call_count, 2)
        self.assertEqual(len(observations), 1)
        self.assertNotIn("DO_NOT_LOG", json.dumps(observations))

    def test_permanent_ready_mismatch_fails_at_original_bounded_deadline(self):
        wrong = {"state": "PREPARE_FOR_SUBMISSION", "specId": "wrong", "imageAsset": {"width": 3, "height": 4}}
        api = mock.Mock()
        api.request.return_value = {"data": {"attributes": wrong}}
        observations = []
        with mock.patch.object(uploader.time, "monotonic", side_effect=[0, 0, 301]), mock.patch.object(uploader.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "Bounded image-processing timeout.*wrong"):
                uploader.wait_image(api, "image", ["expected"], [4, 3], observations.append)
        self.assertEqual(api.request.call_count, 1)
        self.assertEqual(len(observations), 1)


class ResumeTests(unittest.TestCase):
    def setUp(self):
        ExecutionTests.setUp(self)
        second = pathlib.Path(self.directory.name) / "two.png"
        second.write_bytes(png(4, 3, shade=127))
        self.manifest["groups"][0]["files"].append(str(second))
        self.plan = library.plan(self.snapshot, self.manifest)
        upload = self.plan["uploads"][0]
        identity = "existing-image"
        placeholder = "${image:" + upload["file"]["sha256"] + "}"
        self.receipt = {"appId": self.plan["appId"], "versionString": self.plan["versionString"],
            "versionId": self.plan["versionId"], "approvedPlanSha256": "digest", "completed": False,
            "expectedGroups": [[g["locale"], g["placementGroup"]] for g in self.plan["groups"]],
            "groups": [], "uploads": [{"imageId": identity, "source": upload["file"],
                "allowedSpecIds": upload["allowedSpecIds"], "stage": "committed"}],
            "operations": [{"action": upload["reserve"], "status": "completed", "resultId": identity},
                           {"action": uploader.substitute(upload["commit"], {placeholder: identity}),
                            "status": "completed", "resultId": identity}]}
        self.receipt_path.write_text(json.dumps(self.receipt, indent=2) + "\n")
        attributes = {**upload["reserve"]["body"]["data"]["attributes"], "state": "PREPARE_FOR_SUBMISSION",
                      "specId": "dynamic-spec", "imageAsset": {"width": 4, "height": 3}}
        self.members = {"data": [{"type": "appAssetLibraryImages", "id": identity, "attributes": attributes}]}
        self.read_api = mock.Mock()
        self.read_api.list.return_value = self.members
        self.read_api.request.return_value = {"data": {"attributes": attributes}}

    def test_prepare_resume_is_get_only_and_checks_original_image_identity(self):
        before = self.receipt_path.read_bytes()
        with mock.patch.object(library, "GetOnlyAPI", return_value=self.read_api), \
                mock.patch.object(uploader, "delivery_check", return_value={"pixelExact": True}):
            artifact = uploader.prepare_resume(self.plan, "digest", self.receipt_path)
        self.assertFalse(artifact["remoteWritesPerformed"])
        self.assertEqual(len(artifact["reusedImages"]), 1)
        self.assertEqual(len(artifact["remainingUploads"]), 1)
        self.assertEqual(self.receipt_path.read_bytes(), before)
        self.assertTrue(all(call.args[0] == "GET" for call in self.read_api.request.call_args_list))
        self.assertEqual(FakeWriteAPI.calls, [])

    def test_ambiguous_receipt_and_wrong_plan_fail_closed(self):
        uploader.validate_resume_receipt(self.plan, "digest", self.receipt)
        wrong = copy.deepcopy(self.receipt)
        wrong["operations"][0]["resultUnknown"] = True
        with self.assertRaisesRegex(ValueError, "ambiguous"):
            uploader.validate_resume_receipt(self.plan, "digest", wrong)
        with self.assertRaisesRegex(ValueError, "identity/scope"):
            uploader.validate_resume_receipt(self.plan, "other-digest", self.receipt)

    def test_wrong_remote_library_membership_and_file_identity_fail_closed(self):
        for change in ("id", "fileSize"):
            members = copy.deepcopy(self.members)
            if change == "id":
                members["data"][0]["id"] = "different-image"
            else:
                members["data"][0]["attributes"]["fileSize"] += 1
            self.read_api.list.return_value = members
            with self.assertRaises(ValueError):
                uploader.inspect_resume_images(self.read_api, self.plan, self.snapshot, self.receipt)
        self.assertEqual(FakeWriteAPI.calls, [])

    def test_reviewed_resume_reuses_existing_id_and_only_reserves_remaining_file(self):
        inspection = {"imageId": "existing-image", "state": "PREPARE_FOR_SUBMISSION", "specId": "dynamic-spec",
                      "delivery": {"pixelExact": True}, "readyMismatchObservations": []}
        review = {"planSha256": "digest", "receiptSha256": uploader.hashlib.sha256(self.receipt_path.read_bytes()).hexdigest(),
                  "reusedImages": [inspection]}
        attrs = {"state": "PREPARE_FOR_SUBMISSION", "specId": "dynamic-spec", "imageAsset": {"width": 4, "height": 3}}
        # Existing upload is committed and only read/revalidated; one new reserve
        # and commit occur. Fake placement IDs need to be unique for two creates.
        base_request = FakeWriteAPI.request
        placement_counter = 0
        def request(api, method, path, body=None):
            nonlocal placement_counter
            response = base_request(api, method, path, body)
            if path == "/v1/appAssetLibraryPlacements":
                placement_counter += 1
                response["data"]["id"] = "placement-" + str(placement_counter)
            return response
        with mock.patch.object(uploader, "inspect_resume_images", return_value=[inspection]), \
                mock.patch.object(uploader, "upload_ranges"), mock.patch.object(uploader, "wait_image", return_value=attrs), \
                mock.patch.object(uploader, "delivery_check", return_value={"pixelExact": True}), \
                mock.patch.object(library, "verify", return_value={"verified": True, "errors": []}), \
                mock.patch.object(FakeWriteAPI, "request", request):
            uploader.execute(self.plan, "digest", self.receipt_path, resume_review=review)
        receipt = library.load(self.receipt_path)
        self.assertTrue(receipt["completed"])
        self.assertEqual([r["imageId"] for r in receipt["uploads"]], ["existing-image", "image"])
        reservations = [c for c in FakeWriteAPI.calls if c[1] == "/v1/appAssetLibraryImages"]
        self.assertEqual(len(reservations), 1)
        self.assertEqual(reservations[0][2]["data"]["attributes"]["fileName"], "two.png")


if __name__ == "__main__":
    unittest.main()
