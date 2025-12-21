#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

APP_NAME="Dictum"
BUNDLE_ID="com.dictum.app"
VERSION="1.9"

# Пути к sherpa-onnx
SHERPA_ONNX_DIR="/Users/macbookpro/PycharmProjects/sherpa-onnx"
SHERPA_BUILD_DIR="$SHERPA_ONNX_DIR/build-swift-macos"
SHERPA_LIB="$SHERPA_BUILD_DIR/install/lib/libsherpa-onnx-all.a"
SHERPA_INCLUDE="$SHERPA_BUILD_DIR/install/include"

# Путь к модели T-ONE
MODEL_DIR="models/sherpa-onnx-streaming-t-one-russian-2025-09-08"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔨 Чистая пересборка $APP_NAME v$VERSION${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ============================================================
# ФАЗА 0: PRE-BUILD CLEANUP
# ============================================================
echo -e "${YELLOW}📦 Фаза 0: Подготовка к сборке${NC}"
echo ""

# 0.1 Закрываем работающее приложение
echo -e "   → Закрываем запущенное приложение..."
if pgrep -x "$APP_NAME" > /dev/null; then
    killall "$APP_NAME" 2>/dev/null
    sleep 1

    # Проверяем, закрылось ли
    if pgrep -x "$APP_NAME" > /dev/null; then
        echo -e "${YELLOW}      ⚠ Приложение не отвечает, принудительное завершение...${NC}"
        killall -9 "$APP_NAME" 2>/dev/null
        sleep 1
    fi

    echo -e "${GREEN}      ✓ Приложение закрыто${NC}"
else
    echo -e "${GREEN}      ✓ Приложение не было запущено${NC}"
fi

# 0.2 Очищаем TCC permissions
echo -e "   → Очищаем разрешения системы (TCC)..."

# Screen Recording
tccutil reset ScreenCapture "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}      ✓ Screen Recording очищен${NC}"
fi

# Accessibility
tccutil reset Accessibility "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}      ✓ Accessibility очищен${NC}"
fi

# Microphone
tccutil reset Microphone "$BUNDLE_ID" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}      ✓ Microphone очищен${NC}"
fi

# 0.3 Очищаем предыдущую сборку
echo -e "   → Удаляем предыдущую сборку..."
rm -rf "$APP_NAME.app"
rm -f "$APP_NAME"
echo -e "${GREEN}      ✓ Старая сборка удалена${NC}"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Проверяем наличие sherpa-onnx библиотеки
if [ ! -f "$SHERPA_LIB" ]; then
    echo "❌ Не найдена библиотека sherpa-onnx: $SHERPA_LIB"
    echo "   Запустите сборку sherpa-onnx:"
    echo "   cd $SHERPA_ONNX_DIR && ./build-swift-macos.sh"
    exit 1
fi

# Проверяем наличие модели
if [ ! -d "$MODEL_DIR" ]; then
    echo "❌ Не найдена модель T-ONE: $MODEL_DIR"
    echo "   Скачайте модель:"
    echo "   wget https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-streaming-t-one-russian-2025-09-08.tar.bz2"
    echo "   tar xvf sherpa-onnx-streaming-t-one-russian-2025-09-08.tar.bz2 -C models/"
    exit 1
fi

# Создаём структуру .app bundle
echo "📁 Создаём структуру приложения..."
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"
mkdir -p "$APP_NAME.app/Contents/Resources/models"

# Генерируем иконку если нет
if [ ! -f "AppIcon.icns" ]; then
    echo "🎨 Генерируем иконку..."
    swift generate_icon.swift
fi

# Копируем ресурсы
cp Info.plist "$APP_NAME.app/Contents/"
cp AppIcon.icns "$APP_NAME.app/Contents/Resources/"

# Копируем звуки
if [ -d "sound" ]; then
    echo "🔊 Копируем звуковые файлы..."
    cp sound/*.wav "$APP_NAME.app/Contents/Resources/" 2>/dev/null || true
fi

# Копируем модель T-ONE для локального ASR
echo "🧠 Копируем модель T-ONE для локального распознавания речи..."
cp -r "$MODEL_DIR" "$APP_NAME.app/Contents/Resources/models/"

# Создаём PkgInfo
echo "APPL????" > "$APP_NAME.app/Contents/PkgInfo"

# Компилируем Swift с sherpa-onnx
echo "⚙️  Компилируем Swift код с sherpa-onnx..."
swiftc -o "$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework Carbon \
    -framework AVFoundation \
    -framework Security \
    -framework Accelerate \
    -framework CoreML \
    -target arm64-apple-macosx13.0 \
    -O \
    -import-objc-header SherpaOnnx-Bridging-Header.h \
    -I "$SHERPA_INCLUDE" \
    "$SHERPA_LIB" \
    -Xlinker -lc++ \
    SherpaOnnx.swift \
    Dictum.swift

if [ $? -ne 0 ]; then
    echo "❌ Ошибка компиляции"
    exit 1
fi

echo "✅ Компиляция успешна!"

# Подписываем приложение
echo "🔐 Подписываем приложение..."
codesign --force --sign - \
    --entitlements Dictum.entitlements \
    --deep \
    "$APP_NAME.app"

if [ $? -ne 0 ]; then
    echo "❌ Ошибка подписи"
    exit 1
fi

echo "✅ Подпись успешна!"
echo ""

# ============================================================
# ФАЗА 3: POST-BUILD SUMMARY
# ============================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Сборка завершена успешно!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Показываем размер
APP_SIZE=$(du -sh "$APP_NAME.app" | cut -f1)
echo -e "${BLUE}📦 Размер приложения: $APP_SIZE${NC}"
echo ""

# Опции запуска
echo -e "${YELLOW}🚀 Что дальше?${NC}"
echo ""
echo -e "   ${GREEN}1.${NC} Запустить из текущей папки:"
echo -e "      ${BLUE}open $APP_NAME.app${NC}"
echo ""
echo -e "   ${GREEN}2.${NC} Установить в /Applications (рекомендуется):"
echo -e "      ${BLUE}cp -r $APP_NAME.app /Applications/${NC}"
echo -e "      ${BLUE}open /Applications/$APP_NAME.app${NC}"
echo ""
echo -e "${RED}⚠️  ВАЖНО: Требуются разрешения системы${NC}"
echo ""
echo -e "   После запуска предоставьте разрешения в Системных настройках:"
echo -e "   • ${YELLOW}Универсальный доступ${NC} (Accessibility) — для вставки текста"
echo -e "   • ${YELLOW}Микрофон${NC} (Microphone) — для записи голоса"
echo -e "   • ${YELLOW}Запись экрана${NC} (Screen Recording) — для скриншотов"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
