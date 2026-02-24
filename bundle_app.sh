#!/bin/bash

APP_NAME="Zispper"
SOURCES="Sources"
BUILD_DIR=".build/release"
OUTPUT_DIR="."

echo "Building..."
swift build -c release

echo "Creating App Bundle..."
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$OUTPUT_DIR/$APP_NAME.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.user.$APP_NAME</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/> <!-- Hides from Dock, Status Bar App -->
    <key>NSMicrophoneUsageDescription</key>
    <string>Needs microphone access for speech recognition.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Needs to control keyboard for text input.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
</dict>
</plist>
EOF


echo "Signing app..."
codesign --force --deep --sign - "$OUTPUT_DIR/$APP_NAME.app"

echo "Done! App created at $OUTPUT_DIR/$APP_NAME.app"
echo "Please move this to /Applications and grant Accessibility Permissions."
