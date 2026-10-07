#!/usr/bin/env bash
# Capture an explicitly selected, already installed simulator. No build, device
# selection, boot, pose changes, upload, or normal-library mutation occurs here.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKET="$ROOT_DIR/docs/aso/2026-10-07-duo/materials"
DEVICE="" FAMILY="" DISPLAY="" LOCALES="en-US zh-Hans ja zh-Hant" KEYS=""
WAIT_SECONDS="${SCREENSHOT_SAMPLE_WAIT_SECONDS:-12}"
BUNDLE_ID="com.kaede.htmlmarkdownpreviewer"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2";; --family) FAMILY="$2";; --display) DISPLAY="$2";;
    --packet) PACKET="$2";; --locales) LOCALES="${2//,/ }";; --keys) KEYS="${2//,/ }";;
    *) echo "Unknown option: $1" >&2; exit 2;;
  esac
  shift 2
done
for locale in $LOCALES; do
  for filename in weekly-report.html developer-notes.md; do
    [[ -f "$PACKET/fixtures/$locale/$filename" ]] || { echo "Missing localized fixture: $locale/$filename" >&2; exit 2; }
  done
done
[[ -n "$DEVICE" && "$FAMILY" =~ ^(iphone|ipad|duo)$ ]] || { echo "Require --device <existing UDID> --family iphone|ipad|duo" >&2; exit 2; }
[[ -n "${DEVELOPER_DIR:-}" ]] || { echo "Set DEVELOPER_DIR explicitly for this capture; the global Xcode selection is not changed." >&2; exit 2; }
if [[ "$FAMILY" == duo ]]; then
  [[ "$DISPLAY" == 1 || "$DISPLAY" == 3 ]] || { echo "Duo requires --display 1 (Closed) or 3 (Open); set the real pose before running." >&2; exit 2; }
  if [[ -z "$KEYS" ]]; then
    if [[ "$DISPLAY" == 3 ]]; then KEYS="05-library 01-html-report 03-json-preview";
    else KEYS="04-markdown-preview 06-yaml-preview 02-batch-import"; fi
  fi
else
  KEYS="${KEYS:-05-library 01-html-report 04-markdown-preview 03-json-preview 06-yaml-preview 02-batch-import}"
fi
for key in $KEYS; do
  case "$key" in 01-html-report|04-markdown-preview|03-json-preview|06-yaml-preview|02-batch-import|05-library) ;; *) echo "Unknown source key $key" >&2; exit 2;; esac
  if [[ "$FAMILY" == duo ]]; then
    case "$key" in 01-html-report|03-json-preview|05-library) required_display=3;; *) required_display=1;; esac
    [[ "$DISPLAY" == "$required_display" ]] || { echo "$key requires display $required_display; no pose changes are automated." >&2; exit 2; }
  fi
done
python3 - "$DEVICE" <<'PY'
import json,subprocess,sys
groups=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json'],text=True))['devices']
device=next((x for group in groups.values() for x in group if x['udid']==sys.argv[1]),None)
if not device or device['state']!='Booted': raise SystemExit('Explicit existing simulator must already be Booted; no other device is selected.')
PY
APPEARANCE="$(xcrun simctl ui "$DEVICE" appearance)"
CAPTURE_TEMP="$(mktemp -d /tmp/html-previewer-aso-capture.XXXXXX)"
restore() {
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl status_bar "$DEVICE" clear >/dev/null 2>&1 || true
  if [[ "$APPEARANCE" == light || "$APPEARANCE" == dark ]]; then xcrun simctl ui "$DEVICE" appearance "$APPEARANCE" >/dev/null 2>&1 || true; fi
  rm -rf "$CAPTURE_TEMP"
}
trap restore EXIT
for locale in $LOCALES; do
  case "$locale" in en-US) language=en; apple_locale=en_US;; zh-Hans) language=zh-Hans; apple_locale=zh_CN;; zh-Hant) language=zh-Hant; apple_locale=zh_TW;; ja) language=ja; apple_locale=ja_JP;; *) echo "Unsupported locale: $locale" >&2; exit 2;; esac
  output_dir="$PACKET/sources/$locale"; mkdir -p "$output_dir"
  # Reset only the isolated Debug UI-test library, then seed localized templates.
  SIMCTL_CHILD_HTML_PREVIEWER_UI_TESTS=1 xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" --screenshot-reset-library -AppleLanguages "($language)" -AppleLocale "$apple_locale" >/dev/null
  python3 - "$DEVICE" <<'PY'
