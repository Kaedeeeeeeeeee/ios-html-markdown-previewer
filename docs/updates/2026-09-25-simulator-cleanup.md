# Simulator cleanup and iPad boot recovery — 2026-09-25

The simulator inventory contained 32 devices with 65.77 GiB of reported device
data. The Data volume had 14.27 GiB available at the cleanup preflight.

## Scoped cleanup

- Deleted six older, shut-down test devices last used before September 15, plus
  the two HTML Previewer iPads from the failed validation attempts. Names, IDs,
  state, and last-used dates were checked again immediately before deletion.
- Removed the superseded iOS 27 `24A5390f` and watchOS 27 `24R5325f` runtime
  images selected by `simctl runtime delete --outdated --dry-run`.
- Removed the unused watchOS 11.5 `22T572` runtime. Its original MobileAsset
  download remains on disk; runtime removal is not equivalent to reclaiming
  every backing asset byte.
- Preserved other active simulators and recent devices. Shut down this task's
  iPhone after its completed validation, retaining its data.
- Created one replacement iPad Air 11-inch (M3), iOS 26.5, named
  `HTML Previewer QA iPad` (`7A3C8A64-C67B-41CC-8F7F-48BCD635C99C`).

Device sizes include shared APFS extents, so their sum is not an estimate of
unique reclaimed disk space. The cleanup manifest records actual free-space
measurements and each official `simctl` deletion result.

At 06:10:01 UTC, after creating the replacement device and starting UI tests,
available space was 27.21 GiB: an observed net increase of 12.94 GiB. The final
inventory contained 25 devices and six runtime images (previously nine).
Concurrent work and test writes can change these measurements. The watchOS 11.5
source DMG still occupies 4.52 GiB; an official dry run using its parent image ID
found no matching registered runtime, so that asset was left untouched.

After both iPad tests passed and this task's iPad was shut down, the measurement
at 06:12:38 UTC showed 30.75 GiB available, 16.48 GiB more than the preflight.
The device count remained 25. These final figures are recorded in the cleanup
manifest's `afterTests` field; they reflect the volume's observed net change,
including asynchronous reclamation and concurrent activity.

## Boot recovery

The replacement iPad still stalled at the Apple boot progress screen. The app
built and installed successfully, but host-to-simulator launch requests waited
for a response before an app process existed. Process samples traced the wait:

`SpringBoard → BackBoard data migration → CoreLocationMigrator → locationd → dasd`

The simulator's `dasd` was blocked during initialization while synchronously
submitting a task to its own service. After verifying the process and its parent
belonged to this exact fresh QA device, a targeted restart of that process
allowed boot to finish at 06:08:25 UTC. SIGTERM did not stop the blocked process;
SIGKILL let launchd restart it. No launch configuration was changed, and other
devices' services were not restarted.

The app subsequently rendered its HTML sample and bottom-right action capsule.
This evidence identifies a system-service boot stall in the fresh-device retry;
it does not prove that low disk space caused the earlier test-runner failures.

## Evidence

Local evidence is under `DerivedData/SimulatorCleanupQA/`:

- `cleanup-manifest.json`: preflight inventory and deletion results.
- `storage-verification.json`: allocation and removal checks.
- `final-storage-state.json`: post-cleanup counts and free space.
- `ipad-*-sample.txt`: launch and system-service process samples.
- `ipad-stalled-boot.jpg`: Apple boot-progress screenshot.
- `ipad-service-recovery.json`: narrowly scoped recovery actions.

Both iPad UI tests passed (164.9 seconds, zero failures). Native screenshots of
the title/actions, keyboard search, last paragraph, and repeated PDF share
popover were inspected. Results are recorded in
`2026-09-25-preview-bottom-toolbar.md`.

## Follow-up: retain exactly five devices

The user subsequently requested reducing the remaining inventory to five
representative devices. Twenty more devices were removed through `simctl`,
retaining the following existing devices and their data:

| Model | System | Existing name | UUID |
| --- | --- | --- | --- |
| iPhone 18 Pro | iOS 27.0 | iPhone 18 Pro | F56A2968-F35C-4455-8A34-43DCC6CDC319 |
| iPhone 16 Pro Max | iOS 18.5 | FocusDensya UX Comparison | ED576109-EEC6-4F86-A927-635B96DDF97E |
| iPhone SE (3rd generation) | iOS 18.5 | Passnote AP Small Audit 20260827 | 33A52CD6-A4B9-495C-8E07-2B140C8E8353 |
| iPad Air 11-inch (M3) | iPadOS 26.5 | HTML Previewer QA iPad | 7A3C8A64-C67B-41CC-8F7F-48BCD635C99C |
| iPad Pro 12.9-inch (6th generation) | iPadOS 18.5 | Passnote ASO iPad Pro 12.9 | 9216FE52-CA0E-4113-8ED5-19B4BF9755CE |

This retains small, standard, and large phones, two tablet sizes, and three OS
versions. The more recent FocusDensya UX device was kept instead of the duplicate
Release device. The latter was shut down before deletion; no XCTest runner or
build was active on it. The retained FocusDensya and Passnote sessions remained
running. Device names were preserved.

After the device cleanup, iOS 18.4, watchOS 26.5, and watchOS 27.0 had no devices
and were removed using official runtime deletion. Final verification found
exactly five registered devices, all available, and only the three required
runtime images: iOS 18.5, 26.5, and 27.0.

At 06:39:58 UTC the Data volume had 60.09 GiB available, compared with 46.08 GiB
at this follow-up's preflight: an observed net increase of 14.01 GiB. Reclamation
is asynchronous and other tasks share the disk, so these are point-in-time
volume measurements, not a sum of nominal device sizes.

The detailed preflight, deletion results, final inventory, and independent audit
are under `DerivedData/SimulatorCleanupQA/keep-five/`. All 20 removed device IDs
are absent from the registry. Nineteen device directories disappeared completely;
one deleted, unpaired Watch device retained an 8 KiB system-managed skeleton
marked `isDeleted=true`, which was left to CoreSimulator to clean up.
