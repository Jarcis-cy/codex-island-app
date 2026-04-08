#!/bin/bash
# Create a release: notarize, create DMG/ZIP, sign for Sparkle, upload to GitHub, update appcast
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
EXPORT_PATH="$BUILD_DIR/export"
RELEASE_DIR="$PROJECT_DIR/releases"
KEYS_DIR="$PROJECT_DIR/.sparkle-keys"
RELEASE_METADATA_PATH="$BUILD_DIR/release-metadata.env"
DOCS_APPCAST_PATH="$PROJECT_DIR/docs/appcast.xml"
APPCAST_URL="https://raw.githubusercontent.com/Jarcis-cy/codex-island-app/main/docs/appcast.xml"

GITHUB_REPO="Jarcis-cy/codex-island-app"

APP_PATH="$EXPORT_PATH/Codex Island.app"
APP_NAME="CodexIsland"
KEYCHAIN_PROFILE="CodexIsland"
PRIMARY_RELEASE_ASSET=""
PRIMARY_RELEASE_NAME=""
SPARKLE_APPCAST_PATH=""
SPARKLE_ENABLED=false
UNSIGNED_FALLBACK=false

rewrite_appcast_download_url() {
    local file_path="$1"
    local download_url="$2"

    python3 - "$file_path" "$download_url" <<'PY'
import re
import sys

path, url = sys.argv[1:]
text = open(path, encoding="utf-8").read()
text = re.sub(r'url="[^"]+CodexIsland-[^"]+\.(?:dmg|zip)"', f'url="{url}"', text)
open(path, "w", encoding="utf-8").write(text)
PY
}

echo "=== Creating Release ==="
echo ""

if [ -f "$RELEASE_METADATA_PATH" ]; then
    # shellcheck disable=SC1090
    source "$RELEASE_METADATA_PATH"
    PRIMARY_RELEASE_ASSET="${PRIMARY_RELEASE_ASSET:-}"
    if [ "${BUILD_EXPORT_MODE:-}" = "unsigned-fallback" ]; then
        UNSIGNED_FALLBACK=true
    fi
fi

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")

echo "Version: $VERSION (build $BUILD)"
echo ""

DEFAULT_RELEASE_NOTES="$PROJECT_DIR/docs/release-notes/v$VERSION.md"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-$DEFAULT_RELEASE_NOTES}"

mkdir -p "$RELEASE_DIR"

if [ "$UNSIGNED_FALLBACK" = true ]; then
    echo "=== Unsigned Release Fallback ==="
    echo "build.sh reported unsigned fallback mode; publishing the zip asset directly."
    PRIMARY_RELEASE_ASSET="${PRIMARY_RELEASE_ASSET:-$BUILD_DIR/release-assets/$APP_NAME-$VERSION-macOS-unsigned.zip}"
    PRIMARY_RELEASE_NAME="$(basename "$PRIMARY_RELEASE_ASSET")"
