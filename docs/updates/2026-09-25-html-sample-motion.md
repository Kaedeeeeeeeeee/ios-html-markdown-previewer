# Animated HTML weekend sample

The HTML example retains the existing weekend itinerary, system typography, blue accents, neutral surfaces, and light/dark appearance. A new illustrated postcard demonstrates local rendering without page scripts or external resources.

## Changes

- CSS-driven clouds, rotating sun rays, river ripples, rising coffee steam, swaying tree foliage, a moving route segment, and a breathing route marker.
- Native radio controls switch between daylight and evening with color and position transitions. A checkbox pauses/resumes the decorative animations.
- Three stop links scroll to and highlight the corresponding itinerary entry. A native details disclosure provides a packing note.
- Inline SVG gradients, a translucent blurred time badge, responsive layout, visible keyboard focus, and reduced-motion support.
- Reduced-motion mode removes the animations/transitions and hides the unused pause control from both view and focus navigation. Print mode produces a static, light version with the complete itinerary.
- Twelve new strings translated into English, Simplified Chinese, Traditional Chinese, and Japanese. HTML content is escaped through the existing sample helper.
- The new stylesheet applies only to the HTML sample. Markdown and ZIP samples are unchanged. Existing imported copies remain unchanged; opening the HTML sample from Home creates the new version.

## Validation

- iPhone 18 Pro, iOS 27.0 simulator: native Safe Preview displays the scene and animations. Inspected light and dark screenshots; a 25-second recording confirms movement between frames.
- All eight selected tests passed, with no failures or skips: sample generation/import, five PDF/share service tests, built-in sample/settings UI smoke, and repeated HTML PDF export UI smoke.
- Actual PDF exported by the app contains one complete A4 page, including title and footer. Visually inspected its rendered page; no clipping or SVG gradient artifacts were found.
- Ego Lite verified the imported HTML's animation times and computed styles: all nine animation instances advance, freeze when paused, and resume. Day/evening changes are reversible; details and anchor navigation work.
- Browser layouts at widths 320, 402, and 768 in light/dark appearance have no horizontal overflow. Stop links meet a 44-point minimum height. Emulated reduced-motion leaves zero running animations and hides both the pause input and its label.
- All 48 new localization values and source whitespace checks passed.

The browser fixture was copied from the actual simulator import. Its only adjustment was the latest source fix to hide the pause input together with its label in reduced-motion mode; the final simulator build includes that fix.

Result bundle: `~/Library/Developer/XcodeBuildMCP/workspaces/html_preview-0a68f0590b32/result-bundles/test_sim_2026-09-25T04-42-39-975Z_pid64081_fbf14c9f.xcresult`.

Local artifacts under `DerivedData/HTMLMotionQA/`:

- `html-motion-zh.mp4`: native simulator recording.
- `motion-frame-1.png`, `motion-frame-5.png`, `html-dark-zh.jpg`: inspected native images.
- `browser-report.json`: interaction, motion, appearance, and responsive-layout results.
- `weekend-plan.pdf`, `weekend-plan-page-1.png`, `pdf-review.json`: app-exported PDF and visual-review evidence.

Work is local on `codex/html-sample-motion`. No physical-device installation, Git push, or App Store release was performed for this change.
