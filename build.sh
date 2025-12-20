#!/bin/bash

set -e

APP_NAME="Olamba"
BUNDLE_ID="com.olamba.app"
VERSION="1.8"

# Пути к sherpa-onnx
SHERPA_ONNX_DIR="/Users/macbookpro/PycharmProjects/sherpa-onnx"
SHERPA_BUILD_DIR="$SHERPA_ONNX_DIR/build-swift-macos"
SHERPA_LIB="$SHERPA_BUILD_DIR/install/lib/libsherpa-onnx-all.a"
SHERPA_INCLUDE="$SHERPA_BUILD_DIR/install/include"

# Путь к модели T-ONE
MODEL_DIR="models/sherpa-onnx-streaming-t-one-russian-2025-09-08"

echo "🔨 Сборка $APP_NAME.app с локальным ASR..."
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

# Очищаем предыдущую сборку
rm -rf "$APP_NAME.app"
rm -f "$APP_NAME"

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
    Olamba.swift

if [ $? -ne 0 ]; then
    echo "❌ Ошибка компиляции"
    exit 1
fi

echo "✅ Компиляция успешна!"

# Подписываем приложение
echo "🔐 Подписываем приложение..."
codesign --force --sign - \
    --entitlements Olamba.entitlements \
    --deep \
    "$APP_NAME.app"

if [ $? -ne 0 ]; then
    echo "❌ Ошибка подписи"
    exit 1
fi

echo "✅ Подпись успешна!"
echo ""

# Проверяем размер
APP_SIZE=$(du -sh "$APP_NAME.app" | cut -f1)
echo "📦 Размер приложения: $APP_SIZE"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ $APP_NAME.app создан успешно!"
echo ""
echo "Запуск:"
echo "  open $APP_NAME.app"
echo ""
echo "Установка в /Applications:"
echo "  cp -r $APP_NAME.app /Applications/"
echo ""
echo "Или перетащите $APP_NAME.app в папку Программы"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
