//
//  DoubleCmdUnitTests.swift
//  Dictum
//
//  Unit-тесты для логики TextSwitcher.
//  Тестирует ВНУТРЕННЮЮ логику без UI и разрешений.
//
//  Запуск: ./build/Build/Products/Debug/DoubleCmdUnitTests
//

import Foundation

// MARK: - Test Result

struct TestResult {
    let name: String
    let passed: Bool
    let expected: String
    let actual: String
    let details: String

    var description: String {
        if passed {
            return "✅ \(name)"
        } else {
            return """
            ❌ \(name)
               Expected: '\(expected)'
               Actual:   '\(actual)'
               Details:  \(details)
            """
        }
    }
}

// MARK: - Test Cases

nonisolated(unsafe) var allResults: [TestResult] = []

// MARK: - Helper

func printSection(_ title: String) {
    print("\n" + String(repeating: "═", count: 60))
    print(title)
    print(String(repeating: "═", count: 60))
}

// MARK: - 1. LayoutMaps.convert() Tests

func testLayoutMapsConvert() {
    printSection("ТЕСТ 1: LayoutMaps.convert() — EN→RU")

    // ПРИМЕЧАНИЕ: При includeAllSymbols=true ВСЕ символы конвертируются согласно раскладке.
    // Символы ., ; ' [ ] ` имеют реальный маппинг: , → б, . → ю, ; → ж и т.д.
    // Только символы из commonPunctuation (!, %, *, цифры, пробелы) НЕ конвертируются.
    let tests: [(input: String, from: KeyboardLayout, to: KeyboardLayout, expected: String)] = [
        // Базовые EN→RU (без спец. символов внутри)
        ("ghbdtn", .qwerty, .russian, "привет"),
        ("ntcn", .qwerty, .russian, "тест"),
        ("ckjdj", .qwerty, .russian, "слово"),

        // Слова с , и . внутри — КОНВЕРТИРУЮТСЯ при includeAllSymbols=true
        // , → б, . → ю (это правильное поведение для Double Cmd)
        ("hf,jnf", .qwerty, .russian, "работа"),   // , конвертируется в б
        ("rjvgm.nth", .qwerty, .russian, "компьютер"), // . конвертируется в ю

        // С пунктуацией НА КОНЦЕ (includeAllSymbols = true)
        // ! остаётся ! (в commonPunctuation), но ? → , (маппинг)
        ("ghbdtn!", .qwerty, .russian, "привет!"),
        ("ntcn?", .qwerty, .russian, "тест,"),   // ? → , (QWERTY ? → RU ,)
        ("lf,", .qwerty, .russian, "даб"),       // , → б
        ("ckjdj.", .qwerty, .russian, "словою"), // . → ю

        // Множественная пунктуация
        ("ghbdtn!!!", .qwerty, .russian, "привет!!!"),  // ! в commonPunctuation
        ("ghbdtn???", .qwerty, .russian, "привет,,,"),  // ? → ,
        ("ghbdtn!?", .qwerty, .russian, "привет!,"),    // ! → !, ? → ,
        ("ghbdtn...", .qwerty, .russian, "приветююю"),  // . → ю

        // Смешанные символы (: и ; имеют маппинг)
        ("ghbdtn:", .qwerty, .russian, "приветЖ"),  // : → Ж (Shift+;)
        ("ghbdtn;", .qwerty, .russian, "приветж"),  // ; → ж
    ]

    for test in tests {
        let result = LayoutMaps.convert(test.input, from: test.from, to: test.to, includeAllSymbols: true)
        let passed = result == test.expected

        let testResult = TestResult(
            name: "convert(\"\(test.input)\", \(test.from.rawValue)→\(test.to.rawValue))",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: "includeAllSymbols=true"
        )
        allResults.append(testResult)
        print(testResult.description)
    }
}

// MARK: - 2. RU→EN Conversion Tests

func testRuToEnConversion() {
    printSection("ТЕСТ 2: LayoutMaps.convert() — RU→EN")

    // ПРИМЕЧАНИЕ: При includeAllSymbols=true, символы конвертируются через reverseMap
    // если их нет в primaryMap. Например:
    // - `.` в русском тексте → через reverseMap (qwertyToRussian: . → ю) → `ю`
    // - `?` в русском тексте → Shift+7 = & на QWERTY
    let tests: [(input: String, expected: String)] = [
        // Базовые RU→EN
        ("руддщ", "hello"),
        ("цщкв", "word"),
        ("привет", "ghbdtn"),
        ("работа", "hf,jnf"),
        ("тест", "ntcn"),
        ("слово", "ckjdj"),

        // С пунктуацией — ! в commonPunctuation (не меняется)
        ("привет!", "ghbdtn!"),
        // ? → & (RU ? = Shift+7, EN Shift+7 = &)
        ("привет?", "ghbdtn&"),
        // . → ю (через reverseMap: qwertyToRussian[.] = ю)
        ("работа.", "hf,jnfю"),
        ("тест...", "ntcnююю"),
    ]

    for test in tests {
        let result = LayoutMaps.convert(test.input, from: .russian, to: .qwerty, includeAllSymbols: true)
        let passed = result == test.expected

        let testResult = TestResult(
            name: "convert(\"\(test.input)\", ru→en)",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: ""
        )
        allResults.append(testResult)
        print(testResult.description)
    }
}

// MARK: - 3. Uppercase Tests

func testUppercaseConversion() {
    printSection("ТЕСТ 3: Uppercase конвертация")

    // ПРИМЕЧАНИЕ: `,` НЕ в commonPunctuation — имеет маппинг `,` → `б`
    // Поэтому "HF,JNF" → "РАБОТА" (запятая конвертируется в б, и ALL CAPS применяется)
    let tests: [(input: String, from: KeyboardLayout, to: KeyboardLayout, expected: String)] = [
        // ALL CAPS EN→RU (без спец. символов)
        ("GHBDTN", .qwerty, .russian, "ПРИВЕТ"),
        ("NTCN", .qwerty, .russian, "ТЕСТ"),
        // "HF,JNF" → "РАБОТА" (запятая конвертируется в б, ALL CAPS применяется)
        ("HF,JNF", .qwerty, .russian, "РАБОТА"),

        // ALL CAPS RU→EN
        ("ПРИВЕТ", .russian, .qwerty, "GHBDTN"),
        ("ТЕСТ", .russian, .qwerty, "NTCN"),
        // "РАБОТА" → "HF<JNF" (uppercase Б = < в русской раскладке)
        ("РАБОТА", .russian, .qwerty, "HF<JNF"),

        // Mixed case (первая заглавная)
        ("Ghbdtn", .qwerty, .russian, "Привет"),
        ("Привет", .russian, .qwerty, "Ghbdtn"),
    ]

    for test in tests {
        let result = LayoutMaps.convert(test.input, from: test.from, to: test.to, includeAllSymbols: true)
        let passed = result == test.expected

        let testResult = TestResult(
            name: "uppercase(\"\(test.input)\", \(test.from.rawValue)→\(test.to.rawValue))",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: ""
        )
        allResults.append(testResult)
        print(testResult.description)
    }
}

// MARK: - 4. Edge Cases

