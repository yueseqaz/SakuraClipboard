#!/bin/bash
set -e

APP_NAME="SakuraClipboard"
BUILD_DIR="build"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"
VOL_NAME="$APP_NAME Installer"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_PNG="$BUILD_DIR/AppIcon-1024.png"
ICON_ICNS="$BUILD_DIR/AppIcon.icns"

generate_icon() {
  mkdir -p "$BUILD_DIR"
  cat > "$BUILD_DIR/gen_icon.swift" <<'SWIFT'
import AppKit

let output = CommandLine.arguments[1]
let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

image.lockFocus()
let bg = NSBezierPath(roundedRect: rect.insetBy(dx: 56, dy: 56), xRadius: 220, yRadius: 220)
NSColor(calibratedRed: 0.20, green: 0.53, blue: 0.98, alpha: 1).setFill()
bg.fill()

let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 128, dy: 128), xRadius: 160, yRadius: 160)
NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.0, alpha: 1).setFill()
inner.fill()

if let symbol = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: nil) {
    let cfg = NSImage.SymbolConfiguration(pointSize: 420, weight: .bold)
    let sym = symbol.withSymbolConfiguration(cfg) ?? symbol
    let symbolRect = NSRect(x: 302, y: 262, width: 420, height: 500)
    NSColor(calibratedRed: 0.20, green: 0.53, blue: 0.98, alpha: 1).set()
    sym.draw(in: symbolRect)
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to generate icon")
}
try png.write(to: URL(fileURLWithPath: output))
SWIFT

  swift "$BUILD_DIR/gen_icon.swift" "$ICON_PNG"

  rm -rf "$ICONSET_DIR" "$ICON_ICNS"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
}

echo "🔨 编译..."
mkdir -p "$BUILD_DIR"
swiftc -O -framework Cocoa -framework ServiceManagement -lsqlite3 Sources/*.swift -o "$BUILD_DIR/$APP_NAME"

echo "📦 打包..."
rm -rf "$APP_BUNDLE"

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
generate_icon
cp "$ICON_ICNS" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>

    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>

    <key>CFBundleIdentifier</key>
    <string>com.sakura.clipboard</string>

    <key>CFBundleIconFile</key>
    <string>AppIcon</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "💿 生成 DMG..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_NAME"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_NAME"

echo "✅ 完成：$APP_BUNDLE"
echo "✅ 完成：$DMG_NAME"
