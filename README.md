<p align="center">
  <img src="https://img.icons8.com/fluency/96/microphone.png" alt="Dictum Logo" width="96" height="96">
</p>

<h1 align="center">Dictum</h1>

<p align="center">
  <strong>Умный ввод с ИИ для macOS</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13.0+-blue?style=flat-square&logo=apple" alt="macOS 13.0+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT License">
</p>

<p align="center">
  Нативное macOS приложение для умного ввода текста с голосом и ИИ-обработкой.<br>
  Вызывай хоткеем → диктуй или пиши → ИИ обрабатывает → вставляется в любое приложение.
</p>

---

## Возможности

### ИИ-обработка текста
- **Gemini AI** — обработка текста нейросетью
- **Кастомные промпты** — настраиваемые шаблоны обработки (WB, RU, EN, CH)
- **Улучшение текста** — исправление, перефразирование, перевод
- **Быстрые кнопки** — мгновенная обработка одним кликом

### Голосовой ввод
- **Real-time streaming** — текст появляется мгновенно пока говоришь
- **Deepgram Nova-2** — лучшая модель распознавания речи
- **Поддержка русского и английского** языков
- **Дозапись** — продолжай диктовать, текст добавляется к существующему
- **Визуализация** — amplitude bars реагируют на голос

### Быстрый ввод
- **Глобальный хоткей** — вызов из любого приложения (настраиваемый)
- **Auto-paste** — текст автоматически вставляется туда, откуда вызвана модалка
- **Enter во время записи** — останавливает и сразу вставляет
- **Floating window** — всегда поверх других окон

### Удобство
- **История ввода** — последние 50 записей с поиском
- **Два режима** — Аудио (авто-запись) и Текст (ручной ввод)
- **Menu bar иконка** — быстрый доступ и настройки
- **Автозапуск** — опционально при старте системы
- **Звуковые эффекты** — обратная связь при действиях

---

## Демо

```
┌─────────────────────────────────────────────────────────┐
│  ▁▂▃▅▇▅▃▂▁    Recording...                             │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Привет, это текст который я диктую...                 │
│                                                         │
├─────────────────────────────────────────────────────────┤
│  [WB] [RU] [EN] [CH]    [Текст]      [Отправить ↵]     │
└─────────────────────────────────────────────────────────┘
```

---

## Установка

### Из DMG (рекомендуется)

1. Скачайте `Dictum-1.0.dmg`
2. Перетащите `Dictum.app` в папку `Applications`
3. При первом запуске разрешите:
   - **Accessibility** — для вставки текста в другие приложения
   - **Microphone** — для записи голоса

### Сборка из исходников

```bash
git clone https://github.com/user/dictum.git
cd dictum
./build.sh
open Dictum.app
```

---

## Использование

### Быстрый старт

1. **Cmd+`** (или ваш хоткей) — открыть модалку
2. Начните говорить — запись включится автоматически (в режиме Аудио)
3. **Enter** или повторный хоткей — вставить текст и закрыть

### Горячие клавиши

| Клавиши | Действие |
|---------|----------|
| **Cmd+`** | Открыть/закрыть + вставить (настраиваемый) |
| **Enter** | Остановить запись + вставить + закрыть |
| **Shift+Enter** | Новая строка |
| **Esc** | Закрыть без сохранения |
| **Cmd+,** | Настройки |

### Режимы работы

| Режим | Описание |
|-------|----------|
| **Аудио** | Запись включается автоматически при открытии |
| **Текст** | Ручной ввод текста, запись по кнопке |

Переключение — кнопка в нижней панели.

### Дозапись

Если в поле уже есть текст и вы начинаете новую запись — новый текст **добавится** к существующему через пробел.

---

## Настройки

### API Key (Deepgram)

