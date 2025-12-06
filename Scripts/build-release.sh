#!/bin/bash

# VideoPlayer 릴리즈 빌드 및 DMG 생성 스크립트
# 사용법: ./build-release.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/Release"
APP_NAME="VideoPlayer"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"

echo "🚀 VideoPlayer Release Build"
echo "=============================="
echo ""

# 이전 빌드 정리
echo "🧹 Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Release 빌드
echo ""
echo "🔨 Building release..."
cd "$PROJECT_DIR"
swift build -c release

# 앱 번들 생성
echo ""
echo "📦 Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 실행 파일 복사
cp "$PROJECT_DIR/.build/release/VideoPlayer" "$APP_BUNDLE/Contents/MacOS/"

# Info.plist 생성
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleExecutable</key>
    <string>VideoPlayer</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourname.videoplayer</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>VideoPlayer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Video File</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.movie</string>
                <string>public.video</string>
                <string>public.mpeg-4</string>
                <string>public.avi</string>
                <string>org.matroska.mkv</string>
            </array>
        </dict>
    </array>
    <key>NSAppleEventsUsageDescription</key>
    <string>VideoPlayer needs access to control media playback.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>VideoPlayer needs access to your Desktop folder to play videos.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>VideoPlayer needs access to your Documents folder to play videos.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>VideoPlayer needs access to your Downloads folder to play videos.</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>VideoPlayer needs access to external drives to play videos.</string>
</dict>
</plist>
EOF

# PkgInfo 생성
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 라이브러리 번들링
echo ""
echo "📚 Bundling MPV libraries..."
"$SCRIPT_DIR/bundle-dylibs.sh" "$APP_BUNDLE"

# 코드 서명
echo ""
echo "🔐 Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

# DMG 생성
echo ""
echo "💿 Creating DMG..."
DMG_PATH="$BUILD_DIR/$DMG_NAME"
DMG_TEMP="$BUILD_DIR/dmg_temp"

mkdir -p "$DMG_TEMP"
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Applications 심볼릭 링크 추가
ln -s /Applications "$DMG_TEMP/Applications"

# DMG 생성
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_PATH"

# 임시 폴더 정리
rm -rf "$DMG_TEMP"

echo ""
echo "✅ Build complete!"
echo ""
echo "📊 Output:"
echo "   App: $APP_BUNDLE"
echo "   DMG: $DMG_PATH"
echo ""
ls -lh "$BUILD_DIR"/*.dmg
echo ""
echo "🎉 Ready for distribution!"

