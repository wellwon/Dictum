# Dictum - AI-powered Smart Input for macOS

## О проекте

Dictum — умный ввод текста с ИИ для macOS. Floating panel вызывается глобальным хоткеем, позволяет быстро надиктовать или напечатать текст, обработать его с помощью ИИ (Gemini) и вставить в любое приложение.

**Ключевые возможности:**
- Голосовой ввод с двумя режимами:
  - **Deepgram** — облачный streaming в реальном времени
  - **Parakeet v3** — локальная модель, офлайн, Apple Silicon
- ИИ-обработка текста (Gemini) с кастомными промптами
- Сниппеты — быстрая вставка шаблонов текста
- Скриншоты по хоткею
- Auto-paste в любое приложение

**Аналоги и референсы:** SuperWhisper, Raycast, Alfred, Rocket Typist

---

## Технологический стек

### Основной
- **Swift 6.0 + SwiftUI** — нативное macOS приложение (macOS 14.0+)
- **AVAudioEngine** — захват аудио в реальном времени (не AVAudioRecorder!)
- **Carbon API** — глобальные хоткеи (EventHotKey)
- **Keychain API** — безопасное хранение API ключей

### Speech-to-Text

| Провайдер | Тип | Режим | Языки | Требования |
|-----------|-----|-------|-------|------------|
| **Deepgram** | Облако | Streaming | 54+ | API ключ, интернет |
| **Parakeet v3** | Локально | Batch | 25 европейских | Apple Silicon, ~600 MB |

- **Deepgram WebSocket API** — Nova-3 модель, real-time транскрибация
- **FluidAudio SDK** — NVIDIA Parakeet v3 на CoreML, ~190x real-time на ANE

### Критически важные API

#### Для вставки текста в другие приложения
**ВСЕГДА использовать AppleScript + System Events** (как Raycast, Alfred, SuperWhisper):
```swift
let script = """
tell application "System Events"
    keystroke "v" using command down
end tell
"""
let appleScript = NSAppleScript(source: script)
appleScript?.executeAndReturnError(&error)
```

**Почему НЕ CGEvent:**
- CGEvent заблокирован в App Sandbox
- CGEvent ненадёжен для Electron/WebView приложений
- AppleScript работает через Accessibility API — более универсально

#### Для активации предыдущего приложения
```swift
prevApp.activate(options: .activateIgnoringOtherApps)
```
С задержкой 0.25 сек и проверкой активации.

---

## Архитектура

### Ключевые файлы
- `Dictum.swift` — единственный файл с кодом (~10000 строк)
- `project.yml` — конфигурация проекта для xcodegen
- `Info.plist` — конфигурация приложения
- `Dictum.entitlements` — права приложения (sandbox ОТКЛЮЧЁН)
- `DESIGN_SYSTEM.md` — дизайн-система (цвета, отступы)

### Ключевые классы

| Категория | Класс | Назначение |
|-----------|-------|------------|
| **ASR** | `AudioRecordingManager` | WebSocket streaming к Deepgram |
| | `ParakeetASRProvider` | Локальная ASR (FluidAudio/Parakeet v3) |
| **AI** | `GeminiService` | Обработка текста через Gemini API |
| | `GeminiKeyManager` | Управление API ключом Gemini |
| **Deepgram** | `DeepgramService` | REST API транскрибация |
| | `DeepgramManagementService` | Management API (проекты, балансы) |
| | `BillingManager` | Биллинг и usage статистика |
| **Настройки** | `SettingsManager` | UserDefaults настройки |
| | `PromptsManager` | Кастомные AI промпты |
| | `SnippetsManager` | Текстовые сниппеты |
| **Система** | `HistoryManager` | SQLite история заметок |
| | `SoundManager` | Звуки UI |
| | `VolumeManager` | Управление системной громкостью при записи |
| | `UpdateManager` | Проверка обновлений (Sparkle-like) |
| | `AccessibilityHelper` | Accessibility permissions |
| | `KeychainManager` | Хранение API ключей |
| | `APIKeyManager` | Общее управление API ключами |
| | `LaunchAtLoginManager` | Автозапуск при логине |
| **UI** | `AppDelegate` | Окна, хоткеи, paste, menubar |
| | `FloatingPanel` | NSPanel для модалки |

### Архитектура ASR

