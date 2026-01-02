//
//  NgramScorer.swift
//  Dictum
//
//  N-грамм скоринг для определения вероятного языка текста.
//  Использует данные из NgramData.swift (автогенерированные из Leipzig Corpora).
//

import Foundation
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "NgramScorer")

// MARK: - N-gram Scorer

/// Скоринг текста на основе N-грамм статистики
class NgramScorer: @unchecked Sendable {

    /// Singleton
    static let shared = NgramScorer()

    // MARK: - Data References (loaded from JSON at runtime)

    private var ruBigrams: [String: Double] { NgramData.ruBigrams }
    private var enBigrams: [String: Double] { NgramData.enBigrams }
    private var ruTrigrams: [String: Double] { NgramData.ruTrigrams }
    private var enTrigrams: [String: Double] { NgramData.enTrigrams }

    // MARK: - Constants

    /// Вероятность для неизвестных N-грамм (очень низкая)
    private let unknownProbability: Double = 0.00001

    /// Вес триграмм относительно биграмм
    private let trigramWeight: Double = 1.5

    // MARK: - Initialization

    private init() {
        // Загружаем n-граммы из JSON при первом обращении
        NgramData.loadAll()
        logger.info("📊 NgramScorer ready: ru=\(self.ruBigrams.count)+\(self.ruTrigrams.count), en=\(self.enBigrams.count)+\(self.enTrigrams.count)")
    }

    // MARK: - Public API

    /// Вычисляет скор текста для указанного языка
    /// - Parameters:
    ///   - text: Текст для анализа
    ///   - language: Код языка ("ru" или "en")
    /// - Returns: Логарифмический скор (чем выше, тем более вероятен язык)
    func score(_ text: String, language: String) -> Double {
        let normalizedText = text.lowercased()
        guard normalizedText.count >= 2 else { return -Double.infinity }

        let bigrams = language == "ru" ? ruBigrams : enBigrams
        let trigrams = language == "ru" ? ruTrigrams : enTrigrams

        var totalScore: Double = 0.0

        // Биграммы
        let chars = Array(normalizedText)
        for i in 0..<(chars.count - 1) {
            let bigram = String(chars[i...i+1])
            let prob = bigrams[bigram] ?? unknownProbability
            totalScore += log(prob)
        }

        // Триграммы (взвешенные)
        if chars.count >= 3 {
            for i in 0..<(chars.count - 2) {
                let trigram = String(chars[i...i+2])
                let prob = trigrams[trigram] ?? unknownProbability
                totalScore += log(prob) * trigramWeight
            }
        }

        return totalScore
    }

    /// Определяет наиболее вероятный язык текста
    /// - Parameter text: Текст для анализа
    /// - Returns: Код языка ("ru" или "en") или nil если не определён
    func probableLanguage(_ text: String) -> String? {
        guard text.count >= 3 else { return nil }

        let ruScore = score(text, language: "ru")
        let enScore = score(text, language: "en")

        // Нужна значительная разница для уверенного определения
        let threshold: Double = 2.0

        if ruScore > enScore + threshold {
            return "ru"
        } else if enScore > ruScore + threshold {
            return "en"
        }

        return nil
    }

    /// Сравнивает скоры двух текстов для определения какой более вероятен
    /// - Parameters:
    ///   - original: Оригинальный текст
    ///   - originalLanguage: Язык оригинала
    ///   - converted: Конвертированный текст
    ///   - convertedLanguage: Язык конвертированного
    /// - Returns: Отношение скоров (>1 означает converted лучше)
    func compareScores(
        original: String,
        originalLanguage: String,
        converted: String,
        convertedLanguage: String
    ) -> Double {
        let originalScore = score(original, language: originalLanguage)
        let convertedScore = score(converted, language: convertedLanguage)

        // Избегаем деления на очень маленькие числа
        guard originalScore > -1000, convertedScore > -1000 else {
            return 1.0 // Неопределённо
        }

        // Возвращаем отношение экспонент (разницу в логарифмах)
        return exp(convertedScore - originalScore)
    }
}
