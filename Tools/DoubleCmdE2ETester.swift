//
//  DoubleCmdE2ETester.swift
//  Dictum
//
//  E2E тестер для Double Cmd функциональности.
//  Тестирует РЕАЛЬНУЮ работу в TextEdit, НЕ только конвертацию.
//
//  ВАЖНО: НЕ коммитить в git! Только для локальной разработки.
//
//  Требования для запуска:
//  1. Dictum должен быть запущен
//  2. Accessibility permission для этого тестера
//  3. TextEdit будет открыт автоматически
//

import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Test Case Definition

struct TestCase {
    let input: String
    let expected: String
    let category: String
    let description: String

    init(input: String, expected: String, category: String, description: String = "") {
        self.input = input
        self.expected = expected
        self.category = category
        self.description = description.isEmpty ? "\(input) → \(expected)" : description
    }
}

// MARK: - Test Categories

/// Все тест-кейсы для Double Cmd
let allTestCases: [TestCase] = [
    // ═══════════════════════════════════════════════════════════════
    // БАЗОВЫЕ СЛОВА (EN → RU)
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "ghbdtn", expected: "привет", category: "basic_en_to_ru"),
    TestCase(input: "ntcn", expected: "тест", category: "basic_en_to_ru"),
    TestCase(input: "ckjdj", expected: "слово", category: "basic_en_to_ru"),
    TestCase(input: "vbh", expected: "мир", category: "basic_en_to_ru"),

    // ═══════════════════════════════════════════════════════════════
    // БАЗОВЫЕ СЛОВА (RU → EN)
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "ру|", expected: "hel", category: "basic_ru_to_en"),
    TestCase(input: "руддщ", expected: "hello", category: "basic_ru_to_en"),
    TestCase(input: "цщкв", expected: "word", category: "basic_ru_to_en"),
    TestCase(input: "еу|е", expected: "test", category: "basic_ru_to_en"),

    // ═══════════════════════════════════════════════════════════════
    // ПУНКТУАЦИЯ В КОНЦЕ (критический кейс!)
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "ghbdtn!", expected: "привет!", category: "punctuation_end",
             description: "Восклицательный знак в конце"),
    TestCase(input: "ntcn?", expected: "тест?", category: "punctuation_end",
             description: "Вопросительный знак в конце"),
    TestCase(input: "lf,", expected: "да,", category: "punctuation_end",
             description: "Запятая в конце"),
    TestCase(input: "ckjdj.", expected: "слово.", category: "punctuation_end",
             description: "Точка в конце"),
    TestCase(input: "ghbdtn:", expected: "привет:", category: "punctuation_end",
             description: "Двоеточие в конце"),
    TestCase(input: "ghbdtn;", expected: "привет;", category: "punctuation_end",
             description: "Точка с запятой в конце"),

    // ═══════════════════════════════════════════════════════════════
    // МНОЖЕСТВЕННАЯ ПУНКТУАЦИЯ
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "ghbdtn!!!", expected: "привет!!!", category: "multi_punct",
             description: "Три восклицательных знака"),
    TestCase(input: "ghbdtn???", expected: "привет???", category: "multi_punct",
             description: "Три вопросительных знака"),
    TestCase(input: "ghbdtn!?", expected: "привет!?", category: "multi_punct",
             description: "Восклицательный + вопросительный"),
    TestCase(input: "ghbdtn...", expected: "привет...", category: "multi_punct",
             description: "Многоточие"),

    // ═══════════════════════════════════════════════════════════════
    // ПРОБЕЛ ПОСЛЕ СЛОВА
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "ghbdtn ", expected: "привет ", category: "after_space",
             description: "Пробел после слова"),
    TestCase(input: "ntcn  ", expected: "тест  ", category: "after_space",
             description: "Два пробела после слова"),

    // ═══════════════════════════════════════════════════════════════
    // ПУНКТУАЦИЯ + ПРОБЕЛ
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "ghbdtn! ", expected: "привет! ", category: "punct_space",
             description: "Восклицательный + пробел"),
    TestCase(input: "ghbdtn, ", expected: "привет, ", category: "punct_space",
             description: "Запятая + пробел"),

    // ═══════════════════════════════════════════════════════════════
    // ДЛИННЫЙ ТЕКСТ (проверка что НЕ удаляются другие строки)
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "первое ghbdtn", expected: "первое привет", category: "long_text",
             description: "Слово в середине предложения"),
    TestCase(input: "ghbdtn второе", expected: "привет второе", category: "long_text",
             description: "Слово в начале предложения"),

    // ═══════════════════════════════════════════════════════════════
    // ОДИНОЧНЫЕ СИМВОЛЫ (НЕ должны конвертироваться)
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "?", expected: "?", category: "single_char",
             description: "Одиночный символ — НЕ меняется"),
    TestCase(input: "!", expected: "!", category: "single_char",
             description: "Одиночный символ — НЕ меняется"),
    TestCase(input: "a", expected: "a", category: "single_char",
             description: "Одна буква — НЕ меняется (мин. 2 символа)"),

    // ═══════════════════════════════════════════════════════════════
    // КОРОТКИЕ СЛОВА (2-3 символа)
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "lf", expected: "да", category: "short_word",
             description: "Два символа — должно работать"),
    TestCase(input: "ytn", expected: "нет", category: "short_word",
             description: "Три символа"),

    // ═══════════════════════════════════════════════════════════════
    // ЦИФРЫ В СЛОВЕ
    // ═══════════════════════════════════════════════════════════════
    TestCase(input: "ntcn123", expected: "тест123", category: "with_numbers",
             description: "Цифры в конце слова"),
    TestCase(input: "123ntcn", expected: "123тест", category: "with_numbers",
             description: "Цифры в начале слова"),
]

