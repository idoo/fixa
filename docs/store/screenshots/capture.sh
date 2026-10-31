#!/usr/bin/env bash
# Raw App Store captures for Fixa, iPhone 6.9" (1320x2868), sv + en-US.
# Uses its own simulator "Fixa Shots 17 Pro Max"; never touches other devices.
# Needs the Debug simulator build (does not build anything):
#   build/DD/Build/Products/Debug-iphonesimulator/Fixa.app
# Usage: docs/store/screenshots/capture.sh [screen ...]   (SETTLE=<seconds> to wait longer)
# Every simctl call is capped at 60 s so a wedged simulator fails the run instead of hanging it.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
app="$repo/build/DD/Build/Products/Debug-iphonesimulator/Fixa.app"
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
name="Fixa Shots 17 Pro Max"
settle="${SETTLE:-4}"
screens=("$@")
[ ${#screens[@]} -gt 0 ] || screens=(home location receipt privacy settings language)

sim() { timeout 60 xcrun simctl "$@"; }

udid="$(sim list devices -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == name and d.get("isAvailable", True):
            print(d["udid"]); sys.exit()
' "$name")"
[ -n "$udid" ] || udid="$(sim create "$name" "iPhone 17 Pro Max")"
echo "simulator $name $udid"

sim boot "$udid" 2>/dev/null || true
sim bootstatus "$udid" -b >/dev/null
sim status_bar "$udid" override --time 9:41 \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
sim install "$udid" "$app"

shoot() { # locale-dir FixaLanguage AppleLocale screen [output-name]
  local dir="$here/captures/$1" out="${5:-$4}" raw
  mkdir -p "$dir"
  raw="$(mktemp -t fixa-shot).png"
  sim terminate "$udid" "$bundle" >/dev/null 2>&1 || true
  sim launch "$udid" "$bundle" -FixaDemo 1 -FixaScreen "$4" \
    -FixaLanguage "$2" -AppleLocale "$3" >/dev/null
  sleep "$settle"
  sim io "$udid" screenshot --type=png "$raw" >/dev/null 2>&1
  magick "$raw" -alpha off "PNG24:$dir/$out.png"
  rm -f "$raw"
  echo "captured captures/$1/$out.png"
}

for s in "${screens[@]}"; do shoot sv sv sv_SE "$s"; done
for s in "${screens[@]}"; do shoot en-US en en_US "$s"; done
# Frame 05 (write in your language): a Swedish UI shows the kommun's Swedish as is, so the sv
# gallery shows the receipt in Finnish, the en-US gallery in English.
if [[ " ${screens[*]} " == *" receipt "* ]]; then
  shoot sv fi fi_FI receipt receipt-translated
  shoot en-US en en_US receipt receipt-translated
fi

sim terminate "$udid" "$bundle" >/dev/null 2>&1 || true
sim shutdown "$udid"
echo "shut down $name"