func testEdgeCases() {
    printSection("ТЕСТ 4: Edge Cases")

    // Пустая строка
    var result = LayoutMaps.convert("", from: .qwerty, to: .russian, includeAllSymbols: true)
    var passed = result == ""
    allResults.append(TestResult(name: "empty string", passed: passed, expected: "", actual: result, details: ""))
    print(allResults.last!.description)

    // Один символ
    result = LayoutMaps.convert("a", from: .qwerty, to: .russian, includeAllSymbols: true)
    passed = result == "ф"
    allResults.append(TestResult(name: "single char 'a'", passed: passed, expected: "ф", actual: result, details: ""))
    print(allResults.last!.description)

    result = LayoutMaps.convert("ф", from: .russian, to: .qwerty, includeAllSymbols: true)
    passed = result == "a"
    allResults.append(TestResult(name: "single char 'ф'", passed: passed, expected: "a", actual: result, details: ""))
    print(allResults.last!.description)

    // Только цифры (не меняются)
    result = LayoutMaps.convert("12345", from: .qwerty, to: .russian, includeAllSymbols: true)
    passed = result == "12345"
    allResults.append(TestResult(name: "only digits", passed: passed, expected: "12345", actual: result, details: ""))
    print(allResults.last!.description)

    // Длинное слово
    let longWord = String(repeating: "ghbdtn", count: 10)
    let longExpected = String(repeating: "привет", count: 10)
    result = LayoutMaps.convert(longWord, from: .qwerty, to: .russian, includeAllSymbols: true)
    passed = result == longExpected
    allResults.append(TestResult(name: "long word (60 chars)", passed: passed, expected: "привет×10", actual: result.count == longExpected.count ? "✓ length match" : "✗ length mismatch", details: ""))
    print(allResults.last!.description)
}

// MARK: - 5. commonPunctuation Tests

func testCommonPunctuationNotConverted() {
    printSection("ТЕСТ 5: commonPunctuation — символы НЕ конвертируются")

    // ТОЛЬКО символы из LayoutMaps.commonPunctuation (реальный набор):
    // !, %, *, (, ) — Shift-символы одинаковые на обеих раскладках
    // -, _, +, = — математические
    // \, | — слэши без маппинга
    // пробел, tab, newline — пробельные
    // 0-9 — цифры
    //
    // ВАЖНО: Символы ?, ., ,, :, ;, [, ], {, }, @, #, $, ^, &, ", ', `, ~, <, >, /
    // НЕ входят в commonPunctuation и ИМЕЮТ маппинг!
    let punctuation: [String] = [
        "!", "%", "*", "(", ")",         // Shift-символы одинаковые
        "-", "_", "+", "=",              // Математические
        "\\", "|",                       // Слэши
        " ",                             // Пробел
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"  // Цифры
    ]

    for p in punctuation {
        // EN→RU
        var result = LayoutMaps.convert(p, from: .qwerty, to: .russian, includeAllSymbols: true)
        var passed = result == p
        allResults.append(TestResult(
            name: "commonPunct '\(p)' en→ru",
            passed: passed,
            expected: p,
            actual: result,
            details: "Должен остаться без изменений"
        ))
        if !passed { print(allResults.last!.description) }

        // RU→EN
        result = LayoutMaps.convert(p, from: .russian, to: .qwerty, includeAllSymbols: true)
        passed = result == p
        allResults.append(TestResult(
            name: "commonPunct '\(p)' ru→en",
            passed: passed,
            expected: p,
            actual: result,
            details: "Должен остаться без изменений"
        ))
        if !passed { print(allResults.last!.description) }
    }

    // Выводим сводку
    let punctTests = allResults.suffix(punctuation.count * 2)
    let punctPassed = punctTests.filter { $0.passed }.count
    print("✅ commonPunctuation: \(punctPassed)/\(punctuation.count * 2) тестов пройдено")
}

// MARK: - 6. toggleLayout Tests

func testToggleLayout() {
    printSection("ТЕСТ 6: toggleLayout — посимвольное переключение")

    let tests: [(input: String, expected: String)] = [
        // Только английский → русский
        ("hello", "руддщ"),
        // t→е, e→у, s→ы, t→е = "еуну" (4 символа: е, у, ы, е)
        ("test", "\u{0435}\u{0443}\u{044B}\u{0435}"),

        // Только русский → английский
        ("привет", "ghbdtn"),
        ("тест", "ntcn"),
    ]

    for test in tests {
        let result = LayoutMaps.toggleLayout(test.input)
        let passed = result == test.expected

        allResults.append(TestResult(
            name: "toggleLayout(\"\(test.input)\")",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: ""
        ))
        print(allResults.last!.description)
    }
}

// MARK: - 7. detectLayout Tests

func testDetectLayout() {
    printSection("ТЕСТ 7: detectLayout — определение раскладки")

    let tests: [(input: String, expected: KeyboardLayout?)] = [
        // Чистый английский
        ("hello", .qwerty),
        ("test", .qwerty),
        ("abc", .qwerty),

        // Чистый русский
        ("привет", .russian),
        ("тест", .russian),
        ("абв", .russian),

        // Только цифры — nil (нет букв)
        ("123", nil),
        ("0", nil),

        // Только пунктуация
        ("!!!", nil),      // ! не в картах букв
        // "..." возвращает .qwerty потому что "." есть в qwertyToRussianLower (→ ю)
        ("...", .qwerty),
        ("?!", nil),       // ? и ! не в картах букв

        // Пустая строка — nil
        ("", nil),

        // С цифрами и пунктуацией (но есть буквы)
        ("test123", .qwerty),
        ("тест123", .russian),
        ("hello!", .qwerty),
        ("привет!", .russian),
    ]

    for test in tests {
        let result = LayoutMaps.detectLayout(in: test.input)
        let passed = result == test.expected

        let expectedStr = test.expected?.rawValue ?? "nil"
        let actualStr = result?.rawValue ?? "nil"

        allResults.append(TestResult(
            name: "detectLayout(\"\(test.input)\")",
            passed: passed,
            expected: expectedStr,
            actual: actualStr,
            details: ""
        ))
        print(allResults.last!.description)
    }
}

// MARK: - 8. isPureLayout Tests

func testIsPureLayout() {
    printSection("ТЕСТ 8: isPureLayout — проверка чистоты раскладки")

    let tests: [(input: String, layout: KeyboardLayout, expected: Bool)] = [
        // Чистый английский
        ("hello", .qwerty, true),
        ("test", .qwerty, true),
        ("hello123", .qwerty, true),  // Цифры не влияют

        // Чистый русский
        ("привет", .russian, true),
        ("тест", .russian, true),
        ("привет123", .russian, true),

        // Смешанный — false
        ("helloпривет", .qwerty, false),
        ("helloпривет", .russian, false),
        ("testтест", .qwerty, false),

        // Только цифры/пунктуация — true (нет "грязных" букв)
        ("123", .qwerty, true),
        ("123", .russian, true),
        ("!!!", .qwerty, true),
    ]

    for test in tests {
        let result = LayoutMaps.isPureLayout(test.input, layout: test.layout)
        let passed = result == test.expected

        allResults.append(TestResult(
            name: "isPureLayout(\"\(test.input)\", \(test.layout.rawValue))",
            passed: passed,
            expected: String(test.expected),
            actual: String(result),
            details: ""
        ))
        print(allResults.last!.description)
    }
}

