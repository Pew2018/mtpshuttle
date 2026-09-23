#!/bin/bash
set -euo pipefail

cd "`git rev-parse --show-toplevel`/native/OpenMTPNative"

rm -rf dist
APP=""$APP""
mkdir -p "$APP"/Contents/MacOS
mkdir -p "$APP"/Contents/Resources/Kalam/standard
mkdir -p "$APP"/Contents/Resources/Kalam/seg5

test "`uname -m`" = "arm64"

BIN_DIR="`swift build -c release --show-bin-path`"
swift build -c release
BIN="$BIN_DIR/SwiftMTP"
test -x "$BIN"

cp "$BIN" "$APP"/Contents/MacOS/SwiftMTP
cp Info.plist "$APP"/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" "$APP"/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :SwiftMTPGitCommit string $(git rev-parse HEAD)" "$APP"/Contents/Info.plist

cp ../../build/mac/bin/arm64/kalam.dylib "$APP"/Contents/Resources/Kalam/standard/kalam.dylib
cp ../../build/mac/bin/arm64/libusb.dylib "$APP"/Contents/Resources/Kalam/standard/libusb.dylib

if [[ -f ../../build/mac/bin/arm64/kalam-seg5.dylib ]]; then
  cp ../../build/mac/bin/arm64/kalam-seg5.dylib "$APP"/Contents/Resources/Kalam/seg5/kalam-seg5.dylib
fi
if [[ -f ../../build/mac/bin/arm64/libusb-seg5.dylib ]]; then
  cp ../../build/mac/bin/arm64/libusb-seg5.dylib "$APP"/Contents/Resources/Kalam/seg5/libusb-seg5.dylib
fi

find "$APP"/Contents/Resources/Kalam -name "*.dylib" -print0 |
  while IFS= read -r -d '' dylib; do
    codesign --force --sign - "${dylib}"
  done

codesign --force --deep --sign - "$APP"
file "$APP"/Contents/MacOS/SwiftMTP
