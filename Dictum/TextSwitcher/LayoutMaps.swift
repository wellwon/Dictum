//
//  LayoutMaps.swift
//  Dictum
//
//  Таблицы соответствия QWERTY ↔ ЙЦУКЕН для TextSwitcher
//

import Foundation

// MARK: - Keyboard Layout

/// Тип раскладки клавиатуры
enum KeyboardLayout: String, Sendable {
    case qwerty = "en"
    case russian = "ru"

    /// Противоположная раскладка
    var opposite: KeyboardLayout {
        switch self {
        case .qwerty: return .russian
        case .russian: return .qwerty
        }
    }

    /// Код языка для NSSpellChecker/NLLanguageRecognizer
    var languageCode: String {
        return self.rawValue
    }
}

// MARK: - Layout Maps

/// Статические таблицы конвертации между раскладками
enum LayoutMaps {

    // MARK: - Common Punctuation (не конвертируется)

    /// Символы, которые ОДИНАКОВЫ в обеих раскладках и НЕ имеют маппинга.
    /// ТОЛЬКО эти символы НЕ должны конвертироваться при Double Cmd.
    ///
    /// ВАЖНО: Символы с маппингом (`;`, `'`, `[`, `]`, `,`, `.`, `:`, `"`, `/`, `~` и др.)
    /// НЕ входят в этот набор, т.к. они имеют реальный маппинг:
    /// - `;` → `ж`, `'` → `э`, `[` → `х`, `]` → `ъ`
    /// - `,` → `б`, `.` → `ю`, `/` → `.`
    /// - `:` → `Ж`, `"` → `Э`, `{` → `Х`, `}` → `Ъ`
    /// - `~` → `Ё`, `` ` `` → `ё`
    /// - `@` → `"`, `#` → `№`, `$` → `;`, `^` → `:`, `&` → `?`
    /// - `<` → `Б`, `>` → `Ю`, `?` → `,`
    static let commonPunctuation: Set<Character> = [
        // Shift-символы, которые ОДИНАКОВЫ на обеих раскладках:
        "!", "%", "*", "(", ")",        // Shift+1,5,8,9,0 = одинаковы
        // Математические символы (нет маппинга):
        "-", "_", "+", "=",
        // Слэши без маппинга:
        "\\", "|",
        // Пробельные:
        " ", "\t", "\n",
        // Цифры:
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"
    ]

    // MARK: - QWERTY → Russian (ЙЦУКЕН)

    /// Lowercase QWERTY → Russian
    private static let qwertyToRussianLower: [Character: Character] = [
        // Top row
        "`": "ё", "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
        // Middle row
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р",
        "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
        // Bottom row
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь",
        ",": "б", ".": "ю", "/": "."
    ]

    /// Uppercase QWERTY → Russian
    private static let qwertyToRussianUpper: [Character: Character] = [
        // Number row (Shift+)
        "!": "!", "@": "\"", "#": "№", "$": ";", "%": "%",
        "^": ":", "&": "?", "*": "*", "(": "(", ")": ")",
        // Top row
        "~": "Ё", "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З", "{": "Х", "}": "Ъ",
        // Middle row
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р",
        "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
        // Bottom row
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь",
        "<": "Б", ">": "Ю", "?": ","
    ]

    // MARK: - Russian → QWERTY

    /// Lowercase Russian → QWERTY
    private static let russianToQwertyLower: [Character: Character] = [
        // Top row
        "ё": "`", "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t",
        "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
        // Middle row
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h",
        "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
        // Bottom row
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m",
        "б": ",", "ю": "."
    ]

    /// Uppercase Russian → QWERTY
    private static let russianToQwertyUpper: [Character: Character] = [
        // Number row (Shift+ на русской раскладке)
        // Символы одинаковые на обеих раскладках:
        "!": "!",   // Shift+1 = ! на обеих
        "%": "%",   // Shift+5 = % на обеих
        "*": "*",   // Shift+8 = * на обеих
        "(": "(",   // Shift+9 = ( на обеих
        ")": ")",   // Shift+0 = ) на обеих
        // Символы разные:
        "\"": "@",  // Shift+2 RU = ", EN = @
        "№": "#",   // Shift+3 RU = №, EN = #
        ";": "$",   // Shift+4 RU = ;, EN = $
        ":": "^",   // Shift+6 RU = :, EN = ^
        "?": "&",   // Shift+7 RU = ?, EN = &
        // Top row
        "Ё": "~", "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T",
        "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P", "Х": "{", "Ъ": "}",
        // Middle row
        "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H",
        "О": "J", "Л": "K", "Д": "L", "Ж": ":", "Э": "\"",
        // Bottom row
        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M",
        "Б": "<", "Ю": ">"
        // УДАЛЕНО: ",": "?" — это было ошибкой (Shift+, = Б, а не ?)
    ]

    // MARK: - Combined Maps

    /// Полная таблица QWERTY → Russian (lower + upper)
    private static let qwertyToRussian: [Character: Character] = {
        var map = qwertyToRussianLower
        for (k, v) in qwertyToRussianUpper {
            map[k] = v
        }
        return map
    }()

    /// Полная таблица Russian → QWERTY (lower + upper)
    private static let russianToQwerty: [Character: Character] = {
        var map = russianToQwertyLower
        for (k, v) in russianToQwertyUpper {
            map[k] = v
        }
        return map
    }()

    // MARK: - Public API

