#!/bin/zsh
set -eu
cd "$(dirname "$0")"
CLANG_MODULE_CACHE_PATH=/tmp/worshipflow-clang swift build --disable-sandbox --cache-path /tmp/worshipflow-cache -Xswiftc -module-cache-path -Xswiftc /tmp/worshipflow-modules
mkdir -p WorshipFlow.app/Contents/MacOS WorshipFlow.app/Contents/Resources .build/WorshipFlow.iconset
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/WorshipFlow.png --out ".build/WorshipFlow.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/WorshipFlow.png --out ".build/WorshipFlow.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 Assets/package-icon.py
cp Assets/WorshipFlow.png WorshipFlow.app/Contents/Resources/WorshipFlow.png
cp .build/debug/WorshipFlow WorshipFlow.app/Contents/MacOS/
cat > WorshipFlow.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>WorshipFlow</string><key>CFBundleIdentifier</key><string>tech.tophat.WorshipFlow</string><key>CFBundleIconFile</key><string>WorshipFlow.icns</string><key>CFBundleName</key><string>WorshipFlow</string><key>NSAppleEventsUsageDescription</key><string>WorshipFlow controls Music to play and pause tracks you link to songs.</string><key>CFBundleVersion</key><string>4</string><key>CFBundleShortVersionString</key><string>0.1.3</string><key>CFBundlePackageType</key><string>APPL</string><key>LSMinimumSystemVersion</key><string>13.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
