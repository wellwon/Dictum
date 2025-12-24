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
**CGEvent** (как в Maccy, Clipy — популярных clipboard managers):
```swift
let source = CGEventSource(stateID: .combinedSessionState)
source?.setLocalEventsFilterDuringSuppressionState(
    [.permitLocalMouseEvents, .permitSystemDefinedEvents],
    state: .eventSuppressionStateSuppressionInterval
)

let vKeyCode: CGKeyCode = 0x09  // 'v' key
let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
keyVDown?.flags = .maskCommand
keyVUp?.flags = .maskCommand

keyVDown?.post(tap: .cgSessionEventTap)
keyVUp?.post(tap: .cgSessionEventTap)
```

**Почему CGEvent, а не AppleScript:**
- Требует только Accessibility permission (галочка в System Settings)
- НЕ показывает диалог "управление System Events" при первом запуске
- Работает во всех приложениях, включая Electron (проверено в Maccy/Clipy)

#### Для активации предыдущего приложения
```swift
prevApp.activate(options: .activateIgnoringOtherApps)
```
С задержкой 0.25 сек и проверкой активации.

---

## Архитектура

### Файловая структура

Проект разбит на 12 модулей по функциональности:

```
Dictum/
├── DictumApp.swift      # Entry point, AppDelegate, FloatingPanel, меню
├── Core.swift           # DesignSystem, Color+Hex, AppConfig, APIKeyManager
├── Settings.swift       # SettingsManager + весь UI настроек
├── InputModal.swift     # Главное окно ввода с голосом
├── Dictation.swift      # ASR: Deepgram + Parakeet v3
├── AI.swift             # GeminiService для обработки текста
├── Prompts.swift        # Кастомные AI-промпты
├── Snippets.swift       # Текстовые сниппеты
├── History.swift        # История заметок (SQLite)
├── Hotkeys.swift        # HotkeyConfig для Carbon API
├── Updates.swift        # UpdateManager + AppcastParser
└── Components.swift     # Переиспользуемые UI-компоненты
```

### Как найти нужный код

| Задача | Файл |
|--------|------|
| Добавить настройку | `Settings.swift` |
| Изменить UI модалки | `InputModal.swift` |
| Поправить распознавание речи | `Dictation.swift` |
| Добавить AI-функцию | `AI.swift` |
| Новый UI-компонент | `Components.swift` |
| Управление окнами/хоткеями | `DictumApp.swift` |

### Конфигурационные файлы
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

### 7. Скругление рамки окна (NSWindow) — macOS Tahoe 26pt

**ВАЖНО:** Для `.titled` окон скруглять через `superview.layer.cornerRadius`, НЕ через `contentView.layer`!

`contentView.layer` скругляет только контент, а `superview` (_NSThemeFrame) — саму рамку окна.

```swift
// В DictumApp.swift при создании .titled окна:
sw.backgroundColor = .clear
sw.isOpaque = false
sw.contentView = hostingView

// ПОСЛЕ присвоения contentView — скругляем ВНЕШНЮЮ рамку
if let contentView = sw.contentView {
    contentView.superview?.wantsLayer = true
    contentView.superview?.layer?.cornerRadius = 26  // macOS Tahoe
    contentView.superview?.layer?.masksToBounds = true
}
```

**Для `.borderless` окон (InputModal, History):**
```swift
// SwiftUI clipShape работает корректно
.clipShape(RoundedRectangle(cornerRadius: 26))
```

### 8. Контент в области titlebar (fullSizeContentView)

Для окон со стилем `.fullSizeContentView` и прозрачным titlebar, чтобы контент (sidebar, дивайдеры) расширялся в область titlebar:

```swift
// В DictumApp.swift при создании окна:
styleMask: [.titled, .closable, .resizable, .fullSizeContentView]
sw.titlebarAppearsTransparent = true

// В SwiftUI View — применить к КОРНЕВОМУ контейнеру:
HStack(spacing: 0) {
    // sidebar, content...
}
.background(...)
.ignoresSafeArea(.all, edges: .top)  // ВАЖНО: на корневой контейнер!
```

**НЕ применять `.ignoresSafeArea()` к дочерним элементам** — это не работает, т.к. родительский background перекроет.