```
┌─────────────────────────┐     ┌─────────────────────────┐
│  AudioRecordingManager  │     │  ParakeetASRProvider    │
│  (Deepgram, облако)     │     │  (Parakeet v3, локально)│
├─────────────────────────┤     ├─────────────────────────┤
│ Streaming WebSocket     │     │ Batch CoreML            │
│ Real-time interim       │     │ ~190x real-time         │
│ 54+ языков              │     │ 25 европейских          │
│ Нужен интернет          │     │ Офлайн, Apple Silicon   │
└─────────────────────────┘     └─────────────────────────┘
            │                               │
            └───────────┬───────────────────┘
                        ▼
           ┌────────────────────────┐
           │  ASRProviderType enum  │
           │  .deepgram / .local    │
           └────────────────────────┘
```

### ParakeetModelStatus (состояния модели)

```swift
enum ParakeetModelStatus: Equatable {
    case notChecked      // При запуске
    case checking        // Проверка наличия модели
    case notDownloaded   // Модель не найдена
    case downloading     // Скачивание ~600 MB
    case loading         // Загрузка в память
    case ready           // Готова к работе
    case error(String)   // Ошибка
}
```

### Ключевые View

| View | Назначение |
|------|------------|
| `InputModalView` | Главное окно ввода |
| `VoiceOverlayView` | Визуализация записи (amplitude bars) |
| `HistoryListView` | Список истории с поиском |
| `SettingsView` | Окно настроек с табами |
| `UnifiedQuickAccessRow` | Строка быстрого доступа (промпты + сниппеты) |
| `SlidingPromptPanel` | Боковая панель промптов (слева) |
| `SlidingSnippetPanel` | Боковая панель сниппетов (справа) |
| `CustomTextEditor` | NSViewRepresentable для обработки Enter |
| `HotkeyRecorderView` | Запись горячих клавиш |
| `ParakeetModelStatusView` | Статус локальной модели |

### Ключевые Enums

| Enum | Назначение |
|------|------------|
| `ASRProviderType` | `.deepgram` / `.local` |
| `GeminiModel` | Модели Gemini (Flash, Flash-Lite) |
| `DeepgramModelType` | Модели Deepgram (Nova-2, Base) |
| `SettingsTab` | Табы настроек |
| `ParakeetModelStatus` | Статус локальной модели |

---

## Важные паттерны

### 1. Streaming аудио к Deepgram
```swift
// Маленький буфер для низкой задержки (100ms)
inputNode.installTap(onBus: 0, bufferSize: 1600, format: inputFormat)

// Pre-buffering пока WebSocket подключается
if webSocketConnected {
    webSocket?.send(.data(data))
} else {
    audioBuffer.append(data)  // Буферизуем
}
```

### 2. Сохранение и восстановление фокуса
```swift
// ДО открытия модалки
previousApp = NSWorkspace.shared.frontmostApplication

// ПОСЛЕ закрытия
previousApp?.activate(options: .activateIgnoringOtherApps)
// Задержка + AppleScript paste
```

### 3. VoiceOverlayView не блокирует события
```swift
VoiceOverlayView(audioLevel: audioManager.audioLevel)
    .allowsHitTesting(false)  // КРИТИЧНО! Иначе Enter не работает
    .zIndex(2)
```

### 4. Enter работает во время записи
`submitImmediate()` — останавливает запись, собирает текст, вставляет в одно действие.

### 5. КРИТИЧНО: Приложение живёт в menubar — НЕ закрывать при закрытии окон!

**Dictum — menubar приложение.** Закрытие любого окна (настройки, главное окно) НЕ должно завершать приложение!

```swift
// В AppDelegate ОБЯЗАТЕЛЬНО:
func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false  // КРИТИЧНО! Иначе приложение закроется
}
```

**Правила управления окнами:**
```swift
// 1. ВСЕГДА weak reference в async closures
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
    guard let window = window, window.isVisible else { return }
    // ...
}

// 2. ВСЕГДА убирать delegate перед освобождением окна
func windowWillClose(_ notification: Notification) {
    if closedWindow == settingsWindow {
        settingsWindow?.delegate = nil  // Сначала delegate!
        settingsWindow = nil
    }
}

// 3. isReleasedWhenClosed = false для окон, которыми управляем вручную
sw.isReleasedWhenClosed = false  // Мы сами делаем = nil

// 4. showWindow() должен создавать окно если его нет
@objc func showWindow() {
    if window == nil {
        setupWindow()  // Защита от краша
    }
    guard let window = window else { return }
    // ...
}
```

### 6. Боковые sliding панели
```swift
// Панели выезжают слева/справа от модалки
SlidingPromptPanel(...)
    .offset(x: showLeftPanel ? -panelOffset : -panelOffset - 200)
    .opacity(showLeftPanel ? 1 : 0)
    .animation(.easeInOut(duration: 0.25), value: showLeftPanel)
```

