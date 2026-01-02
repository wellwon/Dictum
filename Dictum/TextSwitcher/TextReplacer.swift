//
//  TextReplacer.swift
//  Dictum
//
//  Замена текста через CGEvent (как в Maccy/Clipy).
//  Используется для автоматического исправления раскладки и ручной смены.
//

import Foundation
import AppKit
import Carbon.HIToolbox
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "TextReplacer")

// MARK: - Text Replacer

/// Замена текста через эмуляцию клавиатуры (CGEvent)
class TextReplacer: @unchecked Sendable {

    /// Singleton
    static let shared = TextReplacer()

    // MARK: - Key Codes

    /// Виртуальные коды клавиш
    private enum KeyCode {
        static let backspace: CGKeyCode = 0x33  // Delete/Backspace
        static let v: CGKeyCode = 0x09          // V для Cmd+V
        static let c: CGKeyCode = 0x08          // C для Cmd+C
        static let leftArrow: CGKeyCode = 0x7B  // Left Arrow для выделения слова
    }

    // MARK: - Configuration

    /// Задержка между backspace нажатиями (мс)
    private let backspaceDelay: UInt32 = 1_000  // 1ms в микросекундах (было 10ms — race condition!)

    /// Задержка перед вставкой после удаления
    private let pasteDelay: TimeInterval = 0.003  // 3ms (было 20ms — race condition!)

    /// Задержка для восстановления буфера обмена
    private let clipboardRestoreDelay: TimeInterval = 0.1  // 100ms

    // MARK: - Initialization

    private init() {}

    // MARK: - Public API

    /// Заменяет последнее набранное слово на новое
    /// - Parameters:
    ///   - oldLength: Количество символов для удаления
    ///   - newText: Новый текст для вставки
    @MainActor
    func replaceLastWord(oldLength: Int, newText: String) {
        guard oldLength > 0 else {
            pasteText(newText)
            return
        }

        // 1. Сохраняем текущий буфер обмена
        let savedClipboard = saveClipboard()

        // 2. Удаляем старое слово (Backspace × oldLength)
        deleteCharacters(count: oldLength)

        // 3. Вставляем новое слово через небольшую задержку
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) { [weak self] in
            self?.pasteText(newText)

            // 4. Восстанавливаем буфер обмена
            DispatchQueue.main.asyncAfter(deadline: .now() + (self?.clipboardRestoreDelay ?? 0.1)) {
                self?.restoreClipboard(savedClipboard)
            }
        }

        logger.debug("📝 TextReplacer: заменено \(oldLength) символов на '\(newText)'")
    }

    /// Заменяет выделенный текст на новый
    /// - Parameter newText: Новый текст для вставки
    @MainActor
    func replaceSelectedText(with newText: String) {
        // 1. Сохраняем текущий буфер обмена
        let savedClipboard = saveClipboard()

        // 2. Вставляем новый текст (автоматически заменяет выделение)
        pasteText(newText)

        // 3. Восстанавливаем буфер обмена
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) { [weak self] in
            self?.restoreClipboard(savedClipboard)
        }

        logger.debug("📝 TextReplacer: заменено выделение на '\(newText)'")
    }

    /// Получает выделенный текст через Cmd+C
    /// - Returns: Выделенный текст или nil
    @MainActor
    func getSelectedText() -> String? {
        // 1. Сохраняем текущий буфер
        let savedClipboard = saveClipboard()

        // ГАРАНТИРОВАННОЕ восстановление clipboard (паттерн Maccy)
        defer { restoreClipboard(savedClipboard) }

        // 2. Очищаем буфер
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        // 3. Копируем выделение (Cmd+C)
        simulateCopy()

        // 4. Ждём копирование (увеличено для медленных приложений: Electron, браузеры)
        usleep(100_000)  // 100ms

        // 5. Читаем скопированное
        return pasteboard.string(forType: .string)
    }

    /// Заменяет последнее слово через выделение (Shift+Option+Left)
    /// Этот метод корректно работает независимо от позиции курсора (после пробела и т.д.)
    /// - Parameter newText: Новый текст для вставки
    @MainActor
    func replaceLastWordViaSelection(newText: String) {
        // 1. Сохраняем текущий буфер обмена
        let savedClipboard = saveClipboard()

        // 2. Выделяем слово назад (Shift+Option+Left)
        selectWordBackward()

        // 3. Задержка для обработки выделения приложением
        // 100ms — достаточно даже для медленных приложений (Electron, браузеры)
        usleep(100_000)  // 100ms

        // 4. Вставляем новое слово (автоматически заменяет выделение)
        pasteText(newText)

        // 5. Восстанавливаем буфер обмена
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) { [weak self] in
            self?.restoreClipboard(savedClipboard)
        }

        logger.debug("📝 TextReplacer: заменено слово (selection) на '\(newText)'")
    }

    /// Вставляет текст напрямую (без удаления)
    /// Используется для Cmd+Z rollback после системного Undo
    /// - Parameter text: Текст для вставки
    @MainActor
    func insertText(_ text: String) {
        // 1. Сохраняем текущий буфер обмена
        let savedClipboard = saveClipboard()

        // 2. Вставляем текст
        pasteText(text)

        // 3. Восстанавливаем буфер обмена
        DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) { [weak self] in
            self?.restoreClipboard(savedClipboard)
        }

        logger.debug("📝 TextReplacer: вставлено '\(text)'")
    }

    // MARK: - Private Methods

    /// Выделяет слово назад (Shift+Option+Left)
    /// macOS стандарт — работает во всех приложениях
    private func selectWordBackward() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // keyDown С модификаторами (Shift + Option = выделить слово назад)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.leftArrow, keyDown: true)
        keyDown?.flags = [.maskShift, .maskAlternate]
        keyDown?.post(tap: .cgSessionEventTap)

        // keyUp БЕЗ модификаторов — критично для корректной работы!
        // Некоторые приложения неправильно интерпретируют keyUp с флагами
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.leftArrow, keyDown: false)
        keyUp?.post(tap: .cgSessionEventTap)
    }

    /// Сохраняет содержимое буфера обмена
    private func saveClipboard() -> [NSPasteboard.PasteboardType: Data] {
        let pasteboard = NSPasteboard.general
        var saved: [NSPasteboard.PasteboardType: Data] = [:]

        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type) {
                saved[type] = data
            }
        }

        return saved
    }

    /// Восстанавливает содержимое буфера обмена
    private func restoreClipboard(_ saved: [NSPasteboard.PasteboardType: Data]) {
        guard !saved.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for (type, data) in saved {
            pasteboard.setData(data, forType: type)
        }
    }

    /// Удаляет указанное количество символов (Backspace)
    private func deleteCharacters(count: Int) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        for _ in 0..<count {
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.backspace, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.backspace, keyDown: false)

            keyDown?.post(tap: .cgSessionEventTap)
            keyUp?.post(tap: .cgSessionEventTap)

            // Небольшая задержка между нажатиями
            usleep(backspaceDelay)
        }
    }

    /// Вставляет текст через буфер обмена и Cmd+V
    private func pasteText(_ text: String) {
        // Копируем текст в буфер
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Симулируем Cmd+V
        simulatePaste()
    }

    /// Симулирует Cmd+V (paste)
    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.v, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.v, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }

    /// Симулирует Cmd+C (copy)
    private func simulateCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.c, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.c, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