### 9. Кнопки окна настроек (traffic lights)

Для окна настроек кастомизируются стандартные кнопки окна:

```swift
// 1. Скрыть кнопку minimize
sw.standardWindowButton(.miniaturizeButton)?.isHidden = true

// 2. Переместить zoom на место minimize (убрать пустое место)
if let zoomButton = sw.standardWindowButton(.zoomButton),
   let minimizeButton = sw.standardWindowButton(.miniaturizeButton) {
    zoomButton.setFrameOrigin(minimizeButton.frame.origin)
}

// 3. Сдвинуть close и zoom на 6pt вниз-вправо
let buttonOffset: CGFloat = 6
for buttonType: NSWindow.ButtonType in [.closeButton, .zoomButton] {
    if let button = sw.standardWindowButton(buttonType) {
        button.setFrameOrigin(NSPoint(
            x: button.frame.origin.x + buttonOffset,
            y: button.frame.origin.y - buttonOffset
        ))
    }
}
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

### 🔒 Swift 6 Strict Concurrency — правила

Swift 6 требует явной изоляции потоков. Основные правила:

#### 1. UI-классы требуют `@MainActor`

Любой класс, работающий с AppKit/SwiftUI (окна, панели, делегаты):

```swift
// ✅ ПРАВИЛЬНО
@MainActor
class FloatingPanel: NSPanel { ... }

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate { ... }

@MainActor
class Coordinator: NSObject, NSTextViewDelegate { ... }

// ❌ НЕПРАВИЛЬНО — ошибки "Main actor-isolated property..."
class FloatingPanel: NSPanel { ... }
```

#### 2. UI-функции требуют `@MainActor`

Функции, создающие UI-элементы или работающие с NSSavePanel/NSOpenPanel:

```swift
// ✅ ПРАВИЛЬНО
@MainActor
func createMenuBarIcon() -> NSImage { ... }

@MainActor
func saveConfigToFile() -> URL? {
    let panel = NSSavePanel()
    // ...
}

// ❌ НЕПРАВИЛЬНО — ошибки "Call to main actor-isolated initializer..."
func createMenuBarIcon() -> NSImage { ... }
```

#### 3. Переменные в @Sendable closures

Переменные, захватываемые в `@Sendable` closures (например, в `AVAudioConverter.convert`), требуют специальной обработки:

```swift
// ✅ ПРАВИЛЬНО — использовать Box-класс
private final class BoolBox: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

let hasDataBox = BoolBox(true)
converter.convert(to: outputBuffer, error: &error) { _, outStatus in
    if hasDataBox.value {
        outStatus.pointee = .haveData
        hasDataBox.value = false
        return buffer
    }
    outStatus.pointee = .noDataNow
    return nil
}

// ❌ НЕПРАВИЛЬНО — ошибки "Mutation of captured var in concurrently-executing code"
var hasData = true
converter.convert(...) { _, outStatus in
    if hasData { ... }  // Ошибка!
}
```

#### 4. Non-Sendable типы из системных фреймворков

Для `AVAudioPCMBuffer` и других типов из AVFoundation:

```swift
// ✅ ПРАВИЛЬНО — добавить @preconcurrency к импорту
@preconcurrency import AVFoundation

// ❌ НЕПРАВИЛЬНО — ошибки "Capture of 'buffer' with non-Sendable type"
import AVFoundation
```

#### 5. Deprecated API в macOS 14+

```swift
// ✅ ПРАВИЛЬНО (macOS 14+)
NSApp.activate()
targetApp.activate()

// ❌ DEPRECATED — предупреждения "activateIgnoringOtherApps was deprecated"
NSApp.activate(ignoringOtherApps: true)
targetApp.activate(options: .activateIgnoringOtherApps)
```

#### 6. SwiftUI onChange (macOS 14+)

Новый синтаксис `onChange` с двумя параметрами:

```swift
// ✅ ПРАВИЛЬНО (macOS 14+) — два параметра: oldValue, newValue
.onChange(of: someValue) { _, newValue in
    // используем newValue
}