    /// Конвертирует текст между раскладками
    /// - Parameters:
    ///   - text: Исходный текст
    ///   - from: Исходная раскладка
    ///   - to: Целевая раскладка
    ///   - includeAllSymbols: Если true, конвертирует ВСЕ символы включая пунктуацию (для double Cmd)
    /// - Returns: Конвертированный текст
    static func convert(_ text: String, from: KeyboardLayout, to: KeyboardLayout, includeAllSymbols: Bool = false) -> String {
        guard from != to else { return text }

        let primaryMap: [Character: Character]
        let reverseMap: [Character: Character]  // Для обратного поиска пунктуации

        switch (from, to) {
        case (.qwerty, .russian):
            primaryMap = qwertyToRussian
            reverseMap = [:]  // Не нужен для QWERTY → Russian
        case (.russian, .qwerty):
            primaryMap = russianToQwerty
            reverseMap = qwertyToRussian  // Для символов типа & → ? (& это QWERTY символ в русском тексте)
        default:
            return text
        }

        // Проверяем, все ли буквы в исходном тексте uppercase
        let letters = text.filter { $0.isLetter }
        let isAllUppercase = !letters.isEmpty && letters.allSatisfy { $0.isUppercase }

        let converted = String(text.map { char in
            // Символы без маппинга (!, %, *, цифры, пробелы) — не конвертируем
            if commonPunctuation.contains(char) {
                return char
            }

            // includeAllSymbols = false: конвертируем только буквы (для авто-исправления)
            if !includeAllSymbols && !char.isLetter {
                return char
            }

            // 1. Сначала пробуем основную карту
            if let mapped = primaryMap[char] {
                return mapped
            }

            // 2. Для не-букв при includeAllSymbols пробуем карту противоположного направления
            // Пример: текст "Как дела&" определён как русский, но & — это QWERTY символ
            // reverseMap = qwertyToRussian, где "&" → "?"
            // При конвертации Russian→QWERTY, "&" должен стать "?" (то что получилось бы на RU раскладке)
            if includeAllSymbols && !char.isLetter && !reverseMap.isEmpty {
                if let mappedFromReverse = reverseMap[char] {
                    return mappedFromReverse
                }
            }

            return char
        })

        // Если исходный текст был ALL CAPS, приводим результат к uppercase
        // Это нужно для случаев типа "HF,JNF" → "РАБОТА" (не "РАбОТА")
        if isAllUppercase {
            return converted.uppercased()
        }

        return converted
    }

    /// Определяет раскладку по содержимому текста
    /// - Parameter text: Текст для анализа
    /// - Returns: Предполагаемая раскладка или nil если не определена
    static func detectLayout(in text: String) -> KeyboardLayout? {
        var russianCount = 0
        var latinCount = 0

        for char in text.lowercased() {
            if russianToQwertyLower.keys.contains(char) {
                russianCount += 1
            } else if qwertyToRussianLower.keys.contains(char) {
                latinCount += 1
            }
        }

        if russianCount > latinCount {
            return .russian
        } else if latinCount > russianCount {
            return .qwerty
        }

        return nil
    }

    /// Проверяет, содержит ли текст только символы одной раскладки
    /// - Parameters:
    ///   - text: Текст для проверки
    ///   - layout: Ожидаемая раскладка
    /// - Returns: true если текст содержит только символы указанной раскладки
    static func isPureLayout(_ text: String, layout: KeyboardLayout) -> Bool {
        let chars = Set(text.lowercased())

        switch layout {
        case .russian:
            // Все буквенные символы должны быть русскими
            for char in chars {
                if char.isLetter && !russianToQwertyLower.keys.contains(char) {
                    return false
                }
            }
        case .qwerty:
            // Все буквенные символы должны быть латиницей
            for char in chars {
                if char.isLetter && !qwertyToRussianLower.keys.contains(char) {
                    return false
                }
            }
        }

        return true
    }

    /// Набор символов русской раскладки (только lowercase)
    static let russianCharacters: Set<Character> = Set(russianToQwertyLower.keys)

    /// Набор символов латинской раскладки (только lowercase)
    static let qwertyCharacters: Set<Character> = Set(qwertyToRussianLower.keys)

    /// Все символы QWERTY которые можно конвертировать (lower + upper/shifted)
    /// Включает: {, }, <, >, :, ", ~ и другие shifted-символы
    static let allQwertyMappableCharacters: Set<Character> = {
        var chars = Set(qwertyToRussianLower.keys)
        chars.formUnion(qwertyToRussianUpper.keys)
        return chars
    }()

    /// Все символы Russian которые можно конвертировать (lower + upper)
    static let allRussianMappableCharacters: Set<Character> = {
        var chars = Set(russianToQwertyLower.keys)
        chars.formUnion(russianToQwertyUpper.keys)
        return chars
    }()

    // MARK: - Toggle Layout (для смешанных текстов)

    /// Переключает раскладку для каждого символа независимо
    /// Используется для CMD+мышь, когда текст может быть смешанным (латиница + кириллица)
    /// - Parameter text: Текст для конвертации
    /// - Returns: Текст с переключённой раскладкой для каждого символа
    static func toggleLayout(_ text: String) -> String {
        return String(text.map { char in
            // Русский символ → QWERTY
            if let mapped = russianToQwerty[char] {
                return mapped
            }

            // QWERTY → Russian
            if let mapped = qwertyToRussian[char] {
                return mapped
            }

            // Символ не в таблицах — оставляем как есть
            return char
        })
    }
}
