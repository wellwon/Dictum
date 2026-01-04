//
//  DoubleCmdHandler.swift
//  Dictum
//
//  Обработчик Double Cmd для ручной смены раскладки.
//
//  ИЗОЛИРОВАННЫЙ МОДУЛЬ:
//  - НЕ влияет на авто-коррекцию (отдельная логика)
//  - Использует AXUIElement API для АТОМАРНОЙ замены текста
//  - Fallback на CGEvent для Electron приложений
//
//  РЕШАЕТ ПРОБЛЕМУ RACE CONDITION:
//  - Старый подход: deleteCharacters() + pasteText() = race condition
//  - Новый подход: AXUIElementSetAttributeValue() = одна атомарная операция
//

import Foundation
import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "DoubleCmdHandler")

// MARK: - Double Cmd Handler

/// Обработчик Double Cmd для ручной смены раскладки
/// ИЗОЛИРОВАННЫЙ модуль - не влияет на авто-коррекцию
@MainActor
final class DoubleCmdHandler {

    // MARK: - Singleton

    static let shared = DoubleCmdHandler()

    private init() {}

    // MARK: - Dependencies

    private let textAccessor = AXTextAccessor.shared

    // MARK: - State

    /// Последняя ручная замена (для отката и обучения)
    private var lastManualSwitch: (original: String, converted: String, time: Date)?

    /// Ожидающее обучение (слова + таймер)
    private var pendingLearning: (words: [String], timer: DispatchWorkItem)?

    /// Задержка перед обучением (секунды)
    private let learningDelay: TimeInterval = 2.0

    /// Флаг: идёт замена (для блокировки повторных вызовов)
    private var isReplacing: Bool = false

    // MARK: - External State (из KeyboardMonitor)

    /// Ссылка на KeyboardMonitor для доступа к wordBuffer и lastProcessedWord
    weak var keyboardMonitor: KeyboardMonitor?

    // MARK: - Callbacks

    /// Callback при успешном обучении
    var onLearned: ((String) -> Void)?

    /// Callback при ручной смене (для статистики)
    var onManualSwitch: (() -> Void)?

    // MARK: - Public API

    /// Обработать Double Cmd
    /// - Parameters:
    ///   - wordBuffer: Текущий буфер слова из KeyboardMonitor
    ///   - lastProcessedWord: Последнее обработанное слово
    ///   - pendingPunctuation: Накопленная пунктуация
    ///   - lastAutoSwitch: Последнее автоисправление (для отката)
    /// - Returns: true если обработано, false если ничего не сделано
    @discardableResult
    func handleDoubleCmdAction(
        wordBuffer: String,
        lastProcessedWord: String,
        pendingPunctuation: String,
        lastAutoSwitch: (original: String, converted: String, time: Date)?
    ) -> Bool {
        // Защита от повторных вызовов
        guard !isReplacing else {
            logger.debug("⌨️ Double Cmd: пропущено (isReplacing=true)")
            return false
        }

        isReplacing = true
        defer {
            // Разблокируем через 200ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.isReplacing = false
            }
        }

        NSLog("⌨️ DoubleCmdHandler: wordBuffer='%@', lastProcessedWord='%@', pendingPunctuation='%@'",
              wordBuffer, lastProcessedWord, pendingPunctuation)

        // СЛУЧАЙ 1: Есть pending обучение → откат, отмена обучения
        if cancelPendingLearningIfNeeded() {
            return true
        }

        // СЛУЧАЙ 2: Есть недавнее автоисправление → откат
        if rollbackAutoSwitchIfNeeded(lastAutoSwitch) {
            return true
        }

        // СЛУЧАЙ 3: Получить текст для конвертации
        let textToConvert = getTextToConvert(
            wordBuffer: wordBuffer,
            lastProcessedWord: lastProcessedWord,
            pendingPunctuation: pendingPunctuation
        )

        guard let textInfo = textToConvert else {
            NSLog("⌨️ DoubleCmdHandler: нет текста для конвертации")
            return false
        }

