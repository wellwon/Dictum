//
//  AXTextAccessor.swift
//  Dictum
//
//  Доступ к тексту через Accessibility API (AXUIElement).
//  Атомарные операции замены текста БЕЗ race conditions.
//
//  Преимущества над CGEvent + Clipboard:
//  - Замена текста за ОДНУ атомарную операцию
//  - Не использует clipboard (не нужно сохранять/восстанавливать)
//  - Нет timing-зависимых race conditions
//
//  Ограничения:
//  - Не работает в некоторых Electron приложениях (VS Code, Slack)
//  - Требует Accessibility permission
//

import Foundation
import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "AXTextAccessor")

// MARK: - Text Info

/// Информация о тексте для конвертации
struct TextInfo {
    /// Текст для конвертации
    let text: String

    /// Определённая раскладка текста
    let detectedLayout: KeyboardLayout

    /// true = это выделенный текст, false = последнее слово
    let isSelection: Bool

    /// Позиция курсора (для точной замены)
    let cursorPosition: Int?
}

// MARK: - AXTextAccessor

/// Доступ к тексту через Accessibility API
/// Атомарные операции без race conditions
final class AXTextAccessor: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = AXTextAccessor()

    private init() {}

    // MARK: - Public API: Read Text

    /// Получить текст для конвертации
    /// Приоритет: 1) Выделенный текст, 2) Последнее слово от позиции курсора
    /// - Parameter wordBuffer: Буфер слова из KeyboardMonitor (если AX не доступен)
    /// - Returns: TextInfo или nil если текст не найден
    func getTextForConversion(wordBuffer: String = "") -> TextInfo? {
        // Попытка 1: Получить через AXUIElement
        if let focusedElement = getFocusedElement() {
            // Проверяем выделенный текст
            if let selectedText = getSelectedText(from: focusedElement),
               !selectedText.isEmpty,
               selectedText.count >= 2 {
                logger.debug("📖 AX: найден выделенный текст '\(selectedText)'")
                return TextInfo(
                    text: selectedText,
                    detectedLayout: LayoutMaps.detectLayout(in: selectedText) ?? .qwerty,
                    isSelection: true,
                    cursorPosition: nil
                )
            }

            // Проверяем последнее слово через AX
            if let lastWord = getLastWordFromContext(element: focusedElement),
               lastWord.count >= 2 {
                let cursorPos = getCursorPosition(from: focusedElement)
                logger.debug("📖 AX: найдено последнее слово '\(lastWord)' (cursor: \(cursorPos ?? -1))")
                return TextInfo(
                    text: lastWord,
                    detectedLayout: LayoutMaps.detectLayout(in: lastWord) ?? .qwerty,
                    isSelection: false,
                    cursorPosition: cursorPos
                )
            }
        }

        // Попытка 2: Использовать wordBuffer из KeyboardMonitor
        if !wordBuffer.isEmpty, wordBuffer.count >= 2 {
            logger.debug("📖 AX fallback: используем wordBuffer '\(wordBuffer)'")
            return TextInfo(
                text: wordBuffer,
                detectedLayout: LayoutMaps.detectLayout(in: wordBuffer) ?? .qwerty,
                isSelection: false,
                cursorPosition: nil
            )
        }

        logger.debug("📖 AX: текст для конвертации не найден")
        return nil
    }

    // MARK: - Public API: Write Text (ATOMIC!)

    /// Результат попытки замены текста через AX
    enum ReplaceResult {
        case success                    // Замена успешна
        case failedNoSelection          // Не удалось выделить текст
        case failedAfterSelection       // Выделено но не удалось заменить (текст УЖЕ выделен!)
    }

    /// Заменить текст АТОМАРНО через AXUIElement
    /// - Parameters:
    ///   - newText: Новый текст
    ///   - info: Информация о заменяемом тексте
    /// - Returns: Результат замены (для правильного fallback)
    func replaceTextWithResult(with newText: String, info: TextInfo) -> ReplaceResult {
        guard let focusedElement = getFocusedElement() else {
            logger.warning("⚠️ AX: не удалось получить focused element")
            return .failedNoSelection
        }

        // Проверяем поддержку записи
        guard isAttributeSettable(focusedElement, attribute: kAXSelectedTextAttribute as CFString) else {
            logger.warning("⚠️ AX: kAXSelectedTextAttribute не поддерживает запись")
            return .failedNoSelection
        }

        if info.isSelection {
            // Замена выделенного текста напрямую
            if setSelectedText(focusedElement, text: newText) {
                return .success
            } else {
                // Выделение уже было — fallback просто paste
                return .failedAfterSelection
            }
        } else {
            // Нужно сначала выделить слово, потом заменить
            let length = info.text.count

            // Выделить символы назад от текущей позиции
            guard selectCharactersBackward(focusedElement, length: length) else {
                logger.warning("⚠️ AX: не удалось выделить \(length) символов назад")
                return .failedNoSelection
            }

            // Минимальная пауза чтобы приложение обработало выделение
            usleep(2_000)  // 2ms (было 10ms — race condition!)

            // Заменить выделение
            if setSelectedText(focusedElement, text: newText) {
                return .success
            } else {
                // Текст ВЫДЕЛЕН через AX, но setSelectedText не сработал
                // Fallback должен просто paste, НЕ выделять снова!
                return .failedAfterSelection
            }
        }
    }

    /// Заменить текст АТОМАРНО через AXUIElement (legacy API для совместимости)
    /// - Parameters:
    ///   - newText: Новый текст
    ///   - info: Информация о заменяемом тексте
    /// - Returns: true если замена успешна через AX, false если нужен fallback
    @discardableResult
    func replaceText(with newText: String, info: TextInfo) -> Bool {
        return replaceTextWithResult(with: newText, info: info) == .success
    }

    /// Проверить доступность AXUIElement для текущего приложения
    func isAXAvailable() -> Bool {
        guard let focusedElement = getFocusedElement() else { return false }
        return isAttributeSettable(focusedElement, attribute: kAXSelectedTextAttribute as CFString)
    }

    // MARK: - Private: Get Focused Element

    /// Получить фокусированный UI элемент (текстовое поле)
    private func getFocusedElement() -> AXUIElement? {
        // 1. Получить системный элемент
        let systemWide = AXUIElementCreateSystemWide()

        // 2. Получить фокусированное приложение
        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let app = focusedApp else {
            logger.debug("📖 AX: не удалось получить focused application")
            return nil
        }

        // 3. Получить фокусированный UI элемент внутри приложения
        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elementResult == .success, let element = focusedElement else {
            logger.debug("📖 AX: не удалось получить focused UI element")
            return nil
        }

        return (element as! AXUIElement)
    }

    // MARK: - Private: Read Attributes

    /// Получить выделенный текст
    private func getSelectedText(from element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )

        guard result == .success else { return nil }
        return value as? String
    }

    /// Получить позицию курсора
    private func getCursorPosition(from element: AXUIElement) -> Int? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success, let rangeValue = value else { return nil }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }

        return range.location
    }

    /// Получить весь текст из элемента
    private func getFullText(from element: AXUIElement) -> String? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard result == .success else { return nil }
        return value as? String
    }

    /// Получить последнее слово из контекста (текст до курсора)
    private func getLastWordFromContext(element: AXUIElement) -> String? {
        guard let fullText = getFullText(from: element),
              let cursorPosition = getCursorPosition(from: element),
              cursorPosition > 0 else {
            return nil
        }

        // Получить текст до курсора
        let textIndex = fullText.index(fullText.startIndex, offsetBy: min(cursorPosition, fullText.count))
        let textBeforeCursor = String(fullText[..<textIndex])

        // Найти последнее слово (включая возможную пунктуацию)
        return extractLastWord(from: textBeforeCursor)
    }

    /// Извлечь последнее слово из текста
    private func extractLastWord(from text: String) -> String? {
        guard !text.isEmpty else { return nil }

        var word = ""
        var foundLetter = false

        // Идём с конца
        for char in text.reversed() {
            if char.isLetter {
                foundLetter = true
                word = String(char) + word
            } else if foundLetter {
                // Встретили не-букву после буквы = конец слова
                break
            } else if char.isPunctuation || LayoutMaps.allQwertyMappableCharacters.contains(char) {
                // Пунктуация в конце слова (например "привет!")
                word = String(char) + word
            } else if char.isWhitespace {
                // Пробел = стоп
                break
            }
        }

        // Убрать лидирующую пунктуацию если слово начинается с неё
        while let first = word.first, !first.isLetter && word.count > 1 {
            word.removeFirst()
        }

        return word.isEmpty ? nil : word
    }

    // MARK: - Private: Write Attributes

    /// Установить выделенный текст (АТОМАРНАЯ ЗАМЕНА)
    private func setSelectedText(_ element: AXUIElement, text: String) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )

        if result == .success {
            logger.debug("✅ AX: текст заменён на '\(text)'")
            return true
        } else {
            logger.warning("⚠️ AX: ошибка замены текста: \(result.rawValue)")
            return false
        }
    }

    /// Выделить N символов назад от текущей позиции курсора
    private func selectCharactersBackward(_ element: AXUIElement, length: Int) -> Bool {
        // 1. Получить текущую позицию курсора
        var value: AnyObject?
        let getResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard getResult == .success, let rangeValue = value else {
            NSLog("⚠️ AX selectBackward: не удалось получить позицию курсора")
            return false
        }

        var currentRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &currentRange) else {
            NSLog("⚠️ AX selectBackward: не удалось извлечь CFRange")
            return false
        }

        NSLog("🔍 AX selectBackward: cursor at %d, want to select %d chars backward", currentRange.location, length)

        // 2. Вычислить новый range (выделение назад)
        let newLocation = max(0, currentRange.location - length)
        let newLength = min(length, currentRange.location)
        var newRange = CFRange(location: newLocation, length: newLength)

        NSLog("🔍 AX selectBackward: selecting range [%d, %d]", newLocation, newLength)

        // 3. Создать AXValue для нового range
        guard let newRangeValue = AXValueCreate(.cfRange, &newRange) else {
            NSLog("⚠️ AX selectBackward: не удалось создать AXValue")
            return false
        }

        // 4. Установить выделение
        let setResult = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            newRangeValue
        )

        if setResult == .success {
            // Проверяем что реально выделилось
            if let selectedText = getSelectedText(from: element) {
                NSLog("✅ AX selectBackward: выделено '%@' (%d символов)", selectedText, selectedText.count)
            } else {
                NSLog("✅ AX selectBackward: выделение установлено, но текст не получен")
            }
            return true
        } else {
            NSLog("⚠️ AX selectBackward: ошибка выделения: %d", setResult.rawValue)
            return false
        }
    }

    // MARK: - Private: Attribute Checking

    /// Проверить можно ли записывать в атрибут
    private func isAttributeSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var isSettable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(element, attribute, &isSettable)
        return result == .success && isSettable.boolValue
    }
}