// ❌ DEPRECATED — один параметр
.onChange(of: someValue) { newValue in
    // ...
}
```

#### 7. Классы с mutable state

Для классов с изменяемым состоянием, используемых из разных потоков:

```swift
// ✅ ПРАВИЛЬНО — если класс уже @MainActor, Sendable не нужен
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate { ... }

// ✅ ПРАВИЛЬНО — для синглтонов без UI
class VolumeManager: @unchecked Sendable {
    static let shared = VolumeManager()
    private var savedVolume: Int?
    // ...
}

// ❌ НЕПРАВИЛЬНО — ошибки при использовании из async контекста
class VolumeManager {
    static let shared = VolumeManager()
}
```

### Дизайн-система

**ВАЖНО:** При изменении любых элементов дизайна приложения (цвета, отступы, шрифты, радиусы) — сначала проверить `DESIGN_SYSTEM.md` для использования единых стилей.

- **Не использовать `.green`** — только `DesignSystem.Colors.accent` (#1AAF87)
- **Не хардкодить цвета** — всегда через `DesignSystem.Colors`
- **Единый зеленый** — `#1AAF87` для всех зеленых элементов
- **НЕ добавлять тени на модалки** — `.shadow()` запрещён на главной модалке
- **strokeBorder вместо stroke** — для равномерных бордеров на скруглённых углах

```swift
// Правильно
.foregroundColor(DesignSystem.Colors.accent)
.toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.toggleActive))
.strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)  // бордер модалки

// Неправильно
.foregroundColor(.green)
.shadow(color: .black, radius: 27, y: 24)  // тени на модалке ЗАПРЕЩЕНЫ
.stroke(borderColor, lineWidth: 2)  // неравномерно на углах
```

### 🔒 Corner Radius — ЗАПРЕТ НА ИЗМЕНЕНИЕ

**Стандарт macOS Tahoe: 26pt для Toolbar Window**

Все окна, модалки и уведомления ДОЛЖНЫ использовать `cornerRadius: 26`. Это значение НЕЛЬЗЯ менять без согласования!

**Для `.borderless` окон (InputModal, History):**
```swift
.clipShape(RoundedRectangle(cornerRadius: 26))
.overlay(
    RoundedRectangle(cornerRadius: 26)
        .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
)
```

**Для `.titled` окон (Settings):**
```swift
// ПОСЛЕ sw.contentView = hostingView:
// Скругляем ВНЕШНЮЮ рамку через _NSThemeFrame (superview)
if let contentView = sw.contentView {
    contentView.superview?.wantsLayer = true
    contentView.superview?.layer?.cornerRadius = 26
    contentView.superview?.layer?.masksToBounds = true
}
```

**ЗАПРЕЩЕНО:**
- ❌ Менять cornerRadius без согласования
- ❌ Использовать разные значения для разных окон
- ❌ Скруглять `contentView.layer` вместо `superview` для titled окон
- ❌ Использовать `clipShape` для скругления titled окон (обрезает sidebar)

### Комментирование кода

#### MARK-комментарии для навигации

Используй `// MARK:` для разделения логических секций в файле:

```swift
// MARK: - Properties
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Methods
// MARK: - UI Components
// MARK: - Actions
// MARK: - Helpers
```

#### Документирующие комментарии

Для публичных API используй `///`:

```swift
/// Запускает транскрибацию аудио
/// - Parameter audioData: PCM аудио данные (16kHz, mono)
/// - Returns: Транскрибированный текст
/// - Throws: ASRError если транскрибация не удалась
func transcribe(_ audioData: Data) async throws -> String
```

#### Inline комментарии

Только для неочевидной логики:

```swift
// Буфер 1600 samples = ~100ms при 16kHz — оптимально для streaming
inputNode.installTap(onBus: 0, bufferSize: 1600, format: inputFormat)

// КРИТИЧНО: allowsHitTesting(false) иначе VoiceOverlay блокирует Enter
VoiceOverlayView(audioLevel: level)
    .allowsHitTesting(false)
```

