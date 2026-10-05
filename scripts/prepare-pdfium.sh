#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test "$(uname -m)" = arm64 || { echo 'This pinned development engine supports Apple Silicon only.'; exit 1; }
version=8076
digest=0d6781fe08906baff3d82c90953e519fbc4eb253fe76431e5ed53b157763b97c
destination=.build/deps/pdfium
if test -f "$destination/.localpdf-$version" && test -s "$destination/lib/libpdfium.dylib"; then exit 0; fi
mkdir -p .build/deps
archive=.build/deps/pdfium-$version-arm64.tgz
if ! test -f "$archive"; then
    curl --fail --location --retry 2 --output "$archive.download" "https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/$version/pdfium-mac-arm64.tgz"
    mv "$archive.download" "$archive"
fi
actual=$(shasum -a 256 "$archive" | cut -d ' ' -f 1)
test "$actual" = "$digest" || { echo 'PDFium checksum mismatch. Dependency was not installed.'; exit 1; }
mkdir -p "$destination"
tar -xzf "$archive" -C "$destination"
install_name_tool -id @rpath/libpdfium.dylib "$destination/lib/libpdfium.dylib"
# Changing the install name invalidates the upstream ad-hoc signature.
codesign --force --sign - "$destination/lib/libpdfium.dylib"
touch "$destination/.localpdf-$version"
echo 'Prepared PDFium 8076 (no V8/XFA), checksum verified.'
