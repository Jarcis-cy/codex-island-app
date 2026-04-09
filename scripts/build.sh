#!/bin/bash
# Build Codex Island for release
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MACOS_PROJECT_PATH="$PROJECT_DIR/apps/macos/CodexIsland.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/CodexIsland.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
RELEASE_ASSETS_DIR="$BUILD_DIR/release-assets"
RELEASE_METADATA_PATH="$BUILD_DIR/release-metadata.env"
APP_BUNDLE_NAME="Codex Island.app"

run_xcodebuild() {
    if command -v xcpretty >/dev/null 2>&1; then
        xcodebuild "$@" | xcpretty
    else
        xcodebuild "$@"
    fi
}

write_metadata() {
    local export_mode="$1"
    local app_path="$2"
    local asset_path="$3"
    local version="$4"
    local build="$5"

    cat > "$RELEASE_METADATA_PATH" <<EOF
BUILD_EXPORT_MODE="$export_mode"
APP_PATH="$app_path"
PRIMARY_RELEASE_ASSET="$asset_path"
VERSION="$version"
BUILD="$build"
EOF
}

echo "=== Building Codex Island ==="
echo ""

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$RELEASE_ASSETS_DIR"

cd "$PROJECT_DIR"

echo "Archiving..."
run_xcodebuild archive \
    -project "$MACOS_PROJECT_PATH" \
    -scheme CodexIsland \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_STYLE=Automatic

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

ARCHIVED_APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_BUNDLE_NAME"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ARCHIVED_APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ARCHIVED_APP_PATH/Contents/Info.plist")

echo ""
echo "Exporting..."
if run_xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"; then
    APP_PATH="$EXPORT_PATH/$APP_BUNDLE_NAME"
    write_metadata "signed" "$APP_PATH" "$APP_PATH" "$VERSION" "$BUILD"
else
    echo "WARNING: exportArchive failed. Falling back to unsigned release packaging."
    rm -rf "$EXPORT_PATH"
    mkdir -p "$EXPORT_PATH"
    ditto "$ARCHIVED_APP_PATH" "$EXPORT_PATH/$APP_BUNDLE_NAME"

    UNSIGNED_ZIP_PATH="$RELEASE_ASSETS_DIR/CodexIsland-$VERSION-macOS-unsigned.zip"
    rm -f "$UNSIGNED_ZIP_PATH"
    ditto -c -k --sequesterRsrc --keepParent "$EXPORT_PATH/$APP_BUNDLE_NAME" "$UNSIGNED_ZIP_PATH"

    write_metadata "unsigned-fallback" "$EXPORT_PATH/$APP_BUNDLE_NAME" "$UNSIGNED_ZIP_PATH" "$VERSION" "$BUILD"

    echo "Unsigned fallback zip created at: $UNSIGNED_ZIP_PATH"
fi

echo ""
echo "=== Build Complete ==="
echo "App exported to: $EXPORT_PATH/Codex Island.app"
echo "Release metadata written to: $RELEASE_METADATA_PATH"
echo ""
echo "Next: Run ./scripts/create-release.sh to package and publish the release asset"
