//
//  DoubleCmdAI.swift
//  Dictum
//
//  Обработчик Double Cmd — AI улучшение текста через Gemini.
//
//  При двойном нажатии Cmd:
//  1. Если есть выделенный текст → отправить в Gemini → заменить выделение
//  2. Если нет выделения → получить ВЕСЬ текст из поля → отправить в Gemini → заменить
//
//  Поддерживает:
//  - Undo (Cmd+Z) в течение 30 секунд после замены
//  - Терминал и другие приложения через Cmd+C/Cmd+V fallback
//  - Индикатор загрузки у курсора
//

import Foundation
import AppKit
import SwiftUI
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "DoubleCmdAI")

// MARK: - Undo State

/// Состояние для отмены AI-замены
private struct UndoState {
    let originalText: String
    let isSelection: Bool
    let timestamp: Date
}

/// Thread-safe счётчик для @Sendable closures (Swift 6 concurrency)
private final class IntBox: @unchecked Sendable {
    var value: Int
    init(_ value: Int = 0) { self.value = value }
}

// MARK: - Double Cmd AI Handler

/// Обработчик Double Cmd — улучшение текста через Gemini AI
final class DoubleCmdAI: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = DoubleCmdAI()

    // MARK: - Private Properties

    private let gemini = GeminiService()
    private var lastUndoState: UndoState?
    private var isProcessing = false

    /// Время действия Undo (секунды)
    private let undoTimeout: TimeInterval = 30

    private init() {}

    // MARK: - Public API

    /// Обработать Double Cmd — получить текст, улучшить через AI, заменить
    @MainActor
    func handleDoubleCmdAction() {
        // Не запускаем если уже обрабатываем
        guard !isProcessing else {
            logger.debug("⌨️ Double Cmd AI: уже обрабатываем, пропускаем")
            return
        }

        isProcessing = true
        logger.info("⌨️ Double Cmd AI: начинаем обработку")

        // Показываем notification banner в правом верхнем углу
        AINotificationBanner.shared.show()
        logger.debug("⌨️ Double Cmd AI: notification banner показан")

        Task {
            defer {
                Task { @MainActor in
                    self.isProcessing = false
                    AINotificationBanner.shared.hide()
                }
            }

            // 1. Получить текст (выделенный или весь)
            guard let (text, isSelection) = await getTextToProcess() else {
                logger.warning("⌨️ Double Cmd AI: нет текста для обработки")
                return
            }

            logger.info("⌨️ Double Cmd AI: текст для обработки (\(isSelection ? "выделение" : "весь текст")): '\(text.prefix(50))...'")

            // 2. Сохранить для Undo
            saveForUndo(originalText: text, isSelection: isSelection)

            // 3. Отправить в Gemini с STREAMING для скорости
            let systemPrompt = SettingsManager.shared.enhanceSystemPrompt
            let startTime = Date()

            do {
                let chunkCount = IntBox(0)

                // Используем streaming — получаем первый токен за ~200-400ms вместо 3-5 сек
                let improved = try await gemini.generateContentStreaming(
                    prompt: "Улучши этот текст",
                    userText: text,
                    forAI: true,
                    systemPrompt: systemPrompt
                ) { chunk in
                    chunkCount.value += 1
                    // Можно добавить прогресс-индикатор здесь
                }

                let elapsed = Date().timeIntervalSince(startTime)
                logger.info("⌨️ Double Cmd AI: получен ответ (\(chunkCount.value) chunks, \(String(format: "%.2f", elapsed))s): '\(improved.prefix(50))...'")

                // 4. Заменить текст
                await MainActor.run {
                    replaceText(with: improved, isSelection: isSelection)
                }

            } catch {
                logger.error("⌨️ Double Cmd AI: ошибка Gemini: \(error.localizedDescription)")
                // Очищаем undo state при ошибке
                lastUndoState = nil
            }
        }
    }

    /// Попытаться отменить последнюю AI-замену (вызывается при Cmd+Z)
    /// - Returns: true если отмена выполнена, false если нечего отменять
    @MainActor
    func undoLastReplacement() -> Bool {
        guard let state = lastUndoState else {
            logger.debug("⌨️ Double Cmd AI Undo: нет состояния для отмены")
            return false
        }

        // Проверяем таймаут
        let elapsed = Date().timeIntervalSince(state.timestamp)
        if elapsed > undoTimeout {
            logger.debug("⌨️ Double Cmd AI Undo: прошло \(String(format: "%.1f", elapsed)) сек, таймаут истёк")
            lastUndoState = nil
            return false
        }

        logger.info("⌨️ Double Cmd AI Undo: откатываем к '\(state.originalText.prefix(30))...'")

        // Восстанавливаем оригинальный текст
        replaceText(with: state.originalText, isSelection: state.isSelection)

        // Очищаем состояние
        lastUndoState = nil

        return true
    }

    /// Проверяет есть ли активное состояние для Undo
    var hasUndoState: Bool {
        guard let state = lastUndoState else { return false }
        return Date().timeIntervalSince(state.timestamp) <= undoTimeout
    }

    // MARK: - Private: Get Text

    /// Получить текст для обработки
    /// - Returns: (текст, isSelection) или nil если текста нет
    private func getTextToProcess() async -> (text: String, isSelection: Bool)? {
        // 1. Сначала пробуем через AX API (работает в большинстве приложений)
        if let focusedElement = getFocusedElement() {
            logger.debug("⌨️ getTextToProcess: есть focused element")

            // Проверяем выделенный текст (приоритет)
            let selectedText = getSelectedText(from: focusedElement)
            logger.debug("⌨️ getTextToProcess: selectedText = '\(selectedText?.prefix(30) ?? "nil")'")

            if let selectedText = selectedText, !selectedText.isEmpty {
                logger.info("⌨️ getTextToProcess: найден выделенный текст через AX (\(selectedText.count) символов)")
                return (selectedText, true)
            }

            // Получаем ВЕСЬ текст из поля
            let fullText = getFullText(from: focusedElement)
            logger.debug("⌨️ getTextToProcess: fullText = '\(fullText?.prefix(30) ?? "nil")'")

            if let fullText = fullText, !fullText.isEmpty {
                logger.info("⌨️ getTextToProcess: используем весь текст через AX (\(fullText.count) символов)")
                return (fullText, false)
            }
        } else {
            logger.debug("⌨️ getTextToProcess: НЕТ focused element")
        }

        // 2. Fallback для терминала и других приложений: Cmd+C
        NSLog("⌨️ getTextToProcess: AX не сработал, пробуем Cmd+C fallback")
        if let copiedText = await copySelectedTextViaClipboard() {
            NSLog("⌨️ getTextToProcess: получен текст через Cmd+C (%d символов)", copiedText.count)
            return (copiedText, true)  // Cmd+C работает только с выделением
        }

        NSLog("⌨️ getTextToProcess: не удалось получить текст ни через AX, ни через Cmd+C")
        return nil
    }

    /// Скопировать выделенный текст через Cmd+C и получить из clipboard
    private func copySelectedTextViaClipboard() async -> String? {
        let pasteboard = NSPasteboard.general

        // Сохраняем текущий clipboard
        let savedContent = pasteboard.string(forType: .string)
        let changeCount = pasteboard.changeCount

        // Очищаем clipboard перед копированием
        pasteboard.clearContents()

        NSLog("⌨️ copySelectedTextViaClipboard: отправляем Cmd+C")

        // Cmd+C
        await MainActor.run {
            simulateKeyPress(keyCode: 0x08, modifiers: .maskCommand)  // C
        }

        // Ждём пока clipboard обновится (терминал медленнее)
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            if pasteboard.changeCount != changeCount {
                break  // Clipboard обновился
            }
        }

        // Читаем из clipboard
        let copiedText = pasteboard.string(forType: .string)

        NSLog("⌨️ copySelectedTextViaClipboard: получено '%@'", copiedText?.prefix(30).description ?? "nil")

        // Проверяем что что-то скопировалось
        guard let text = copiedText, !text.isEmpty else {
            // Восстанавливаем clipboard если копирование не удалось
            if let saved = savedContent {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
            logger.warning("⌨️ copySelectedTextViaClipboard: не удалось скопировать")
            return nil
        }

        return text
    }

    // MARK: - Private: Replace Text

    /// Заменить текст в активном поле
    private func replaceText(with newText: String, isSelection: Bool) {
        // Пробуем сначала через AX API
        if let focusedElement = getFocusedElement() {
            if isSelection {
                // Заменяем выделенный текст напрямую через AX
                if setSelectedText(focusedElement, text: newText) {
                    logger.info("⌨️ replaceText: выделение заменено через AX")
                    return
                }
            }
        }

        // Fallback: clipboard + paste
        logger.debug("⌨️ replaceText: используем clipboard")

        if isSelection {
            // Просто вставляем (выделение уже есть)
            pasteText(newText)
        } else {
            // Выделяем весь текст и вставляем
            selectAllAndPaste(newText)
        }
    }

    /// Выделить весь текст и вставить новый
    private func selectAllAndPaste(_ text: String) {
        // Cmd+A для выделения всего
        simulateKeyPress(keyCode: 0x00, modifiers: .maskCommand)  // A

        // Небольшая пауза
        usleep(50_000)  // 50ms

        // Вставляем через clipboard
        pasteText(text)
    }

    /// Вставить текст через clipboard + Cmd+V
    private func pasteText(_ text: String) {
        // Сохраняем текущий clipboard
        let pasteboard = NSPasteboard.general
        let savedContent = pasteboard.string(forType: .string)

        // Записываем новый текст
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Cmd+V
        simulateKeyPress(keyCode: 0x09, modifiers: .maskCommand)  // V

        // Восстанавливаем clipboard через небольшую задержку
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let saved = savedContent {
                pasteboard.clearContents()
                pasteboard.setString(saved, forType: .string)
            }
        }
    }

    /// Симулировать нажатие клавиши
    private func simulateKeyPress(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = modifiers
        keyUp.flags = modifiers

        keyDown.post(tap: .cgSessionEventTap)
        usleep(10_000)  // 10ms между down и up
        keyUp.post(tap: .cgSessionEventTap)
    }

    // MARK: - Private: Undo State

    private func saveForUndo(originalText: String, isSelection: Bool) {
        lastUndoState = UndoState(
            originalText: originalText,
            isSelection: isSelection,
            timestamp: Date()
        )
        logger.debug("⌨️ saveForUndo: сохранено '\(originalText.prefix(30))...' (isSelection: \(isSelection))")
    }

    // MARK: - Private: AX API Wrappers

    /// Получить фокусированный UI элемент
    private func getFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedApp: AnyObject?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard appResult == .success, let app = focusedApp else {
            return nil
        }

        var focusedElement: AnyObject?
        let elementResult = AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard elementResult == .success, let element = focusedElement else {
            return nil
        }

        return (element as! AXUIElement)
    }

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

    /// Установить выделенный текст
    private func setSelectedText(_ element: AXUIElement, text: String) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return result == .success
    }
}

