#!/bin/bash
set -euo pipefail

cd "`git rev-parse --show-toplevel`/native/OpenMTPNative"

rm -rf dist
mkdir -p dist/OpenMTP.app/Contents/MacOS
mkdir -p dist/OpenMTP.app/Contents/Resources/Kalam/standard
mkdir -p dist/OpenMTP.app/Contents/Resources/Kalam/seg5

test "`uname -m`" = "arm64"

swift build -c release
BIN="`swift build -c release --show-bin-path`/OpenMTPNative"
test -x "`swift build -c release --show-bin-path`/OpenMTPNative"

cp "`swift build -c release --show-bin-path`/OpenMTPNative" dist/OpenMTP.app/Contents/MacOS/OpenMTPNative
cp Info.plist dist/OpenMTP.app/Contents/Info.plist

cp ../../build/mac/bin/arm64/kalam.dylib dist/OpenMTP.app/Contents/Resources/Kalam/standard/kalam.dylib
cp ../../build/mac/bin/arm64/libusb.dylib dist/OpenMTP.app/Contents/Resources/Kalam/standard/libusb.dylib

if [[ -f ../../build/mac/bin/arm64/kalam-seg5.dylib ]]; then
  cp ../../build/mac/bin/arm64/kalam-seg5.dylib dist/OpenMTP.app/Contents/Resources/Kalam/seg5/kalam-seg5.dylib
fi
if [[ -f ../../build/mac/bin/arm64/libusb-seg5.dylib ]]; then
  cp ../../build/mac/bin/arm64/libusb-seg5.dylib dist/OpenMTP.app/Contents/Resources/Kalam/seg5/libusb-seg5.dylib
fi

find dist/OpenMTP.app/Contents/Resources/Kalam -name "*.dylib" -print0 |
  while IFS= read -r -d '' dylib; do
    codesign --force --sign - "${dylib}"
  done

codesign --force --deep --sign - dist/OpenMTP.app
file dist/OpenMTP.app/Contents/MacOS/OpenMTPNative
