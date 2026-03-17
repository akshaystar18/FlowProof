#!/bin/bash
set -e

echo "================================"
echo "  FlowProof - macOS Build Script"
echo "================================"
echo ""

# Check for Xcode/Swift
if ! command -v swift &> /dev/null; then
    echo "ERROR: Swift toolchain not found."
    echo "Please install Xcode from the App Store or run:"
    echo "  xcode-select --install"
    exit 1
fi

echo "Swift version: $(swift --version 2>&1 | head -1)"
echo ""

# Step 1: Resolve dependencies
echo "[1/3] Resolving dependencies..."
swift package resolve
echo "  Done."
echo ""

# Step 2: Build
echo "[2/3] Building FlowProof..."
swift build -c release 2>&1 | tail -5
echo "  Build complete."
echo ""

# Step 3: Create .app bundle
echo "[3/3] Creating FlowProof.app bundle..."

APP_DIR="$(pwd)/FlowProof.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy the built binary
BUILD_DIR=$(swift build -c release --show-bin-path)
cp "$BUILD_DIR/FlowProof" "$MACOS_DIR/FlowProof"

# Create Info.plist for the .app bundle
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>FlowProof</string>
    <key>CFBundleDisplayName</key>
    <string>FlowProof</string>
    <key>CFBundleIdentifier</key>
    <string>com.flowproof.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>FlowProof</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>YAML Workflow</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>yaml</string>
                <string>yml</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
        </dict>
    </array>
    <key>NSAccessibilityUsageDescription</key>
    <string>FlowProof needs accessibility access to automate UI workflows in other applications.</string>
</dict>
</plist>
PLIST

# Create entitlements
cat > "$CONTENTS_DIR/entitlements.plist" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.accessibility</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS

# Sign the app (ad-hoc)
codesign --force --sign - "$APP_DIR"

echo ""
echo "================================"
echo "  Build Successful!"
echo "================================"
echo ""
echo "  App location: $APP_DIR"
echo ""
echo "  To run:"
echo "    open $APP_DIR"
echo ""
echo "  Or move to Applications:"
echo "    cp -R $APP_DIR /Applications/"
echo "    open /Applications/FlowProof.app"
echo ""
echo "  IMPORTANT: On first launch, you'll need to:"
echo "  1. Grant Accessibility permission in System Settings"
echo "     (Settings > Privacy & Security > Accessibility)"
echo "  2. Grant Screen Recording permission if prompted"
echo ""