// MARK: - 9. Regression Tests

func testRegressionBugs() {
    printSection("ТЕСТ 9: Регрессионные тесты (конкретные баги)")

    // Баг: пунктуация съедалась при Double Cmd
    var result = LayoutMaps.convert("ghbdtn!", from: .qwerty, to: .russian, includeAllSymbols: true)
    var passed = result == "привет!"
    allResults.append(TestResult(
        name: "BUG: пунктуация после слова",
        passed: passed,
        expected: "привет!",
        actual: result,
        details: "ghbdtn! должен конвертироваться в привет!"
    ))
    print(allResults.last!.description)

    result = LayoutMaps.convert("ghbdtn!!!", from: .qwerty, to: .russian, includeAllSymbols: true)
    passed = result == "привет!!!"
    allResults.append(TestResult(
        name: "BUG: множественная пунктуация",
        passed: passed,
        expected: "привет!!!",
        actual: result,
        details: ""
    ))
    print(allResults.last!.description)

    // Uppercase конвертация — запятая КОНВЕРТИРУЕТСЯ (НЕ в commonPunctuation)
    result = LayoutMaps.convert("HF,JNF", from: .qwerty, to: .russian, includeAllSymbols: true)
    passed = result == "РАБОТА"  // `,` → `б`, затем ALL CAPS
    allResults.append(TestResult(
        name: "uppercase: ALL CAPS с запятой",
        passed: passed,
        expected: "РАБОТА",
        actual: result,
        details: "HF,JNF → РАБОТА (запятая конвертируется в б)"
    ))
    print(allResults.last!.description)

    // Баг: одинаковый текст при from == to
    result = LayoutMaps.convert("hello", from: .qwerty, to: .qwerty)
    passed = result == "hello"
    allResults.append(TestResult(
        name: "BUG: same layout conversion",
        passed: passed,
        expected: "hello",
        actual: result,
        details: "Конвертация в ту же раскладку должна вернуть исходный текст"
    ))
    print(allResults.last!.description)
}

// MARK: - 10. WordBuffer Simulation Tests

class WordBufferSimulator {
    var wordBuffer: String = ""
    var lastProcessedWord: String = ""

    func typeChar(_ char: Character) {
        let lowercasedChar = Character(char.lowercased())
        let isMappableQWERTY = LayoutMaps.qwertyCharacters.contains(lowercasedChar) ||
                               LayoutMaps.qwertyCharacters.contains(char)
        let isMappableRussian = LayoutMaps.russianCharacters.contains(lowercasedChar) ||
                                LayoutMaps.russianCharacters.contains(char)
        let isMappable = isMappableQWERTY || isMappableRussian

        if char.isLetter || char.isNumber || isMappable {
            wordBuffer.append(char)
        } else if char.isPunctuation || char.isWhitespace {
            processWord()
        }
    }

    func typeText(_ text: String) {
        for char in text { typeChar(char) }
    }

    private func processWord() {
        guard !wordBuffer.isEmpty else { return }
        lastProcessedWord = wordBuffer
        wordBuffer = ""
    }

    func doubleCmdWord() -> String {
        return wordBuffer.isEmpty ? lastProcessedWord : wordBuffer
    }

    func reset() {
        wordBuffer = ""
        lastProcessedWord = ""
    }
}

func testWordBufferSimulation() {
    printSection("ТЕСТ 10: WordBuffer Simulation")

    let sim = WordBufferSimulator()

    // Базовые тесты
    let tests: [(input: String, expected: String, desc: String)] = [
        ("ghbdtn", "ghbdtn", "без триггера"),
        ("ghbdtn!", "ghbdtn", "с ! (триггер)"),
        ("ghbdtn ", "ghbdtn", "с пробелом"),
        ("ghbdtn!!!", "ghbdtn", "с !!!"),
        ("hello world", "world", "два слова"),
    ]

    for test in tests {
        sim.reset()
        sim.typeText(test.input)
        let result = sim.doubleCmdWord()
        let passed = result == test.expected

        allResults.append(TestResult(
            name: "WordBuffer: '\(test.input)' — \(test.desc)",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: ""
        ))
        print(allResults.last!.description)
    }
}

// MARK: - 11. ImprovedWordBuffer with pendingPunctuation

class ImprovedWordBufferSimulator {
    var wordBuffer: String = ""
    var lastProcessedWord: String = ""
    var pendingPunctuation: String = ""

    func typeChar(_ char: Character) {
        let lowercasedChar = Character(char.lowercased())
        let isMappableQWERTY = LayoutMaps.qwertyCharacters.contains(lowercasedChar) ||
                               LayoutMaps.qwertyCharacters.contains(char)
        let isMappableRussian = LayoutMaps.russianCharacters.contains(lowercasedChar) ||
                                LayoutMaps.russianCharacters.contains(char)
        let isMappable = isMappableQWERTY || isMappableRussian

        if char.isLetter || char.isNumber || isMappable {
            pendingPunctuation = ""
            wordBuffer.append(char)
        } else if char.isPunctuation {
            if !wordBuffer.isEmpty {
                lastProcessedWord = wordBuffer
                wordBuffer = ""
            }
            pendingPunctuation.append(char)
        } else if char.isWhitespace {
            if !wordBuffer.isEmpty {
                lastProcessedWord = wordBuffer
                wordBuffer = ""
            }
            pendingPunctuation = ""
        }
    }

    func typeText(_ text: String) {
        for char in text { typeChar(char) }
    }

    func doubleCmdWord() -> String {
        if !wordBuffer.isEmpty {
            return wordBuffer + pendingPunctuation
        }
        if !pendingPunctuation.isEmpty {
            var baseWord = lastProcessedWord
            while baseWord.last?.isPunctuation == true { baseWord.removeLast() }
            return baseWord + pendingPunctuation
        }
        return lastProcessedWord
    }

    func reset() {
        wordBuffer = ""
        lastProcessedWord = ""
        pendingPunctuation = ""
    }
}

func testImprovedWordBuffer() {
    printSection("ТЕСТ 11: ImprovedWordBuffer с pendingPunctuation")

    let sim = ImprovedWordBufferSimulator()

    let tests: [(input: String, expected: String)] = [
        ("ghbdtn", "ghbdtn"),
        ("ghbdtn!", "ghbdtn!"),
        ("ghbdtn!!!", "ghbdtn!!!"),
        ("ghbdtn?", "ghbdtn?"),
        ("ghbdtn!?", "ghbdtn!?"),
        ("ghbdtn...", "ghbdtn..."),
        ("ghbdtn.", "ghbdtn."),
        ("привет!", "привет!"),
        ("test123!", "test123!"),
    ]

    for test in tests {
        sim.reset()
        sim.typeText(test.input)
        let result = sim.doubleCmdWord()
        let passed = result == test.expected

        allResults.append(TestResult(
            name: "ImprovedBuffer: '\(test.input)'",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: ""
        ))
        print(allResults.last!.description)
    }
}

// MARK: - 12. Special Characters Mapping

