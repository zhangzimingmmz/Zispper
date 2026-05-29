#!/bin/bash
set -euo pipefail

APP_NAME="zispper"
BUILD_DIR=".build/release"
OUTPUT_DIR="."
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-com.zhangziming.zispper}"

echo "Building release binary..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BINARY"

cat > "$INFO_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_IDENTIFIER</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>需要麦克风权限来录制语音，并将语音转换成文字。</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>需要辅助功能权限来监听 Fn 键，并把识别结果粘贴到当前输入框。</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

echo "Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Done. App created at $APP_BUNDLE"
echo "如果 macOS 重新询问权限，请在系统设置里授予麦克风和辅助功能权限。"