---

## Функциональность

### Промпты (PromptsManager)
- 4 встроенных: WB, RU, EN, CH
- Кастомные промпты с редактированием
- Drag & drop сортировка
- Видимость/скрытие отдельных промптов

### Сниппеты (SnippetsManager)
- Текстовые шаблоны для быстрой вставки
- Редактирование inline
- Добавление через боковую панель

### Скриншоты
- Хоткей Cmd+Shift+D
- Интерактивный выбор области
- Путь к файлу копируется в буфер

### Обновления (UpdateManager)
- Sparkle-like проверка обновлений
- Appcast.xml для версий
- Автопроверка раз в сутки

---

## Требования и permissions

### Info.plist
```xml
<key>NSAppleEventsUsageDescription</key>
<string>Для вставки текста в другие приложения</string>
<key>NSMicrophoneUsageDescription</key>
<string>Для записи голосовых заметок</string>
<key>NSScreenCaptureUsageDescription</key>
<string>Для скриншотов по горячей клавише</string>
```

### Entitlements
```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- ОТКЛЮЧЁН для CGEvent/AppleScript -->
<key>com.apple.security.device.audio-input</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

### System Permissions (нужны вручную)
- **Accessibility** — System Settings → Privacy & Security → Accessibility
- **Microphone** — запрашивается автоматически
- **Screen Recording** — для скриншотов

---

## Принципы разработки

### ⚠️ КРИТИЧЕСКИЕ ПРАВИЛА (не нарушать!)

1. **Приложение НЕ закрывается при закрытии окон** — это menubar app, живёт в трее
2. **Всегда `[weak window]` в async closures** — иначе краш при закрытии окна
3. **`delegate = nil` перед `window = nil`** — избегаем повторных вызовов
4. **`isReleasedWhenClosed = false`** — мы сами управляем lifecycle окон
5. **`showWindow()` создаёт окно если его нет** — защита от nil reference

### 🚫 При ошибках компиляции — ИСПРАВЛЯТЬ КОД, не настройки!

**НИКОГДА не понижать версии при ошибках:**
- ❌ НЕ менять Swift 6.0 → Swift 5.9
- ❌ НЕ менять macOS 14.0 → macOS 13.0
- ❌ НЕ удалять зависимости (FluidAudio и др.)
- ❌ НЕ менять project.yml / Info.plist для "обхода" ошибок

**ВСЕГДА исправлять сам код:**
- ✅ Исправить синтаксис под актуальную версию Swift
- ✅ Добавить недостающие import'ы
- ✅ Исправить deprecated API на современные аналоги
- ✅ Адаптировать код под Swift 6 Concurrency (async/await, Sendable)

```swift
// Пример: ошибка Sendable в Swift 6
// ❌ НЕПРАВИЛЬНО: понизить до Swift 5.9
// ✅ ПРАВИЛЬНО: добавить @unchecked Sendable или исправить архитектуру

// Было (ошибка в Swift 6):
class MyManager: ObservableObject { ... }

// Стало (исправлено):
class MyManager: ObservableObject, @unchecked Sendable { ... }
```

**Причина:** Понижение версий создаёт технический долг и ломает совместимость с зависимостями (FluidAudio требует macOS 14.0+).

### Дизайн-система

**ВАЖНО:** При изменении любых элементов дизайна приложения (цвета, отступы, шрифты, радиусы) — сначала проверить `DESIGN_SYSTEM.md` для использования единых стилей.

- **Не использовать `.green`** — только `DesignSystem.Colors.accent` (#1AAF87)
- **Не хардкодить цвета** — всегда через `DesignSystem.Colors`
- **Единый зеленый** — `#1AAF87` для всех зеленых элементов

```swift
// Правильно
.foregroundColor(DesignSystem.Colors.accent)
.toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.toggleActive))

// Неправильно
.foregroundColor(.green)
```

### ВСЕГДА делать research лучших решений

Перед реализацией любой функции — исследовать как это делают:
- **Raycast** — clipboard, paste, keyboard simulation
- **Alfred** — workflow, hotkeys, AppleScript integration
- **SuperWhisper** — voice recording, streaming transcription
- **Rocket Typist** — text expansion, paste methods
- **Maccy** — clipboard management

### Использовать продвинутый стек