from pathlib import Path
import subprocess,sys,time
container=Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[1],'com.kaede.htmlmarkdownpreviewer','data'],text=True).strip())
imports=container/'Library/Application Support/com.kaede.htmlmarkdownpreviewer/UITestLibrary/Imports'
deadline=time.monotonic()+30;empty_since=None
while time.monotonic()<deadline:
    remaining=list(imports.glob('*/metadata.json'))
    if not remaining:
        empty_since=empty_since or time.monotonic()
        if time.monotonic()-empty_since>=1:break
    else:empty_since=None
    time.sleep(.2)
else:raise SystemExit('Isolated UITestLibrary reset did not settle empty; seeding aborted.')
print('Isolated library reset verified empty.')
PY
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
  python3 "$ROOT_DIR/scripts/prepare-aso-materials.py" --packet "$PACKET" --seed "$DEVICE" --locale "$locale"
  for key in $KEYS; do
    xcrun simctl ui "$DEVICE" appearance light
    case "$key" in
      01-html-report) args=(--screenshot-open-document=weekly-report.html);;
      04-markdown-preview) args=(--screenshot-open-document=developer-notes.md);;
      03-json-preview) args=(--screenshot-sample=json);;
      06-yaml-preview) xcrun simctl ui "$DEVICE" appearance dark; args=(--screenshot-sample=yaml);;
      02-batch-import) args=(--screenshot-reset-library "--batch-import-fixture=$(uuidgen)" --batch-import-scenario=showcase);;
      05-library)
        args=(--screenshot-library)
        if [[ "$FAMILY" == duo || "$FAMILY" == ipad ]]; then args+=(--screenshot-open-document=weekly-report.html); fi
        ;;
    esac
    SIMCTL_CHILD_HTML_PREVIEWER_UI_TESTS=1 xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE_ID" "${args[@]}" -AppleLanguages "($language)" -AppleLocale "$apple_locale" >/dev/null
    xcrun simctl status_bar "$DEVICE" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
    sleep "$WAIT_SECONDS"
    capture_args=(io "$DEVICE" screenshot)
    if [[ -n "$DISPLAY" ]]; then capture_args+=("--display=$DISPLAY"); fi
    # Simulator services may not have access to /Volumes. Copy native bytes from
    # our unique temporary directory without image conversion or resampling.
    xcrun simctl "${capture_args[@]}" "$CAPTURE_TEMP/capture.png" >/dev/null
    cp "$CAPTURE_TEMP/capture.png" "$output_dir/$FAMILY-$key.png"
    python3 - "$output_dir/$FAMILY-$key.png" "$PACKET" "$DEVICE" "$FAMILY" "$key" "$locale" "$DISPLAY" <<'PY'
from PIL import Image
from pathlib import Path
import sys,json,hashlib,datetime,subprocess,plistlib
path=Path(sys.argv[1]);packet=Path(sys.argv[2]);im=Image.open(path)
app=Path(subprocess.check_output(['xcrun','simctl','get_app_container',sys.argv[3],'com.kaede.htmlmarkdownpreviewer','app'],text=True).strip())
info=plistlib.loads((app/'Info.plist').read_bytes());binaries={}
for name in [info['CFBundleExecutable'],info['CFBundleExecutable']+'.debug.dylib']:
    f=app/name
    if f.is_file(): binaries[name]=hashlib.sha256(f.read_bytes()).hexdigest()
record={'capturedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'path':str(path.relative_to(packet)),'deviceId':sys.argv[3],'family':sys.argv[4],'sourceKey':sys.argv[5],'locale':sys.argv[6],'displayId':int(sys.argv[7]) if sys.argv[7] else None,'pixels':list(im.size),'mode':im.mode,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'appVersion':info.get('CFBundleShortVersionString'),'buildNumber':info.get('CFBundleVersion'),'installedExecutableSHA256':binaries,'developerDirectory':__import__('os').environ['DEVELOPER_DIR'],'sourceKind':'Actual simulator app capture; isolated UITestLibrary and synthetic fixtures','poseSelection':'Native operator sets pose before capture; script does not change pose','visualReview':'pending','sourcePixelsEdited':False}
record_path=packet/'capture-records'/sys.argv[6]/(sys.argv[4]+'-'+sys.argv[5]+'.json');record_path.parent.mkdir(parents=True,exist_ok=True);record_path.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n')
print(str(path),im.size,im.mode)
PY
  done
done
