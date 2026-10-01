#!/bin/bash
set -e
cd "$(dirname "$0")"

# Name, bundle ID and version come from the same file the Xcode project uses.
setting() { sed -n "s/^$1 *= *//p" Support/MDView.xcconfig; }
NAME="$(setting PRODUCT_NAME)"

APP="${1:-/Applications}/$NAME.app"
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

mv /tmp/mdview-universal "$MACOS/$NAME"

if [ -f AppIcon.icns ]; then
    cp AppIcon.icns "$RESOURCES/AppIcon.icns"
fi

sed -e "s/\$(PRODUCT_NAME)/$NAME/g" \
    -e "s/\$(EXECUTABLE_NAME)/$NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$(setting PRODUCT_BUNDLE_IDENTIFIER)/g" \
    -e "s/\$(MARKETING_VERSION)/$(setting MARKETING_VERSION)/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/$(setting CURRENT_PROJECT_VERSION)/g" \
    -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/$(setting MACOSX_DEPLOYMENT_TARGET)/g" \
    Support/Info.plist > "$CONTENTS/Info.plist"

# Ad-hoc signed, but sandboxed with the same entitlements as the App Store build.
codesign --force -s - --entitlements Support/MDView.entitlements "$APP"

echo "$NAME installed to $APP"