// MARK: - Key Code Mapping

/// Структура для хранения keyCode и флага Shift
struct KeyCodeInfo {
    let code: CGKeyCode
    let shift: Bool

    init(_ code: CGKeyCode, shift: Bool = false) {
        self.code = code
        self.shift = shift
    }
}

/// Маппинг символов на keyCode (US QWERTY layout)
/// Для русских букв нужно переключить раскладку!
func keyCodeForChar(_ char: Character) -> KeyCodeInfo? {
    let keyMap: [Character: KeyCodeInfo] = [
        // Буквы (нижний регистр)
        "a": KeyCodeInfo(0x00), "b": KeyCodeInfo(0x0B), "c": KeyCodeInfo(0x08),
        "d": KeyCodeInfo(0x02), "e": KeyCodeInfo(0x0E), "f": KeyCodeInfo(0x03),
        "g": KeyCodeInfo(0x05), "h": KeyCodeInfo(0x04), "i": KeyCodeInfo(0x22),
        "j": KeyCodeInfo(0x26), "k": KeyCodeInfo(0x28), "l": KeyCodeInfo(0x25),
        "m": KeyCodeInfo(0x2E), "n": KeyCodeInfo(0x2D), "o": KeyCodeInfo(0x1F),
        "p": KeyCodeInfo(0x23), "q": KeyCodeInfo(0x0C), "r": KeyCodeInfo(0x0F),
        "s": KeyCodeInfo(0x01), "t": KeyCodeInfo(0x11), "u": KeyCodeInfo(0x20),
        "v": KeyCodeInfo(0x09), "w": KeyCodeInfo(0x0D), "x": KeyCodeInfo(0x07),
        "y": KeyCodeInfo(0x10), "z": KeyCodeInfo(0x06),

        // Буквы (верхний регистр)
        "A": KeyCodeInfo(0x00, shift: true), "B": KeyCodeInfo(0x0B, shift: true),
        "C": KeyCodeInfo(0x08, shift: true), "D": KeyCodeInfo(0x02, shift: true),
        "E": KeyCodeInfo(0x0E, shift: true), "F": KeyCodeInfo(0x03, shift: true),
        "G": KeyCodeInfo(0x05, shift: true), "H": KeyCodeInfo(0x04, shift: true),
        "I": KeyCodeInfo(0x22, shift: true), "J": KeyCodeInfo(0x26, shift: true),
        "K": KeyCodeInfo(0x28, shift: true), "L": KeyCodeInfo(0x25, shift: true),
        "M": KeyCodeInfo(0x2E, shift: true), "N": KeyCodeInfo(0x2D, shift: true),
        "O": KeyCodeInfo(0x1F, shift: true), "P": KeyCodeInfo(0x23, shift: true),
        "Q": KeyCodeInfo(0x0C, shift: true), "R": KeyCodeInfo(0x0F, shift: true),
        "S": KeyCodeInfo(0x01, shift: true), "T": KeyCodeInfo(0x11, shift: true),
        "U": KeyCodeInfo(0x20, shift: true), "V": KeyCodeInfo(0x09, shift: true),
        "W": KeyCodeInfo(0x0D, shift: true), "X": KeyCodeInfo(0x07, shift: true),
        "Y": KeyCodeInfo(0x10, shift: true), "Z": KeyCodeInfo(0x06, shift: true),

        // Цифры
        "0": KeyCodeInfo(0x1D), "1": KeyCodeInfo(0x12), "2": KeyCodeInfo(0x13),
        "3": KeyCodeInfo(0x14), "4": KeyCodeInfo(0x15), "5": KeyCodeInfo(0x17),
        "6": KeyCodeInfo(0x16), "7": KeyCodeInfo(0x1A), "8": KeyCodeInfo(0x1C),
        "9": KeyCodeInfo(0x19),

        // Пунктуация (без Shift)
        ";": KeyCodeInfo(0x29), "'": KeyCodeInfo(0x27), ",": KeyCodeInfo(0x2B),
        ".": KeyCodeInfo(0x2F), "/": KeyCodeInfo(0x2C), "`": KeyCodeInfo(0x32),
        "[": KeyCodeInfo(0x21), "]": KeyCodeInfo(0x1E), "\\": KeyCodeInfo(0x2A),
        "-": KeyCodeInfo(0x1B), "=": KeyCodeInfo(0x18),

        // Пунктуация (с Shift)
        "!": KeyCodeInfo(0x12, shift: true),  // Shift+1
        "@": KeyCodeInfo(0x13, shift: true),  // Shift+2
        "#": KeyCodeInfo(0x14, shift: true),  // Shift+3
        "$": KeyCodeInfo(0x15, shift: true),  // Shift+4
        "%": KeyCodeInfo(0x17, shift: true),  // Shift+5
        "^": KeyCodeInfo(0x16, shift: true),  // Shift+6
        "&": KeyCodeInfo(0x1A, shift: true),  // Shift+7
        "*": KeyCodeInfo(0x1C, shift: true),  // Shift+8
        "(": KeyCodeInfo(0x19, shift: true),  // Shift+9
        ")": KeyCodeInfo(0x1D, shift: true),  // Shift+0
        "_": KeyCodeInfo(0x1B, shift: true),  // Shift+-
        "+": KeyCodeInfo(0x18, shift: true),  // Shift+=
        ":": KeyCodeInfo(0x29, shift: true),  // Shift+;
        "\"": KeyCodeInfo(0x27, shift: true), // Shift+'
        "<": KeyCodeInfo(0x2B, shift: true),  // Shift+,
        ">": KeyCodeInfo(0x2F, shift: true),  // Shift+.
        "?": KeyCodeInfo(0x2C, shift: true),  // Shift+/
        "~": KeyCodeInfo(0x32, shift: true),  // Shift+`
        "{": KeyCodeInfo(0x21, shift: true),  // Shift+[
        "}": KeyCodeInfo(0x1E, shift: true),  // Shift+]
        "|": KeyCodeInfo(0x2A, shift: true),  // Shift+\

        // Специальные
        " ": KeyCodeInfo(0x31),  // Space
    ]

    // Для русских букв — используем ту же физическую клавишу но в русской раскладке
    // Это будет работать если раскладка уже русская
    let russianKeyMap: [Character: KeyCodeInfo] = [
        "а": KeyCodeInfo(0x03), "б": KeyCodeInfo(0x2B), "в": KeyCodeInfo(0x02),
        "г": KeyCodeInfo(0x20), "д": KeyCodeInfo(0x25), "е": KeyCodeInfo(0x11),
        "ё": KeyCodeInfo(0x32), "ж": KeyCodeInfo(0x29), "з": KeyCodeInfo(0x23),
        "и": KeyCodeInfo(0x0B), "й": KeyCodeInfo(0x0C), "к": KeyCodeInfo(0x0F),
        "л": KeyCodeInfo(0x28), "м": KeyCodeInfo(0x09), "н": KeyCodeInfo(0x10),
        "о": KeyCodeInfo(0x26), "п": KeyCodeInfo(0x05), "р": KeyCodeInfo(0x04),
        "с": KeyCodeInfo(0x08), "т": KeyCodeInfo(0x2D), "у": KeyCodeInfo(0x0E),
        "ф": KeyCodeInfo(0x00), "х": KeyCodeInfo(0x21), "ц": KeyCodeInfo(0x0D),
        "ч": KeyCodeInfo(0x07), "ш": KeyCodeInfo(0x22), "щ": KeyCodeInfo(0x1F),
        "ъ": KeyCodeInfo(0x1E), "ы": KeyCodeInfo(0x01), "ь": KeyCodeInfo(0x2E),
        "э": KeyCodeInfo(0x27), "ю": KeyCodeInfo(0x2F), "я": KeyCodeInfo(0x06),

        // Верхний регистр (Shift)
        "А": KeyCodeInfo(0x03, shift: true), "Б": KeyCodeInfo(0x2B, shift: true),
        "В": KeyCodeInfo(0x02, shift: true), "Г": KeyCodeInfo(0x20, shift: true),
        "Д": KeyCodeInfo(0x25, shift: true), "Е": KeyCodeInfo(0x11, shift: true),
        "Ё": KeyCodeInfo(0x32, shift: true), "Ж": KeyCodeInfo(0x29, shift: true),
        "З": KeyCodeInfo(0x23, shift: true), "И": KeyCodeInfo(0x0B, shift: true),
        "Й": KeyCodeInfo(0x0C, shift: true), "К": KeyCodeInfo(0x0F, shift: true),
        "Л": KeyCodeInfo(0x28, shift: true), "М": KeyCodeInfo(0x09, shift: true),
        "Н": KeyCodeInfo(0x10, shift: true), "О": KeyCodeInfo(0x26, shift: true),
        "П": KeyCodeInfo(0x05, shift: true), "Р": KeyCodeInfo(0x04, shift: true),
        "С": KeyCodeInfo(0x08, shift: true), "Т": KeyCodeInfo(0x2D, shift: true),
        "У": KeyCodeInfo(0x0E, shift: true), "Ф": KeyCodeInfo(0x00, shift: true),
        "Х": KeyCodeInfo(0x21, shift: true), "Ц": KeyCodeInfo(0x0D, shift: true),
        "Ч": KeyCodeInfo(0x07, shift: true), "Ш": KeyCodeInfo(0x22, shift: true),
        "Щ": KeyCodeInfo(0x1F, shift: true), "Ъ": KeyCodeInfo(0x1E, shift: true),
        "Ы": KeyCodeInfo(0x01, shift: true), "Ь": KeyCodeInfo(0x2E, shift: true),
        "Э": KeyCodeInfo(0x27, shift: true), "Ю": KeyCodeInfo(0x2F, shift: true),
        "Я": KeyCodeInfo(0x06, shift: true),
    ]

    return keyMap[char] ?? russianKeyMap[char]
}

