#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION="${CONFIGURATION:-debug}"
PRODUCT="${PRODUCT:-MCPHQApp}"
CLI_PRODUCT="${CLI_PRODUCT:-mcphq}"
APP_NAME="${APP_NAME:-MCP-HQ}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.mcphq.app}"
APP_CATEGORY="${APP_CATEGORY:-public.app-category.developer-tools}"
MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-14.0}"
APP_ICON_PATH="${APP_ICON_PATH:-}"
APP_ICON_NAME="${APP_ICON_NAME:-MCPHQAppIcon}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
CODESIGN_FLAGS="${CODESIGN_FLAGS:-}"
CLEAN_SWIFT_BUILD="${CLEAN_SWIFT_BUILD:-0}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

version_from_git() {
    git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true
}

build_number_from_git() {
    git rev-list --count HEAD 2>/dev/null || true
}

MARKETING_VERSION="${MARKETING_VERSION:-$(version_from_git)}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(build_number_from_git)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "error: MARKETING_VERSION must be numeric dot-separated form such as 0.1.0 (got '$MARKETING_VERSION')" >&2
    exit 64
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    echo "error: BUILD_NUMBER must be numeric dot-separated form such as 1 or 42.1 (got '$BUILD_NUMBER')" >&2
    exit 64
fi

