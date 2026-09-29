#!/usr/bin/env bash
# Generate the Xcode project, run OysterKit tests, and build the Oyster app + widget.
set -euo pipefail

cd "$(dirname "$0")/.."

SIMULATOR_ID="${SIMULATOR_ID:-32F771ED-67A4-4961-AE8A-3EEC2C83C617}"
DESTINATION="platform=iOS Simulator,id=${SIMULATOR_ID}"
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData}"

command -v xcodegen >/dev/null || { echo "xcodegen not found: brew install xcodegen" >&2; exit 1; }

echo "==> xcodegen generate"
xcodegen generate --quiet

echo "==> OysterKit tests"
xcodebuild test \
  -project Oyster.xcodeproj \
  -scheme OysterKit \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

echo "==> Build Oyster (app + widget)"
xcodebuild build \
  -project Oyster.xcodeproj \
  -scheme Oyster \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO

echo "==> All green"
