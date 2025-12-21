#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

APP_NAME="Dictum"
BUNDLE_ID="com.dictum.app"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔄 Перезагрузка ${APP_NAME}...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Закрываем старую версию
echo -e "${YELLOW}1️⃣  Закрываем запущенное приложение...${NC}"
if pgrep -x "$APP_NAME" > /dev/null; then
    killall "$APP_NAME" 2>/dev/null
    sleep 1
    if pgrep -x "$APP_NAME" > /dev/null; then
        killall -9 "$APP_NAME" 2>/dev/null
    fi
    echo -e "${GREEN}   ✓ Приложение закрыто${NC}"
else
    echo -e "${GREEN}   ✓ Приложение не было запущено${NC}"
fi
echo ""

# 2. Очищаем разрешения
echo -e "${YELLOW}2️⃣  Очищаем разрешения...${NC}"

# Screen Recording
echo -e "   • Сбрасываем Screen Recording..."
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}     ✓ Screen Recording очищен${NC}"
else
    echo -e "${RED}     ⚠ Не удалось сбросить Screen Recording${NC}"
fi

# Accessibility
echo -e "   • Сбрасываем Accessibility..."
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}     ✓ Accessibility очищен${NC}"
else
    echo -e "${RED}     ⚠ Не удалось сбросить Accessibility${NC}"
fi

# Microphone
echo -e "   • Сбрасываем Microphone..."
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}     ✓ Microphone очищен${NC}"
else
    echo -e "${RED}     ⚠ Не удалось сбросить Microphone${NC}"
fi

echo ""

# 3. Пересобираем приложение (только если нужно)
NEED_REBUILD=false
BINARY="Dictum.app/Contents/MacOS/Dictum"

if [[ "$1" == "--rebuild" ]] || [[ "$1" == "-r" ]]; then
    NEED_REBUILD=true
    echo -e "${YELLOW}3️⃣  Пересобираем приложение (--rebuild)...${NC}"
elif [ ! -f "$BINARY" ]; then
    NEED_REBUILD=true
    echo -e "${YELLOW}3️⃣  Пересобираем приложение (бинарник не найден)...${NC}"
elif [ "Dictum.swift" -nt "$BINARY" ]; then
    NEED_REBUILD=true
    echo -e "${YELLOW}3️⃣  Пересобираем приложение (исходники изменились)...${NC}"
fi

if [ "$NEED_REBUILD" = true ]; then
    ./build.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Ошибка сборки!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}3️⃣  Пересборка не требуется${NC}"
    echo -e "${GREEN}   ✓ Бинарник актуален${NC}"
fi
echo ""

# 4. Запускаем новую версию
echo -e "${YELLOW}4️⃣  Запускаем новую версию...${NC}"
sleep 1
open "${APP_NAME}.app"

# Проверяем что запустилось
sleep 2
if pgrep -x "$APP_NAME" > /dev/null; then
    echo -e "${GREEN}   ✓ Приложение запущено${NC}"
else
    echo -e "${RED}   ⚠ Приложение не запустилось${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Готово!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}💡 Важно:${NC}"
echo -e "   • Заново предоставьте разрешения в Системных настройках"
echo -e "   • Accessibility: Настройки → Конфиденциальность → Универсальный доступ"
echo -e "   • Screen Recording: Настройки → Конфиденциальность → Запись экрана"
echo -e "   • Microphone: Настройки → Конфиденциальность → Микрофон"
echo ""