else
    echo "=== Step 1: Notarizing ==="

    if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
        echo ""
        echo "No keychain profile found. Set up credentials with:"
        echo ""
        echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
        echo "      --apple-id \"your@email.com\" \\"
        echo "      --team-id \"2DKS5U9LV4\" \\"
        echo "      --password \"xxxx-xxxx-xxxx-xxxx\""
        echo ""
        echo "Create an app-specific password at: https://appleid.apple.com"
        echo ""
        read -p "Skip notarization for now? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        SKIP_NOTARIZATION=true
        echo "WARNING: Skipping notarization. Users will see Gatekeeper warnings!"
    else
        ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
        echo "Creating zip for notarization..."
        ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

        echo "Submitting for notarization..."
        xcrun notarytool submit "$ZIP_PATH" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait

        echo "Stapling notarization ticket..."
        xcrun stapler staple "$APP_PATH"

        rm "$ZIP_PATH"
        echo "Notarization complete!"
    fi

    echo ""
    echo "=== Step 2: Creating DMG ==="

    DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
    rm -f "$DMG_PATH"

    if command -v create-dmg &>/dev/null; then
        echo "Using create-dmg for prettier output..."
        create-dmg \
            --volname "Codex Island" \
            --window-size 600 400 \
            --icon-size 100 \
            --icon "Codex Island.app" 150 200 \
            --app-drop-link 450 200 \
            --hide-extension "Codex Island.app" \
            "$DMG_PATH" \
            "$APP_PATH"
    else
        echo "Using hdiutil (install create-dmg for prettier DMG: brew install create-dmg)"
        hdiutil create -volname "Codex Island" \
            -srcfolder "$APP_PATH" \
            -ov -format UDZO \
            "$DMG_PATH"
    fi

    echo "DMG created: $DMG_PATH"
    echo ""

    if [ -z "${SKIP_NOTARIZATION:-}" ]; then
        echo "=== Step 3: Notarizing DMG ==="

        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$KEYCHAIN_PROFILE" \
            --wait

        xcrun stapler staple "$DMG_PATH"
        echo "DMG notarized!"
        echo ""
    fi

    echo "=== Step 4: Signing for Sparkle ==="

    SPARKLE_SIGN=""
    GENERATE_APPCAST=""
    POSSIBLE_PATHS=(
        "$HOME/Library/Developer/Xcode/DerivedData/CodexIsland-*/SourcePackages/artifacts/sparkle/Sparkle/bin"
    )

    for path_pattern in "${POSSIBLE_PATHS[@]}"; do
        for path in $path_pattern; do
            if [ -x "$path/sign_update" ]; then
                SPARKLE_SIGN="$path/sign_update"
                GENERATE_APPCAST="$path/generate_appcast"
                break 2
            fi
        done
    done

    if [ -z "$SPARKLE_SIGN" ]; then
        echo "WARNING: Could not find Sparkle tools."
        echo "Skipping Sparkle signing."
    elif [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
        echo "WARNING: No private key found at $KEYS_DIR/eddsa_private_key"
        echo "Run ./scripts/generate-keys.sh first"
        echo ""
        echo "Skipping Sparkle signing."
    else
        echo "Signing DMG for Sparkle..."
        SIGNATURE=$("$SPARKLE_SIGN" --ed-key-file "$KEYS_DIR/eddsa_private_key" "$DMG_PATH")

        echo ""
        echo "Sparkle signature:"
        echo "$SIGNATURE"
        echo ""

        APPCAST_DIR="$RELEASE_DIR/appcast"
        mkdir -p "$APPCAST_DIR"
        cp "$DMG_PATH" "$APPCAST_DIR/"
        "$GENERATE_APPCAST" --ed-key-file "$KEYS_DIR/eddsa_private_key" "$APPCAST_DIR"

        SPARKLE_APPCAST_PATH="$APPCAST_DIR/appcast.xml"
        SPARKLE_ENABLED=true
        echo "Appcast generated at: $SPARKLE_APPCAST_PATH"
    fi

    PRIMARY_RELEASE_ASSET="$DMG_PATH"
    PRIMARY_RELEASE_NAME="$(basename "$DMG_PATH")"
fi

echo ""
echo "=== Step 5: Creating GitHub Release ==="

if ! command -v gh &>/dev/null; then
    echo "WARNING: gh CLI not found. Install with: brew install gh"
    echo "Skipping GitHub release."
else
    if gh release view "v$VERSION" --repo "$GITHUB_REPO" &>/dev/null; then
        echo "Release v$VERSION already exists. Updating..."
        gh release upload "v$VERSION" "$PRIMARY_RELEASE_ASSET" --repo "$GITHUB_REPO" --clobber
        if [ -f "$RELEASE_NOTES_FILE" ]; then
            echo "Updating release notes from $RELEASE_NOTES_FILE"
            gh release edit "v$VERSION" \
                --repo "$GITHUB_REPO" \
                --title "Codex Island v$VERSION" \
                --notes-file "$RELEASE_NOTES_FILE"
        fi
    else
        echo "Creating release v$VERSION..."
        if [ -f "$RELEASE_NOTES_FILE" ]; then
            echo "Using release notes from $RELEASE_NOTES_FILE"
            gh release create "v$VERSION" "$PRIMARY_RELEASE_ASSET" \
                --repo "$GITHUB_REPO" \
                --title "Codex Island v$VERSION" \
                --notes-file "$RELEASE_NOTES_FILE"
        else
            gh release create "v$VERSION" "$PRIMARY_RELEASE_ASSET" \
                --repo "$GITHUB_REPO" \
                --title "Codex Island v$VERSION" \
                --notes "## Codex Island v$VERSION

### Installation / 安装
1. Download \`$PRIMARY_RELEASE_NAME\`
2. Open or extract the archive and move Codex Island to Applications
3. Launch Codex Island from Applications

1. 下载 \`$PRIMARY_RELEASE_NAME\`
2. 打开或解压归档文件，把 Codex Island 放到 Applications
3. 从 Applications 启动 Codex Island

### Auto-updates / 自动更新
After installation, Codex Island will automatically check for updates when a signed Sparkle feed is available.

安装完成后，当存在可用的签名 Sparkle feed 时，Codex Island 会自动检查更新。"
        fi
    fi

    GITHUB_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$PRIMARY_RELEASE_NAME"
    echo "GitHub release created: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
    echo "Download URL: $GITHUB_DOWNLOAD_URL"
fi

echo ""
echo "=== Step 6: Updating Repository Appcast ==="

if [ "$SPARKLE_ENABLED" = true ] && [ -f "$SPARKLE_APPCAST_PATH" ] && [ -n "${GITHUB_DOWNLOAD_URL:-}" ]; then
    cp "$SPARKLE_APPCAST_PATH" "$DOCS_APPCAST_PATH"
    rewrite_appcast_download_url "$DOCS_APPCAST_PATH" "$GITHUB_DOWNLOAD_URL"
    echo "Updated $DOCS_APPCAST_PATH"
    echo "Raw appcast URL: $APPCAST_URL"
else
    echo "Sparkle appcast not generated in this run."
    echo "Leaving $DOCS_APPCAST_PATH unchanged."
fi

echo ""
echo "=== Release Complete ==="
echo ""
echo "Files created:"
echo "  - Asset: $PRIMARY_RELEASE_ASSET"
if [ -f "$SPARKLE_APPCAST_PATH" ]; then
    echo "  - Appcast: $SPARKLE_APPCAST_PATH"
fi
if [ -n "${GITHUB_DOWNLOAD_URL:-}" ]; then
    echo "  - GitHub: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
fi
if [ -f "$DOCS_APPCAST_PATH" ]; then
    echo "  - Repository appcast: $DOCS_APPCAST_PATH"
fi