// MARK: - Input Source Switching

/// Текущая раскладка
func getCurrentInputSource() -> String {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    if let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
        return Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
    }
    return ""
}

/// Переключение раскладки на английскую
func switchToEnglish() {
    let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    for source in sources {
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if id.contains("ABC") || id.contains("US") {
                TISSelectInputSource(source)
                usleep(100_000)  // 100ms для переключения
                return
            }
        }
    }
}

/// Переключение раскладки на русскую
func switchToRussian() {
    let sources = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    for source in sources {
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if id.contains("Russian") {
                TISSelectInputSource(source)
                usleep(100_000)  // 100ms для переключения
                return
            }
        }
    }
}

// MARK: - CGEvent Helpers

/// Печатает символ через CGEvent
func typeChar(_ char: Character) {
    guard let keyInfo = keyCodeForChar(char) else {
        print("⚠️ Не найден keyCode для символа: '\(char)'")
        return
    }

    let source = CGEventSource(stateID: .hidSystemState)

    let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyInfo.code, keyDown: true)
    let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyInfo.code, keyDown: false)

    if keyInfo.shift {
        keyDown?.flags = .maskShift
        keyUp?.flags = .maskShift
    }

    keyDown?.post(tap: .cgSessionEventTap)
    keyUp?.post(tap: .cgSessionEventTap)
}

