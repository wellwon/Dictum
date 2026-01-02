//
//  TechBuzzwordsManager.swift
//  Dictum
//
//  СЛОЙ 0 валидации — технические термины которые НИКОГДА не конвертируются.
//  Загружает 1300+ терминов из tech_buzzwords_2025.json
//

import Foundation
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "TechBuzzwords")

// MARK: - Tech Buzzwords Manager

/// Менеджер технических терминов — СЛОЙ 0 валидации
/// Слова из этого списка НИКОГДА не конвертируются (docker, npm, git, etc.)
class TechBuzzwordsManager: @unchecked Sendable {

    /// Singleton
    static let shared = TechBuzzwordsManager()

    /// Fast O(1) lookup
    private var buzzwordsSet: Set<String> = []

    // MARK: - Compound Buzzwords Support (gpt-4, c++, react-native)

    /// Символы которые могут быть частью составных терминов
    private static let compoundChars: Set<Character> = ["-", "+", "#", "."]

    /// Префиксы составных buzzwords для O(1) look-ahead
    /// Например: "gpt-" для "gpt-4", "react-" для "react-native"
    private var compoundPrefixes: Set<String> = []

    // MARK: - Initialization

    private init() {
        loadBuzzwords()
        buildCompoundPrefixes()
    }

    // MARK: - Public API

    /// Проверяет есть ли слово в списке tech buzzwords
    /// - Parameter word: Слово для проверки (case-insensitive)
    /// - Returns: true если слово в списке buzzwords
    func contains(_ word: String) -> Bool {
        let lowercased = word.lowercased()
        let found = buzzwordsSet.contains(lowercased)
        // Детальное логирование для отладки
        NSLog("🔧 TechBuzzwords.contains('%@' → '%@') = %@ (set.count=%d)",
              word, lowercased, found ? "YES" : "NO", buzzwordsSet.count)
        return found
    }

    /// Количество загруженных терминов
    var count: Int {
        return buzzwordsSet.count
    }

    // MARK: - Compound Buzzwords API

    /// Проверяет является ли символ частью составного термина
    /// - Parameter char: Символ для проверки (-, +, #, .)
    /// - Returns: true если символ может быть частью составного buzzword
    static func isCompoundChar(_ char: Character) -> Bool {
        return compoundChars.contains(char)
    }

    /// Проверяет может ли текущий буфер + следующий символ образовать составной buzzword
    /// Используется в KeyboardMonitor для look-ahead при встрече punctuation
    /// - Parameters:
    ///   - buffer: Текущее накопленное слово (например "gpt" или "пзе" на русской раскладке)
    ///   - nextChar: Следующий символ (например "-")
    /// - Returns: true если есть buzzword начинающийся с buffer+nextChar (например "gpt-")
    func mightBeCompound(_ buffer: String, nextChar: Character) -> Bool {
        guard Self.compoundChars.contains(nextChar) else { return false }
        let potential = buffer.lowercased() + String(nextChar).lowercased()

        // Проверяем оригинальный буфер
        if compoundPrefixes.contains(potential) {
            NSLog("🔧 TechBuzzwords.mightBeCompound('%@' + '%@') = YES — продолжаем накопление", buffer, String(nextChar))
            return true
        }

        // ИСПРАВЛЕНИЕ: Также проверяем СКОНВЕРТИРОВАННУЮ версию
        // Это нужно для случаев типа "вфдд-" → "dall-" (DALL-E)
        let swappedRU = LayoutMaps.convert(buffer, from: .russian, to: .qwerty)
        let swappedEN = LayoutMaps.convert(buffer, from: .qwerty, to: .russian)
        let potentialRU = swappedRU.lowercased() + String(nextChar).lowercased()
        let potentialEN = swappedEN.lowercased() + String(nextChar).lowercased()

        if compoundPrefixes.contains(potentialRU) {
            NSLog("🔧 TechBuzzwords.mightBeCompound('%@'→'%@' + '%@') = YES — corrupted compound", buffer, swappedRU, String(nextChar))
            return true
        }
        if compoundPrefixes.contains(potentialEN) {
            NSLog("🔧 TechBuzzwords.mightBeCompound('%@'→'%@' + '%@') = YES — corrupted compound", buffer, swappedEN, String(nextChar))
            return true
        }

        return false
    }

