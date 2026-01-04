#!/bin/bash

# Dictum — сброс всех TCC разрешений и onboarding
#
# ⛔ СИСТЕМА РАЗРЕШЕНИЙ ЗАМОРОЖЕНА (январь 2026)
#
# Dictum использует ТОЛЬКО 3 разрешения:
#   1. Accessibility — для CGEventTap (хоткеи, TextSwitcher, paste)
#   2. Microphone — для записи голоса
#   3. ScreenCapture — для скриншотов
#
# ❌ Input Monitoring (ListenEvent) НЕ ИСПОЛЬЗУЕТСЯ!
#    Причина: Accessibility покрывает CGEventTap .listenOnly
#    НЕ добавлять tccutil reset ListenEvent!
#
# Подробности: см. CLAUDE.md → "Требования и permissions"

BUNDLE_ID="com.dictum.app"

echo "🔄 Сброс разрешений и onboarding для Dictum..."

# Убить все запущенные версии
pkill -9 -f "Dictum" 2>/dev/null || true

# Сбросить TCC разрешения (ТОЛЬКО 3 штуки!)
# ⛔ НЕ добавлять ListenEvent — Input Monitoring не используется!
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null || true

# Сбросить флаг прохождения onboarding
defaults delete "$BUNDLE_ID" settings.onboardingCompleted 2>/dev/null || true
echo "🧹 Onboarding флаг сброшен"

# Сбросить флаг Screen Recording запроса (чтобы приложение появилось в списке)
defaults delete "$BUNDLE_ID" hasAskedForScreenRecording 2>/dev/null || true
echo "🧹 Screen Recording флаг сброшен"

echo "✅ Готово! Разрешения и onboarding сброшены."

# Запустить версию из локального build (Debug или Release)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEBUG_APP="$PROJECT_DIR/build/Build/Products/Debug/Dictum.app"
RELEASE_APP="$PROJECT_DIR/build/Build/Products/Release/Dictum.app"

if [ -d "$DEBUG_APP" ]; then
    echo "🚀 Запуск Debug: $DEBUG_APP"
    open "$DEBUG_APP"
elif [ -d "$RELEASE_APP" ]; then
    echo "🚀 Запуск Release: $RELEASE_APP"
    open "$RELEASE_APP"
else
    echo "⚠️ Приложение не найдено. Собираю Debug..."
    cd "$PROJECT_DIR"
    xcodebuild -project Dictum.xcodeproj -scheme Dictum -configuration Debug -derivedDataPath ./build -destination 'platform=macOS,arch=arm64' -quiet build
    if [ -d "$DEBUG_APP" ]; then
        echo "🚀 Запуск: $DEBUG_APP"
        open "$DEBUG_APP"
    else
        echo "❌ Сборка не удалась"
        exit 1
    fi
fi
