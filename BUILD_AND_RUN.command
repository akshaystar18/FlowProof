#!/bin/bash
# Double-click this file in Finder to build and launch FlowProof
# macOS will ask to open with Terminal — click OK

# Move to the script's directory
cd "$(dirname "$0")"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║      FlowProof — Build & Launch      ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── Check for Swift ──────────────────────────────────────────────────────────
if ! command -v swift &>/dev/null; then
    echo "❌  Swift not found."
    echo ""
    echo "    Please install Xcode from the App Store:"
    echo "    https://apps.apple.com/app/xcode/id497799835"
    echo ""
    echo "    Or install Command Line Tools:"
    echo "    xcode-select --install"
    echo ""
    read -p "Press Enter to exit..."
    exit 1
fi

SWIFT_VER=$(swift --version 2>&1 | head -1)
echo "✅  $SWIFT_VER"
echo ""

# ── Resolve dependencies ─────────────────────────────────────────────────────
echo "📦  Resolving dependencies (Yams, GRDB)..."
if ! swift package resolve 2>&1; then
    echo ""
    echo "❌  Dependency resolution failed."
    echo "    Make sure you have an internet connection."
    read -p "Press Enter to exit..."
    exit 1
fi
echo "✅  Dependencies resolved."
echo ""

# ── Build ────────────────────────────────────────────────────────────────────
echo "🔨  Building FlowProof (release)..."
echo "    (This may take 2–5 minutes on first build)"
echo ""

if ! swift build -c release 2>&1; then
    echo ""
    echo "❌  Build failed. See errors above."
    read -p "Press Enter to exit..."
    exit 1
fi

echo ""
echo "✅  Build complete!"
echo ""

# ── Create .app bundle ───────────────────────────────────────────────────────
echo "📱  Packaging FlowProof.app..."

APP="$HOME/Desktop/FlowProof.app"
BIN_PATH=$(swift build -c release --show-bin-path 2>/dev/null)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_PATH/FlowProof" "$APP/Contents/MacOS/FlowProof"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FlowProof</string>
    <key>CFBundleDisplayName</key><string>FlowProof</string>
    <key>CFBundleIdentifier</key><string>com.flowproof.app</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>FlowProof</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>YAML Workflow</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>yaml</string><string>yml</string></array>
            <key>CFBundleTypeRole</key><string>Editor</string>
        </dict>
    </array>
    <key>NSAccessibilityUsageDescription</key>
    <string>FlowProof needs Accessibility access to automate UI workflows.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>FlowProof needs Screen Recording to capture screenshots during workflow runs.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "✅  FlowProof.app created on Desktop."
echo ""

# ── Also copy to /Applications ───────────────────────────────────────────────
echo "📂  Installing to /Applications..."
cp -R "$APP" /Applications/FlowProof.app 2>/dev/null && echo "✅  Installed to /Applications/FlowProof.app" || echo "⚠️   Could not copy to /Applications (try manually)"
echo ""

# ── Grant Accessibility (prompt) ─────────────────────────────────────────────
echo "🔐  Opening Accessibility settings (grant permission when prompted)..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null || true
sleep 1

# ── Launch ───────────────────────────────────────────────────────────────────
echo "🚀  Launching FlowProof..."
open "$APP"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║   FlowProof is running! Enjoy 🎉     ║"
echo "╚══════════════════════════════════════╝"
echo ""
echo "  If the app quits immediately, go to:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  and enable FlowProof, then relaunch."
echo ""