    // MARK: - Private Methods

    /// Загружает buzzwords из JSON файла
    private func loadBuzzwords() {
        // Пробуем несколько путей для поддержки и app bundle, и CLI tool
        let possibleURLs: [URL?] = [
            // 1. App bundle (для Dictum.app)
            Bundle.main.url(forResource: "tech_buzzwords_2025", withExtension: "json", subdirectory: "Resources"),
            // 2. CLI tool: Resources рядом с исполняемым файлом
            URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent("tech_buzzwords_2025.json"),
            // 3. Development: путь относительно исходного файла
            // TechBuzzwordsManager.swift в Dictum/TextSwitcher/, Resources в Dictum/Resources/
            // Поэтому нужно ДВА уровня вверх (в отличие от NgramData.swift который в Dictum/)
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // → Dictum/TextSwitcher/
                .deletingLastPathComponent()  // → Dictum/
                .appendingPathComponent("Resources")
                .appendingPathComponent("tech_buzzwords_2025.json")
        ]

        var foundURL: URL?
        for possibleURL in possibleURLs {
            guard let url = possibleURL else { continue }
            if FileManager.default.fileExists(atPath: url.path) {
                foundURL = url
                break
            }
        }

        guard let url = foundURL else {
            logger.warning("⚠️ TechBuzzwordsManager: tech_buzzwords_2025.json не найден")
            NSLog("⚠️ TechBuzzwordsManager: JSON НЕ НАЙДЕН! buzzwordsSet будет пустым!")
            return
        }
        NSLog("🔧 TechBuzzwordsManager: найден JSON по пути %@", url.path)

        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
                logger.warning("⚠️ TechBuzzwordsManager: неверный формат JSON")
                return
            }

            // Собираем все слова из всех категорий
            for (category, words) in json {
                for word in words {
                    buzzwordsSet.insert(word.lowercased())
                }
                logger.debug("🔧 TechBuzzwordsManager: категория '\(category)' — \(words.count) терминов")
            }

            logger.info("✅ TechBuzzwordsManager: загружено \(self.buzzwordsSet.count) терминов из \(json.count) категорий")
            NSLog("🔧 TechBuzzwordsManager: ЗАГРУЖЕНО %d терминов из %d категорий", buzzwordsSet.count, json.count)

        } catch {
            logger.error("⚠️ TechBuzzwordsManager: ошибка загрузки JSON — \(error.localizedDescription)")
        }
    }

    /// Строит множество префиксов для составных buzzwords
    /// Например: для "gpt-4" добавляет "gpt-", для "c++" добавляет "c+", для "react-native" добавляет "react-"
    private func buildCompoundPrefixes() {
        compoundPrefixes.removeAll()

        for buzzword in buzzwordsSet {
            // Ищем все позиции compound символов в слове
            for (index, char) in buzzword.enumerated() {
                if Self.compoundChars.contains(char) {
                    // Добавляем префикс включая compound символ
                    let prefixEndIndex = buzzword.index(buzzword.startIndex, offsetBy: index + 1)
                    let prefix = String(buzzword[..<prefixEndIndex])
                    compoundPrefixes.insert(prefix)
                }
            }
        }

        logger.info("🔧 TechBuzzwordsManager: построено \(self.compoundPrefixes.count) compound prefixes")
        NSLog("🔧 TechBuzzwordsManager: compound prefixes: %d (примеры: %@)",
              compoundPrefixes.count,
              Array(compoundPrefixes.prefix(10)).joined(separator: ", "))
    }
}