| Задача | Правильный метод | НЕ использовать |
|--------|------------------|-----------------|
| Paste в другое приложение | AppleScript + System Events | CGEvent (ненадёжно) |
| Захват аудио real-time | AVAudioEngine | AVAudioRecorder (медленно) |
| Speech-to-text (облако) | WebSocket streaming (Deepgram) | REST API (задержка) |
| Speech-to-text (локально) | FluidAudio + CoreML (Parakeet) | Whisper.cpp (медленнее) |
| Глобальные хоткеи | Carbon EventHotKey | NSEvent monitors only |
| Хранение API ключей | Keychain | UserDefaults (небезопасно) |

### Низкая задержка — приоритет

- Буфер аудио: 1600 samples (~100ms), не 4096
- Pre-buffering пока WebSocket подключается
- `audioEngine.prepare()` ДО старта записи

---

## Сборка и тестирование

### Требования
- **macOS 14.0+** (Sonoma)
- **Apple Silicon** (M1/M2/M3) — для локальной ASR
- **Xcode 16+**
- **xcodegen** (`brew install xcodegen`)

### Сборка

```bash
# Генерация Xcode проекта из project.yml
xcodegen generate

# Сборка через xcodebuild
xcodebuild -project Dictum.xcodeproj \
    -scheme Dictum \
    -configuration Release \
    -derivedDataPath ./build \
    build

# Копирование .app
cp -r ./build/Build/Products/Release/Dictum.app ./

# Запуск
open Dictum.app

# Логи
# Console.app → фильтр "Dictum"
```

### project.yml (ключевые секции)

```yaml
name: Dictum
options:
  xcodeVersion: "16.2"
  deploymentTarget:
    macOS: "14.0"

packages:
  FluidAudio:
    url: https://github.com/FluidInference/FluidAudio.git
    from: 0.8.0

targets:
  Dictum:
    settings:
      SWIFT_VERSION: "6.0"
    dependencies:
      - package: FluidAudio
        product: FluidAudio
```

---

## Известные проблемы и решения

| Проблема | Причина | Решение |
|----------|---------|---------|
| Paste не работает | Нет Accessibility permission | Добавить в System Settings |
| Paste не работает в Electron | CGEvent игнорируется | Использовать AppleScript |
| Enter не работает при записи | VoiceOverlayView перехватывает события | `.allowsHitTesting(false)` |
| Первые слова теряются | Большой буфер / нет pre-buffering | Буфер 1600 + pre-buffer |
| Дублирование текста | finalTranscript не сбрасывается | Всегда `finalTranscript = ""` в начале |
| Краш при закрытии настроек | Strong capture в async closure | `[weak window]`, `delegate = nil` |
| Приложение закрывается при закрытии окна | `applicationShouldTerminateAfterLastWindowClosed` = true | Вернуть `false` |

---

## API Keys

- **Deepgram API Key** — хранится в Keychain (com.dictum.app / deepgram-api-key)
- **Gemini API Key** — хранится в Keychain (com.dictum.app / gemini-api-key)
- Вводятся в настройках приложения

---

## Локальная модель Parakeet

### Расположение файлов
- **Модель**: `~/Library/Application Support/FluidAudio/Models/parakeet-v3/`
- **Размер**: ~600 MB (скачивается при первом запуске)

### Управление моделью
В настройках приложения есть секция "Локальная модель" с:
- Статусом модели (checking → downloading → ready)
- Кнопкой "Скачать модель" если не установлена
- Кнопкой удаления (trash icon) с подтверждением

### FluidAudio SDK
- **Репозиторий**: https://github.com/FluidInference/FluidAudio
- **Версия**: 0.8.0
- **API**: `AsrModels.downloadAndLoad()`, `AsrManager.transcribe()`

---

## Структура UI модалки

```
┌──────────────────────────────────────────────────────────┐
│  [Поле ввода текста]                          [sparkles] │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  [WB] [RU] [EN] [CH] [+промпты]    [сниппеты+]           │  ← Row 1: Quick Access
├──────────────────────────────────────────────────────────┤
│  [🎤 Запись] | [📋 История]    [📝/🎙️]  [Отправить ↵]  │  ← Row 2: Actions
└──────────────────────────────────────────────────────────┘
     ↑                                        ↑
 Sliding Panel (left)                   Sliding Panel (right)
   [Промпты]                              [Сниппеты]
```

---

## Контакты и ресурсы

- Deepgram Docs: https://developers.deepgram.com/docs
- FluidAudio SDK: https://github.com/FluidInference/FluidAudio
- Gemini API: https://ai.google.dev
- Raycast API: https://developers.raycast.com
- macOS Accessibility: https://developer.apple.com/documentation/accessibility
