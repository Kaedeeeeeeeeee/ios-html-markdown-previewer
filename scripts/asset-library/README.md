# App Asset Library screenshot release tools

`asset_library.py` only makes GET requests; `plan` and `manifest` are offline.
`upload_assets.py` is a separate execution path. It has not been run during the
read-only preparation phase. It requires separate authorization, the exact
reviewed plan SHA-256, and `--confirm-remote-writes`. No tool creates versions or
localizations, submits review, or deletes reusable library images.

Requirements: Python 3.9+, configured `asc` CLI for discovery/execution. Execution
also requires Pillow. `asc auth token --confirm` output is captured in process
memory and never printed or saved. API pagination and redirects are checked;
ASC bearer tokens never go to upload/delivery hosts. Receipts exclude signed
upload URLs and upload headers.

## Discover and prepare a review artifact

Run from the repository root:

```sh
python3 scripts/asset-library/asset_library.py discover \
  --app-id 6785794966 --version-string 1.8 \
  --output /tmp/html-asset-library-1.8-snapshot.json

python3 scripts/asset-library/asset_library.py specs \
  --snapshot /tmp/html-asset-library-1.8-snapshot.json \
  --group IPHONE_DUO_PROFILE

python3 scripts/asset-library/asset_library.py manifest \
  --snapshot /tmp/html-asset-library-1.8-snapshot.json \
  --screenshots-root docs/app-store-screenshots \
  --order-json docs/aso/2026-10-07-duo/materials/order.json \
  --map iphone=IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE \
  --map ipad=IPAD_13_PROFILE --map duo=IPHONE_DUO_PROFILE \
  --output /tmp/html-asset-library-1.8-manifest.json

python3 scripts/asset-library/asset_library.py plan \
  --snapshot /tmp/html-asset-library-1.8-snapshot.json \
  --manifest /tmp/html-asset-library-1.8-manifest.json \
  --output /tmp/html-asset-library-1.8-plan.json

shasum -a 256 /tmp/html-asset-library-1.8-plan.json
python3 -m unittest discover -s scripts/asset-library -p 'test_*.py' -v
```

The profile IDs in this example were verified against the live catalog on
2026-10-07; the implementation does not hardcode device-to-profile/spec enums.
Refresh discovery whenever planning/executing. The manifest follows all four
locales and the six `outputSuffixes` in `order.json`; per-locale files only are
used, not the root English compatibility copies. A missing locale or a parent
other than `PREPARE_FOR_SUBMISSION` blocks execution. A missing/invalid file
blocks plan generation. All images get dimensions, format, alpha-channel, size,
CRC/metadata, and SHA-256 checks. Actual decoding is checked again with Pillow
before uploading. Identical bytes across locales share one reusable image.

Review `versionId`, every localization/group, expected existing IDs, source
hashes, allowed spec IDs, removals, and six-image order. Existing copied 1.8
screenshots are replaced only within their 1.8 groups. Existing previews are
retained before new screenshots; other groups are unchanged. `placementGroupPosition`
is a sort key, not a writable attribute. Dynamic reference data supplies limits
and compatibility; exact dimensions are authoritative over nominal aspect labels.

## Execute only after the release owner authorizes the reviewed plan

```sh
python3 scripts/asset-library/upload_assets.py \
  --plan /tmp/html-asset-library-1.8-plan.json \
  --approved-plan-sha256 APPROVED_SHA256 \
  --expected-app-id 6785794966 \
  --expected-version-id e9e623b5-1cad-42fd-a8fc-db5b0f2be9f5 \
  --expected-locales en-US,zh-Hans,ja,zh-Hant \
  --expected-groups IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE,IPAD_13_PROFILE,IPHONE_DUO_PROFILE \
  --expected-images-per-group 6 \
  --receipt /tmp/html-asset-library-1.8-upload-receipt.json \
  --confirm-remote-writes
```

