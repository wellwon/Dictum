//
//  TextSwitcherCLI.swift
//  Dictum
//
//  CLI для тестирования логики TextSwitcher без UI и разрешений.
//  Теперь с контекстным трекингом!
//  Запуск: ./build/Build/Products/Debug/TextSwitcherCLI "текст для теста"
//

import Foundation
import NaturalLanguage
import AppKit

// MARK: - Context Tracker (эмуляция контекста KeyboardMonitor)

/// Трекер контекста для эмуляции поведения KeyboardMonitor
class ContextTracker {
    /// История конвертаций
    private var conversionHistory: [(layout: KeyboardLayout, wasSwitched: Bool)] = []

    /// Порог для контекстного биаса
    private let contextBiasThreshold: Double = 0.5

    /// Минимум слов для анализа
    private let minContextWords: Int = 2

    /// Флаг: последнее слово было CLI командой — аргументы НЕ конвертировать
    private(set) var inCliMode: Bool = false

    /// Записывает решение о конвертации
    /// - Parameters:
    ///   - isCliCommand: true если слово — CLI команда (tar, git, npm)
    func recordDecision(originalLayout: KeyboardLayout, wasSwitched: Bool, targetLayout: KeyboardLayout?, isCliCommand: Bool = false) {
        let resultLayout = wasSwitched ? (targetLayout ?? originalLayout.opposite) : originalLayout
        conversionHistory.append((layout: resultLayout, wasSwitched: wasSwitched))

        // Устанавливаем CLI режим если это CLI команда
        if isCliCommand {
            inCliMode = true
        }
    }

    /// Вычисляет контекстный биас
    func calculateBias(for currentLayout: KeyboardLayout) -> KeyboardLayout? {
        guard conversionHistory.count >= minContextWords else { return nil }

        var switchedToRussian = 0
        var switchedToEnglish = 0
        var totalSwitched = 0

        for entry in conversionHistory {
            if entry.wasSwitched {
                totalSwitched += 1
                if entry.layout == .russian {
                    switchedToRussian += 1
                } else {
                    switchedToEnglish += 1
                }
            }
        }

        let switchRatio = Double(totalSwitched) / Double(conversionHistory.count)
        guard switchRatio >= contextBiasThreshold else { return nil }

        if switchedToRussian > switchedToEnglish && currentLayout == .qwerty {
            return .russian
        } else if switchedToEnglish > switchedToRussian && currentLayout == .russian {
            return .qwerty
        }

        return nil
    }

    /// Очищает историю
    func clear() {
        conversionHistory.removeAll()
        inCliMode = false
    }

    /// Сбрасывает CLI режим (при начале нового предложения)
    func resetCliMode() {
        inCliMode = false
    }

    /// Описание текущего состояния
    var description: String {
        let switched = conversionHistory.filter { $0.wasSwitched }.count
        let toRu = conversionHistory.filter { $0.wasSwitched && $0.layout == .russian }.count
        let toEn = conversionHistory.filter { $0.wasSwitched && $0.layout == .qwerty }.count
        return "[\(conversionHistory.count) слов, \(switched) конверт. (RU:\(toRu), EN:\(toEn))]"
    }
}

// MARK: - Token Structure

/// Токен текста — слово или разделитель (пунктуация/пробелы)
struct Token {
    let text: String
    let isWord: Bool  // false = separator (punctuation/whitespace)
}

// MARK: - Sensitive String Patterns

/// Паттерны для sensitive strings (UUID, JWT, API keys, etc.)
/// Эти строки НЕ должны конвертироваться — они технические идентификаторы
enum SensitivePatterns {
    /// Проверяет, является ли строка sensitive (UUID, JWT, API key, etc.)
    /// Вызывается ПЕРЕД токенизацией, чтобы защитить строки с `-` и `_`
    static func isSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
        if isUUID(trimmed) { return true }

        // API keys: sk_live_*, pk_test_*, api_key_*, etc.
        if isAPIKey(trimmed) { return true }

        // JWT: xxx.xxx.xxx (base64 parts separated by dots)
        if isJWT(trimmed) { return true }

        // File with extension: name.ext
        if isFileWithExtension(trimmed) { return true }

        // Version string: v1, v2, v12, etc.
        if isVersionString(trimmed) { return true }

        // Windows path: C:\, D:\, etc.
        if isWindowsPath(trimmed) { return true }

        // IPv6 localhost: ::1, :::, etc.
        if isIPv6Localhost(trimmed) { return true }

