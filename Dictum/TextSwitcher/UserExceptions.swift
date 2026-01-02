//
//  UserExceptions.swift
//  Dictum
//
//  Управление исключениями пользователя для TextSwitcher.
//  Слова в этом списке не будут автоматически исправляться.
//

import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "UserExceptions")

// MARK: - User Exception Model

/// Исключение пользователя — слово, которое не должно автоматически исправляться
struct UserException: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    let word: String
    let addedAt: Date
    let reason: ExceptionReason

    enum ExceptionReason: String, Codable {
        case manual = "manual"          // Добавлено вручную в настройках
        case autoLearned = "auto_learned"  // Обучено через double-Cmd
    }
}

/// Формат файла исключений для экспорта/импорта
struct ExceptionsFile: Codable {
    let version: Int
    let exportedAt: Date
    let exceptions: [UserException]

    static let currentVersion = 1
}

// MARK: - User Exceptions Manager

/// Менеджер исключений пользователя
class UserExceptionsManager: ObservableObject, @unchecked Sendable {

    /// Singleton
    static let shared = UserExceptionsManager()

    // MARK: - Published Properties

    /// Список исключений (для UI)
    @Published private(set) var exceptions: [UserException] = []

    /// Количество исключений
    var count: Int { exceptions.count }

    // MARK: - Private Properties

    /// Путь к файлу хранения
    private let storageURL: URL

    /// Set для быстрого поиска (lowercase)
    private var wordSet: Set<String> = []

    /// Очередь для thread-safe операций
    private let queue = DispatchQueue(label: "com.dictum.userexceptions", qos: .userInitiated)

    // MARK: - Initialization

    private init() {
        // ~/Library/Application Support/Dictum/text_switcher_exceptions.json
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dictumFolder = appSupport.appendingPathComponent("Dictum", isDirectory: true)

        // Создаём папку если не существует
        try? FileManager.default.createDirectory(at: dictumFolder, withIntermediateDirectories: true)

        self.storageURL = dictumFolder.appendingPathComponent("text_switcher_exceptions.json")

        loadFromDisk()

        logger.info("📚 UserExceptionsManager: загружено \(self.exceptions.count) исключений")
    }

    // MARK: - Public API

    /// Добавляет слово в исключения
    /// - Parameters:
    ///   - word: Слово для добавления
    ///   - reason: Причина добавления
    func addException(_ word: String, reason: UserException.ExceptionReason = .autoLearned) {
        let normalizedWord = word.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedWord.isEmpty else { return }

        // Проверяем дубликаты
        guard !wordSet.contains(normalizedWord) else {
            logger.debug("📚 UserExceptions: '\(word)' уже в списке")
            return
        }

        let exception = UserException(
            word: normalizedWord,
            addedAt: Date(),
            reason: reason
        )

        queue.async { [weak self] in
            guard let self = self else { return }

            self.wordSet.insert(normalizedWord)

            DispatchQueue.main.async {
                self.exceptions.append(exception)
                self.saveToDisk()
            }
        }

        logger.info("📚 UserExceptions: добавлено '\(word)' (reason: \(reason.rawValue))")
    }

    /// Добавляет несколько слов из текста (разбивает по пробелам)
    /// - Parameters:
    ///   - text: Текст с одним или несколькими словами
    ///   - reason: Причина добавления
    func addWordsFromText(_ text: String, reason: UserException.ExceptionReason = .autoLearned) {
        let words = text.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 3 }