// MARK: - AI Notification Banner

/// macOS-style notification banner в правом верхнем углу экрана
/// Показывает индикатор загрузки во время AI обработки
@MainActor
final class AINotificationBanner {

    static let shared = AINotificationBanner()

    // MARK: - Configuration

    private let windowWidth: CGFloat = 320   // Как нативные macOS уведомления
    private let windowHeight: CGFloat = 64
    private let rightPadding: CGFloat = 16
    private let topPadding: CGFloat = 8      // Как у нативных macOS уведомлений
    private let slideDistance: CGFloat = 50
    private let showDuration: TimeInterval = 0.3
    private let hideDuration: TimeInterval = 0.2

    // MARK: - State

    private var window: NSWindow?

    private init() {}

    // MARK: - Public API

    /// Показать notification banner в правом верхнем углу
    func show() {
        hide()  // Скрыть предыдущий если есть

        guard let screen = NSScreen.main else {
            logger.warning("🔔 AINotificationBanner: нет main screen")
            return
        }

        // Вычисляем финальную позицию (справа сверху)
        let finalX = screen.frame.maxX - windowWidth - rightPadding
        let finalY = screen.frame.maxY - windowHeight - topPadding

        // Создаём окно
        let window = NSWindow(
            contentRect: NSRect(x: finalX, y: finalY, width: windowWidth, height: windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = NSHostingView(rootView: AINotificationView())

        // Начальная позиция для анимации (справа за экраном)
        window.alphaValue = 0
        window.setFrame(
            NSRect(x: finalX + slideDistance, y: finalY, width: windowWidth, height: windowHeight),
            display: false
        )
        window.orderFront(nil)

        // Slide-in анимация
        NSAnimationContext.runAnimationGroup { context in
            context.duration = showDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(
                NSRect(x: finalX, y: finalY, width: windowWidth, height: windowHeight),
                display: true
            )
        }

        self.window = window
        logger.info("🔔 AINotificationBanner: показан")
    }

    /// Скрыть notification banner с анимацией
    func hide() {
        guard let window = window else { return }

        let frame = window.frame

        // Slide-out анимация
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(
                NSRect(
                    x: frame.origin.x + slideDistance,
                    y: frame.origin.y,
                    width: frame.width,
                    height: frame.height
                ),
                display: true
            )
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
        })

        logger.debug("🔔 AINotificationBanner: скрыт")
    }
}

// MARK: - AI Notification View (SwiftUI)

/// SwiftUI view для notification banner в стиле нативных macOS уведомлений
struct AINotificationView: View {
    @State private var isAnimating = false

    /// Название текущей модели из настроек
    private var modelName: String {
        SettingsManager.shared.selectedGeminiModel.displayName
    }

    var body: some View {
        HStack(spacing: 12) {
            // Вращающаяся иконка (как в модалке)
            Image(systemName: "rays")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                )
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
                .animation(
                    Animation.linear(duration: 1).repeatForever(autoreverses: false),
                    value: isAnimating
                )

            // Текстовый блок
            VStack(alignment: .leading, spacing: 2) {
                // Заголовок + время
                HStack {
                    Text("Dictum")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("Сейчас")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }

                // Модель + описание
                Text("\(modelName) · Улучшаю текст...")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: 320, height: 64)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
        .onAppear {
            isAnimating = true
        }
    }
}