if [[ -n "$APP_ICON_PATH" ]]; then
    if [[ ! -f "$APP_ICON_PATH" ]]; then
        echo "error: APP_ICON_PATH does not exist or is not a file: $APP_ICON_PATH" >&2
        exit 66
    fi
    if [[ "$APP_ICON_PATH" != *.icns ]]; then
        echo "error: APP_ICON_PATH must point to a .icns file (got '$APP_ICON_PATH')" >&2
        exit 66
    fi
    if [[ -z "$APP_ICON_NAME" || "$APP_ICON_NAME" == */* ]]; then
        echo "error: APP_ICON_NAME must be a resource filename or stem, not a path" >&2
        exit 66
    fi
fi

xml_escape() {
    local value="$1"
    value="${value//&/&amp;}"
    value="${value//</&lt;}"
    value="${value//>/&gt;}"
    value="${value//\"/&quot;}"
    value="${value//\'/&apos;}"
    printf '%s' "$value"
}

safe_rm_app() {
    local path="$1"
    if [[ -z "$path" || "$path" == "/" || "$path" != *.app ]]; then
        echo "error: refusing to remove non-.app bundle path: $path" >&2
        exit 65
    fi
    rm -rf "$path"
}

plist_value() {
    local plist_path="$1"
    local key="$2"
    plutil -extract "$key" raw -o - "$plist_path" 2>/dev/null || true
}

require_plist_value() {
    local plist_path="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual="$(plist_value "$plist_path" "$key")"
    if [[ "$actual" != "$expected" ]]; then
        echo "error: $key expected '$expected' in $plist_path but found '$actual'" >&2
        exit 67
    fi
}

validate_bundle() {
    local bundle_path="$1"
    local info_plist="$bundle_path/Contents/Info.plist"
    local app_executable="$bundle_path/Contents/MacOS/$PRODUCT"
    local cli_executable="$bundle_path/Contents/MacOS/$CLI_PRODUCT"

    [[ -d "$bundle_path/Contents/MacOS" ]] || { echo "error: missing Contents/MacOS in $bundle_path" >&2; exit 67; }
    [[ -d "$bundle_path/Contents/Resources" ]] || { echo "error: missing Contents/Resources in $bundle_path" >&2; exit 67; }
    [[ -x "$app_executable" ]] || { echo "error: missing executable $app_executable" >&2; exit 67; }
    [[ -x "$cli_executable" ]] || { echo "error: missing helper executable $cli_executable" >&2; exit 67; }
    [[ -f "$bundle_path/Contents/PkgInfo" ]] || { echo "error: missing PkgInfo in $bundle_path" >&2; exit 67; }

    plutil -lint "$info_plist" >/dev/null
    require_plist_value "$info_plist" CFBundleExecutable "$PRODUCT"
    require_plist_value "$info_plist" CFBundleIdentifier "$BUNDLE_IDENTIFIER"
    require_plist_value "$info_plist" CFBundleName "$APP_NAME"
    require_plist_value "$info_plist" CFBundlePackageType APPL
    require_plist_value "$info_plist" CFBundleShortVersionString "$MARKETING_VERSION"
    require_plist_value "$info_plist" CFBundleVersion "$BUILD_NUMBER"
    require_plist_value "$info_plist" LSApplicationCategoryType "$APP_CATEGORY"
    require_plist_value "$info_plist" LSMinimumSystemVersion "$MIN_MACOS_VERSION"

    if [[ -n "$APP_ICON_PATH" ]]; then
        local icon_resource_name="${APP_ICON_NAME%.icns}.icns"
        [[ -f "$bundle_path/Contents/Resources/$icon_resource_name" ]] || {
            echo "error: missing icon resource Contents/Resources/$icon_resource_name" >&2
            exit 67
        }
        require_plist_value "$info_plist" CFBundleIconFile "${icon_resource_name%.icns}"
    fi
}

if [[ "$CLEAN_SWIFT_BUILD" == "1" ]]; then
    swift package clean
fi

swift build -c "$CONFIGURATION" --product "$PRODUCT"
swift build -c "$CONFIGURATION" --product "$CLI_PRODUCT"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BUNDLE_PATH="${BUNDLE_PATH:-$ROOT_DIR/.build/$APP_NAME.app}"
TMP_BUNDLE_PATH="${BUNDLE_PATH%.app}.tmp.$$.app"

safe_rm_app "$TMP_BUNDLE_PATH"
mkdir -p "$TMP_BUNDLE_PATH/Contents/MacOS" "$TMP_BUNDLE_PATH/Contents/Resources"

cp "$BIN_DIR/$PRODUCT" "$TMP_BUNDLE_PATH/Contents/MacOS/$PRODUCT"
chmod +x "$TMP_BUNDLE_PATH/Contents/MacOS/$PRODUCT"
cp "$BIN_DIR/$CLI_PRODUCT" "$TMP_BUNDLE_PATH/Contents/MacOS/$CLI_PRODUCT"
chmod +x "$TMP_BUNDLE_PATH/Contents/MacOS/$CLI_PRODUCT"

ICON_PLIST_ENTRY=""
if [[ -n "$APP_ICON_PATH" ]]; then
    ICON_RESOURCE_NAME="${APP_ICON_NAME%.icns}.icns"
    cp "$APP_ICON_PATH" "$TMP_BUNDLE_PATH/Contents/Resources/$ICON_RESOURCE_NAME"
    ICON_PLIST_ENTRY="    <key>CFBundleIconFile</key>
    <string>$(xml_escape "${ICON_RESOURCE_NAME%.icns}")</string>"
fi

cat > "$TMP_BUNDLE_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(xml_escape "$PRODUCT")</string>
    <key>CFBundleIdentifier</key>
    <string>$(xml_escape "$BUNDLE_IDENTIFIER")</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
${ICON_PLIST_ENTRY}
    <key>CFBundleName</key>
    <string>$(xml_escape "$APP_NAME")</string>
    <key>CFBundleDisplayName</key>
    <string>$(xml_escape "$APP_NAME")</string>
    <key>CFBundleGetInfoString</key>
    <string>$(xml_escape "$APP_NAME $MARKETING_VERSION ($BUILD_NUMBER)")</string>
    <key>CFBundleSpokenName</key>
    <string>$(xml_escape "MCP HQ")</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$(xml_escape "$MARKETING_VERSION")</string>
    <key>CFBundleVersion</key>
    <string>$(xml_escape "$BUILD_NUMBER")</string>
    <key>LSApplicationCategoryType</key>
    <string>$(xml_escape "$APP_CATEGORY")</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(xml_escape "$MIN_MACOS_VERSION")</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026 MCP-HQ contributors</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$TMP_BUNDLE_PATH/Contents/PkgInfo"
validate_bundle "$TMP_BUNDLE_PATH"

safe_rm_app "$BUNDLE_PATH"
mv "$TMP_BUNDLE_PATH" "$BUNDLE_PATH"

if [[ -n "$SIGN_IDENTITY" ]]; then
    if [[ -n "$CODESIGN_FLAGS" ]]; then
        # shellcheck disable=SC2206 # Intentionally allow callers to pass simple codesign flag words.
        EXTRA_CODESIGN_FLAGS=($CODESIGN_FLAGS)
        codesign --force --sign "$SIGN_IDENTITY" "${EXTRA_CODESIGN_FLAGS[@]}" "$BUNDLE_PATH"
    else
        codesign --force --sign "$SIGN_IDENTITY" "$BUNDLE_PATH"
    fi
    codesign --verify --deep --strict "$BUNDLE_PATH"
fi

echo "Built $BUNDLE_PATH"
echo "Version: $MARKETING_VERSION ($BUILD_NUMBER)"
echo "Helper: Contents/MacOS/$CLI_PRODUCT"
if [[ -n "$APP_ICON_PATH" ]]; then
    echo "Icon: Contents/Resources/${APP_ICON_NAME%.icns}.icns"
else
    echo "Icon: default macOS app icon (set APP_ICON_PATH=/path/to/icon.icns to embed one)"
fi
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "Signed with identity: $SIGN_IDENTITY"
else
    echo "Signing skipped. Set SIGN_IDENTITY='-' for ad-hoc signing or a Developer ID identity for distribution."
fi
