#!/bin/bash

# Скрипт для инкремента версии приложения
# Использование: ./scripts/bump_version.sh [major|minor|patch]
#
# major: 1.9 -> 2.0, 1.9.1 -> 2.0
# minor: 1.9 -> 1.10, 1.9.1 -> 1.10
# patch: 1.9 -> 1.9.1, 1.9.1 -> 1.9.2

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PLIST_FILE="Info.plist"

# Проверяем наличие Info.plist
if [ ! -f "$PLIST_FILE" ]; then
    echo -e "${RED}Ошибка: $PLIST_FILE не найден${NC}"
    echo "Запустите скрипт из корневой директории проекта"
    exit 1
fi

# Получаем текущую версию
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_FILE")
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_FILE")

echo -e "${BLUE}Текущая версия: $CURRENT_VERSION (build $CURRENT_BUILD)${NC}"
echo ""

# Парсим версию
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
MAJOR="${VERSION_PARTS[0]:-0}"
MINOR="${VERSION_PARTS[1]:-0}"
PATCH="${VERSION_PARTS[2]:-}"

# Определяем тип инкремента
BUMP_TYPE="${1:-patch}"

case "$BUMP_TYPE" in
    major)
        MAJOR=$((MAJOR + 1))
        MINOR=0
        PATCH=""
        ;;
    minor)
        MINOR=$((MINOR + 1))
        PATCH=""
        ;;
    patch)
        if [ -z "$PATCH" ]; then
            PATCH=1
        else
            PATCH=$((PATCH + 1))
        fi
        ;;
    *)
        echo -e "${RED}Неизвестный тип: $BUMP_TYPE${NC}"
        echo "Использование: $0 [major|minor|patch]"
        exit 1
        ;;
esac

# Формируем новую версию
if [ -z "$PATCH" ]; then
    NEW_VERSION="$MAJOR.$MINOR"
else
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
fi

# Вычисляем новый build number (убираем точки и складываем)
NEW_BUILD=$((MAJOR * 100 + MINOR * 10 + ${PATCH:-0}))

echo -e "${YELLOW}Новая версия: $NEW_VERSION (build $NEW_BUILD)${NC}"
echo ""

# Запрашиваем подтверждение
read -p "Применить изменения? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Отменено${NC}"
    exit 0
fi

# Обновляем Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST_FILE"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST_FILE"

echo ""
echo -e "${GREEN}✅ Версия обновлена: $CURRENT_VERSION → $NEW_VERSION${NC}"
echo -e "${GREEN}✅ Build обновлён: $CURRENT_BUILD → $NEW_BUILD${NC}"
echo ""
echo -e "${BLUE}Следующие шаги:${NC}"
echo "  1. git add Info.plist"
echo "  2. git commit -m \"Bump version to $NEW_VERSION\""
echo "  3. git tag v$NEW_VERSION"
echo "  4. git push && git push --tags"
