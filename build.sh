#!/bin/bash
# Winamp macOS Build Script

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="Winamp"

ARCH="$(uname -m)"
case "$ARCH" in
    arm64|x86_64) ;;
    *)
        echo "Unsupported macOS architecture: $ARCH" >&2
        exit 1
        ;;
esac
DESTINATION="platform=macOS,arch=${ARCH}"

echo "🎵 Building Winamp macOS..."
echo ""

# Parse arguments
CONFIGURATION="Debug"
RUN_AFTER_BUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            CONFIGURATION="Release"
            shift
            ;;
        --run)
            RUN_AFTER_BUILD=true
            shift
            ;;
        --clean)
            echo "🧹 Cleaning build folder..."
            xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
                       -scheme "${PROJECT_NAME}" \
                       -configuration "${CONFIGURATION}" \
                       -destination "${DESTINATION}" \
                       ONLY_ACTIVE_ARCH=YES \
                       clean
            echo "✅ Clean complete"
            echo ""
            shift
            ;;
        --help)
            echo "Usage: ./build.sh [options]"
            echo ""
            echo "Options:"
            echo "  --release    Build release configuration (default: debug)"
            echo "  --run        Run the app after building"
            echo "  --clean      Clean before building"
            echo "  --help       Show this help message"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run './build.sh --help' for usage information"
            exit 1
            ;;
    esac
done

# Build
echo "🔨 Building ${CONFIGURATION} configuration..."
xcodebuild -project "${PROJECT_DIR}/${PROJECT_NAME}.xcodeproj" \
           -scheme "${PROJECT_NAME}" \
           -configuration "${CONFIGURATION}" \
           -destination "${DESTINATION}" \
           ONLY_ACTIVE_ARCH=YES \
           build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build succeeded!"
    echo ""
    
    # Find the built app
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*/Build/Products/${CONFIGURATION}/${PROJECT_NAME}.app -maxdepth 0 2>/dev/null | head -n 1)
    
    if [ -n "$APP_PATH" ]; then
        echo "📦 Built application: $APP_PATH"
        
        # Run if requested
        if [ "$RUN_AFTER_BUILD" = true ]; then
            echo ""
            echo "🚀 Launching Winamp..."
            open "$APP_PATH"
        fi
    fi
else
    echo ""
    echo "❌ Build failed!"
    exit 1
fi