#### НЕ добавлять комментарии:
- К очевидному коду (`// increment counter` перед `counter += 1`)
- Закомментированный код — удалять, не комментировать
- TODO без issue/задачи — либо делать сразу, либо создавать issue
- `#Preview` блоки — не используем (Xcode Preview не даёт инспектировать элементы)

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
| Paste в другое приложение | CGEvent (как Maccy/Clipy) | AppleScript (диалог System Events) |
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

### Development Workflow

#### ⚠️ ЕДИНЫЙ ПУТЬ СБОРКИ: `./build/`

**ВСЕ сборки** (Xcode и CLI) используют один путь: `./build/`

Это настроено в `project.yml`:
```yaml
options:
  derivedDataPath: build
```

**Почему это важно:**
- Permissions (TCC) привязаны к CDHash приложения
- Один путь = одна версия = permissions работают везде
- Нет путаницы между DerivedData и локальным build

#### Скрипты

| Скрипт | Назначение |
|--------|------------|
| `./scripts/run-debug.sh` | Сборка Debug + запуск |
| `./scripts/dictum_reload.sh` | Пересборка Debug + запуск |
| `./scripts/dictum_reload.sh -r` | Пересборка Release + запуск |
| `./scripts/reset-permissions.sh` | Сброс TCC + запуск |
| `./scripts/build.sh` | Release сборка (для дистрибуции) |

#### Пути к приложению

| Конфигурация | Путь |
|--------------|------|
| **Debug** | `./build/Build/Products/Debug/Dictum.app` |
| **Release** | `./build/Build/Products/Release/Dictum.app` |

#### Запуск приложения

```bash
# Debug (разработка):
./scripts/run-debug.sh

# Или напрямую:
open ./build/Build/Products/Debug/Dictum.app

# Release:
./scripts/dictum_reload.sh --release
```

#### Xcode

При запуске через Xcode (⌘R) проект автоматически использует `./build/` благодаря:

1. **project.yml**: `derivedDataPath: build`
2. **WorkspaceSettings.xcsettings**: настройки workspace

**Файл настроек workspace:**
```
Dictum.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings
```

Содержит:
```xml
<key>DerivedDataCustomLocation</key>
<string>build</string>
<key>DerivedDataLocationStyle</key>
<string>WorkspaceRelativePath</string>
```

**Настройки Xcode (должны быть):**
- Xcode → Settings → Locations → Build Location: **Custom Relative to Workspace**
- Products: `build/Build/Products`
- Intermediates: `build/Build/Intermediates.noindex`

**После изменения project.yml нужно перегенерировать проект:**
```bash
xcodegen generate
```

#### Проверка конфигурации

```bash
# 1. Проверить что в Launch Services ОДНА копия:
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep "path:.*Dictum.app" | grep -v Index.noindex

# 2. Проверить что на диске ОДНА копия:
find ~/PycharmProjects/Dictum -name "Dictum.app" -type d | grep -v Index.noindex

# 3. После сборки из Xcode (⌘B) проверить дату:
ls -la ./build/Build/Products/Debug/Dictum.app
# Дата должна обновиться
```

#### Решение проблем с разрешениями

**Симптомы:**
- После выдачи разрешения и нажатия "Restart" открывается приложение без разрешений
- Разрешения слетают при пересборке
- macOS запускает не ту копию приложения

**Причина:** В Launch Services зарегистрировано несколько копий Dictum.app с разными путями/подписями.

**Решение:**

```bash
# 1. Посмотреть все зарегистрированные копии:
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -A3 "path:.*Dictum.app"

# 2. Удалить лишние записи из Launch Services:
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "/путь/к/старой/Dictum.app"

# 3. Удалить DerivedData (если есть копии там):
rm -rf ~/Library/Developer/Xcode/DerivedData/Dictum-*

# 4. Пересобрать и запустить:
xcodegen generate
xcodebuild -project Dictum.xcodeproj -scheme Dictum -configuration Debug -derivedDataPath ./build build
open ./build/Build/Products/Debug/Dictum.app
```

**Результат:** После этого в Launch Services будет только одна копия, и разрешения будут работать корректно.

#### Индикатор версии

В настройках отображается тип сборки: "Dictum v1.92 (Debug)" или "Dictum v1.92 (Release)".

### Генерация проекта

```bash
# Из project.yml
xcodegen generate

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
