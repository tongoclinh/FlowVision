#!/bin/bash
# Build FlowVision and optionally run it.
# Uses a separate DerivedData to avoid invalidating Xcode IDE cache.
#
# Usage:
#   ./scripts/build-and-run.sh          # build only
#   ./scripts/build-and-run.sh --run    # build + launch app
#   ./scripts/build-and-run.sh --clean  # clean build

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="/tmp/FlowVision-cli-build"
SCHEME="FlowVision"
CONFIG="Debug"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIG/FlowVisionDbg.app"

RUN=false
CLEAN=false

for arg in "$@"; do
    case "$arg" in
        --run)   RUN=true ;;
        --clean) CLEAN=true ;;
        *)       echo "Unknown option: $arg"; exit 1 ;;
    esac
done

cd "$PROJECT_DIR"

if $CLEAN; then
    echo "Cleaning derived data..."
    rm -rf "$DERIVED_DATA"
fi

echo "Building $SCHEME ($CONFIG)..."
xcodebuild \
    -project FlowVision.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=4EU79BL8K3 \
    build 2>&1 | tail -5

if $RUN; then
    echo "Launching $APP_PATH..."
    open "$APP_PATH"
fi