The executable first checks the separately specified app/version/locale/group/
count scope, then rechecks target version identity/editability, localization
IDs, catalog specifications, exact existing placement order, every local file
hash, and action scope. It then reserves images, uploads every byte range using
server-provided methods and headers, and commits `uploaded=true`. It does not
send `sourceFileChecksum` or `specId`; ASC classifies the processed image.
Processing polling is bounded to five minutes per image. Returned specification
and dimensions must match the plan. Delivered PNGs are downloaded at original
dimensions and compared pixel-for-pixel with local PNGs, with byte and decoded
pixel hashes recorded. JPEG delivery records pixel hashes but permits lossy
pixel differences; this release packet uses PNG.

Only after *all* images validate and deliver does the executable recheck the
parent/order, delete the planned old screenshot placements, create new ones,
and issue a group ordering request. Each successful mutation is journaled to an
atomic local receipt without credentials. Final discovery checks exact placement
IDs/order, image IDs, processed spec IDs, dimensions, and asset states.

Failure stops without automatic POST retry or rollback. Keep the receipt and
inspect the actual state before recovery; an existing receipt blocks blind
reexecution. Already uploaded unplaced images are harmless reusable assets.
Placement replacement is not atomic: a failure after old-placement deletion
requires deliberate recovery before submission. The tool deliberately never
deletes image assets. The published 1.7 localization IDs are never targeted.

If a ready asset temporarily has missing/mismatched classification or image
dimensions, the original five-minute GET deadline still applies. Matching all
expected fields is mandatory; permanent mismatches fail. Only safe state/spec/
dimension/file-size observations are journaled, without delivery/upload URLs.

An incomplete *upload-phase* receipt with every reserve/commit result known can
be recovered explicitly. First run the same plan/scope command with
`--prepare-resume --resume-review /tmp/resume-review.json` instead of
`--confirm-remote-writes`. This only reads ASC and generates a review artifact;
it never changes the original receipt. It verifies the plan/receipt hashes,
complete ordered reserve/commit history, local file hashes, membership of each
existing image ID in this app's library, exact filename/size/category/reference
name, fresh spec/dimensions, and delivered pixels. The artifact lists the reused
IDs and remaining uploads. Review and separately approve its SHA-256. Then use
`--resume --resume-review /tmp/resume-review.json
--approved-resume-review-sha256 APPROVED_RESUME_SHA256` alongside the original
scope/plan flags and `--confirm-remote-writes`. Execution checks the original
receipt hash again and rereads/revalidates every existing image before reserving
only the remaining files. Pending/unknown operations, partial blob uploads,
ambiguous IDs, and any already-started placement phase fail closed and require
manual GET reconciliation, never an automatic retry.

## Independent readback

```sh
python3 scripts/asset-library/asset_library.py discover \
  --app-id 6785794966 --version-string 1.8 \
  --output /tmp/html-asset-library-1.8-after.json
python3 scripts/asset-library/asset_library.py verify \
  --snapshot /tmp/html-asset-library-1.8-after.json \
  --receipt /tmp/html-asset-library-1.8-upload-receipt.json
```

## Verified Duo reference data (2026-10-07)

App library ID `6785794966`; profile `IPHONE_DUO_PROFILE`; platform
`IPHONE_APP_STORE`; display class `IPHONE_DUO`; family `IPHONE`. The live
`APP_SCREENSHOT` mapping accepts PNG/JPEG without alpha, at most 524288000 bytes,
and at most ten screenshots per group:

| Dimensions | Live spec ID |
| --- | --- |
| 2034 × 1398 | `47d5a794-c036-4342-8923-988990c81af9` |
| 1398 × 2034 | `205e7ab6-a23a-4ee2-b327-0a99ec2a2520` |
| 2853 × 2007 | `b83915b8-5b87-4e63-bba5-ab3a0c439862` |
| 2007 × 2853 | `5d458eef-8339-4a1f-a484-83d53834cfec` |

Apple's current model separates reusable image assets and surface placements.
Legacy screenshot sets are deprecated and their display-type enum does not
provide the Duo profile. Use the catalog/group mapping, not a guessed legacy enum.

Primary documentation:
[Asset Library](https://developer.apple.com/documentation/appstoreconnectapi/app-asset-library),
[discovering specifications](https://developer.apple.com/documentation/appstoreconnectapi/discovering-asset-specifications),
[image upload lifecycle](https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets),
[surface placements and ordering](https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces),
[migration](https://developer.apple.com/documentation/appstoreconnectapi/migrating-to-the-app-asset-library).
