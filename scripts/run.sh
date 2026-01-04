#!/bin/bash
#
# run.sh - Быстрый запуск Dictum (БЕЗ сборки)
#
# Использование:
#   ./scripts/run.sh           # Debug (по умолчанию)
#   ./scripts/run.sh --release # Release
#   ./scripts/run.sh -r        # Release
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Определяем конфигурацию
if [[ "$1" == "--release" ]] || [[ "$1" == "-r" ]]; then
    CONFIG="Release"
else
    CONFIG="Debug"
fi

APP_PATH="$PROJECT_DIR/build/Build/Products/$CONFIG/Dictum.app"

# Проверяем, что приложение существует
if [ ! -d "$APP_PATH" ]; then
    echo "❌ Приложение не найдено: $APP_PATH"
    echo "   Сначала соберите: ./scripts/dictum_reload.sh"
    exit 1
fi

# Закрываем старую версию если запущена
if pgrep -x "Dictum" > /dev/null; then
    killall "Dictum" 2>/dev/null || true
    sleep 0.5
fi

# Запускаем
echo "🚀 Запуск: $APP_PATH"
open "$APP_PATH"
