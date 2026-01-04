// NgramData.swift
// Runtime загрузка n-грамм из JSON файлов
//
// Sources:
// - Russian: Taiga Corpus (taiga_social_ru 50% + taiga_subtitles_ru 50%)
// - English: Preserved from previous version
//
// Данные хранятся в JSON для быстрой компиляции.
// Для регенерации: scripts/generate_ngrams.py → scripts/convert_ngrams_to_json.py

import Foundation

/// N-грамм статистика для детекции языка
enum NgramData {

    // MARK: - Data Storage

    /// Биграммы русского языка
    nonisolated(unsafe) private(set) static var ruBigrams: [String: Double] = [:]

    /// Триграммы русского языка
    nonisolated(unsafe) private(set) static var ruTrigrams: [String: Double] = [:]

    /// Биграммы английского языка
    nonisolated(unsafe) private(set) static var enBigrams: [String: Double] = [:]

    /// Триграммы английского языка
    nonisolated(unsafe) private(set) static var enTrigrams: [String: Double] = [:]

    /// Флаг загрузки
    nonisolated(unsafe) private(set) static var isLoaded: Bool = false

    // MARK: - Loading

    /// Загрузить все n-граммы из JSON файлов
    static func loadAll() {
        guard !isLoaded else { return }

        let startTime = CFAbsoluteTimeGetCurrent()

        ruBigrams = loadJSON("ngrams_ru_bigrams")
        ruTrigrams = loadJSON("ngrams_ru_trigrams")
        enBigrams = loadJSON("ngrams_en_bigrams")
        enTrigrams = loadJSON("ngrams_en_trigrams")

        isLoaded = true

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        NSLog("📊 NgramData loaded in %.1f ms: ru=\(ruBigrams.count)+\(ruTrigrams.count), en=\(enBigrams.count)+\(enTrigrams.count)", elapsed)
    }

    // MARK: - Private

    private static func loadJSON(_ name: String) -> [String: Double] {
        // Пробуем несколько путей для поддержки и app bundle, и CLI tool
        let possibleURLs: [URL?] = [
            // 1. App bundle (для Dictum.app)
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Resources"),
            // 2. CLI tool: Resources рядом с исполняемым файлом
            URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(name).json"),
            // 3. Development: путь относительно проекта
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(name).json")
        ]

        for possibleURL in possibleURLs {
            guard let url = possibleURL else { continue }
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    let dict = try JSONDecoder().decode([String: Double].self, from: data)
                    return dict
                } catch {
                    NSLog("⚠️ NgramData: ошибка загрузки \(name).json: \(error)")
                }
            }
        }

        NSLog("⚠️ NgramData: файл не найден: \(name).json")
        return [:]
    }
}
