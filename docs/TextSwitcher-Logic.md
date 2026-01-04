# TextSwitcher: Полная документация логики

> Автоматическое исправление раскладки клавиатуры QWERTY <-> ЙЦУКЕН

**Версия:** 1.0
**Дата:** 2025-12-31
**Accuracy:** 99.7% (1490/1495 тестов)

---

## Содержание

1. [Обзор архитектуры](#обзор-архитектуры)
2. [Компоненты системы](#компоненты-системы)
3. [Слои валидации HybridValidator](#слои-валидации-hybridvalidator)
4. [KeyboardMonitor: Мониторинг клавиатуры](#keyboardmonitor-мониторинг-клавиатуры)
5. [LayoutMaps: Маппинги раскладок](#layoutmaps-маппинги-раскладок)
6. [NgramScorer: Статистический анализ](#ngramscorer-статистический-анализ)
7. [TechBuzzwords: Защита технических терминов](#techbuzzwords-защита-технических-терминов)
8. [Пользовательские данные](#пользовательские-данные)
9. [TextReplacer: Замена текста](#textreplacer-замена-текста)
10. [Алгоритм обработки слова](#алгоритм-обработки-слова)
11. [Permissions и требования](#permissions-и-требования)

---

## Обзор архитектуры

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        TextSwitcherManager                               │
│                    (Главный координатор, singleton)                      │
│                                                                          │
│  - Включение/выключение функциональности                                 │
│  - Статистика (autoSwitchCount, manualSwitchCount)                       │
│  - Режим обучения (isLearningEnabled)                                    │
│  - Показ toast-уведомлений                                               │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         KeyboardMonitor                                  │
│                   (CGEventTap для Input Monitoring)                      │
│                                                                          │
│  - Перехват keyDown событий                                              │
│  - Накопление wordBuffer                                                 │
│  - Отслеживание контекста (последние 10 слов)                           │
│  - Детекция Double Cmd (ручная смена раскладки)                         │
│  - Обработка Cmd+Z (rollback)                                            │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
    ┌───────────────────────────┐   ┌───────────────────────────────┐
    │     HybridValidator       │   │       TextReplacer            │
    │   (10 слоёв валидации)    │   │   (CGEvent paste/backspace)   │
    │                           │   │                               │
    │  .keep / .switchLayout    │   │  replaceLastWord()            │
    │  .noDecision              │   │  insertText()                 │
    └───────────────────────────┘   └───────────────────────────────┘
                    │
        ┌───────────┼───────────────────┐
        ▼           ▼                   ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ LayoutMaps   │ │ NgramScorer  │ │TechBuzzwords │
│ (маппинги)   │ │ (статистика) │ │ (whitelist)  │
└──────────────┘ └──────────────┘ └──────────────┘
```

---

## Компоненты системы

### Файловая структура

```
Dictum/TextSwitcher/
├── TextSwitcherManager.swift   # Главный координатор
├── KeyboardMonitor.swift       # Мониторинг клавиатуры (1251 строка)
├── HybridValidator.swift       # 10-слойная валидация (600+ строк)
├── LayoutMaps.swift            # QWERTY <-> ЙЦУКЕН маппинги
├── NgramScorer.swift           # Bigram/Trigram скоринг
├── TechBuzzwordsManager.swift  # Технические термины (853 слова)
├── UserExceptions.swift        # Исключения пользователя
├── ForcedConversions.swift     # Принудительные конвертации
└── TextReplacer.swift          # Замена текста через CGEvent
```

### Менеджеры (все Singleton)

| Класс | Назначение |
|-------|------------|
| `TextSwitcherManager.shared` | Главный координатор |
| `KeyboardMonitor.shared` | Мониторинг клавиатуры |
| `HybridValidator.shared` | Валидация слов |
| `NgramScorer.shared` | N-gram скоринг |
| `TechBuzzwordsManager.shared` | Технические термины |
| `UserExceptionsManager.shared` | Исключения пользователя |
| `ForcedConversionsManager.shared` | Принудительные конвертации |
| `TextReplacer.shared` | Замена текста |

---

## Слои валидации HybridValidator

HybridValidator использует каскадную систему из 10 слоёв. Каждый слой возвращает одно из трёх решений:

```swift
enum ValidationDecision {
    case keep                           // Оставить как есть
    case switchLayout(to: Layout, reason: String)  // Переключить раскладку
    case noDecision                     // Передать следующему слою
}
```

### Порядок слоёв (от высшего приоритета к низшему)

| Слой | Название | Описание |
|------|----------|----------|
| **-2** | Single-letter whitelist | Однобуквенные слова (`d`→`в`, `r`→`к`) |
| **-1** | User exceptions | Исключения пользователя (никогда не менять) |
| **0** | Tech buzzwords | Технические термины (docker, npm, git) |
| **0.1** | Common short words EN | Частые короткие EN слова (the, and, is) |
| **0.5** | Forced conversions | Принудительные конвертации (обучение) |
| **1** | Detectable layout | Раскладка определяется по символам |
| **1.5** | Partial detection | Частичное определение (mixed chars) |
| **2** | Context bias | Использование контекста (последние слова) |
| **2.1** | N-gram scoring | Статистический анализ bigrams/trigrams |
| **3** | SpellChecker | macOS спеллчекер (NSSpellChecker) |
| **4** | Ambiguous words | Слова-амбиграммы (одинаковы в обеих раскладках) |

---

### Слой -2: Single-letter whitelist

**Файл:** `HybridValidator.swift:59-80`

Однобуквенные слова, которые имеют чёткое соответствие:

```swift
private let singleLetterConversions: [Character: (target: String, layout: Layout)] = [
    // QWERTY → Russian предлоги/союзы
    "d": ("в", .russian), "D": ("В", .russian),   // предлог "в"
    "b": ("и", .russian), "B": ("И", .russian),   // союз "и"
    "c": ("с", .russian), "C": ("С", .russian),   // предлог "с"
    "f": ("а", .russian), "F": ("А", .russian),   // союз "а"
    "r": ("к", .russian), "R": ("К", .russian),   // предлог "к"
    "e": ("у", .russian), "E": ("У", .russian),   // предлог "у"
    "j": ("о", .russian), "J": ("О", .russian),   // предлог "о"
    "z": ("я", .russian), "Z": ("Я", .russian),   // местоимение "я"

    // Russian → English
    "Ш": ("I", .qwerty), "ш": ("i", .qwerty),     // местоимение "I"
    "Ф": ("A", .qwerty), "ф": ("a", .qwerty),     // артикль "a"
]
```

**Логика с контекстом:**

```swift
if normalizedWord.count == 1, let firstChar = normalizedWord.first {
    if let conversion = singleLetterConversions[firstChar] {
        // 1. Контекстный биас
        if let bias = biasTowardLayout {
            if bias == conversion.layout {
                return .switchLayout(to: conversion.layout, reason: "single_letter_with_context")
            }
            if bias == currentLayout {
                return .keep
            }
        }
        // 2. Без контекста: проверяем TechBuzzwords (R — язык программирования)
        if TechBuzzwordsManager.shared.contains(normalizedWord) {
            return .keep
        }
        // 3. Конвертируем по умолчанию
        return .switchLayout(to: conversion.layout, reason: "single_letter_whitelist")
    }
}
```

---

### Слой -1: User exceptions

**Файл:** `UserExceptions.swift`

Слова, которые пользователь добавил в исключения — **никогда не конвертируются**.

**Хранение:** `~/Library/Application Support/Dictum/text_switcher_exceptions.json`

```swift
if UserExceptionsManager.shared.contains(normalizedWord) {
    return .keep
}
```

**Как добавить исключение:**
- Через UI настроек (ручное добавление)
- Через double Cmd + Cmd+Z (автоматическое обучение)

---

### Слой 0: Tech buzzwords

**Файл:** `TechBuzzwordsManager.swift`

853 технических термина из 27 категорий, которые **никогда не конвертируются**.

**Источник:** `Dictum/Resources/tech_buzzwords_2025.json`

**Категории:**
- `programming_languages`: python, javascript, rust, go, R, V...
- `frameworks`: react, angular, vue, django, fastapi...
- `tools`: docker, kubernetes, git, npm, webpack...
- `databases`: postgresql, mongodb, redis, elasticsearch...
- `cloud`: aws, azure, gcp, lambda, s3...
- `ai_ml`: tensorflow, pytorch, transformers, llm...
- `protocols`: http, https, websocket, grpc...
- И ещё 20 категорий...

```swift
if TechBuzzwordsManager.shared.contains(normalizedWord) {
    return .keep
}
```

**Compound buzzwords:** Поддержка составных терминов (gpt-4, c++, react-native).

---

### Слой 0.1: Common short words EN

**Файл:** `HybridValidator.swift:96-108`

Частые короткие английские слова (2-4 буквы), которые нельзя конвертировать:

```swift
private let commonShortWordsEN: Set<String> = [
    // 2 буквы
    "ok", "no", "go", "my", "me", "we", "he", "it", "to", "do", "be", "so",
    "of", "in", "on", "at", "by", "up", "or", "as", "if", "an",
    "id", "am", "us", "hi", "oh", "ah",

    // 3 буквы
    "the", "and", "for", "not", "you", "but", "can", "all", "get", "new",
    "out", "now", "how", "who", "why", "see", "use", "way", "own", "our",
    "say", "let", "set", "put", "add", "run", "try", "ask", "big", "end",

    // 4 буквы
    "this", "that", "will", "with", "have", "from", "they", "been", "call",
    "code", "like", "just", "also", "more", "than"
]
```

---

### Слой 0.5: Forced conversions

**Файл:** `ForcedConversions.swift`

Принудительные конвертации — слова, которые пользователь подтвердил через double Cmd.

**Хранение:** `~/Library/Application Support/Dictum/forced_conversions.json`

```swift
if let forcedResult = ForcedConversionsManager.shared.getConversion(for: word) {
    let targetLayout = detectLayoutOf(forcedResult)
    return .switchLayout(to: targetLayout, reason: "forced_conversion")
}
```

**Жёсткое знание:** После 3+ подтверждений слово становится "жёстким знанием" (не удаляется автоматически).

---

### Слой 1: Detectable layout

**Файл:** `HybridValidator.swift:220-270`

Определение раскладки по содержимым символам:

```swift
let detectedLayout = LayoutMaps.detectLayout(of: normalizedWord)

switch detectedLayout {
case .russian:
    // Слово уже на русском — если не в EN словаре, оставляем
    if !isEnglishWord(normalizedWord) {
        return .keep
    }
case .qwerty:
    // Слово на английском — если в EN словаре, оставляем
    if isEnglishWord(normalizedWord) {
        return .keep
    }
case .mixed:
    // Смешанные символы — передаём дальше
    return .noDecision
case .unknown:
    return .noDecision
}
```

---

### Слой 1.5: Partial detection

Обработка слов со смешанными символами (RU + EN).

Примеры: `{орошо` (Х набран как {), `еуыеs` (test набран частично на RU).

---

### Слой 2: Context bias

**Файл:** `KeyboardMonitor.swift:680-750`

Использование контекста последних слов для определения вероятной раскладки.

```swift
// История последних 10 слов (30 секунд)
private var contextHistory: [(word: String, layout: Layout, timestamp: Date)] = []

func calculateContextBias() -> Layout? {
    let recentWords = contextHistory.filter {
        Date().timeIntervalSince($0.timestamp) < 30
    }

    let ruCount = recentWords.filter { $0.layout == .russian }.count
    let enCount = recentWords.filter { $0.layout == .qwerty }.count

    // Нужен явный перевес (>= 2 слова)
    if ruCount >= 2 && ruCount > enCount {
        return .russian
    }
    if enCount >= 2 && enCount > ruCount {
        return .qwerty
    }
    return nil
}
```

---

### Слой 2.1: N-gram scoring

**Файл:** `NgramScorer.swift`

Статистический анализ на основе bigrams и trigrams из Leipzig Corpora.

**Данные:** `NgramData.swift` (загружается из JSON-файлов)

```swift
func score(_ word: String, for language: Language) -> Double {
    var totalScore: Double = 0

    // Bigrams
    for i in 0..<(word.count - 1) {
        let bigram = String(word[i..<i+2])
        if let logProb = bigramData[language]?[bigram] {
            totalScore += logProb
        } else {
            totalScore += unknownPenalty  // -10.0
        }
    }

    // Trigrams (если слово >= 3 символов)
    for i in 0..<(word.count - 2) {
        let trigram = String(word[i..<i+3])
        if let logProb = trigramData[language]?[trigram] {
            totalScore += logProb
        }
    }

    return totalScore
}
```

**Ratio calculation:**

```swift
let ruScore = scorer.score(word, for: .russian)
let enScore = scorer.score(convertedWord, for: .english)
let ratio = ruScore - enScore

// ratio > 0 → больше похоже на русский
// ratio < 0 → больше похоже на английский
```

---

### Слой 3: SpellChecker

**Файл:** `HybridValidator.swift:350-400`

Использование macOS NSSpellChecker для проверки слов.

```swift
let checker = NSSpellChecker.shared

func isRussianWord(_ word: String) -> Bool {
    let range = checker.checkSpelling(of: word, startingAt: 0, language: "ru", wrap: false, inSpellDocumentWithTag: 0)
    return range.location == NSNotFound  // Нет ошибок = валидное слово
}

func isEnglishWord(_ word: String) -> Bool {
    let range = checker.checkSpelling(of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0)
    return range.location == NSNotFound
}
```

---

### Слой 4: Ambiguous words

Слова-амбиграммы, которые выглядят одинаково в обеих раскладках.

Примеры: `а` (RU) vs `a` (EN), `о` (RU) vs `o` (EN).

Для таких слов используется контекстный биас или оставляем как есть.

---

## KeyboardMonitor: Мониторинг клавиатуры

**Файл:** `KeyboardMonitor.swift` (1251 строка)

### CGEventTap

Использует низкоуровневый CGEventTap для перехвата всех нажатий клавиш:

```swift
let eventMask = (1 << CGEventType.keyDown.rawValue)

let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: CGEventMask(eventMask),
    callback: { proxy, type, event, refcon in
        // Обработка события
    },
    userInfo: Unmanaged.passUnretained(self).toOpaque()
)

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
```

### Word Buffer

Накопление символов в буфер до разделителя (пробел, enter, пунктуация):

```swift
private var wordBuffer: String = ""

func handleKeyDown(event: CGEvent) {
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Получаем символ
    guard let char = characterForKeyCode(keyCode, flags: event.flags) else { return }

    // Разделитель?
    if char.isWhitespace || char.isPunctuation {
        if !wordBuffer.isEmpty {
            processWord(wordBuffer)
            wordBuffer = ""
        }
        return
    }

    // Добавляем в буфер
    wordBuffer.append(char)
}
```

### Double Cmd Detection

Детекция двойного нажатия Cmd для ручной смены раскладки:

```swift
private var lastCmdPressTime: Date?
private let doubleCmdThreshold: TimeInterval = 0.4  // 400ms

func handleFlagsChanged(event: CGEvent) {
    let flags = event.flags

    // Cmd нажат?
    if flags.contains(.maskCommand) {
        if let lastPress = lastCmdPressTime,
           Date().timeIntervalSince(lastPress) < doubleCmdThreshold {
            // Double Cmd detected!
            handleDoubleCmdSwitch()
            lastCmdPressTime = nil
        } else {
            lastCmdPressTime = Date()
        }
    }
}

func handleDoubleCmdSwitch() {
    // 1. Получаем выделенный текст или последнее слово
    // 2. Конвертируем в другую раскладку
    // 3. Заменяем через TextReplacer
    // 4. Если isLearningEnabled, сохраняем в ForcedConversions
}
```

### Cmd+Z Rollback

Отслеживание Cmd+Z для отката последней автозамены:

```swift
private var lastReplacement: (original: String, replaced: String, timestamp: Date)?

func handleCmdZ() {
    guard let last = lastReplacement,
          Date().timeIntervalSince(last.timestamp) < 5.0 else { return }

    // Пользователь отменил нашу замену
    // Добавляем оригинал в исключения
    if TextSwitcherManager.shared.isLearningEnabled {
        UserExceptionsManager.shared.addException(last.original, reason: .autoLearned)
        TextSwitcherManager.shared.showLearnedToast(word: last.original)
    }

    lastReplacement = nil
}
```

---

## LayoutMaps: Маппинги раскладок

**Файл:** `LayoutMaps.swift`

### Таблицы маппингов

```swift
// QWERTY → Russian (lowercase)
static let qwertyToRussianLower: [Character: Character] = [
    "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г",
    "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
    "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о",
    "k": "л", "l": "д", ";": "ж", "'": "э",
    "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
    ",": "б", ".": "ю", "/": ".",
    "`": "ё"
]

// QWERTY → Russian (uppercase / shifted)
static let qwertyToRussianUpper: [Character: Character] = [
    "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г",
    "I": "Ш", "O": "Щ", "P": "З", "{": "Х", "}": "Ъ",
    "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О",
    "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
    "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
    "<": "Б", ">": "Ю", "?": ",",
    "~": "Ё"
]
```

### Наборы символов

```swift
/// Все символы QWERTY (lower + upper + shifted)
static let allQwertyMappableCharacters: Set<Character> = {
    var chars = Set(qwertyToRussianLower.keys)
    chars.formUnion(qwertyToRussianUpper.keys)
    return chars
}()

/// Все русские символы
static let allRussianMappableCharacters: Set<Character> = {
    var chars = Set(russianToQwertyLower.keys)
    chars.formUnion(russianToQwertyUpper.keys)
    return chars
}()
```

### Функции

```swift
/// Конвертирует строку в другую раскладку
static func convert(_ string: String, to layout: Layout) -> String

/// Определяет раскладку строки
static func detectLayout(of string: String) -> Layout

/// Переключает раскладку строки
static func toggleLayout(_ string: String) -> String
```

---

## NgramScorer: Статистический анализ

**Файл:** `NgramScorer.swift`

### Источник данных

Leipzig Corpora — частотные n-граммы для русского и английского языков.

**Файлы:**
- `ngrams_en_bigrams.json` — английские биграммы
- `ngrams_en_trigrams.json` — английские триграммы
- `ngrams_ru_bigrams.json` — русские биграммы
- `ngrams_ru_trigrams.json` — русские триграммы

### Алгоритм скоринга

```swift
class NgramScorer {
    private var enBigrams: [String: Double] = [:]
    private var enTrigrams: [String: Double] = [:]
    private var ruBigrams: [String: Double] = [:]
    private var ruTrigrams: [String: Double] = [:]

    private let unknownPenalty: Double = -10.0

    func score(_ word: String, for language: Language) -> Double {
        let lowercased = word.lowercased()
        var score: Double = 0

        // Bigram scoring
        let bigrams = language == .russian ? ruBigrams : enBigrams
        for i in 0..<(lowercased.count - 1) {
            let start = lowercased.index(lowercased.startIndex, offsetBy: i)
            let end = lowercased.index(start, offsetBy: 2)
            let bigram = String(lowercased[start..<end])

            score += bigrams[bigram] ?? unknownPenalty
        }

        // Trigram scoring (если слово >= 3 символов)
        if lowercased.count >= 3 {
            let trigrams = language == .russian ? ruTrigrams : enTrigrams
            for i in 0..<(lowercased.count - 2) {
                let start = lowercased.index(lowercased.startIndex, offsetBy: i)
                let end = lowercased.index(start, offsetBy: 3)
                let trigram = String(lowercased[start..<end])

                score += trigrams[trigram] ?? unknownPenalty
            }
        }

        return score
    }

    /// Ratio: положительный = русский, отрицательный = английский
    func calculateRatio(word: String, convertedWord: String) -> Double {
        let ruScore = score(word, for: .russian)
        let enScore = score(convertedWord, for: .english)
        return ruScore - enScore
    }
}
```

---

## TechBuzzwords: Защита технических терминов

**Файл:** `TechBuzzwordsManager.swift`

### Статистика

- **853** термина
- **27** категорий
- **O(1)** lookup через HashSet

### Категории

```json
{
  "programming_languages": ["python", "javascript", "typescript", "rust", "go", "r", "v", ...],
  "frameworks": ["react", "angular", "vue", "django", "fastapi", "express", ...],
  "tools": ["docker", "kubernetes", "git", "npm", "yarn", "webpack", ...],
  "databases": ["postgresql", "mysql", "mongodb", "redis", "elasticsearch", ...],
  "cloud_services": ["aws", "azure", "gcp", "lambda", "s3", "ec2", ...],
  "ai_ml": ["tensorflow", "pytorch", "transformers", "llm", "chatgpt", ...],
  ...
}
```

### Compound Buzzwords

Поддержка составных терминов с разделителями:

```swift
private let compoundBuzzwords: Set<String> = [
    "gpt-4", "gpt-4o", "c++", "c#", "f#",
    "react-native", "vue-router", "redux-saga",
    "pre-commit", "post-commit",
    ...
]

func contains(_ word: String) -> Bool {
    let normalized = word.lowercased()
    return buzzwordsSet.contains(normalized) || compoundBuzzwords.contains(normalized)
}
```

---

## Пользовательские данные

### UserExceptions (Исключения)

**Файл:** `UserExceptions.swift`

Слова, которые пользователь не хочет автоматически исправлять.

**Хранение:** `~/Library/Application Support/Dictum/text_switcher_exceptions.json`

```json
{
  "version": 1,
  "exportedAt": "2025-12-31T12:00:00Z",
  "exceptions": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "word": "привет",
      "addedAt": "2025-12-30T10:00:00Z",
      "reason": "auto_learned"
    }
  ]
}
```

**Причины добавления:**
- `manual` — добавлено вручную в настройках
- `auto_learned` — обучено через Cmd+Z после неправильной автозамены

### ForcedConversions (Принудительные конвертации)

**Файл:** `ForcedConversions.swift`

Слова, которые пользователь подтвердил через double Cmd.

**Хранение:** `~/Library/Application Support/Dictum/forced_conversions.json`

```json
{
  "version": 1,
  "exportedAt": "2025-12-31T12:00:00Z",
  "conversions": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440001",
      "originalWord": "руддщ",
      "convertedWord": "hello",
      "addedAt": "2025-12-30T10:00:00Z",
      "confirmationCount": 3
    }
  ]
}
```

**Жёсткое знание:** `confirmationCount >= 3` — слово не удаляется автоматически.

---

## TextReplacer: Замена текста

**Файл:** `TextReplacer.swift`

### Методы замены

```swift
class TextReplacer {
    /// Заменяет последнее слово через Backspace + Paste
    @MainActor
    func replaceLastWord(oldLength: Int, newText: String)

    /// Заменяет выделенный текст
    @MainActor
    func replaceSelectedText(with newText: String)

    /// Вставляет текст напрямую
    @MainActor
    func insertText(_ text: String)

    /// Получает выделенный текст через Cmd+C
    @MainActor
    func getSelectedText() -> String?
}
```

### Алгоритм replaceLastWord

```swift
func replaceLastWord(oldLength: Int, newText: String) {
    // 1. Сохраняем clipboard
    let savedClipboard = saveClipboard()

    // 2. Удаляем старое слово (Backspace × oldLength)
    deleteCharacters(count: oldLength)

    // 3. Ждём 3ms (важно для race condition!)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.003) {
        // 4. Вставляем новый текст
        self.pasteText(newText)

        // 5. Восстанавливаем clipboard через 100ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.restoreClipboard(savedClipboard)
        }
    }
}
```

### CGEvent для эмуляции клавиш

```swift
private func deleteCharacters(count: Int) {
    let source = CGEventSource(stateID: .combinedSessionState)

    for _ in 0..<count {
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)

        usleep(1_000)  // 1ms между нажатиями
    }
}

private func simulatePaste() {
    let source = CGEventSource(stateID: .combinedSessionState)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // V
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

    keyDown?.flags = .maskCommand
    keyUp?.flags = .maskCommand

    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
}
```

---

## Алгоритм обработки слова

### Полный flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Пользователь набирает "ghbdtn"                │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│           KeyboardMonitor: CGEventTap перехватывает              │
│           keyDown события, накапливает в wordBuffer              │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Пользователь нажимает Space / Enter                 │
│              → wordBuffer = "ghbdtn"                             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    HybridValidator.validate()                    │
│                                                                  │
│  Слой -2: singleLetterConversions        → noDecision           │
│  Слой -1: UserExceptions.contains()      → noDecision           │
│  Слой  0: TechBuzzwords.contains()       → noDecision           │
│  Слой 0.1: commonShortWordsEN            → noDecision           │
│  Слой 0.5: ForcedConversions.get()       → noDecision           │
│  Слой  1: detectLayout() = .qwerty       → проверить словарь    │
│          → "ghbdtn" не в EN словаре                              │
│  Слой  2: contextBias = .russian         → switchLayout         │
│  Слой 2.1: N-gram ratio = 15.3           → подтверждение        │
│                                                                  │
│  Результат: .switchLayout(to: .russian, reason: "ngram_ratio") │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                LayoutMaps.convert("ghbdtn", to: .russian)        │
│                         → "привет"                               │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│         TextReplacer.replaceLastWord(oldLength: 6,               │
│                                      newText: "привет")          │
│                                                                  │
│  1. Сохранить clipboard                                          │
│  2. 6 × Backspace                                                │
│  3. Paste "привет"                                               │
│  4. Восстановить clipboard                                       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Пользователь видит: "привет "                       │
│              (автоматически исправлено!)                         │
└─────────────────────────────────────────────────────────────────┘
```

---

## Permissions и требования

### macOS Permissions

| Permission | Где запросить | Зачем |
|------------|---------------|-------|
| **Input Monitoring** | System Settings → Privacy & Security → Input Monitoring | CGEventTap для перехвата клавиш |
| **Accessibility** | System Settings → Privacy & Security → Accessibility | CGEvent для эмуляции клавиш |

### Проверка permissions

```swift
func checkInputMonitoringPermission() -> Bool {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): false]
    return AXIsProcessTrustedWithOptions(options)
}

func requestAccessibilityPermission() {
    let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    AXIsProcessTrustedWithOptions(options)
}
```

### Требования системы

- **macOS 14.0+** (Sonoma)
- **Apple Silicon** или Intel (CGEventTap работает на обоих)

---

## Логирование

### os.Logger

Все компоненты используют `os.Logger`:

```swift
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "HybridValidator")

logger.debug("...")   // Отладка
logger.info("...")    // Информация
logger.warning("...") // Предупреждения
logger.error("...")   // Ошибки
```

### Просмотр логов

```bash
# Все логи TextSwitcher
./scripts/logs.sh

# Только определённая категория
./scripts/logs.sh -t  # TextSwitcher
```

---

## Метрики и тестирование

### Текущие результаты

- **Accuracy:** 99.7% (1490/1495 тестов)
- **Категории тестов:**
  - `en_common_words` — частые английские слова
  - `ru_common_words` — частые русские слова
  - `tech_buzzwords` — технические термины
  - `mixed_lang` — смешанные тексты
  - `short_words` — короткие слова (2-3 буквы)
  - `edge_cases` — граничные случаи
  - `shifted_symbols` — символы с Shift ({, <, >, :)
  - `single_letters_conflict` — конфликтные буквы (r, e, j, z)

### Запуск тестов

```bash
# Полный тест
python3 scripts/batch_test_switcher.py

# С выводом ошибок
python3 scripts/batch_test_switcher.py --verbose
```

---

## Известные ограничения

1. **Слова с `/` и `|`** — символы разбивают слово на части
2. **Очень короткие слова (1-2 буквы)** — требуют контекста для точного определения
3. **Новые технические термины** — нужно добавлять в `tech_buzzwords_2025.json`
4. **Слова-омонимы** — `tot` (EN) vs `еще` (RU) — зависят от контекста

---

## Changelog

### v1.0 (2025-12-31)
- 10-слойная система валидации
- N-gram scoring на базе Leipzig Corpora
- 853 технических термина
- Context bias с историей 10 слов
- Double Cmd для ручной смены
- Cmd+Z для отмены и обучения
- 99.7% accuracy (1490/1495 тестов)