/// Печатает текст посимвольно
func typeText(_ text: String, layout: String = "en") {
    // Переключаем раскладку если нужно
    let needsRussian = text.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF }

    if needsRussian {
        switchToRussian()
    } else {
        switchToEnglish()
    }

    for char in text {
        typeChar(char)
        usleep(30_000)  // 30ms между символами
    }
}

/// Симулирует Double Cmd (два нажатия Cmd с паузой)
func simulateDoubleCmd() {
    let source = CGEventSource(stateID: .hidSystemState)
    let cmdKeyCode: CGKeyCode = 0x37  // Left Command

    // ═══ Первое нажатие Cmd ═══
    let press1 = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true)
    press1?.flags = .maskCommand
    press1?.post(tap: .cgSessionEventTap)
    usleep(50_000)  // 50ms удержание

    let release1 = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false)
    release1?.post(tap: .cgSessionEventTap)
    usleep(150_000)  // 150ms между нажатиями (меньше 400ms для Double Cmd)

    // ═══ Второе нажатие Cmd ═══
    let press2 = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true)
    press2?.flags = .maskCommand
    press2?.post(tap: .cgSessionEventTap)
    usleep(50_000)  // 50ms удержание

    let release2 = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false)
    release2?.post(tap: .cgSessionEventTap)

    // Ждём завершения замены в Dictum
    usleep(700_000)  // 700ms для надёжности
}

