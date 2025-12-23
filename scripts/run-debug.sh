#!/bin/bash
#
# run-debug.sh - Launch Debug version of Dictum from DerivedData
#
# Usage: ./scripts/run-debug.sh
#
# This script finds and launches the Debug build created by Xcode.
# Both Xcode and Claude use the same Debug version, so permissions
# (Accessibility, Microphone, etc.) only need to be granted once.
#

DERIVED_DATA=~/Library/Developer/Xcode/DerivedData

# Find Debug build (exclude Index.noindex which contains non-runnable builds)
APP=$(find "$DERIVED_DATA" -path "*/Dictum-*/Build/Products/Debug/Dictum.app" -not -path "*/Index.noindex/*" -type d 2>/dev/null | head -1)

if [ -z "$APP" ]; then
    echo "❌ Debug build not found in DerivedData"
    echo ""
    echo "Please build the app first:"
    echo "  1. Open Dictum.xcodeproj in Xcode"
    echo "  2. Press ⌘R (Run) or click ▶️"
    echo ""
    echo "Or build via CLI:"
    echo "  xcodebuild -project Dictum.xcodeproj -scheme Dictum -configuration Debug build"
    exit 1
fi

echo "🚀 Launching Debug build:"
echo "   $APP"
echo ""

# Kill existing instances
pkill -9 -f "Dictum.app" 2>/dev/null

# Small delay to ensure clean start
sleep 0.5

# Launch app
open "$APP"

echo "✅ Dictum started"