1. Зарегистрируйтесь на [deepgram.com](https://deepgram.com)
2. Создайте API Key в консоли
3. Вставьте в Настройки → AI → API Key

### Хоткеи

Настройки → Хоткеи → кликните на поле и нажмите новую комбинацию.

### Автозапуск

Настройки → Основные → Запускать при входе в систему

---

## Требования

- **macOS 13.0** или новее
- **Apple Silicon** (arm64) или Intel
- **Deepgram API Key** — для голосового ввода (бесплатный tier: 200 часов/мес)
- **Gemini API Key** — для ИИ-обработки текста (опционально)

### Permissions

| Permission | Зачем |
|------------|-------|
| **Accessibility** | Вставка текста в другие приложения (Cmd+V) |
| **Microphone** | Запись голоса |

---

## Технологии

- **Swift + SwiftUI** — нативный UI
- **AVAudioEngine** — real-time захват аудио
- **Deepgram WebSocket** — streaming транскрибация
- **Gemini AI** — обработка текста нейросетью
- **AppleScript + System Events** — надёжная вставка (как Raycast, Alfred)
- **Keychain** — безопасное хранение API ключей

---

## Структура проекта

```
Dictum/
├── Dictum.swift           # Весь код приложения (~3500 строк)
├── Info.plist             # Конфигурация приложения
├── Dictum.entitlements    # Права доступа
├── AppIcon.icns           # Иконка
├── build.sh               # Скрипт сборки
├── dictum_reload.sh       # Перезапуск с очисткой permissions
├── create_dmg.sh          # Создание DMG
├── claude.md              # Документация для разработки
├── sound/                 # Звуковые эффекты
│   ├── start.wav
│   ├── stop.wav
│   ├── copy.wav
│   └── close.wav
└── README.md
```

---

## Для разработчиков и AI ассистентов

### Технический стек

**Это нативное macOS приложение на Swift 5.9+ с использованием современных технологий:**

- **Язык**: Swift 5.9+
- **UI Framework**: SwiftUI (100% нативный SwiftUI, без UIKit/AppKit кроме NSViewRepresentable)
- **Архитектура**: MVVM с ObservableObject
- **Минимальная версия**: macOS 13.0 (Ventura)
- **Целевая платформа**: macOS (arm64 + x86_64)

### Архитектура приложения

**Монолитный файл** (`Dictum.swift`, ~3500 строк) с четкой модульной структурой:

#### Основные компоненты:

1. **Managers (ObservableObject):**
   - `SettingsManager` - управление настройками (UserDefaults)
   - `AudioRecordingManager` - real-time аудио запись + WebSocket транскрипция
   - `BillingManager` - Management API для биллинга Deepgram
   - `HistoryManager` - хранение и поиск истории заметок
   - `KeychainManager` - безопасное хранение API ключей
   - `SoundManager` - воспроизведение звуковых эффектов

2. **Services:**
   - `DeepgramService` - REST API для одноразовой транскрипции аудиофайлов
   - `DeepgramManagementService` - Management API v1 (проекты, балансы, usage)

3. **SwiftUI Views:**
   - `InputModalView` - главное модальное окно (floating window)
   - `HistoryListView` - список истории с поиском
   - `SettingsPanelView` - настройки с табами (General, Hotkeys, Deepgram, AI)
   - `VoiceOverlayView` - amplitude визуализация
   - `CustomTextEditor` - NSViewRepresentable обертка для NSTextView

4. **AppDelegate:**
   - Глобальные хоткеи (MASShortcut или Carbon)
   - Menu bar item
   - Event monitoring

### Ключевые технологии

**Audio:**
- `AVAudioEngine` + `AVAudioInputNode` для real-time захвата
- WebSocket streaming к Deepgram API
- PCM Linear16, 16kHz, моно
- Interim results для мгновенной транскрипции

**Deepgram API:**
- WebSocket: `wss://api.deepgram.com/v1/listen`
- REST: `https://api.deepgram.com/v1/listen`
- Management API: `https://api.deepgram.com/v1/projects`
- Модели: Nova 2, Nova 2 General, Base
- Authorization: `Token <API_KEY>`

**UI/UX:**
- SwiftUI для всего интерфейса
- `VisualEffectBackground` - glassmorphism эффекты
- Floating window (NSPanel level: .floating)
- Dark mode only
- Dynamic height с `.fixedSize(vertical: true)`

**Data Storage:**
- `UserDefaults` - настройки и история (JSON)
- Base64 в UserDefaults - API ключи (не настоящий Keychain)
- In-memory - состояния UI

**macOS Integration:**
- Accessibility API - вставка текста через симуляцию Cmd+V
- Global event monitoring - хоткеи
- Launch at Login - LaunchAtLoginManager
- Menu bar app - NSStatusBar

### Важные особенности кода

**1. Все в одном файле:**
- Монолитная структура для простоты
- ~3500 строк с четкими MARK секциями
- Нет модульности - всё в Dictum.swift

**2. SwiftUI patterns:**
- `@Published` свойства для реактивности
- `@StateObject` / `@ObservedObject` для менеджеров
- `@ViewBuilder` для композиции UI
- Async/await для сетевых запросов

**3. WebSocket streaming:**
- URLSession WebSocketTask
- Real-time binary audio streaming (каждые 100ms)
- Обработка interim_results и final transcript
- Utterance detection (2000ms тишины)

**4. NSViewRepresentable:**
- `CustomTextEditor` - обертка NSTextView для многострочного ввода
- `HotkeyRecorderView` - обертка для записи хоткеев

### Скрипты разработки

**dictum_reload.sh** — перезапуск приложения с очисткой системных разрешений:

```bash
# Обычный перезапуск (пересборка только если исходники изменились)
./dictum_reload.sh

# Принудительная пересборка
./dictum_reload.sh --rebuild
./dictum_reload.sh -r
```

Что делает скрипт:
1. Закрывает запущенное приложение
2. Сбрасывает permissions (Accessibility, Microphone, Screen Recording)
3. Пересобирает только если `Dictum.swift` новее бинарника (или флаг `--rebuild`)
4. Запускает приложение

После запуска нужно заново выдать разрешения в System Settings.

### Правила разработки

При работе с этим проектом:

1. **Всегда использовать Swift и SwiftUI** - это macOS приложение, не Python/JS
2. **Редактировать Dictum.swift** - монолитная архитектура
3. **Компилировать через build.sh** - не Xcode project
4. **Тестировать на macOS** - специфичные API (Accessibility, WebSocket, Audio)
5. **Сохранять обратную совместимость** с macOS 13.0+

### API Keys требования

- **Default/Member keys** - только транскрипция (usage:write)
- **Admin/Owner keys** - транскрипция + биллинг + Management API

---

## Troubleshooting

### Вставка не работает

1. Проверьте **System Settings → Privacy & Security → Accessibility**
2. Убедитесь что Dictum в списке и галочка стоит
3. Перезапустите приложение

### Голос не записывается

1. Проверьте **System Settings → Privacy & Security → Microphone**
2. Убедитесь что API Key введён в настройках

### Хоткей не срабатывает

1. Проверьте Accessibility permission
2. Возможно конфликт с другим приложением — смените хоткей

---

## Лицензия

MIT License — используйте свободно.

---

<p align="center">
  Made with ❤️ — AI-powered smart input for macOS
</p>
