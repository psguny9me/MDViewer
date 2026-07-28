#!/usr/bin/env bash
# .app 번들 패키징 스크립트
# 사용:  ./scripts/build-app.sh [debug|release]
#        결과: build/MDViewer.app
set -euo pipefail

# 앱 버전 — 릴리스 시 여기만 올린다.
VERSION="1.1.0"
BUILD_NUM="2"

CFG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$CFG" == "release" ]]; then
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
else
    swift build
    BIN_DIR="$(swift build --show-bin-path)"
fi

APP="$ROOT/build/MDViewer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/MDViewer" "$APP/Contents/MacOS/MDViewer"

# SwiftPM resource bundle
if [[ -d "$BIN_DIR/MDViewer_MDViewer.bundle" ]]; then
    cp -R "$BIN_DIR/MDViewer_MDViewer.bundle" "$APP/Contents/Resources/"
fi

# 앱 아이콘
ICON_SRC="$ROOT/Sources/MDViewer/Resources/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MDViewer</string>
    <key>CFBundleDisplayName</key>
    <string>MDViewer</string>
    <key>CFBundleIdentifier</key>
    <string>app.local.mdviewer</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUM</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MDViewer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
                <string>public.plain-text</string>
            </array>
        </dict>
        <dict>
            <key>CFBundleTypeName</key>
            <string>JSON Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.json</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST

# 코드 서명 (로컬 ad-hoc) - Hardened/Gatekeeper 없이 동작
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
