#!/bin/bash
#
# dev.sh - Универсальный скрипт разработки Dictum
#
# Использование:
#   ./scripts/dev.sh         # Build Debug + Run
#   ./scripts/dev.sh --reset # Build Debug + Сброс TCC/onboarding + Run
#   ./scripts/dev.sh -r      # Короткая форма --reset
#

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

APP_NAME="Dictum"
BUNDLE_ID="com.dictum.app"
APP_PATH="$PROJECT_DIR/build/Build/Products/Debug/$APP_NAME.app"

# Парсинг аргументов
RESET=false

for arg in "$@"; do
    case $arg in
        --reset|-r)
            RESET=true
            ;;
        --help|-h)
            echo "Использование: $0 [--reset|-r]"
            echo ""
            echo "  --reset, -r     Сбросить TCC разрешения и onboarding"
            exit 0
            ;;
        *)
            echo "Неизвестный аргумент: $arg"
            echo "Используйте --help для справки"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔄 Dictum Development${NC}"
if [ "$RESET" = true ]; then
    echo -e "${YELLOW}   + Сброс TCC/onboarding${NC}"
fi
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Закрываем приложение
echo -e "${YELLOW}1️⃣  Закрываем приложение...${NC}"
if pgrep -x "$APP_NAME" > /dev/null; then
    killall "$APP_NAME" 2>/dev/null || true
    sleep 1
    if pgrep -x "$APP_NAME" > /dev/null; then
        killall -9 "$APP_NAME" 2>/dev/null || true
        sleep 1
    fi
    echo -e "${GREEN}   ✓ Закрыто${NC}"
else
    echo -e "${GREEN}   ✓ Не запущено${NC}"
fi
echo ""

# 2. Сброс (если --reset)
if [ "$RESET" = true ]; then
    echo -e "${YELLOW}2️⃣  Сброс TCC разрешений и onboarding...${NC}"
    tccutil reset ListenEvent "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null || true
    tccutil reset AppleEvents "$BUNDLE_ID" 2>/dev/null || true
    defaults delete "$BUNDLE_ID" settings.onboardingCompleted 2>/dev/null || true
    defaults delete "$BUNDLE_ID" settings.currentOnboardingStep 2>/dev/null || true
    defaults delete "$BUNDLE_ID" hasAskedForScreenRecording 2>/dev/null || true
    echo -e "${GREEN}   ✓ Сброшено${NC}"
    echo ""
fi

# 3. Сборка
if [ "$RESET" = true ]; then
    STEP="3️⃣"
else
    STEP="2️⃣"
fi

echo -e "${YELLOW}${STEP}  Сборка (Debug)...${NC}"
xcodebuild -project Dictum.xcodeproj \
    -scheme Dictum \
    -configuration Debug \
    -derivedDataPath ./build \
    -destination 'platform=macOS,arch=arm64' \
    -quiet \
    build

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ Сборка не удалась${NC}"
    exit 1
fi
echo -e "${GREEN}   ✓ Собрано${NC}"
echo ""

# 4. Запуск
if [ "$RESET" = true ]; then
    STEP="4️⃣"
else
    STEP="3️⃣"
fi

echo -e "${YELLOW}${STEP}  Запуск...${NC}"
open "$APP_PATH"

sleep 2
if pgrep -x "$APP_NAME" > /dev/null; then
    echo -e "${GREEN}   ✓ Запущено${NC}"
else
    echo -e "${RED}   ⚠ Не запустилось${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Готово!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}📍 $APP_PATH${NC}"
