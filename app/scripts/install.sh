#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Build first
bash scripts/build.sh

# Copy to Applications
echo "Installing to /Applications..."
rm -rf "/Applications/Localhost Mirror.app"
cp -R "build/Localhost Mirror.app" "/Applications/Localhost Mirror.app"

echo "Installed: /Applications/Localhost Mirror.app"
echo "You can now open it from Spotlight or Finder."
