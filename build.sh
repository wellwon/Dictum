#!/bin/bash

set -e

APP_NAME="Olamba"
BUNDLE_ID="com.olamba.app"
VERSION="1.0"

echo "🔨 Сборка $APP_NAME.app..."
echo ""

# Очищаем предыдущую сборку
rm -rf "$APP_NAME.app"
rm -f "$APP_NAME"

# Создаём структуру .app bundle
echo "📁 Создаём структуру приложения..."
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

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

# Создаём PkgInfo
echo "APPL????" > "$APP_NAME.app/Contents/PkgInfo"

# Компилируем Swift
echo "⚙️  Компилируем Swift код..."
swiftc -o "$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    -framework Carbon \
    -framework AVFoundation \
    -target arm64-apple-macosx13.0 \
    -O \
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