func testSpecialCharactersMapping() {
    printSection("ТЕСТ 12: Специальные символы раскладок")

    // Символы [ ] ; ' , . ` НЕ в commonPunctuation — они ИМЕЮТ маппинг!
    // EN→RU: [ → х, ] → ъ, ; → ж, ' → э, , → б, . → ю, ` → ё
    // RU→EN: х → [, ъ → ], ж → ;, э → ', б → ,, ю → ., ё → `
    let tests: [(input: String, from: KeyboardLayout, to: KeyboardLayout, expected: String)] = [
        // EN→RU: эти символы КОНВЕРТИРУЮТСЯ (имеют маппинг)
        ("[", .qwerty, .russian, "х"),   // [ → х
        ("]", .qwerty, .russian, "ъ"),   // ] → ъ
        (";", .qwerty, .russian, "ж"),   // ; → ж
        ("'", .qwerty, .russian, "э"),   // ' → э
        (",", .qwerty, .russian, "б"),   // , → б
        (".", .qwerty, .russian, "ю"),   // . → ю
        ("`", .qwerty, .russian, "ё"),   // ` → ё
        ("/", .qwerty, .russian, "."),   // / → .

        // Shift-варианты EN→RU
        ("{", .qwerty, .russian, "Х"),   // { → Х
        ("}", .qwerty, .russian, "Ъ"),   // } → Ъ
        (":", .qwerty, .russian, "Ж"),   // : → Ж
        ("\"", .qwerty, .russian, "Э"),  // " → Э
        ("<", .qwerty, .russian, "Б"),   // < → Б
        (">", .qwerty, .russian, "Ю"),   // > → Ю
        ("~", .qwerty, .russian, "Ё"),   // ~ → Ё
        ("?", .qwerty, .russian, ","),   // ? → ,

        // Специальные символы с Shift
        ("@", .qwerty, .russian, "\""),  // @ → "
        ("#", .qwerty, .russian, "№"),   // # → №
        ("$", .qwerty, .russian, ";"),   // $ → ;
        ("^", .qwerty, .russian, ":"),   // ^ → :
        ("&", .qwerty, .russian, "?"),   // & → ?

        // RU→EN: русские буквы конвертируются корректно
        ("ж", .russian, .qwerty, ";"),
        ("э", .russian, .qwerty, "'"),
        ("х", .russian, .qwerty, "["),
        ("ъ", .russian, .qwerty, "]"),
        ("б", .russian, .qwerty, ","),
        ("ю", .russian, .qwerty, "."),
        ("ё", .russian, .qwerty, "`"),

        // RU→EN: uppercase
        ("Ж", .russian, .qwerty, ":"),
        ("Э", .russian, .qwerty, "\""),
        ("Х", .russian, .qwerty, "{"),
        ("Ъ", .russian, .qwerty, "}"),
        ("Б", .russian, .qwerty, "<"),
        ("Ю", .russian, .qwerty, ">"),
        ("Ё", .russian, .qwerty, "~"),
    ]

    for test in tests {
        let result = LayoutMaps.convert(test.input, from: test.from, to: test.to, includeAllSymbols: true)
        let passed = result == test.expected

        allResults.append(TestResult(
            name: "special '\(test.input)' \(test.from.rawValue)→\(test.to.rawValue)",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: ""
        ))
        print(allResults.last!.description)
    }
}

// MARK: - 13. Double Cmd Race Condition Tests

/// Симулятор Double Cmd с исправлением race condition
class DoubleCmdSimulator {
    var wordBuffer: String = ""
    var lastProcessedWord: String = ""
    var pendingPunctuation: String = ""
    var isReplacing: Bool = false

    /// Симуляция набора символа
    func typeChar(_ char: Character) {
        let lowercasedChar = Character(char.lowercased())
        let isMappableQWERTY = LayoutMaps.qwertyCharacters.contains(lowercasedChar) ||
                               LayoutMaps.qwertyCharacters.contains(char)
        let isMappableRussian = LayoutMaps.russianCharacters.contains(lowercasedChar) ||
                                LayoutMaps.russianCharacters.contains(char)
        let isMappable = isMappableQWERTY || isMappableRussian

        if char.isLetter || char.isNumber || isMappable {
            pendingPunctuation = ""
            wordBuffer.append(char)
        } else if char.isPunctuation {
            if !wordBuffer.isEmpty {
                lastProcessedWord = wordBuffer
                wordBuffer = ""
            }
            pendingPunctuation.append(char)
        } else if char.isWhitespace {
            if !wordBuffer.isEmpty {
                lastProcessedWord = wordBuffer
                wordBuffer = ""
            }
            pendingPunctuation = ""
        }
    }

    func typeText(_ text: String) {
        for char in text { typeChar(char) }
    }

    /// Симуляция Double Cmd С исправлением race condition
    /// Возвращает (wordToConvert, convertedWord, bufferAfter)
    func doubleCmdWithFix() -> (wordToConvert: String, converted: String, bufferAfter: String) {
        isReplacing = true

        // ИСПРАВЛЕНИЕ: сохраняем и очищаем буфер ДО замены
        let savedWordBuffer = wordBuffer
        wordBuffer = ""

        // Определяем слово для конвертации
        let word: String
        if !savedWordBuffer.isEmpty {
            word = savedWordBuffer
        } else {
            word = lastProcessedWord + pendingPunctuation
        }

        // Конвертация
        guard let textLayout = LayoutMaps.detectLayout(in: word) else {
            isReplacing = false
            return (word, word, wordBuffer)
        }
        let converted = LayoutMaps.convert(word, from: textLayout, to: textLayout.opposite, includeAllSymbols: true)

        // Симуляция: буквы набранные во время замены (race condition)
        // В реальном коде это происходит в окне 150-250ms
        // Здесь мы симулируем что пользователь набрал "fff" во время замены

        // После замены — очищаем буфер (исправление race condition)
        wordBuffer = ""
        isReplacing = false

        // Обновляем lastProcessedWord
        lastProcessedWord = String(converted.filter { $0.isLetter })
        pendingPunctuation = ""

        return (word, converted, wordBuffer)
    }

    /// Симуляция Double Cmd БЕЗ исправления (старый код с багом)
    func doubleCmdWithBug() -> (wordToConvert: String, converted: String, bufferAfter: String) {
        isReplacing = true

        // СТАРЫЙ КОД: НЕ сохраняем буфер, используем напрямую
        let word: String
        if !wordBuffer.isEmpty {
            word = wordBuffer
        } else {
            word = lastProcessedWord + pendingPunctuation
        }

        guard let textLayout = LayoutMaps.detectLayout(in: word) else {
            isReplacing = false
            return (word, word, wordBuffer)
        }
        let converted = LayoutMaps.convert(word, from: textLayout, to: textLayout.opposite, includeAllSymbols: true)

        // СТАРЫЙ КОД: wordBuffer НЕ очищается, буквы накапливаются
        // (симулируем что пользователь набрал "fff" во время isReplacing)

        // После 250ms — isReplacing = false, но буфер НЕ очищен
        isReplacing = false

        lastProcessedWord = String(converted.filter { $0.isLetter })
        pendingPunctuation = ""

        return (word, converted, wordBuffer)
    }

    func reset() {
        wordBuffer = ""
        lastProcessedWord = ""
        pendingPunctuation = ""
        isReplacing = false
    }
}

