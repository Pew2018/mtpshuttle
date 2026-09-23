#!/bin/bash
set -euo pipefail

cd "`git rev-parse --show-toplevel`/native/OpenMTPNative"

rm -rf dist
mkdir -p dist/SwiftMTP.app/Contents/MacOS
mkdir -p dist/SwiftMTP.app/Contents/Resources/Kalam/standard
mkdir -p dist/SwiftMTP.app/Contents/Resources/Kalam/seg5

test "`uname -m`" = "arm64"

swift build -c release
BIN="`swift build -c release --show-bin-path`/SwiftMTP"
test -x "`swift build -c release --show-bin-path`/SwiftMTP"

cp "`swift build -c release --show-bin-path`/SwiftMTP" dist/SwiftMTP.app/Contents/MacOS/SwiftMTP
cp Info.plist dist/SwiftMTP.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${GITHUB_RUN_NUMBER:-1}" dist/SwiftMTP.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Add :SwiftMTPGitCommit string $(git rev-parse HEAD)" dist/SwiftMTP.app/Contents/Info.plist

cp ../../build/mac/bin/arm64/kalam.dylib dist/SwiftMTP.app/Contents/Resources/Kalam/standard/kalam.dylib
cp ../../build/mac/bin/arm64/libusb.dylib dist/SwiftMTP.app/Contents/Resources/Kalam/standard/libusb.dylib

if [[ -f ../../build/mac/bin/arm64/kalam-seg5.dylib ]]; then
  cp ../../build/mac/bin/arm64/kalam-seg5.dylib dist/SwiftMTP.app/Contents/Resources/Kalam/seg5/kalam-seg5.dylib
fi
if [[ -f ../../build/mac/bin/arm64/libusb-seg5.dylib ]]; then
  cp ../../build/mac/bin/arm64/libusb-seg5.dylib dist/SwiftMTP.app/Contents/Resources/Kalam/seg5/libusb-seg5.dylib
fi

find dist/SwiftMTP.app/Contents/Resources/Kalam -name "*.dylib" -print0 |
  while IFS= read -r -d '' dylib; do
    codesign --force --sign - "${dylib}"
  done

codesign --force --deep --sign - dist/SwiftMTP.app
file dist/SwiftMTP.app/Contents/MacOS/SwiftMTP
# Keep executable permissions inside the Actions artifact.
ditto -c -k --sequesterRsrc --keepParent dist/SwiftMTP.app dist/SwiftMTP-arm64.zip