/// Получает весь текст из активного приложения через Cmd+A, Cmd+C
func getTextFromApp() -> String? {
    let source = CGEventSource(stateID: .hidSystemState)

    // Cmd+A (Select All)
    let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true)
    let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false)
    aDown?.flags = .maskCommand
    aUp?.flags = .maskCommand
    aDown?.post(tap: .cgSessionEventTap)
    aUp?.post(tap: .cgSessionEventTap)
    usleep(100_000)

    // Cmd+C (Copy)
    let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
    let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
    cDown?.flags = .maskCommand
    cUp?.flags = .maskCommand
    cDown?.post(tap: .cgSessionEventTap)
    cUp?.post(tap: .cgSessionEventTap)
    usleep(150_000)  // Больше времени для копирования

    return NSPasteboard.general.string(forType: .string)
}

/// Очищает документ (Cmd+A, Delete)
func clearDocument() {
    let source = CGEventSource(stateID: .hidSystemState)

    // Cmd+A
    let aDown = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: true)
    aDown?.flags = .maskCommand
    aDown?.post(tap: .cgSessionEventTap)
    let aUp = CGEvent(keyboardEventSource: source, virtualKey: 0x00, keyDown: false)
    aUp?.flags = .maskCommand
    aUp?.post(tap: .cgSessionEventTap)
    usleep(50_000)

    // Delete
    let delDown = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: true)
    delDown?.post(tap: .cgSessionEventTap)
    let delUp = CGEvent(keyboardEventSource: source, virtualKey: 0x33, keyDown: false)
    delUp?.post(tap: .cgSessionEventTap)
    usleep(100_000)
}

