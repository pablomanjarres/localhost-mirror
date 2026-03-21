#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building Localhost Mirror..."
swift build -c release 2>&1

APP_DIR="build/Localhost Mirror.app/Contents"
rm -rf build
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp .build/release/LocalhostMirror "$APP_DIR/MacOS/LocalhostMirror"
cp Info.plist "$APP_DIR/"

# Ad-hoc sign
codesign --force --sign - "build/Localhost Mirror.app"

echo "Built: build/Localhost Mirror.app"