        for word in words {
            addException(word, reason: reason)
        }
    }

    /// Удаляет слово из исключений
    /// - Parameter word: Слово для удаления
    func removeException(_ word: String) {
        let normalizedWord = word.lowercased()

        queue.async { [weak self] in
            guard let self = self else { return }

            self.wordSet.remove(normalizedWord)

            DispatchQueue.main.async {
                self.exceptions.removeAll { $0.word == normalizedWord }
                self.saveToDisk()
            }
        }

        logger.info("📚 UserExceptions: удалено '\(word)'")
    }

    /// Удаляет исключение по ID
    /// - Parameter id: ID исключения
    func removeException(id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }

            if let exception = self.exceptions.first(where: { $0.id == id }) {
                self.wordSet.remove(exception.word)
            }

            DispatchQueue.main.async {
                self.exceptions.removeAll { $0.id == id }
                self.saveToDisk()
            }
        }
    }

    /// Проверяет, содержится ли слово в исключениях
    /// - Parameter word: Слово для проверки
    /// - Returns: true если слово в исключениях
    func contains(_ word: String) -> Bool {
        return wordSet.contains(word.lowercased())
    }

    /// Очищает все исключения
    func clearAll() {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.wordSet.removeAll()

            DispatchQueue.main.async {
                self.exceptions.removeAll()
                self.saveToDisk()
            }
        }

        logger.info("📚 UserExceptions: очищено")
    }

    // MARK: - Export / Import

    /// Экспортирует исключения в JSON файл
    /// - Returns: URL сохранённого файла или nil при ошибке
    @MainActor
    func exportToFile() -> URL? {
        let panel = NSSavePanel()
        panel.title = "Экспорт исключений"
        panel.nameFieldStringValue = "dictum_exceptions_\(dateString()).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        let file = ExceptionsFile(
            version: ExceptionsFile.currentVersion,
            exportedAt: Date(),
            exceptions: exceptions
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(file)
            try data.write(to: url)

            logger.info("📚 UserExceptions: экспортировано \(self.exceptions.count) исключений в \(url.path)")
            return url
        } catch {
            logger.error("📚 UserExceptions: ошибка экспорта: \(error)")
            return nil
        }
    }

    /// Импортирует исключения из JSON файла
    /// - Parameter url: URL файла для импорта (если nil, показывает диалог)
    /// - Returns: Количество импортированных исключений или -1 при ошибке
    @MainActor
    func importFromFile(_ url: URL? = nil) -> Int {
        let fileURL: URL

        if let url = url {
            fileURL = url
        } else {
            let panel = NSOpenPanel()
            panel.title = "Импорт исключений"
            panel.allowedContentTypes = [.json]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false

            guard panel.runModal() == .OK, let selected = panel.url else {
                return -1
            }
            fileURL = selected
        }

        do {
            let data = try Data(contentsOf: fileURL)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let file = try decoder.decode(ExceptionsFile.self, from: data)

            var importedCount = 0

            for exception in file.exceptions {
                if !wordSet.contains(exception.word) {
                    wordSet.insert(exception.word)
                    exceptions.append(exception)
                    importedCount += 1
                }
            }

            saveToDisk()

            logger.info("📚 UserExceptions: импортировано \(importedCount) новых исключений из \(fileURL.path)")
            return importedCount
        } catch {
            logger.error("📚 UserExceptions: ошибка импорта: \(error)")
            return -1
        }
    }

    // MARK: - Private Methods

    /// Загружает исключения с диска
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            // Пробуем новый формат
            if let file = try? decoder.decode(ExceptionsFile.self, from: data) {
                exceptions = file.exceptions
            } else {
                // Fallback: старый формат (просто массив)
                exceptions = try decoder.decode([UserException].self, from: data)
            }

            // Строим Set для быстрого поиска
            wordSet = Set(exceptions.map { $0.word })
        } catch {
            logger.error("📚 UserExceptions: ошибка загрузки: \(error)")
        }
    }

    /// Сохраняет исключения на диск
    private func saveToDisk() {
        let file = ExceptionsFile(
            version: ExceptionsFile.currentVersion,
            exportedAt: Date(),
            exceptions: exceptions
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(file)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            logger.error("📚 UserExceptions: ошибка сохранения: \(error)")
        }
    }

    /// Форматирует дату для имени файла
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