// MARK: - Test Runner

struct TestResult {
    let test: TestCase
    let actual: String
    let passed: Bool
}

/// Запускает один тест
func runSingleTest(_ test: TestCase) -> TestResult {
    // 1. Очистить документ
    clearDocument()
    usleep(200_000)

    // 2. Ввести текст (определяем раскладку автоматически)
    typeText(test.input)
    usleep(300_000)

    // 3. Симулировать Double Cmd
    simulateDoubleCmd()

    // 4. Получить результат
    let result = getTextFromApp() ?? ""
    let trimmedResult = result.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedExpected = test.expected.trimmingCharacters(in: .whitespacesAndNewlines)

    let passed = trimmedResult == trimmedExpected

    return TestResult(test: test, actual: result, passed: passed)
}

/// Запускает все тесты указанной категории
func runTestsForCategory(_ category: String) -> [TestResult] {
    let tests = allTestCases.filter { $0.category == category }
    var results: [TestResult] = []

    for test in tests {
        let result = runSingleTest(test)
        results.append(result)
        usleep(500_000)  // Пауза между тестами
    }

    return results
}

/// Запускает все тесты
func runAllTests() -> [TestResult] {
    var results: [TestResult] = []

    for test in allTestCases {
        let result = runSingleTest(test)
        results.append(result)

        // Печатаем результат сразу
        if result.passed {
            print("✅ [\(test.category)] \(test.description)")
        } else {
            print("❌ [\(test.category)] \(test.description)")
            print("   Input:    '\(test.input)'")
            print("   Expected: '\(test.expected)'")
            print("   Actual:   '\(result.actual)'")
        }

        usleep(500_000)  // Пауза между тестами
    }

    return results
}

// MARK: - Report Generation

func printReport(_ results: [TestResult]) {
    let passed = results.filter { $0.passed }.count
    let failed = results.count - passed

    print("\n" + String(repeating: "═", count: 60))
    print("ИТОГИ ТЕСТИРОВАНИЯ")
    print(String(repeating: "═", count: 60))
    print("Всего тестов: \(results.count)")
    print("✅ Успешно:   \(passed)")
    print("❌ Провалено: \(failed)")

    if failed > 0 {
        print("\n" + String(repeating: "─", count: 60))
        print("ПРОВАЛЫ ПО КАТЕГОРИЯМ:")
        print(String(repeating: "─", count: 60))

        let failedByCategory = Dictionary(grouping: results.filter { !$0.passed }) { $0.test.category }
        for (category, failures) in failedByCategory.sorted(by: { $0.key < $1.key }) {
            print("\n📁 \(category): \(failures.count) провалов")
            for failure in failures {
                print("   • \(failure.test.input) → '\(failure.actual)' (ожидалось '\(failure.test.expected)')")
            }
        }

        print("\n" + String(repeating: "─", count: 60))
        print("ГДЕ ИСКАТЬ ПРОБЛЕМУ:")
        print(String(repeating: "─", count: 60))

        for category in failedByCategory.keys.sorted() {
            switch category {
            case "basic_en_to_ru", "basic_ru_to_en":
                print("• \(category): LayoutMaps.convert() или detectLayout()")
            case "punctuation_end", "multi_punct":
                print("• \(category): selectWordBackward() НЕ выделяет пунктуацию")
            case "after_space", "punct_space":
                print("• \(category): wordBuffer vs lastProcessedWord")
            case "long_text":
                print("• \(category): replaceLastWordViaSelection() удаляет лишнее")
            case "single_char", "short_word":
                print("• \(category): Минимальная длина слова в KeyboardMonitor")
            case "with_numbers":
                print("• \(category): Обработка цифр в слове")
            default:
                print("• \(category): Неизвестная категория")
            }
        }
    }

    print("\n" + String(repeating: "═", count: 60))
}

