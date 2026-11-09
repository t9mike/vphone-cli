#!/bin/zsh
set -euo pipefail
here=${0:a:h}
out=${1:?pass a temporary output directory}
mkdir -p "$out/StandByProbe.bundle"
xcrun --sdk iphoneos clang -arch arm64e -miphoneos-version-min=26.0 -fobjc-arc \
  -Wall -Wextra -Werror -dynamiclib -framework Foundation \
  "$here/StandByProbe.m" -o "$out/StandByProbe.bundle/StandByProbe"
cat > "$out/StandByProbe.bundle/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.vphone.StandByProbe</string>
<key>CFBundleExecutable</key><string>StandByProbe</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
PLIST
codesign --force --sign - "$out/StandByProbe.bundle"
print -- "$out/StandByProbe.bundle"
