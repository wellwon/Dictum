//
//  ForcedConversions.swift
//  Dictum
//
//  СЛОЙ 0.5 валидации — принудительные конвертации (белый список).
//  Слова в этом списке ВСЕГДА конвертируются в указанную форму.
//  Приоритет ВЫШЕ словаря!
//
//  Пример: руддщ → hello (пользователь подтвердил через double Cmd)
//

import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "ForcedConversions")

// MARK: - Forced Conversion Model

/// Принудительная конвертация — слово которое ВСЕГДА конвертируется
struct ForcedConversion: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let originalWord: String      // Что набрано (руддщ)
    let convertedWord: String     // Во что конвертировать (hello)
    let addedAt: Date
    var confirmationCount: Int    // 3+ = жёсткое знание

    /// Является ли жёстким знанием (3+ подтверждения)
    var isHardKnowledge: Bool {
        confirmationCount >= 3
    }
}

/// Формат файла для экспорта/импорта
struct ForcedConversionsFile: Codable {
    let version: Int
    let exportedAt: Date
    let conversions: [ForcedConversion]

    static let currentVersion = 1
}

// MARK: - Forced Conversions Manager

/// Менеджер принудительных конвертаций (белый список)
class ForcedConversionsManager: ObservableObject, @unchecked Sendable {

    /// Singleton
    static let shared = ForcedConversionsManager()

    // MARK: - Published Properties

    /// Список конвертаций (для UI)
    @Published private(set) var conversions: [ForcedConversion] = []

    /// Количество конвертаций
    var count: Int { conversions.count }

    /// Количество жёстких знаний
    var hardKnowledgeCount: Int { conversions.filter { $0.isHardKnowledge }.count }

    // MARK: - Private Properties

    /// Путь к файлу хранения
    private let storageURL: URL

    /// Map для быстрого O(1) lookup: originalWord → convertedWord
    private var lookupMap: [String: String] = [:]

    /// Очередь для thread-safe операций
    private let queue = DispatchQueue(label: "com.dictum.forcedconversions", qos: .userInitiated)

    // MARK: - Initialization

    private init() {
        // ~/Library/Application Support/Dictum/forced_conversions.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dictumFolder = appSupport.appendingPathComponent("Dictum", isDirectory: true)

        // Создаём папку если не существует
        try? FileManager.default.createDirectory(at: dictumFolder, withIntermediateDirectories: true)

        self.storageURL = dictumFolder.appendingPathComponent("forced_conversions.json")

        loadFromDisk()

        logger.info("📗 ForcedConversionsManager: загружено \(self.conversions.count) конвертаций (\(self.hardKnowledgeCount) жёстких)")
    }

    // MARK: - Public API

    /// Получает конвертацию для слова (O(1) lookup)
    /// - Parameter word: Слово для проверки (case-insensitive)
    /// - Returns: Конвертированное слово или nil если не найдено
    func getConversion(for word: String) -> String? {
        let normalized = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let result = lookupMap[normalized]

        if result != nil {
            logger.debug("📗 getConversion: '\(word)' → '\(result ?? "nil")'")
        }

        return result
    }

    /// Добавляет новую конвертацию или увеличивает счётчик существующей
    /// - Parameters:
    ///   - original: Оригинальное слово (руддщ)
    ///   - converted: Конвертированное слово (hello)
    func addConversion(original: String, converted: String) {
        let normalizedOriginal = original.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedConverted = converted.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedOriginal.isEmpty, !normalizedConverted.isEmpty else { return }

        // Проверяем существует ли уже
        if lookupMap[normalizedOriginal] != nil {
            // Увеличиваем счётчик
            incrementConfirmation(original: normalizedOriginal)
            return
        }

        let conversion = ForcedConversion(
            originalWord: normalizedOriginal,
            convertedWord: normalizedConverted,
            addedAt: Date(),
            confirmationCount: 1
        )

        queue.async { [weak self] in
            guard let self = self else { return }

            self.lookupMap[normalizedOriginal] = normalizedConverted

            DispatchQueue.main.async {
                self.conversions.append(conversion)
                self.saveToDisk()
            }
        }

        logger.info("📗 addConversion: '\(original)' → '\(converted)'")
    }

    /// Увеличивает счётчик подтверждений для конвертации
    /// - Parameter original: Оригинальное слово
    func incrementConfirmation(original: String) {
        let normalized = original.lowercased()

        queue.async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if let index = self.conversions.firstIndex(where: { $0.originalWord == normalized }) {
                    self.conversions[index].confirmationCount += 1
                    let count = self.conversions[index].confirmationCount

                    self.saveToDisk()

                    if count == 3 {
                        logger.info("🔒 Жёсткое знание: '\(original)' → '\(self.conversions[index].convertedWord)' (count=\(count))")
                    } else {
                        logger.debug("📗 incrementConfirmation: '\(original)' count=\(count)")
                    }
                }
            }
        }
    }

    /// Удаляет конвертацию
    /// - Parameter original: Оригинальное слово для удаления
    func removeConversion(original: String) {
        let normalized = original.lowercased()

        queue.async { [weak self] in
            guard let self = self else { return }

            self.lookupMap.removeValue(forKey: normalized)

            DispatchQueue.main.async {
                self.conversions.removeAll { $0.originalWord == normalized }
                self.saveToDisk()
            }
        }

        logger.info("📗 removeConversion: '\(original)'")
    }

    /// Удаляет конвертацию по ID
    /// - Parameter id: ID конвертации
    func removeConversion(id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let conversion = self.conversions.first(where: { $0.id == id }) {
                self.lookupMap.removeValue(forKey: conversion.originalWord)
            }

            DispatchQueue.main.async {
                self.conversions.removeAll { $0.id == id }
                self.saveToDisk()
            }
        }
    }

    /// Очищает все конвертации
    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.lookupMap.removeAll()

            DispatchQueue.main.async {
                self.conversions.removeAll()
                self.saveToDisk()
            }
        }

        logger.info("📗 ForcedConversions: очищено")
    }

    /// Проверяет, содержится ли слово в конвертациях
    /// - Parameter word: Слово для проверки
    /// - Returns: true если слово в конвертациях
    func contains(_ word: String) -> Bool {
        return lookupMap[word.lowercased()] != nil
    }

    // MARK: - Private Methods

    /// Загружает конвертации с диска
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Пробуем новый формат
            if let file = try? decoder.decode(ForcedConversionsFile.self, from: data) {
                conversions = file.conversions
            } else {
                // Fallback: старый формат (просто массив)
                conversions = try decoder.decode([ForcedConversion].self, from: data)
            }

            // Строим Map для быстрого поиска
            lookupMap = Dictionary(uniqueKeysWithValues: conversions.map { ($0.originalWord, $0.convertedWord) })
        } catch {
            logger.error("📗 ForcedConversions: ошибка загрузки: \(error)")
        }
    }

    /// Сохраняет конвертации на диск
    private func saveToDisk() {
        let file = ForcedConversionsFile(
            version: ForcedConversionsFile.currentVersion,
            exportedAt: Date(),
            conversions: conversions
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(file)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("📗 ForcedConversions: ошибка сохранения: \(error)")
        }
    }
}