// MARK: - Main Entry Point

@main
struct DoubleCmdE2ETesterApp {
    static func main() {
        runApp()
    }
}

func runApp() {
    print("""
    ╔══════════════════════════════════════════════════════════╗
    ║        Double Cmd E2E Tester v1.0                        ║
    ║        Тестирование РЕАЛЬНОЙ функции Double Cmd          ║
    ╠══════════════════════════════════════════════════════════╣
    ║  ВАЖНО:                                                  ║
    ║  1. Dictum должен быть ЗАПУЩЕН                          ║
    ║  2. TextEdit откроется автоматически                     ║
    ║  3. НЕ трогайте мышь/клавиатуру во время теста          ║
    ╚══════════════════════════════════════════════════════════╝
    """)

    // Проверяем аргументы
    let args = CommandLine.arguments

    if args.contains("--help") || args.contains("-h") {
        print("""

        Использование:
          DoubleCmdE2ETester              Запустить все тесты
          DoubleCmdE2ETester --category X Запустить только категорию X
          DoubleCmdE2ETester --list       Показать все категории

        Категории:
          basic_en_to_ru    Базовые EN → RU
          basic_ru_to_en    Базовые RU → EN
          punctuation_end   Пунктуация в конце
          multi_punct       Множественная пунктуация
          after_space       После пробела
          punct_space       Пунктуация + пробел
          long_text         Длинный текст
          single_char       Одиночные символы
          short_word        Короткие слова (2-3 символа)
          with_numbers      С цифрами
        """)
        return
    }

    if args.contains("--list") {
        let categories = Set(allTestCases.map { $0.category }).sorted()
        print("\nДоступные категории (\(categories.count)):")
        for cat in categories {
            let count = allTestCases.filter { $0.category == cat }.count
            print("  • \(cat) (\(count) тестов)")
        }
        return
    }

    // Открываем TextEdit
    print("\n🚀 Открываю TextEdit...")
    NSWorkspace.shared.launchApplication("TextEdit")
    sleep(2)  // Ждём открытия

    // Создаём новый документ (Cmd+N)
    print("📄 Создаю новый документ...")
    let source = CGEventSource(stateID: .hidSystemState)
    let nDown = CGEvent(keyboardEventSource: source, virtualKey: 0x2D, keyDown: true)
    nDown?.flags = .maskCommand
    nDown?.post(tap: .cgSessionEventTap)
    let nUp = CGEvent(keyboardEventSource: source, virtualKey: 0x2D, keyDown: false)
    nUp?.flags = .maskCommand
    nUp?.post(tap: .cgSessionEventTap)
    sleep(1)

    // Запускаем тесты
    var results: [TestResult]

    if let categoryIndex = args.firstIndex(of: "--category"), categoryIndex + 1 < args.count {
        let category = args[categoryIndex + 1]
        print("\n🧪 Запуск тестов категории: \(category)\n")
        results = runTestsForCategory(category)
    } else {
        print("\n🧪 Запуск ВСЕХ тестов (\(allTestCases.count) штук)\n")
        results = runAllTests()
    }

    // Выводим отчёт
    printReport(results)

    // Возвращаем exit code
    let failed = results.filter { !$0.passed }.count
    exit(Int32(failed > 0 ? 1 : 0))
}
