#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
bundle='.build/LocalPDF.app'
mkdir -p "$bundle/Contents/MacOS"
mkdir -p "$bundle/Contents/Frameworks" "$bundle/Contents/Resources/pdfium-licenses"
cp .build/deps/pdfium/lib/libpdfium.dylib "$bundle/Contents/Frameworks/libpdfium.dylib.next"
mv "$bundle/Contents/Frameworks/libpdfium.dylib.next" "$bundle/Contents/Frameworks/libpdfium.dylib"
cp docs/pdfium-licenses/* "$bundle/Contents/Resources/pdfium-licenses/"
localpdf_bin_dir=$(swift build --show-bin-path)
cp "$localpdf_bin_dir/LocalPDF" "$bundle/Contents/MacOS/LocalPDF.next"
mv "$bundle/Contents/MacOS/LocalPDF.next" "$bundle/Contents/MacOS/LocalPDF"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalPDF</string>
<key>CFBundleIdentifier</key><string>org.localpdf.dev</string>
<key>CFBundleName</key><string>LocalPDF</string>
<key>CFBundleDisplayName</key><string>LocalPDF</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
plutil -lint "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
