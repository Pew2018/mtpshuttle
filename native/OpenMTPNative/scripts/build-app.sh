#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/OpenMTP.app"
BIN_NAME="OpenMTPNative"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "Swift version:"
swift --version

ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  echo "Expected an arm64 runner, got: $ARCH"
  exit 1
fi

echo "Building SwiftUI app for arm64..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/$BIN_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Built executable not found: $BIN_PATH"
  exit 1
fi

echo "Built binary:"
file "$BIN_PATH"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Ad-hoc signing makes the local test artifact easier to launch without a Developer ID.
codesign --force --deep --sign - "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent   "$APP_DIR"   "$DIST_DIR/OpenMTPNative-arm64.zip"

echo "Created:"
ls -lh "$DIST_DIR/OpenMTPNative-arm64.zip"