        // SHA-like hash: 7+ hex characters
        if isShaHash(trimmed) { return true }

        // Hash prefix: sha256:xxx, sha1:xxx, md5:xxx, etc.
        if isHashPrefix(trimmed) { return true }

        return false
    }

    // MARK: - Pattern Checkers

    /// UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    private static func isUUID(_ text: String) -> Bool {
        let pattern = "^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// API keys: sk_live_*, pk_test_*, api_*, key_*, token_*, secret_*
    private static func isAPIKey(_ text: String) -> Bool {
        // Pattern: prefix_suffix_value or prefix_value
        let pattern = "^(sk|pk|api|key|token|secret)_[a-zA-Z0-9_]+$"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// JWT: three base64 parts separated by dots
    private static func isJWT(_ text: String) -> Bool {
        // JWT has exactly 2 dots, and each part is base64-like
        let parts = text.split(separator: ".")
        guard parts.count == 3 else { return false }

        // Each part should be base64url (alphanumeric + - + _ + =)
        let base64Pattern = "^[A-Za-z0-9_-]+=*$"
        for part in parts {
            if String(part).range(of: base64Pattern, options: .regularExpression) == nil {
                return false
            }
        }
        return true
    }

    /// File with known extension: name.css, script.js, etc.
    private static func isFileWithExtension(_ text: String) -> Bool {
        guard let dotIndex = text.lastIndex(of: ".") else { return false }
        let ext = String(text[text.index(after: dotIndex)...]).lowercased()
        let name = String(text[..<dotIndex])

        // Name should be valid (alphanumeric + _ + -)
        let validName = name.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil

        return validName && knownExtensions.contains(ext)
    }

    /// Corrupted file path: Russian name + . + English extension
    /// Example: зфслфпу.json (should convert to package.json)
    static func isCorruptedFilePath(_ text: String) -> (isCorrupted: Bool, corrected: String?) {
        guard let dotIndex = text.lastIndex(of: ".") else { return (false, nil) }
        let ext = String(text[text.index(after: dotIndex)...]).lowercased()
        let name = String(text[..<dotIndex])

        // Extension must be known
        guard knownExtensions.contains(ext) else { return (false, nil) }

        // Name should contain Cyrillic characters
        let hasCyrillic = name.contains { c in
            let s = c.lowercased()
            return s >= "а" && s <= "я" || s == "ё"
        }
        guard hasCyrillic else { return (false, nil) }

        // Convert name from Russian layout to QWERTY
        let correctedName = LayoutMaps.convert(name, from: .russian, to: .qwerty)
        return (true, "\(correctedName).\(ext)")
    }

    /// Known file extensions
    private static let knownExtensions: Set<String> = [
        "css", "js", "ts", "jsx", "tsx", "json", "yaml", "yml", "xml", "html", "htm",
        "py", "rb", "go", "rs", "swift", "kt", "java", "c", "cpp", "h", "hpp",
        "md", "txt", "csv", "sql", "sh", "bash", "zsh", "ps1", "bat", "cmd",
        "env", "ini", "toml", "conf", "cfg", "lock", "log"
    ]

    /// Version string: v1, v2, v12, V1, etc.
    private static func isVersionString(_ text: String) -> Bool {
        let pattern = "^[vV][0-9]+$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Windows path: C:\, D:\, etc.
    private static func isWindowsPath(_ text: String) -> Bool {
        let pattern = "^[A-Za-z]:\\\\"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// IPv6 localhost: ::1, :::, etc.
    private static func isIPv6Localhost(_ text: String) -> Bool {
        // Starts with :: and optionally followed by digits
        let pattern = "^::+[0-9]*$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// SHA-like hash: 7+ lowercase hex characters
    private static func isShaHash(_ text: String) -> Bool {
        guard text.count >= 7 && text.count <= 64 else { return false }
        let pattern = "^[a-f0-9]+$"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Hash prefix: sha256:xxx, sha1:xxx, md5:xxx, sha512:xxx, etc.
    private static func isHashPrefix(_ text: String) -> Bool {
        // Pattern: hash_algorithm:hex_value
        let pattern = "^(sha256|sha1|sha512|sha384|md5|sha):[a-fA-F0-9]+$"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Main

@main
struct TextSwitcherCLI {
    nonisolated(unsafe) static let contextTracker = ContextTracker()

    static func main() {
        print("═══════════════════════════════════════════════════════════")
        print("  TextSwitcher CLI — с контекстной валидацией")
        print("═══════════════════════════════════════════════════════════")
        print()

        // Тест-кейсы
        let testCases: [String]

        if CommandLine.arguments.count > 1 {
            // Аргументы из командной строки
            testCases = Array(CommandLine.arguments.dropFirst())
        } else {
            // Дефолтные тест-кейсы
            testCases = [
                "Ctqxfc Dkflf tot gjghjie",
                "tot попрошу",
                "ghbdtn",      // привет
                "руддщ",       // hello
                "Docker",      // tech buzzword
                "DHL",         // uppercase abbreviation
            ]
        }

        for (index, testCase) in testCases.enumerated() {
            // Очищаем контекст между разными тест-кейсами
            contextTracker.clear()

            print("───────────────────────────────────────────────────────────")
            print("  TEST \(index + 1): \"\(testCase)\"")
            print("───────────────────────────────────────────────────────────")

            processText(testCase)
            print()
        }

        print("═══════════════════════════════════════════════════════════")
        print("  Готово!")
        print("═══════════════════════════════════════════════════════════")
    }

    // MARK: - Public API for Tests

    /// Обрабатывает текст и возвращает результат (для тестов)
    /// Включает проверку на sensitive strings ПЕРЕД токенизацией
    static func process(_ text: String) -> String {
        // PRE-TOKENIZATION CHECK: Sensitive strings (UUID, JWT, API keys)
        // Проверяем ВЕСЬ текст ДО токенизации, чтобы защитить строки с `-` и `_`
        if SensitivePatterns.isSensitive(text) {
            return text  // Не конвертировать sensitive strings
        }

        // PRE-TOKENIZATION CHECK: Corrupted file paths (зфслфпу.json → package.json)
        let fileCheck = SensitivePatterns.isCorruptedFilePath(text)
        if fileCheck.isCorrupted, let corrected = fileCheck.corrected {
            return corrected  // Конвертировать имя файла, сохранить расширение
        }

        // Нормальная обработка
        let tokens = tokenize(text)
        return processTokens(tokens)
    }

    // MARK: - Processing

    static func processText(_ text: String) {
        // ════════════════════════════════════════════════════════════════
        // PRE-TOKENIZATION CHECK: Sensitive strings (UUID, JWT, API keys)
        // Проверяем ВЕСЬ текст ДО токенизации, чтобы защитить строки с `-` и `_`
        // ════════════════════════════════════════════════════════════════
        if SensitivePatterns.isSensitive(text) {
            print("  🛡️ SENSITIVE STRING — не конвертировать")
            print("  ═══════════════════════════════════════════════════════")
            print("  ИТОГОВЫЙ РЕЗУЛЬТАТ:")
            print("  Вход:  \"\(text)\"")
            print("  Выход: \"\(text)\"")
            return
        }

        // PRE-TOKENIZATION CHECK: Corrupted file paths (зфслфпу.json → package.json)
        let fileCheck = SensitivePatterns.isCorruptedFilePath(text)
        if fileCheck.isCorrupted, let corrected = fileCheck.corrected {
            print("  📁 CORRUPTED FILE PATH — конвертируем в \"\(corrected)\"")
            print("  ═══════════════════════════════════════════════════════")
            print("  ИТОГОВЫЙ РЕЗУЛЬТАТ:")
            print("  Вход:  \"\(text)\"")
            print("  Выход: \"\(corrected)\"")
            return
        }

        // Токенизация с сохранением пунктуации
        let tokens = tokenize(text)
        let words = tokens.filter { $0.isWord }.map { $0.text }

        print("  Слова: \(words)")
        print()

        for word in words {
            processWord(word)
        }

        // Показываем финальный результат
        print("  ═══════════════════════════════════════════════════════")
        print("  ИТОГОВЫЙ РЕЗУЛЬТАТ:")
        print("  Контекст: \(contextTracker.description)")

        // Обрабатываем токены с сохранением пунктуации
        let result = processTokens(tokens)

        print("  Вход:  \"\(text)\"")
        print("  Выход: \"\(result)\"")
    }

    static func extractWords(from text: String) -> [String] {
        var words: [String] = []
        var currentWord = ""
        let chars = Array(text)

        // Хелпер: проверяет, начинается ли слово с заглавной латинской буквы
        func startsWithUppercaseLatin() -> Bool {
            guard let first = currentWord.first, first.isLetter else { return false }
            let lc = Character(first.lowercased())
            return first.isUppercase && lc >= "a" && lc <= "z"
        }

        // Хелпер: проверяет, всё ли слово в нижнем регистре (латиница)
        func isAllLowercaseLatin() -> Bool {
            guard !currentWord.isEmpty else { return false }
            for c in currentWord {
                if c.isLetter {
                    let lc = Character(c.lowercased())
                    if !(lc >= "a" && lc <= "z") || c.isUppercase {
                        return false
                    }
                }
            }
            return true
        }

        for (index, char) in chars.enumerated() {
            // Look-ahead: следующий символ
            let nextChar: Character? = (index + 1 < chars.count) ? chars[index + 1] : nil

            // Проверяем: это layout mapping char?
            // Lowercase: `,`, `;`, `[`, `]`, `'`, `` ` ``, `.` → б, ж, х, ъ, э, ё, ю
            // Shifted:   `<`, `:`, `{`, `}`, `"`, `~`, `>` → Б, Ж, Х, Ъ, Э, Ё, Ю
            // Shifted layout chars: ? → , (Shift+/ на QWERTY = , на русской)
            let shiftedLayoutChars: Set<Character> = ["<", ">", "\"", "~", "{", "}", ":", "?"]
            let isQwertyLayoutChar = !char.isLetter && (
                LayoutMaps.qwertyCharacters.contains(char) ||
                LayoutMaps.qwertyCharacters.contains(Character(char.lowercased())) ||
                shiftedLayoutChars.contains(char)
            )

            // Layout char является частью слова ЕСЛИ:
            // 1. После него идёт буква/цифра (середина слова), ИЛИ
            // 2. Слово в нижнем регистре (не начало предложения) — `vthl;` = мердж
            // НО НЕ если слово начинается с заглавной — `Ghbdtn,` = Привет,
            let hasNextLetterOrDigit = nextChar != nil && (
                nextChar!.isLetter ||
                nextChar!.isNumber ||
                LayoutMaps.qwertyCharacters.contains(nextChar!) ||
                LayoutMaps.qwertyCharacters.contains(Character(nextChar!.lowercased())) ||
                shiftedLayoutChars.contains(nextChar!)
            )

            // Trailing layout chars которые могут быть буквами на конце слова:
            // `;` → ж (мердж), `'` → э, `[` → х (смех), `]` → ъ, `.` → ю (ревью, отправлю)
            // `,` → б (способ: cgjcj, → способ) — включаем только для lowercase слов (isAllLowercaseLatin)
            // ДОБАВЛЕНО: { → Х, } → Ъ, : → Ж (shifted версии на конце слова типа ЧУЖИХ)
            // ДОБАВЛЕНО: ? → , (Shift+/ на QWERTY = , на русской, ghbdtn? → привет,)
            let validTrailingLayoutChars: Set<Character> = [";", "'", "[", "]", "`", ".", "{", "}", ":", "?", ","]
            let isValidTrailingChar = validTrailingLayoutChars.contains(char)
            // Backtick (`) → ё — особый случай, почти никогда не пунктуация на конце
            let isBacktickAtEnd = char == "`" && !hasNextLetterOrDigit && !currentWord.isEmpty
            // Dot (.) на конце слова которое выглядит как QWERTY → может быть `ю` (Перезвоню)
            let isDotAtEndOfQwertyWord = char == "." && !hasNextLetterOrDigit && !currentWord.isEmpty &&
                currentWord.allSatisfy { c in c.isLetter && (c.lowercased().first ?? "я") >= "a" && (c.lowercased().first ?? "я") <= "z" }
            let isEndOfLowercaseWord = isValidTrailingChar && !hasNextLetterOrDigit && isAllLowercaseLatin()
            // Shifted layout chars ({, }, :, <, >, ~, ") на конце QWERTY слова → ЧУЖИХ, МОЖЕШЬ, и т.д.
            let isShiftedAtEndOfQwertyWord = shiftedLayoutChars.contains(char) && !hasNextLetterOrDigit && !currentWord.isEmpty &&
                currentWord.allSatisfy { c in
                    (c.isLetter && (c.lowercased().first ?? "я") >= "a" && (c.lowercased().first ?? "я") <= "z") ||
                    (!c.isLetter && (LayoutMaps.allQwertyMappableCharacters.contains(c) || shiftedLayoutChars.contains(c)))
                }
            let isLayoutCharInWord = isQwertyLayoutChar && (hasNextLetterOrDigit || isEndOfLowercaseWord || isBacktickAtEnd || isDotAtEndOfQwertyWord || isShiftedAtEndOfQwertyWord)

            if char.isLetter || char.isNumber || isLayoutCharInWord {
                currentWord.append(char)
            } else if TechBuzzwordsManager.isCompoundChar(char) {
                // COMPOUND BUZZWORDS: проверяем может ли это быть частью составного термина (gpt-4, c++, react-native)
                if TechBuzzwordsManager.shared.mightBeCompound(currentWord, nextChar: char) {
                    // Продолжаем накапливать — это часть составного buzzword
                    currentWord.append(char)
                } else {
                    // Обычная пунктуация — завершаем слово
                    if !currentWord.isEmpty {
                        words.append(currentWord)
                        currentWord = ""
                    }
                }
            } else {
                // Пробел или другая пунктуация — завершаем слово
                if !currentWord.isEmpty {
                    words.append(currentWord)
                    currentWord = ""
                }
            }
        }

        // Добавляем последнее слово
        if !currentWord.isEmpty {
            words.append(currentWord)
        }

        return words
    }

    /// Токенизация текста с сохранением пунктуации
    /// Возвращает массив токенов (слова + разделители)
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var currentWord = ""
        var currentSeparator = ""
        let chars = Array(text)

        // Хелперы для определения layout chars
        // Shifted: { → Х, } → Ъ, : → Ж, " → Э, ~ → Ё, < → Б, > → Ю, ? → ,
        let shiftedLayoutChars: Set<Character> = ["<", ">", "\"", "~", "{", "}", ":", "?"]
        // Trailing chars которые могут быть буквами на конце слова:
        // ; → ж, ' → э, [ → х, ] → ъ, ` → ё, . → ю, , → б
        // ДОБАВЛЕНО: { → Х, } → Ъ, : → Ж (shifted версии на конце слова типа ЧУЖИХ)
        // ДОБАВЛЕНО: ? → , (Shift+/ на QWERTY = , на русской)
        let validTrailingLayoutChars: Set<Character> = [";", "'", "[", "]", "`", ".", "{", "}", ":", "?", ","]

        func isLayoutChar(_ char: Character) -> Bool {
            return !char.isLetter && (
                LayoutMaps.qwertyCharacters.contains(char) ||
                LayoutMaps.qwertyCharacters.contains(Character(char.lowercased())) ||
                shiftedLayoutChars.contains(char)
            )
        }

        func isAllLowercaseLatin(_ word: String) -> Bool {
            guard !word.isEmpty else { return false }
            for c in word {
                if c.isLetter {
                    let lc = Character(c.lowercased())
                    if !(lc >= "a" && lc <= "z") || c.isUppercase {
                        return false
                    }
                }
            }
            return true
        }

        func flushWord() {
            if !currentWord.isEmpty {
                tokens.append(Token(text: currentWord, isWord: true))
                currentWord = ""
            }
        }

        func flushSeparator() {
            if !currentSeparator.isEmpty {
                tokens.append(Token(text: currentSeparator, isWord: false))
                currentSeparator = ""
            }
        }

        for (index, char) in chars.enumerated() {
            let nextChar: Character? = (index + 1 < chars.count) ? chars[index + 1] : nil

            let hasNextLetterOrDigit = nextChar != nil && (
                nextChar!.isLetter ||
                nextChar!.isNumber ||
                LayoutMaps.qwertyCharacters.contains(nextChar!) ||
                LayoutMaps.qwertyCharacters.contains(Character(nextChar!.lowercased())) ||
                shiftedLayoutChars.contains(nextChar!)
            )

            let isValidTrailingChar = validTrailingLayoutChars.contains(char)
            // Backtick (`) → ё — особый случай, почти никогда не пунктуация на конце
            let isBacktickAtEnd = char == "`" && !hasNextLetterOrDigit && !currentWord.isEmpty
            // Dot (.) на конце слова которое выглядит как QWERTY → может быть `ю` (Перезвоню, отправлю)
            // Проверяем: если слово содержит ТОЛЬКО латиницу (lowercase или mixed case) и нет пробела после
            let isDotAtEndOfQwertyWord = char == "." && !hasNextLetterOrDigit && !currentWord.isEmpty &&
                currentWord.allSatisfy { $0.isLetter && ($0.lowercased().first ?? "я") >= "a" && ($0.lowercased().first ?? "я") <= "z" }
            let isEndOfLowercaseWord = isValidTrailingChar && !hasNextLetterOrDigit && isAllLowercaseLatin(currentWord)
            // Shifted layout chars ({, }, :, <, >, ~, ") на конце QWERTY слова → ЧУЖИХ, МОЖЕШЬ, и т.д.
            // Проверяем: слово содержит латиницу/layout chars и shifted char на конце
            let isShiftedAtEndOfQwertyWord = shiftedLayoutChars.contains(char) && !hasNextLetterOrDigit && !currentWord.isEmpty &&
                currentWord.allSatisfy { c in
                    (c.isLetter && (c.lowercased().first ?? "я") >= "a" && (c.lowercased().first ?? "я") <= "z") ||
                    (!c.isLetter && (LayoutMaps.allQwertyMappableCharacters.contains(c) || shiftedLayoutChars.contains(c)))
                }
            let isLayoutCharInWord = isLayoutChar(char) && (hasNextLetterOrDigit || isEndOfLowercaseWord || isBacktickAtEnd || isDotAtEndOfQwertyWord || isShiftedAtEndOfQwertyWord)

            let isWordChar = char.isLetter || char.isNumber || isLayoutCharInWord ||
                (TechBuzzwordsManager.isCompoundChar(char) && TechBuzzwordsManager.shared.mightBeCompound(currentWord, nextChar: char))

            if isWordChar {
                // Если были разделители — сохраняем их
                flushSeparator()
                currentWord.append(char)
            } else {
                // Если было слово — сохраняем его
                flushWord()
                currentSeparator.append(char)
            }
        }

        // Сохраняем последний токен
        flushWord()
        flushSeparator()

        return tokens
    }

    /// Обработка токенов с сохранением пунктуации
    static func processTokens(_ tokens: [Token]) -> String {
        var result = ""
        contextTracker.clear()

        for token in tokens {
            if token.isWord {
                let word = token.text

                // CLI MODE: Если предыдущее слово было CLI командой — аргументы НЕ конвертировать
                if contextTracker.inCliMode {
                    result += word
                    contextTracker.recordDecision(originalLayout: .qwerty, wasSwitched: false, targetLayout: nil, isCliCommand: false)
                    continue
                }

                // VERSION STRINGS: v1, v2, V12, etc. — НЕ конвертировать
                if SensitivePatterns.isSensitive(word) {
                    result += word
                    contextTracker.recordDecision(originalLayout: .qwerty, wasSwitched: false, targetLayout: nil, isCliCommand: false)
                    continue
                }

                // NUMBERS MIXED: обрабатываем слова с числами (1nen → 1тут)
                let processedWord = processWordWithNumbers(word)
                result += processedWord.result

                if processedWord.wasSwitched {
                    contextTracker.recordDecision(originalLayout: processedWord.layout, wasSwitched: true, targetLayout: processedWord.layout.opposite, isCliCommand: false)
                } else {
                    let isCliCommand = HybridValidator.isCliCommand(word.split(separator: " ").first.map(String.init) ?? word)
                    contextTracker.recordDecision(originalLayout: processedWord.layout, wasSwitched: false, targetLayout: nil, isCliCommand: isCliCommand)
                }
            } else {
                // Разделитель — добавляем как есть
                result += token.text
            }
        }

        return result
    }

    /// Результат обработки слова с числами
    private struct WordWithNumbersResult {
        let result: String
        let wasSwitched: Bool
        let layout: KeyboardLayout
    }

    /// Обрабатывает слово, которое может содержать числа
    /// Примеры: 1nen → 1тут, nen1 → тут1, test123 → тест123
    private static func processWordWithNumbers(_ word: String) -> WordWithNumbersResult {
        let detectedLayout = detectLayout(word)
        let bias = contextTracker.calculateBias(for: detectedLayout)

        // ВАЖНО: Сначала проверяем, является ли ВСЁ слово buzzword (b2b, k8s, s3, etc.)
        // Делаем это ДО разбиения на сегменты!
        if TechBuzzwordsManager.shared.contains(word) {
            return WordWithNumbersResult(result: word, wasSwitched: false, layout: detectedLayout)
        }

        // Также проверяем конвертированную версию (и2и → b2b)
        let converted = LayoutMaps.convert(word, from: detectedLayout, to: detectedLayout.opposite)
        if TechBuzzwordsManager.shared.contains(converted) {
            return WordWithNumbersResult(result: converted, wasSwitched: true, layout: detectedLayout.opposite)
        }

        // Проверяем: есть ли в слове И буквы И цифры?
        let hasLetters = word.contains(where: { $0.isLetter })
        let hasDigits = word.contains(where: { $0.isNumber })

        // Если нет букв или нет цифр — обычная обработка
        if !hasLetters || !hasDigits {
            return processWordNormally(word, layout: detectedLayout, bias: bias)
        }

        // Разделяем на сегменты: (цифры)(буквы)(цифры)(буквы)...
        var segments: [(text: String, isDigits: Bool)] = []
        var currentSegment = ""
        var currentIsDigits: Bool? = nil

        for char in word {
            let isDigit = char.isNumber

            if currentIsDigits == nil {
                currentIsDigits = isDigit
                currentSegment.append(char)
            } else if currentIsDigits == isDigit {
                currentSegment.append(char)
            } else {
                // Тип изменился — сохраняем предыдущий сегмент
                if !currentSegment.isEmpty {
                    segments.append((currentSegment, currentIsDigits!))
                }
                currentSegment = String(char)
                currentIsDigits = isDigit
            }
        }

        // Добавляем последний сегмент
        if !currentSegment.isEmpty, let isDigits = currentIsDigits {
            segments.append((currentSegment, isDigits))
        }

        // Обрабатываем каждый буквенный сегмент
        var resultParts: [String] = []
        var anySwitched = false

        for segment in segments {
            if segment.isDigits {
                // Цифры оставляем как есть
                resultParts.append(segment.text)
            } else {
                // Буквы — валидируем
                let letterResult = processWordNormally(segment.text, layout: detectedLayout, bias: bias)
                resultParts.append(letterResult.result)
                if letterResult.wasSwitched {
                    anySwitched = true
                }
            }
        }

        return WordWithNumbersResult(
            result: resultParts.joined(),
            wasSwitched: anySwitched,
            layout: detectedLayout
        )
    }

    /// Обычная обработка слова (без чисел)
    private static func processWordNormally(_ word: String, layout: KeyboardLayout, bias: KeyboardLayout?) -> WordWithNumbersResult {
        let validationResult = HybridValidator.shared.validate(word, currentLayout: layout, biasTowardLayout: bias)

        switch validationResult {
        case .keep:
            return WordWithNumbersResult(result: word, wasSwitched: false, layout: layout)

        case .switchLayout(let targetLayout, let reason):
            let converted: String
            if reason.hasPrefix("mixed_buzzword:") {
                converted = String(reason.dropFirst("mixed_buzzword:".count))
            } else {
                converted = LayoutMaps.convert(word, from: layout, to: targetLayout, includeAllSymbols: true)
            }
            return WordWithNumbersResult(result: converted, wasSwitched: true, layout: layout)
        }
    }

    static func processWord(_ word: String) {
        // minLength = 1 — single-letter слова обрабатываются HybridValidator
        // HybridValidator имеет whitelist для Ш→I, ф→a, d→в, b→и
        let minLength = 1

        guard word.count >= minLength else {
            print("  ⏭️ \"\(word)\" — пропуск (пустое)")
            return
        }

        print("  ┌─ Слово: \"\(word)\"")

        // CLI MODE: Если предыдущее слово было CLI командой — аргументы НЕ конвертировать
        // Примеры: "tar -xzf" → "tar" это CLI, "-xzf" это аргумент
        // "yarn dlx" → "yarn" это CLI, "dlx" это аргумент
        if contextTracker.inCliMode {
            print("  │  🛠️ CLI режим: аргумент команды — НЕ конвертировать")
            print("  │")
            print("  └─ РЕЗУЛЬТАТ: 🔵 KEEP (cli_argument)")
            print()
            // Записываем как KEEP (не CLI команда, просто аргумент)
            contextTracker.recordDecision(originalLayout: .qwerty, wasSwitched: false, targetLayout: nil, isCliCommand: false)
            return
        }

        // Определяем текущую раскладку по символам
        let detectedLayout = detectLayout(word)
        print("  │  Раскладка: \(detectedLayout.rawValue.uppercased())")

        // Конвертируем в противоположную раскладку
        let converted = LayoutMaps.convert(word, from: detectedLayout, to: detectedLayout.opposite, includeAllSymbols: true)
        print("  │  Конвертация: \"\(word)\" → \"\(converted)\"")

        // N-gram скоринг
        let originalScore = NgramScorer.shared.score(word, language: detectedLayout.languageCode)
        let convertedScore = NgramScorer.shared.score(converted, language: detectedLayout.opposite.languageCode)
        let ratio = exp(convertedScore - originalScore)

        print("  │  N-gram:")
        print("  │    Original (\(detectedLayout.rawValue)): \(String(format: "%.2f", originalScore))")
        print("  │    Converted (\(detectedLayout.opposite.rawValue)): \(String(format: "%.2f", convertedScore))")
        print("  │    Ratio: \(String(format: "%.2f", ratio))")

        // SpellChecker
        let validOriginal = isValidInDictionary(word, language: detectedLayout.languageCode)
        let validConverted = isValidInDictionary(converted, language: detectedLayout.opposite.languageCode)

        print("  │  SpellChecker:")
        print("  │    \"\(word)\" (\(detectedLayout.rawValue)): \(validOriginal ? "✓ валидно" : "✗ невалидно")")
        print("  │    \"\(converted)\" (\(detectedLayout.opposite.rawValue)): \(validConverted ? "✓ валидно" : "✗ невалидно")")

        // Tech Buzzwords
        let isBuzzword = TechBuzzwordsManager.shared.contains(word)
        if isBuzzword {
            print("  │  TechBuzzword: ✓ найдено — НЕ конвертировать")
        }

        // Контекстный биас
        let contextBias = contextTracker.calculateBias(for: detectedLayout)
        if let bias = contextBias {
            print("  │  🎯 Контекстный биас: → \(bias.rawValue.uppercased()) \(contextTracker.description)")
        } else {
            print("  │  Контекст: \(contextTracker.description)")
        }

        // Валидация через HybridValidator С КОНТЕКСТОМ!
        let result = HybridValidator.shared.validate(word, currentLayout: detectedLayout, biasTowardLayout: contextBias)

        // Записываем решение в контекст
        // Проверяем, является ли это CLI командой
        let isCliCommand: Bool
        switch result {
        case .keep:
            // Проверяем, была ли причина "cli_command" — через NSLog мы видим это
            // HybridValidator логирует "Layer -2.4 (CLI)" для CLI команд
            // К сожалению, reason не возвращается для .keep, поэтому проверяем вручную
            let firstToken = word.split(separator: " ").first.map(String.init) ?? word
            isCliCommand = HybridValidator.isCliCommand(firstToken)
            contextTracker.recordDecision(originalLayout: detectedLayout, wasSwitched: false, targetLayout: nil, isCliCommand: isCliCommand)
        case .switchLayout(let targetLayout, _):
            isCliCommand = false
            contextTracker.recordDecision(originalLayout: detectedLayout, wasSwitched: true, targetLayout: targetLayout, isCliCommand: isCliCommand)
        }

        // Вывод результата
        print("  │")
        switch result {
        case .keep:
            if isCliCommand {
                print("  └─ РЕЗУЛЬТАТ: 🔵 KEEP (cli_command)")
            } else {
                print("  └─ РЕЗУЛЬТАТ: 🔵 KEEP (оставить как есть)")
            }
        case .switchLayout(let layout, let reason):
            // Специальная обработка mixed_buzzword (а# → f#)
            let finalResult: String
            if reason.hasPrefix("mixed_buzzword:") {
                finalResult = String(reason.dropFirst("mixed_buzzword:".count))
            } else {
                finalResult = converted
            }
            print("  └─ РЕЗУЛЬТАТ: 🟢 SWITCH → \(layout.rawValue.uppercased()) (\(reason))")
            print("     Исправлено: \"\(word)\" → \"\(finalResult)\"")
        }
        print()
    }

    // MARK: - Helpers

    static func detectLayout(_ word: String) -> KeyboardLayout {
        // Определяем раскладку по первому буквенному символу
        for char in word.lowercased() {
            // Кириллица
            if char >= "а" && char <= "я" || char == "ё" {
                return .russian
            }
            // Латиница
            if char >= "a" && char <= "z" {
                return .qwerty
            }
        }
        return .qwerty // default
    }

    static func isValidInDictionary(_ word: String, language: String) -> Bool {
        let spellChecker = NSSpellChecker.shared
        let languageCode = language == "ru" ? "ru_RU" : "en_US"

        let range = spellChecker.checkSpelling(
            of: word,
            startingAt: 0,
            language: languageCode,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )

        // Если range.location == NSNotFound — слово валидное
        return range.location == NSNotFound
    }
}