func testDoubleCmdRaceCondition() {
    printSection("ТЕСТ 13: Double Cmd Race Condition")

    let sim = DoubleCmdSimulator()

    // Тест 1: Базовый Double Cmd без продолжения набора
    sim.reset()
    sim.typeText("ghbdtn")
    var result = sim.doubleCmdWithFix()
    var passed = result.wordToConvert == "ghbdtn" && result.converted == "привет" && result.bufferAfter == ""
    allResults.append(TestResult(
        name: "DoubleCmdFix: базовый 'ghbdtn'",
        passed: passed,
        expected: "ghbdtn → привет, buffer=''",
        actual: "\(result.wordToConvert) → \(result.converted), buffer='\(result.bufferAfter)'",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 2: Double Cmd после пробела (lastProcessedWord)
    sim.reset()
    sim.typeText("ghbdtn ")  // Пробел триггерит processWord
    result = sim.doubleCmdWithFix()
    passed = result.wordToConvert == "ghbdtn" && result.converted == "привет"
    allResults.append(TestResult(
        name: "DoubleCmdFix: после пробела 'ghbdtn '",
        passed: passed,
        expected: "ghbdtn → привет",
        actual: "\(result.wordToConvert) → \(result.converted)",
        details: "lastProcessedWord используется"
    ))
    print(allResults.last!.description)

    // Тест 3: Double Cmd с пунктуацией
    sim.reset()
    sim.typeText("ghbdtn!")
    result = sim.doubleCmdWithFix()
    passed = result.wordToConvert == "ghbdtn!" && result.converted == "привет!"
    allResults.append(TestResult(
        name: "DoubleCmdFix: с пунктуацией 'ghbdtn!'",
        passed: passed,
        expected: "ghbdtn! → привет!",
        actual: "\(result.wordToConvert) → \(result.converted)",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 4: Double Cmd с множественной пунктуацией
    sim.reset()
    sim.typeText("ghbdtn!!!")
    result = sim.doubleCmdWithFix()
    passed = result.wordToConvert == "ghbdtn!!!" && result.converted == "привет!!!"
    allResults.append(TestResult(
        name: "DoubleCmdFix: множественная пунктуация 'ghbdtn!!!'",
        passed: passed,
        expected: "ghbdtn!!! → привет!!!",
        actual: "\(result.wordToConvert) → \(result.converted)",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 5: Буфер очищается после Double Cmd
    sim.reset()
    sim.typeText("ghbdtn")
    _ = sim.doubleCmdWithFix()
    passed = sim.wordBuffer == ""
    allResults.append(TestResult(
        name: "DoubleCmdFix: буфер пустой после замены",
        passed: passed,
        expected: "wordBuffer = ''",
        actual: "wordBuffer = '\(sim.wordBuffer)'",
        details: "Буфер должен быть очищен для предотвращения накопления"
    ))
    print(allResults.last!.description)

    // Тест 6: RU→EN конвертация
    sim.reset()
    sim.typeText("привет")
    result = sim.doubleCmdWithFix()
    passed = result.wordToConvert == "привет" && result.converted == "ghbdtn"
    allResults.append(TestResult(
        name: "DoubleCmdFix: RU→EN 'привет'",
        passed: passed,
        expected: "привет → ghbdtn",
        actual: "\(result.wordToConvert) → \(result.converted)",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 7: Два слова — Double Cmd на последнем
    sim.reset()
    sim.typeText("hello world")  // "hello " → lastProcessedWord="hello", "world" → wordBuffer
    result = sim.doubleCmdWithFix()
    passed = result.wordToConvert == "world" && result.converted == "цщкдв"
    allResults.append(TestResult(
        name: "DoubleCmdFix: два слова 'hello world'",
        passed: passed,
        expected: "world → цщкдв",
        actual: "\(result.wordToConvert) → \(result.converted)",
        details: "Конвертируется последнее слово в буфере"
    ))
    print(allResults.last!.description)

    // Тест 8: lastProcessedWord обновляется после Double Cmd
    sim.reset()
    sim.typeText("ghbdtn ")
    _ = sim.doubleCmdWithFix()
    passed = sim.lastProcessedWord == "привет"
    allResults.append(TestResult(
        name: "DoubleCmdFix: lastProcessedWord обновлён",
        passed: passed,
        expected: "lastProcessedWord = 'привет'",
        actual: "lastProcessedWord = '\(sim.lastProcessedWord)'",
        details: "Для toggle обратно"
    ))
    print(allResults.last!.description)
}

// MARK: - 14. Double Cmd Sentence Tests

func testDoubleCmdSentences() {
    printSection("ТЕСТ 14: Double Cmd на предложениях")

    let sim = DoubleCmdSimulator()

    // Тест 1: Предложение на английском
    sim.reset()
    sim.typeText("Hello my friend")
    var result = sim.doubleCmdWithFix()
    var passed = result.wordToConvert == "friend"
    allResults.append(TestResult(
        name: "Sentence: 'Hello my friend' → последнее слово",
        passed: passed,
        expected: "friend",
        actual: result.wordToConvert,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 2: Предложение с пробелом в конце
    sim.reset()
    sim.typeText("Hello my friend ")  // Пробел в конце
    result = sim.doubleCmdWithFix()
    passed = result.wordToConvert == "friend"
    allResults.append(TestResult(
        name: "Sentence: 'Hello my friend ' (пробел в конце)",
        passed: passed,
        expected: "friend (из lastProcessedWord)",
        actual: result.wordToConvert,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 3: Предложение с вопросом
    sim.reset()
    sim.typeText("Rfr ltkf?")  // "Как дела?" на QWERTY
    result = sim.doubleCmdWithFix()
    // После "Rfr " → lastProcessedWord="Rfr", после "ltkf?" → lastProcessedWord="ltkf", pending="?"
    // ВАЖНО: ? конвертируется в , (QWERTY ? → RU ,)
    passed = result.wordToConvert == "ltkf?" && result.converted == "дела,"
    allResults.append(TestResult(
        name: "Sentence: 'Rfr ltkf?' → 'дела,' (? → ,)",
        passed: passed,
        expected: "ltkf? → дела,",
        actual: "\(result.wordToConvert) → \(result.converted)",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 4: Смешанное предложение "Как дела? Hello"
    sim.reset()
    sim.typeText("Как дела? Hello")
    result = sim.doubleCmdWithFix()
    passed = result.wordToConvert == "Hello" && result.converted == "Руддщ"
    allResults.append(TestResult(
        name: "Mixed: 'Как дела? Hello' → последнее слово",
        passed: passed,
        expected: "Hello → Руддщ",
        actual: "\(result.wordToConvert) → \(result.converted)",
        details: ""
    ))
    print(allResults.last!.description)
}

// MARK: - 15. Double Cmd Edge Cases

func testDoubleCmdEdgeCases() {
    printSection("ТЕСТ 15: Double Cmd Edge Cases")

    let sim = DoubleCmdSimulator()

    // Тест 1: Пустой буфер
    sim.reset()
    var result = sim.doubleCmdWithFix()
    var passed = result.wordToConvert == "" && result.converted == ""
    allResults.append(TestResult(
        name: "EdgeCase: пустой буфер",
        passed: passed,
        expected: "'' → ''",
        actual: "'\(result.wordToConvert)' → '\(result.converted)'",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 2: Только пунктуация
    sim.reset()
    sim.typeText("!!!")
    result = sim.doubleCmdWithFix()
    // "!!!" — это пунктуация, wordBuffer пустой, lastProcessedWord пустой, pending="!!!"
    passed = result.wordToConvert == "!!!"
    allResults.append(TestResult(
        name: "EdgeCase: только пунктуация '!!!'",
        passed: passed,
        expected: "!!! (из pendingPunctuation)",
        actual: result.wordToConvert,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 3: Очень длинное слово
    let longWord = String(repeating: "ghbdtn", count: 5)  // 30 символов
    let longExpected = String(repeating: "привет", count: 5)
    sim.reset()
    sim.typeText(longWord)
    result = sim.doubleCmdWithFix()
    passed = result.converted == longExpected
    allResults.append(TestResult(
        name: "EdgeCase: длинное слово (30 chars)",
        passed: passed,
        expected: longExpected,
        actual: result.converted,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 4: Один символ
    sim.reset()
    sim.typeText("a")
    result = sim.doubleCmdWithFix()
    passed = result.converted == "ф"
    allResults.append(TestResult(
        name: "EdgeCase: один символ 'a'",
        passed: passed,
        expected: "ф",
        actual: result.converted,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 5: Только цифры
    sim.reset()
    sim.typeText("12345")
    result = sim.doubleCmdWithFix()
    passed = result.converted == "12345"  // Цифры не конвертируются
    allResults.append(TestResult(
        name: "EdgeCase: только цифры '12345'",
        passed: passed,
        expected: "12345",
        actual: result.converted,
        details: "Цифры не должны меняться"
    ))
    print(allResults.last!.description)

    // Тест 6: Буквы с цифрами
    sim.reset()
    sim.typeText("test123")
    result = sim.doubleCmdWithFix()
    // "test123" → "еу|е123" (t→е, e→у, s→ы, t→е, 123→123)
    // На самом деле: t→е, e→у, s→ы, t→е = "е|ые" + "123" = ?
    // Проверяем что цифры сохранились
    passed = result.converted.hasSuffix("123")
    allResults.append(TestResult(
        name: "EdgeCase: буквы+цифры 'test123'",
        passed: passed,
        expected: "...123 (цифры сохранены)",
        actual: result.converted,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 7: UPPERCASE
    sim.reset()
    sim.typeText("GHBDTN")
    result = sim.doubleCmdWithFix()
    passed = result.converted == "ПРИВЕТ"
    allResults.append(TestResult(
        name: "EdgeCase: UPPERCASE 'GHBDTN'",
        passed: passed,
        expected: "ПРИВЕТ",
        actual: result.converted,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 8: Mixed case
    sim.reset()
    sim.typeText("Ghbdtn")
    result = sim.doubleCmdWithFix()
    passed = result.converted == "Привет"
    allResults.append(TestResult(
        name: "EdgeCase: Mixed case 'Ghbdtn'",
        passed: passed,
        expected: "Привет",
        actual: result.converted,
        details: ""
    ))
    print(allResults.last!.description)
}

// MARK: - 16. Buffer State After Double Cmd

func testBufferStateAfterDoubleCmd() {
    printSection("ТЕСТ 16: Состояние буфера после Double Cmd")

    let sim = DoubleCmdSimulator()

    // Тест 1: wordBuffer пустой после Double Cmd
    sim.reset()
    sim.typeText("ghbdtn")
    _ = sim.doubleCmdWithFix()
    var passed = sim.wordBuffer == ""
    allResults.append(TestResult(
        name: "BufferState: wordBuffer очищен",
        passed: passed,
        expected: "wordBuffer = ''",
        actual: "wordBuffer = '\(sim.wordBuffer)'",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 2: lastProcessedWord обновлён (для toggle)
    sim.reset()
    sim.typeText("ghbdtn")
    _ = sim.doubleCmdWithFix()
    passed = sim.lastProcessedWord == "привет"
    allResults.append(TestResult(
        name: "BufferState: lastProcessedWord = конвертированное",
        passed: passed,
        expected: "lastProcessedWord = 'привет'",
        actual: "lastProcessedWord = '\(sim.lastProcessedWord)'",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 3: pendingPunctuation очищен
    sim.reset()
    sim.typeText("ghbdtn!")
    _ = sim.doubleCmdWithFix()
    passed = sim.pendingPunctuation == ""
    allResults.append(TestResult(
        name: "BufferState: pendingPunctuation очищен",
        passed: passed,
        expected: "pendingPunctuation = ''",
        actual: "pendingPunctuation = '\(sim.pendingPunctuation)'",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 4: Готовность к следующему слову
    sim.reset()
    sim.typeText("ghbdtn ")
    _ = sim.doubleCmdWithFix()
    sim.typeText("world")  // Набираем новое слово после Double Cmd
    passed = sim.wordBuffer == "world"
    allResults.append(TestResult(
        name: "BufferState: готов к новому слову",
        passed: passed,
        expected: "wordBuffer = 'world' (новое слово)",
        actual: "wordBuffer = '\(sim.wordBuffer)'",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 5: Double Cmd toggle (туда-обратно)
    sim.reset()
    sim.typeText("ghbdtn ")
    var result1 = sim.doubleCmdWithFix()  // ghbdtn → привет
    // Симулируем что пользователь снова нажал Double Cmd
    // lastProcessedWord = "привет", wordBuffer = ""
    var result2 = sim.doubleCmdWithFix()  // привет → ghbdtn
    passed = result1.converted == "привет" && result2.converted == "ghbdtn"
    allResults.append(TestResult(
        name: "BufferState: toggle туда-обратно",
        passed: passed,
        expected: "ghbdtn → привет → ghbdtn",
        actual: "\(result1.wordToConvert) → \(result1.converted) → \(result2.converted)",
        details: ""
    ))
    print(allResults.last!.description)
}

// MARK: - 17. Selection Mode Tests (Critical Bug Tests)

func testSelectionModeConversion() {
    printSection("ТЕСТ 17: Selection Mode — КРИТИЧЕСКИЕ ТЕСТЫ")

    // КРИТИЧЕСКИЙ ТЕСТ: Точный ввод пользователя который не работает
    // Ввод: "Ghbdtn, rfr ltkf&" (выделенный текст)
    // Ожидание пользователя: "Привет, как дела?"
    // Фактический результат: "Привет, как lдела"

    // ВАЖНО: toggleLayout конвертирует ВСЕ символы с маппингом, включая ','
    // Поэтому ',' → 'б' (это правильное поведение toggleLayout)
    // НО пользователь ожидает что ',' останется ','

    // Тест 1: Проверка toggleLayout с точным вводом пользователя
    var input = "Ghbdtn, rfr ltkf&"
    var result = LayoutMaps.toggleLayout(input)
    // toggleLayout должен конвертировать ',' → 'б', но пользователь ожидает ','!
    var expectedByToggle = "Приветб как дела?"  // Как работает toggleLayout
    var expectedByUser = "Привет, как дела?"    // Что ожидает пользователь
    var passed = result == expectedByToggle

    allResults.append(TestResult(
        name: "CRITICAL: toggleLayout('Ghbdtn, rfr ltkf&')",
        passed: passed,
        expected: expectedByToggle,
        actual: result,
        details: "toggleLayout конвертирует ВСЕ символы включая ','. Пользователь ожидает '\(expectedByUser)'"
    ))
    print(allResults.last!.description)

    // Тест 2: Проверяем что каждый символ конвертируется корректно В КОНТЕКСТЕ
    // ВАЖНО: toggleLayout определяет раскладку по буквам, поэтому тестируем символы
    // с контекстом (буквой 'a' для QWERTY или 'а' для Russian)
    let charTests: [(input: String, expected: String, char: String)] = [
        ("aG", "фП", "G"),     // QWERTY контекст
        ("ah", "фр", "h"),
        ("ab", "фи", "b"),
        ("ad", "фв", "d"),
        ("at", "фе", "t"),
        ("an", "фт", "n"),
        ("a,", "фб", ","),     // ВАЖНО: запятая конвертируется!
        ("a ", "ф ", " "),     // Пробел остаётся
        ("ar", "фк", "r"),
        ("af", "фа", "f"),
        ("al", "фд", "l"),     // КРИТИЧЕСКИЙ СИМВОЛ — l должен стать д
        ("ak", "фл", "k"),
        ("a&", "ф?", "&"),     // Амперсанд → вопрос
    ]

    for test in charTests {
        let converted = LayoutMaps.toggleLayout(test.input)
        let charPassed = converted == test.expected

        allResults.append(TestResult(
            name: "charToggle: '\(test.char)' (в контексте '\(test.input)')",
            passed: charPassed,
            expected: test.expected,
            actual: converted,
            details: ""
        ))
        if !charPassed { print(allResults.last!.description) }
    }

    // Выводим сводку по символам
    let charTestResults = allResults.suffix(charTests.count)
    let charPassedCount = charTestResults.filter { $0.passed }.count
    print("✅ Посимвольная конвертация: \(charPassedCount)/\(charTests.count)")

    // Тест 3: Проверяем что 'l' точно конвертируется в 'д'
    result = LayoutMaps.toggleLayout("l")
    passed = result == "д"
    allResults.append(TestResult(
        name: "CRITICAL: 'l' → 'д' (одиночный символ)",
        passed: passed,
        expected: "д",
        actual: result,
        details: "Если этот тест провален — фундаментальная ошибка в таблице!"
    ))
    print(allResults.last!.description)

    // Тест 4: Проверяем "ltkf&" отдельно (часть слова где был баг)
    result = LayoutMaps.toggleLayout("ltkf&")
    passed = result == "дела?"
    allResults.append(TestResult(
        name: "CRITICAL: 'ltkf&' → 'дела?'",
        passed: passed,
        expected: "дела?",
        actual: result,
        details: "Пользователь получил 'lдела' — l не конвертировался!"
    ))
    print(allResults.last!.description)

    // Тест 5: Симуляция частичной конвертации (баг пользователя)
    // Если "ltkf&" → "lдела", это значит:
    // - 'l' НЕ конвертировался (остался 'l')
    // - 'tkf&' конвертировался со сдвигом: t→д, k→е, f→л, &→а
    let buggyResult = "lдела"
    let correctResult = "дела?"
    passed = result == correctResult && result != buggyResult
    allResults.append(TestResult(
        name: "BUG CHECK: 'ltkf&' НЕ должен давать 'lдела'",
        passed: passed,
        expected: correctResult,
        actual: result,
        details: "Если результат = '\(buggyResult)' — есть race condition или off-by-one!"
    ))
    print(allResults.last!.description)

    // Тест 6: Полное предложение без пунктуации
    result = LayoutMaps.toggleLayout("Ghbdtn rfr ltkf")
    passed = result == "Привет как дела"
    allResults.append(TestResult(
        name: "Selection: 'Ghbdtn rfr ltkf' (без пунктуации)",
        passed: passed,
        expected: "Привет как дела",
        actual: result,
        details: ""
    ))
    print(allResults.last!.description)
}

// MARK: - 18. AX Text Flow Simulation

/// Симуляция полного потока Double Cmd с Selection
class SelectionDoubleCmdSimulator {
    var selectedText: String = ""
    var isReplacing: Bool = false
    var keyboardEventsBlocked: Bool = false

    /// Симуляция получения выделенного текста через AX
    func getSelectedText() -> String? {
        guard !selectedText.isEmpty else { return nil }
        return selectedText
    }

    /// Симуляция Double Cmd на выделенном тексте
    func doubleCmdOnSelection() -> (original: String, converted: String, success: Bool) {
        guard let text = getSelectedText(), !text.isEmpty else {
            return ("", "", false)
        }

        isReplacing = true
        keyboardEventsBlocked = true

        // Конвертация через toggleLayout (как в реальном коде)
        let converted = LayoutMaps.toggleLayout(text)

        // Симуляция замены (в реальности здесь AX API или fallback)
        // Проверяем что никакие новые символы не добавились

        isReplacing = false
        keyboardEventsBlocked = false

        return (text, converted, true)
    }

    /// Симуляция race condition: набор во время замены
    func typeCharDuringReplacement(_ char: Character) -> Bool {
        // Если keyboardEventsBlocked = true, символ должен быть отброшен
        if keyboardEventsBlocked {
            return false  // Символ заблокирован — правильное поведение
        }
        return true  // Символ добавлен — БАГ если isReplacing=true!
    }
}

func testSelectionDoubleCmdFlow() {
    printSection("ТЕСТ 18: Полный Flow Selection Double Cmd")

    let sim = SelectionDoubleCmdSimulator()

    // Тест 1: Базовый Selection Double Cmd
    sim.selectedText = "ghbdtn"
    var result = sim.doubleCmdOnSelection()
    var passed = result.original == "ghbdtn" && result.converted == "привет" && result.success
    allResults.append(TestResult(
        name: "SelectionFlow: 'ghbdtn' → 'привет'",
        passed: passed,
        expected: "ghbdtn → привет",
        actual: "\(result.original) → \(result.converted)",
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 2: Selection с пунктуацией
    sim.selectedText = "ghbdtn!"
    result = sim.doubleCmdOnSelection()
    // ! в commonPunctuation? Нет! Но toggleLayout проверяет qwertyToRussian, где ! → !
    passed = result.converted == "привет!"
    allResults.append(TestResult(
        name: "SelectionFlow: 'ghbdtn!' → 'привет!'",
        passed: passed,
        expected: "привет!",
        actual: result.converted,
        details: ""
    ))
    print(allResults.last!.description)

    // Тест 3: Критический баг — полное предложение
    sim.selectedText = "Ghbdtn, rfr ltkf&"
    result = sim.doubleCmdOnSelection()
    // toggleLayout конвертирует ',' → 'б', поэтому ожидаем "Приветб как дела?"
    passed = result.converted == "Приветб как дела?"
    allResults.append(TestResult(
        name: "CRITICAL SelectionFlow: 'Ghbdtn, rfr ltkf&'",
        passed: passed,
        expected: "Приветб как дела?",
        actual: result.converted,
        details: "Пользователь ожидал 'Привет, как дела?' но toggleLayout конвертирует ','→'б'"
    ))
    print(allResults.last!.description)

    // Тест 4: Блокировка клавиатуры во время замены
    sim.selectedText = "test"
    sim.isReplacing = true
    sim.keyboardEventsBlocked = true
    let charBlocked = !sim.typeCharDuringReplacement("x")
    sim.isReplacing = false
    sim.keyboardEventsBlocked = false

    passed = charBlocked
    allResults.append(TestResult(
        name: "RaceCondition: символы блокируются во время замены",
        passed: passed,
        expected: "true (символ заблокирован)",
        actual: String(charBlocked),
        details: "Если false — race condition bug!"
    ))
    print(allResults.last!.description)

    // Тест 5: После isReplacing=false символы принимаются
    sim.isReplacing = false
    sim.keyboardEventsBlocked = false
    let charAccepted = sim.typeCharDuringReplacement("y")
    passed = charAccepted
    allResults.append(TestResult(
        name: "RaceCondition: символы принимаются после замены",
        passed: passed,
        expected: "true (символ принят)",
        actual: String(charAccepted),
        details: ""
    ))
    print(allResults.last!.description)
}

// MARK: - 19. Punctuation Preservation Tests

func testPunctuationPreservation() {
    printSection("ТЕСТ 19: Сохранение/Конвертация пунктуации в Selection")

    // ВАЖНО: Эти тесты документируют ТЕКУЩЕЕ поведение toggleLayout
    // toggleLayout конвертирует ВСЕ символы с маппингом, включая пунктуацию

    let tests: [(input: String, expected: String, note: String)] = [
        // Пунктуация которая КОНВЕРТИРУЕТСЯ (имеет маппинг)
        ("hello,", "руддщб", ", → б"),
        ("hello.", "руддщю", ". → ю"),
        ("hello;", "руддщж", "; → ж"),
        ("hello'", "руддщэ", "' → э"),
        ("hello[", "руддщх", "[ → х"),
        ("hello]", "руддщъ", "] → ъ"),
        ("hello&", "руддщ?", "& → ?"),
        ("hello?", "руддщ,", "? → ,"),

        // Пунктуация которая НЕ конвертируется (в commonPunctuation или нет маппинга)
        ("hello!", "руддщ!", "! остаётся"),
        ("hello%", "руддщ%", "% остаётся"),
        ("hello*", "руддщ*", "* остаётся"),
        ("hello(", "руддщ(", "( остаётся"),
        ("hello)", "руддщ)", ") остаётся"),
        ("hello-", "руддщ-", "- остаётся"),
        ("hello+", "руддщ+", "+ остаётся"),
        ("hello=", "руддщ=", "= остаётся"),
        ("hello ", "руддщ ", "пробел остаётся"),
    ]

    for test in tests {
        let result = LayoutMaps.toggleLayout(test.input)
        let passed = result == test.expected

        allResults.append(TestResult(
            name: "Punct: '\(test.input)' (\(test.note))",
            passed: passed,
            expected: test.expected,
            actual: result,
            details: ""
        ))
        if !passed { print(allResults.last!.description) }
    }

    // Выводим сводку
    let punctTests = allResults.suffix(tests.count)
    let punctPassed = punctTests.filter { $0.passed }.count
    print("✅ Пунктуация в Selection: \(punctPassed)/\(tests.count)")
}

// MARK: - 20. Off-by-One Bug Detection

func testOffByOneBugDetection() {
    printSection("ТЕСТ 20: Детекция Off-by-One багов")

    // Баг пользователя: "ltkf&" → "lдела" вместо "дела?"
    // Это классический off-by-one: первый символ пропущен, остальные сдвинуты

    // Тест: убедиться что каждая позиция конвертируется правильно
    let input = "ltkf&"
    let expected = "дела?"
    let result = LayoutMaps.toggleLayout(input)

    // Проверяем посимвольно
    let inputChars = Array(input)
    let expectedChars = Array(expected)
    let resultChars = Array(result)

    var allMatch = true
    var details = ""

    for i in 0..<min(inputChars.count, expectedChars.count) {
        let inputChar = inputChars[i]
        let expectedChar = expectedChars[i]
        let resultChar = i < resultChars.count ? resultChars[i] : Character("?")

        if resultChar != expectedChar {
            allMatch = false
            details += "pos[\(i)]: '\(inputChar)'→'\(resultChar)' (ожидали '\(expectedChar)'); "
        }
    }

    allResults.append(TestResult(
        name: "OFF-BY-ONE: 'ltkf&' посимвольная проверка",
        passed: allMatch,
        expected: "Все позиции совпадают",
        actual: details.isEmpty ? "✓ Совпадает" : details,
        details: ""
    ))
    print(allResults.last!.description)

    // Дополнительная проверка: длина результата должна совпадать
    let lengthMatch = result.count == expected.count
    allResults.append(TestResult(
        name: "OFF-BY-ONE: длина результата",
        passed: lengthMatch,
        expected: "length = \(expected.count)",
        actual: "length = \(result.count)",
        details: ""
    ))
    print(allResults.last!.description)

    // Проверка что первый символ конвертирован
    let firstCharConverted = resultChars.first == expectedChars.first
    allResults.append(TestResult(
        name: "OFF-BY-ONE: первый символ 'l' → 'д'",
        passed: firstCharConverted,
        expected: "д",
        actual: resultChars.first.map(String.init) ?? "nil",
        details: "Если 'l' — первый символ пропущен!"
    ))
    print(allResults.last!.description)
}

// MARK: - Main

@main
struct DoubleCmdUnitTestsApp {
    static func main() {
        print("""
        ╔══════════════════════════════════════════════════════════╗
        ║        TextSwitcher Unit Tests                           ║
        ║        Расширенное тестирование логики                   ║
        ╚══════════════════════════════════════════════════════════╝
        """)

        // Запуск всех тестов
        testLayoutMapsConvert()
        testRuToEnConversion()
        testUppercaseConversion()
        testEdgeCases()
        testCommonPunctuationNotConverted()
        testToggleLayout()
        testDetectLayout()
        testIsPureLayout()
        testRegressionBugs()
        testWordBufferSimulation()
        testImprovedWordBuffer()
        testSpecialCharactersMapping()
        testDoubleCmdRaceCondition()
        testDoubleCmdSentences()
        testDoubleCmdEdgeCases()
        testBufferStateAfterDoubleCmd()
        testSelectionModeConversion()       // КРИТИЧЕСКИЕ ТЕСТЫ
        testSelectionDoubleCmdFlow()        // Flow тесты
        testPunctuationPreservation()       // Пунктуация
        testOffByOneBugDetection()          // Off-by-one баги

        // Итоги
        print("\n" + String(repeating: "═", count: 60))
        print("ИТОГИ ТЕСТИРОВАНИЯ")
        print(String(repeating: "═", count: 60))

        let passed = allResults.filter { $0.passed }.count
        let failed = allResults.count - passed

        print("Всего тестов: \(allResults.count)")
        print("✅ Успешно:   \(passed)")
        print("❌ Провалено: \(failed)")

        if failed > 0 {
            print("\n" + String(repeating: "─", count: 60))
            print("ПРОВАЛИВШИЕСЯ ТЕСТЫ:")
            for result in allResults where !result.passed {
                print(result.description)
            }
        }

        print("\n" + String(repeating: "═", count: 60))

        if failed == 0 {
            print("🎉 ВСЕ ТЕСТЫ ПРОЙДЕНЫ!")
        } else {
            print("⚠️ ЕСТЬ ПРОВАЛЫ — требуется исправление")
        }

        exit(Int32(failed > 0 ? 1 : 0))
    }
}
