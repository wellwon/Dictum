#!/bin/bash
#
# run-debug.sh - Сборка и запуск Debug версии Dictum
#
# Использование: ./scripts/run-debug.sh
#
# Все сборки (Xcode и CLI) используют единый путь: ./build/
# Это гарантирует что permissions работают одинаково.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="Dictum"
BUNDLE_ID="com.dictum.app"
DEBUG_APP="$PROJECT_DIR/build/Build/Products/Debug/$APP_NAME.app"

echo "🔨 Сборка Debug версии..."

# Убить существующие процессы
pkill -9 -f "$APP_NAME.app" 2>/dev/null || true
sleep 0.5

# Сбросить TCC разрешения
echo "🔄 Сброс разрешений..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null || true

# Сбросить флаг прохождения onboarding
defaults delete "$BUNDLE_ID" settings.onboardingCompleted 2>/dev/null || true

# Сбросить флаг Screen Recording запроса (чтобы приложение появилось в списке)
defaults delete "$BUNDLE_ID" hasAskedForScreenRecording 2>/dev/null || true

# Собрать Debug
xcodebuild -project Dictum.xcodeproj \
    -scheme Dictum \
    -configuration Debug \
    -derivedDataPath ./build \
    -destination 'platform=macOS,arch=arm64' \
    -quiet \
    build

if [ ! -d "$DEBUG_APP" ]; then
    echo "❌ Сборка не удалась: $DEBUG_APP не найден"
    exit 1
fi

echo "✅ Сборка завершена"
echo ""
echo "🚀 Запуск: $DEBUG_APP"

open "$DEBUG_APP"

echo ""
echo "⚠️  Если нужны permissions:"
echo "   System Settings → Privacy & Security → Accessibility → Enable Dictum"
