#!/bin/bash

# Dictum Log Viewer
# Просмотр логов приложения

APP_NAME="Dictum"
SUBSYSTEM="com.dictum.app"

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${GREEN}📋 Dictum Log Viewer${NC}"
echo ""

# Проверяем аргументы
case "${1:-stream}" in
    "stream"|"-s")
        echo -e "${YELLOW}Streaming logs (live)...${NC}"
        echo "Press Ctrl+C to stop"
        echo ""
        log stream --predicate "processImagePath CONTAINS \"$APP_NAME\"" --style compact
        ;;
    "last"|"-l")
        MINUTES="${2:-5}"
        echo -e "${YELLOW}Showing logs from last $MINUTES minutes...${NC}"
        echo ""
        log show --predicate "processImagePath CONTAINS \"$APP_NAME\"" --last "${MINUTES}m" --style compact
        ;;
    "keyboard"|"-k")
        echo -e "${CYAN}Streaming KeyboardEventMonitor logs...${NC}"
        echo "Press Ctrl+C to stop"
        echo ""
        log stream --predicate "subsystem == \"$SUBSYSTEM\" AND category == \"KeyboardEventMonitor\"" --style compact
        ;;
    "textswitcher"|"-t")
        echo -e "${CYAN}Streaming all TextSwitcher logs...${NC}"
        echo "Press Ctrl+C to stop"
        echo ""
        log stream --predicate "subsystem == \"$SUBSYSTEM\"" --style compact
        ;;
    "console"|"-c")
        echo -e "${GREEN}Opening Console.app with Dictum filter...${NC}"
        open -a Console
        echo "Set filter to: processImagePath CONTAINS \"Dictum\""
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command] [options]"
        echo ""
        echo -e "${YELLOW}Commands:${NC}"
        echo "  stream, -s        Live stream ALL logs (default)"
        echo "  last, -l [N]      Show logs from last N minutes (default: 5)"
        echo "  keyboard, -k      Stream KeyboardEventMonitor only"
        echo "  textswitcher, -t  Stream all TextSwitcher logs"
        echo "  console, -c       Open Console.app"
        echo "  help, -h          Show this help"
        echo ""
        echo -e "${YELLOW}Log categories in project:${NC}"
        echo "  📱 App lifecycle   - 🚀 запуск, ✅ инициализация"
        echo "  🔐 Permissions     - Accessibility, Microphone, Screen"
        echo "  🎤 ASR/Dictation   - Deepgram, Parakeet v3"
        echo "  🤖 AI/Gemini       - обработка текста"
        echo "  📸 Screenshots     - скриншоты"
        echo "  ⌨️  TextSwitcher   - переключение раскладки (Logger)"
        echo ""
        echo -e "${YELLOW}Examples:${NC}"
        echo "  $0              # Stream all logs"
        echo "  $0 -l 10        # Last 10 minutes"
        echo "  $0 -k           # Only keyboard events"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use '$0 --help' for usage"
        exit 1
        ;;
esac
