#!/bin/bash
set -e
cd "$(dirname "$0")"

APP="/Applications/MDView.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building arm64..."
swift build -c release --arch arm64
echo "Building x86_64..."
swift build -c release --arch x86_64

echo "Creating universal binary..."
lipo -create \
    .build/arm64-apple-macosx/release/mdview \
    .build/x86_64-apple-macosx/release/mdview \
    -output /tmp/mdview-universal

echo "Creating app bundle..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

mv /tmp/mdview-universal "$MACOS/mdview"

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$RESOURCES/AppIcon.icns"
fi

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MDView</string>
    <key>CFBundleDisplayName</key>
    <string>MDView</string>
    <key>CFBundleIdentifier</key>
    <string>com.mdview.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>mdview</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>md</string>
                <string>markdown</string>
                <string>mdown</string>
                <string>mkd</string>
                <string>txt</string>
            </array>
        </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key>
    <string>MDView needs access to open files.</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP"

echo "MDView installed to $APP"