        // СЛУЧАЙ 4: Конвертировать текст
        convertText(textInfo)
        return true
    }

    // MARK: - Case 1: Cancel Pending Learning

    /// Отменяет pending обучение и откатывает замену
    /// - Returns: true если было что отменять
    private func cancelPendingLearningIfNeeded() -> Bool {
        guard let pending = pendingLearning else { return false }

        pending.timer.cancel()
        pendingLearning = nil

        // Откатываем обратно на оригинал
        if let last = lastManualSwitch {
            // Используем AX для атомарного отката
            let rollbackInfo = TextInfo(
                text: last.converted,
                detectedLayout: LayoutMaps.detectLayout(in: last.converted) ?? .qwerty,
                isSelection: true,  // Текст должен быть ещё выделен
                cursorPosition: nil
            )

            if !textAccessor.replaceText(with: last.original, info: rollbackInfo) {
                // Fallback на TextReplacer
                TextReplacer.shared.replaceSelectedText(with: last.original)
            }

            NSLog("⌨️ Double CMD: откат '%@' → '%@', обучение отменено", last.converted, last.original)
            logger.info("⏪ Откат: \(last.converted) → \(last.original), обучение отменено")
        }

        lastManualSwitch = nil
        return true
    }

    // MARK: - Case 2: Rollback Auto-Switch

    /// Откатывает недавнее автоисправление
    /// - Parameter lastAutoSwitch: Информация о последнем автоисправлении
    /// - Returns: true если был откат
    private func rollbackAutoSwitchIfNeeded(_ lastAutoSwitch: (original: String, converted: String, time: Date)?) -> Bool {
        let autoRollbackWindow: TimeInterval = 3.0

        guard let autoSwitch = lastAutoSwitch,
              Date().timeIntervalSince(autoSwitch.time) < autoRollbackWindow else {
            return false
        }

        // Откат автоисправления
        let rollbackInfo = TextInfo(
            text: autoSwitch.converted,
            detectedLayout: LayoutMaps.detectLayout(in: autoSwitch.converted) ?? .qwerty,
            isSelection: false,
            cursorPosition: nil
        )

        if !textAccessor.replaceText(with: autoSwitch.original, info: rollbackInfo) {
            // Fallback на TextReplacer
            TextReplacer.shared.replaceCharactersViaSelection(
                count: autoSwitch.converted.count,
                newText: autoSwitch.original
            )
        }

        NSLog("⌨️ Double CMD: откат автоисправления '%@' → '%@'", autoSwitch.converted, autoSwitch.original)
        logger.info("⏪ Откат автоисправления: \(autoSwitch.converted) → \(autoSwitch.original)")

        // Сигнализируем KeyboardMonitor очистить lastAutoSwitch
        NotificationCenter.default.post(name: .doubleCmdAutoRollback, object: nil)

        return true
    }

    // MARK: - Case 3: Get Text to Convert

    /// Получает текст для конвертации
    private func getTextToConvert(
        wordBuffer: String,
        lastProcessedWord: String,
        pendingPunctuation: String
    ) -> TextInfo? {
        let minWordLength = 2

        NSLog("🔍 getTextToConvert: wordBuffer='%@' (%d), lastProcessedWord='%@' (%d), pendingPunctuation='%@'",
              wordBuffer, wordBuffer.count, lastProcessedWord, lastProcessedWord.count, pendingPunctuation)

        // Приоритет 1: AXUIElement — ТОЛЬКО для выделенного текста!
        // НЕ используем AX для определения последнего слова — wordBuffer надёжнее
        if let axTextInfo = textAccessor.getTextForConversion(wordBuffer: "") {
            if axTextInfo.isSelection && axTextInfo.text.count >= minWordLength {
                NSLog("✅ getTextToConvert: AX вернул ВЫДЕЛЕНИЕ '%@'", axTextInfo.text)
                return axTextInfo
            } else {
                NSLog("⏭️ getTextToConvert: AX вернул НЕ-выделение '%@' — игнорируем, используем wordBuffer",
                      axTextInfo.text)
            }
        }

        // Приоритет 2: wordBuffer + pendingPunctuation (ГЛАВНЫЙ для режима набора!)
        let wordWithPunc = wordBuffer + pendingPunctuation
        if !wordBuffer.isEmpty && wordWithPunc.count >= minWordLength {
            NSLog("✅ getTextToConvert: используем wordBuffer+punc '%@'", wordWithPunc)
            return TextInfo(
                text: wordWithPunc,
                detectedLayout: LayoutMaps.detectLayout(in: wordWithPunc) ?? .qwerty,
                isSelection: false,
                cursorPosition: nil
            )
        }

        // Приоритет 3: lastProcessedWord + pendingPunctuation (для случая когда слово уже обработано)
        let combined = lastProcessedWord + pendingPunctuation
        if !combined.isEmpty && combined.count >= minWordLength {
            NSLog("✅ getTextToConvert: используем lastProcessedWord+punc '%@'", combined)
            return TextInfo(
                text: combined,
                detectedLayout: LayoutMaps.detectLayout(in: combined) ?? .qwerty,
                isSelection: false,
                cursorPosition: nil
            )
        }

        NSLog("❌ getTextToConvert: нет текста для конвертации")
        return nil
    }

    // MARK: - Case 4: Convert Text

    /// Конвертирует текст
    private func convertText(_ info: TextInfo) {
        let converted: String

        if info.isSelection {
            // Для выделенного текста используем toggleLayout (посимвольная конвертация)
            // Это корректно обрабатывает смешанные тексты
            converted = LayoutMaps.toggleLayout(info.text)
        } else {
            // Для последнего слова используем convert с includeAllSymbols
            converted = LayoutMaps.convert(
                info.text,
                from: info.detectedLayout,
                to: info.detectedLayout.opposite,
                includeAllSymbols: true
            )
        }

        NSLog("⌨️ DoubleCmdHandler: конвертация '%@' → '%@'", info.text, converted)

        // АТОМАРНАЯ замена через AXUIElement
        let result = textAccessor.replaceTextWithResult(with: converted, info: info)

        switch result {
        case .success:
            // AX успешно заменил текст
            break

        case .failedNoSelection:
            // AX не смог выделить текст — полный fallback (выделить + paste)
            NSLog("⌨️ DoubleCmdHandler: AX не смог выделить, полный fallback")
            fallbackReplace(newText: converted, info: info, textAlreadySelected: false)

        case .failedAfterSelection:
            // AX выделил текст но не смог заменить — просто paste (текст УЖЕ выделен!)
            NSLog("⌨️ DoubleCmdHandler: AX выделил но не заменил, paste-only fallback")
            fallbackReplace(newText: converted, info: info, textAlreadySelected: true)
        }

        // Сохранить для отката
        lastManualSwitch = (original: info.text, converted: converted, time: Date())

        // Определяем целевую раскладку
        let targetLayout = LayoutMaps.detectLayout(in: converted) ?? info.detectedLayout.opposite

        // Переключить системную раскладку
        switchKeyboardLayout(to: targetLayout)

        // Уведомляем KeyboardMonitor об обновлении состояния
        NotificationCenter.default.post(
            name: .doubleCmdCompleted,
            object: nil,
            userInfo: [
                "convertedWord": String(converted.filter { $0.isLetter }),
                "original": info.text
            ]
        )

        // Запустить таймер обучения (если включено)
        if TextSwitcherManager.shared.isLearningEnabled {
            startLearningTimer(original: info.text, converted: converted)
            logger.info("🔄 Ручная смена: \(info.text) → \(converted), ожидание \(self.learningDelay) сек...")
        } else {
            logger.info("🔄 Ручная смена: \(info.text) → \(converted) [обучение выключено]")
            onManualSwitch?()
        }
    }

    // MARK: - Fallback Replace (CGEvent)

    /// Fallback замена через CGEvent (для Electron приложений)
    /// Использует СИНХРОННЫЕ методы для избежания race conditions
    /// - Parameters:
    ///   - newText: Новый текст для вставки
    ///   - info: Информация о тексте
    ///   - textAlreadySelected: true если AX уже выделил текст (не выделять снова!)
    private func fallbackReplace(newText: String, info: TextInfo, textAlreadySelected: Bool) {
        if info.isSelection || textAlreadySelected {
            // Выделение уже есть (либо было изначально, либо AX выделил)
            // Просто paste — текст заменится автоматически
            TextReplacer.shared.pasteTextSync(newText)
        } else {
            // Нужно выделить + paste с СИНХРОННЫМИ задержками
            TextReplacer.shared.replaceCharactersSync(
                count: info.text.count,
                newText: newText
            )
        }
    }

    // MARK: - Keyboard Layout Switching

    /// Переключает системную раскладку клавиатуры
    private func switchKeyboardLayout(to targetLayout: KeyboardLayout) {
        let targetSourceID: String
        switch targetLayout {
        case .qwerty:
            targetSourceID = "com.apple.keylayout.ABC"
        case .russian:
            targetSourceID = "com.apple.keylayout.Russian"
        }

        let filter: [String: Any] = [
            kTISPropertyInputSourceID as String: targetSourceID
        ]

        guard let sourceList = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource],
              let source = sourceList.first else {
            // Пробуем альтернативные ID
            let alternativeIDs: [String]
            switch targetLayout {
            case .qwerty:
                alternativeIDs = ["com.apple.keylayout.US", "com.apple.keylayout.USExtended"]
            case .russian:
                alternativeIDs = ["com.apple.keylayout.RussianWin", "com.apple.keylayout.Russian-Phonetic"]
            }

            for altID in alternativeIDs {
                let altFilter: [String: Any] = [kTISPropertyInputSourceID as String: altID]
                if let altList = TISCreateInputSourceList(altFilter as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource],
                   let altSource = altList.first {
                    let status = TISSelectInputSource(altSource)
                    logger.info("⌨️ Раскладка → \(targetLayout.rawValue) (alt: \(altID)): \(status == noErr ? "OK" : "ERROR \(status)")")
                    return
                }
            }

            logger.warning("⌨️ Раскладка не найдена: \(targetSourceID)")
            return
        }

        let status = TISSelectInputSource(source)
        logger.info("⌨️ Раскладка → \(targetLayout.rawValue): \(status == noErr ? "OK" : "ERROR \(status)")")
    }

    // MARK: - Learning Timer

    /// Запускает таймер обучения
    private func startLearningTimer(original: String, converted: String) {
        let learningTimer = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // 2 секунды прошли без отмены → сохраняем в ForcedConversions
            let originalWord = original.trimmingCharacters(in: .punctuationCharacters)
            let convertedWord = converted.trimmingCharacters(in: .punctuationCharacters)

            if originalWord.count >= 2 && convertedWord.count >= 2 {
                ForcedConversionsManager.shared.addConversion(original: originalWord, converted: convertedWord)
            }

            self.onLearned?(originalWord)

            self.pendingLearning = nil
            self.lastManualSwitch = nil

            logger.info("📚 Обучено: \(originalWord) → \(convertedWord)")

            self.onManualSwitch?()
        }

        pendingLearning = (words: [original], timer: learningTimer)
        DispatchQueue.main.asyncAfter(deadline: .now() + learningDelay, execute: learningTimer)
    }

    // MARK: - State Access

    /// Проверить есть ли pending обучение
    var hasPendingLearning: Bool {
        pendingLearning != nil
    }

    /// Очистить состояние
    func clearState() {
        pendingLearning?.timer.cancel()
        pendingLearning = nil
        lastManualSwitch = nil
        isReplacing = false
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Double Cmd откатил автоисправление
    static let doubleCmdAutoRollback = Notification.Name("doubleCmdAutoRollback")

    /// Double Cmd завершил конвертацию
    static let doubleCmdCompleted = Notification.Name("doubleCmdCompleted")
}
