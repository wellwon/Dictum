# Dictum - AI-powered Smart Input for macOS

## О проекте

Dictum — умный ввод текста с ИИ для macOS. Floating panel вызывается глобальным хоткеем, позволяет быстро надиктовать или напечатать текст, обработать его с помощью ИИ (Gemini) и вставить в любое приложение.

**Ключевые возможности:**
- Голосовой ввод с real-time транскрибацией (Deepgram)
- ИИ-обработка текста (Gemini) с кастомными промптами
- Быстрые кнопки WB/RU/EN/CH для разных стилей обработки
- Auto-paste в любое приложение

**Аналоги и референсы:** SuperWhisper, Raycast, Alfred, Rocket Typist

---

## Технологический стек

### Основной
- **Swift + SwiftUI** — нативное macOS приложение
- **AVAudioEngine** — захват аудио в реальном времени (не AVAudioRecorder!)
- **Deepgram WebSocket API** — streaming speech-to-text (Nova-3 модель, 54% точнее Whisper)
- **Carbon API** — глобальные хоткеи (EventHotKey)
- **Keychain API** — безопасное хранение API ключей

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
- `Dictum.swift` — единственный файл с кодом (~2700 строк)
- `build.sh` — скрипт сборки
- `Info.plist` — конфигурация приложения
- `Dictum.entitlements` — права приложения (sandbox ОТКЛЮЧЁН)

### Ключевые классы

| Класс | Назначение |
|-------|------------|
| `AudioRecordingManager` | WebSocket streaming к Deepgram, захват аудио |
| `SettingsManager` | Настройки приложения (UserDefaults) |
| `HistoryManager` | История заметок (SQLite) |
| `SoundManager` | Звуки UI |
| `AccessibilityHelper` | Проверка/запрос Accessibility permission |
| `AppDelegate` | Управление окнами, хоткеями, paste |

### Ключевые View

| View | Назначение |
|------|------------|
| `InputModalView` | Главное окно ввода |
| `VoiceOverlayView` | Визуализация записи (amplitude bars) |
| `HistoryListView` | Список истории |
| `SettingsPanelView` | Окно настроек с табами |
| `CustomTextEditor` | NSViewRepresentable для обработки Enter |

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

---

## Требования и permissions

### Info.plist
```xml
<key>NSAppleEventsUsageDescription</key>
<string>Для вставки текста в другие приложения</string>
<key>NSMicrophoneUsageDescription</key>
<string>Для записи голосовых заметок</string>
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

---

## Принципы разработки

### Дизайн-система

**ВАЖНО:** При изменении любых элементов дизайна приложения (цвета, отступы, шрифты, радиусы) — сначала проверить `DESIGN_SYSTEM.md` для использования единых стилей.

- **Не использовать `.green`** — только `DesignSystem.Colors.accent` (#1AAF87)
- **Не хардкодить цвета** — всегда через `DesignSystem.Colors`
- **Единый зеленый** — `#1AAF87` для всех зеленых элементов (тумблеры, индикаторы, статусы)

```swift
// Правильно
.foregroundColor(DesignSystem.Colors.accent)
.toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.toggleActive))

// Неправильно
.foregroundColor(.green)
.toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.4, blue: 0.2)))
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
| Speech-to-text | WebSocket streaming (Deepgram) | REST API (задержка) |
| Глобальные хоткеи | Carbon EventHotKey | NSEvent monitors only |
| Хранение API ключей | Keychain | UserDefaults (небезопасно) |

### Низкая задержка — приоритет

- Буфер аудио: 1600 samples (~100ms), не 4096
- Pre-buffering пока WebSocket подключается
- `audioEngine.prepare()` ДО старта записи

---

## Сборка и тестирование

```bash
# Сборка
./build.sh

# Запуск
open Dictum.app

# Логи
# Console.app → фильтр "Dictum"
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

---

## API Keys

- **Deepgram API Key** — хранится в Keychain (com.dictum.app / deepgram-api-key)
- Вводится в настройках приложения

---

## Контакты и ресурсы

- Deepgram Docs: https://developers.deepgram.com/docs
- Raycast API: https://developers.raycast.com
- macOS Accessibility: https://developer.apple.com/documentation/accessibility
