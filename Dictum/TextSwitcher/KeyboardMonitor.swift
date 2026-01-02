//
//  KeyboardMonitor.swift
//  Dictum
//
//  Мониторинг клавиатуры для TextSwitcher.
//  - Глобальный мониторинг через NSEvent
//  - Буфер слова для автоисправления
//  - Double CMD для ручной смены раскладки (как Double Shift в Caramba)
//  - Отложенное обучение (2 сек без отмены)
//

import Foundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices  // Для AXIsProcessTrusted()
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "KeyboardMonitor")

// MARK: - Keyboard Monitor

/// Мониторинг клавиатуры для автоматического исправления раскладки
class KeyboardMonitor: @unchecked Sendable {

    /// Singleton
    static let shared = KeyboardMonitor()

    // MARK: - Monitors

    // Локальный монитор убран — вызывал двойную обработку событий

    // MARK: - CGEventTap (Input Monitoring - работает сразу без рестарта!)
    private var keyboardEventTap: CFMachPort?
    private var keyboardRunLoopSource: CFRunLoopSource?

    // MARK: - State

    /// Буфер текущего слова
    private var wordBuffer: String = ""

    /// Последнее обработанное слово (для Double CMD после пробела)
    private var lastProcessedWord: String = ""

    /// Накопленная пунктуация после последнего слова (для Double CMD: "ghbdtn!" → "ghbdtn" + "!")
    private var pendingPunctuation: String = ""

    /// Последняя автоматическая замена (для отката)
    private var lastAutoSwitch: (original: String, converted: String, time: Date)?

    /// Последняя ручная замена (для отложенного обучения)
    private var lastManualSwitch: (original: String, converted: String, time: Date)?

    /// Ожидающее обучение (слова + таймер)
    private var pendingLearning: (words: [String], timer: DispatchWorkItem)?

    /// Флаг паузы
    private var isPaused: Bool = false

    /// Флаг блокировки во время замены (предотвращает race condition)
    private var isReplacing: Bool = false

    /// Флаг активности мониторинга
    private(set) var isMonitoring: Bool = false

    // MARK: - Double CMD State (как Double Shift в Caramba)

    /// Время ОТПУСКАНИЯ первого CMD (для детекции Double CMD)
    private var firstCmdReleaseTime: Date?

    /// Время нажатия текущего CMD
    private var cmdPressTime: Date?

    /// CMD сейчас зажат
    private var cmdHeld: Bool = false

    /// Была нажата другая клавиша пока CMD зажат (CMD+C, CMD+V и т.д.)
    private var otherKeyDuringCmd: Bool = false

    /// Максимальное время между двумя CMD для Double CMD (мс)
    private let doubleCmdThreshold: TimeInterval = 0.4  // 400ms как в Caramba

    // MARK: - Layout Switch Bias (для коротких слов типа "tot" → "еще")

    /// Предыдущая системная раскладка (для определения недавнего переключения)
    private var previousSystemLayout: KeyboardLayout = .qwerty

    /// Время последнего переключения раскладки
    private var lastLayoutSwitchTime: Date?

    /// Окно для биаса (если раскладка сменилась менее 5 сек назад)
    private let layoutBiasWindow: TimeInterval = 5.0

    // MARK: - Context Bias (для "tot" в контексте "Сейчас Влада tot попрошу")

    /// История решений конвертации (последние N слов)
    /// true = конвертировано в русский, false = оставлено как есть или конвертировано в английский
    private var conversionHistory: [(layout: KeyboardLayout, wasSwitched: Bool, time: Date)] = []

    /// Максимальный размер истории
    private let maxConversionHistory: Int = 10

    /// Минимальное количество слов для анализа контекста
    private let minContextWords: Int = 2

    /// Порог для контекстного биаса (какой % слов должен быть конвертирован)
    private let contextBiasThreshold: Double = 0.5

    /// Временное окно для контекста (сек)
    private let contextTimeWindow: TimeInterval = 30.0

    // MARK: - Configuration

    /// Окно для отката автоисправления (сек)
    private let autoRollbackWindow: TimeInterval = 3.0

    /// Задержка перед обучением (сек)
    private let learningDelay: TimeInterval = 2.0

    // debounce убран — обработка синхронная для точности позиции курсора

    // MARK: - Callbacks

    /// Callback для показа зелёного тоста при обучении
    var onLearned: ((String) -> Void)?

    /// Callback для обновления статистики
    var onAutoSwitch: (() -> Void)?
    var onManualSwitch: (() -> Void)?

    // MARK: - Initialization

    private init() {
        logger.info("⌨️ KeyboardMonitor инициализирован")
        setupActiveAppObserver()
    }

    /// Настраивает наблюдатель смены активного приложения для очистки буфера
    private func setupActiveAppObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // При смене приложения очищаем буфер — предотвращает накопление символов
            self?.clearWordBuffer()
            self?.lastProcessedWord = ""
            // Очищаем историю контекста — новое приложение = новый контекст
            self?.clearContextHistory()
            logger.debug("⌨️ Смена приложения — буфер и контекст очищены")
        }
    }

    // MARK: - Public API

    /// Запускает мониторинг клавиатуры
    /// - Returns: true если мониторинг успешно запущен
    @discardableResult
    func startMonitoring() -> Bool {
        NSLog("⌨️ KeyboardMonitor: startMonitoring() ВЫЗВАН")

        guard !isMonitoring else {
            NSLog("⌨️ KeyboardMonitor: уже мониторит, пропускаем")
            return true
        }

        // Проверяем Input Monitoring (для CGEventTap .listenOnly)
        let hasInputMonitoring = CGPreflightListenEventAccess()
        NSLog("⌨️ KeyboardMonitor: CGPreflightListenEventAccess = %@", hasInputMonitoring ? "true" : "false")

        // Также проверяем Accessibility (нужен для TextReplacer — вставка текста)
        let hasAccessibility = AXIsProcessTrusted()
        NSLog("⌨️ KeyboardMonitor: AXIsProcessTrusted = %@", hasAccessibility ? "true" : "false")

        guard hasInputMonitoring else {
            NSLog("⌨️ KeyboardMonitor: НЕТ Input Monitoring — запрашиваю...")
            CGRequestListenEventAccess()
            logger.warning("⌨️ KeyboardMonitor: НЕТ Input Monitoring разрешения!")
            return false
        }

        // CGEventTap для keyDown + flagsChanged
        // .listenOnly = Input Monitoring permission (работает СРАЗУ без рестарта!)
        NSLog("⌨️ KeyboardMonitor: создаю CGEventTap...")

        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()

                switch type {
                case .keyDown:
                    monitor.handleKeyDownCGEvent(event)
                case .flagsChanged:
                    monitor.handleFlagsChangedCGEvent(event)
                case .tapDisabledByTimeout:
                    // macOS отключает tap если callback слишком долгий — перезапускаем
                    if let tap = monitor.keyboardEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        NSLog("🔄 KeyboardMonitor CGEventTap перезапущен после timeout")
                    }
                default:
                    break
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("⌨️ KeyboardMonitor: ОШИБКА создания CGEventTap!")
            logger.error("⌨️ KeyboardMonitor: ОШИБКА создания CGEventTap!")
            return false
        }

        keyboardEventTap = eventTap

        // Добавляем в RunLoop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        keyboardRunLoopSource = source

        // Активируем tap
        CGEvent.tapEnable(tap: eventTap, enable: true)

        isMonitoring = true
        NSLog("⌨️ KeyboardMonitor: CGEventTap мониторинг УСПЕШНО запущен ✅ (Input Monitoring)")
        logger.info("⌨️ KeyboardMonitor: мониторинг УСПЕШНО запущен (CGEventTap)")
        return true
    }

    /// Останавливает мониторинг клавиатуры
    func stopMonitoring() {
        // Убираем CGEventTap
        if let source = keyboardRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            keyboardRunLoopSource = nil
        }
        if let tap = keyboardEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            keyboardEventTap = nil
        }

        clearState()
        isMonitoring = false
        logger.info("⌨️ KeyboardMonitor: мониторинг остановлен")
    }

    /// Приостанавливает обработку (во время диктовки)
    func pause() {
        isPaused = true
        clearWordBuffer()
        clearContextHistory()
        logger.debug("⌨️ KeyboardMonitor: пауза")
    }

    /// Возобновляет обработку
    func resume() {
        isPaused = false
        logger.debug("⌨️ KeyboardMonitor: возобновлено")
    }

    // MARK: - Event Handling

    /// Обработка нажатия клавиши
    private func handleKeyDown(_ event: NSEvent) {
        // ДИАГНОСТИКА: логируем КАЖДОЕ событие
        NSLog("⌨️ handleKeyDown: keyCode=%d, chars='%@', modifiers=%lu",
              event.keyCode, event.characters ?? "nil", event.modifierFlags.rawValue)

        guard !isPaused else { return }

        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Отслеживаем раскладку на КАЖДОМ событии!
        // Это обновляет lastLayoutSwitchTime если пользователь переключил раскладку
        _ = detectCurrentKeyboardLayout()
        // isReplacing НЕ блокирует накопление символов — только processWordIfNeeded

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // CMD+любая клавиша — НЕ конвертируем при Double CMD
        if cmdHeld && modifiers.contains(.command) {
            otherKeyDuringCmd = true
        }

        // Cmd+Shift+Space УБРАН — используется Double CMD

        // Игнорируем остальные события с модификаторами (Cmd+, Ctrl+, etc.)
        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return
        }

        // ИСПРАВЛЕНО: используем helper вместо event.characters (nil в глобальных мониторах)
        guard let characters = characterFromEvent(event), !characters.isEmpty else { return }

        let keyCode = event.keyCode

        // Обработка специальных клавиш
        switch keyCode {
        case 36, 76:  // Enter, Numpad Enter
            // Enter не вставляет символ, просто новая строка — без триггера
            // ИСПРАВЛЕНИЕ: очищаем буфер ТОЛЬКО если слово обработано
            if processWordIfNeeded(triggerChar: nil) {
                clearWordBuffer()
            }

        case 48:  // Tab
            // Tab — не символ в тексте, без триггера
            if processWordIfNeeded(triggerChar: nil) {
                clearWordBuffer()
            }

        case 49:  // Space
            // ВАЖНО: пробел уже вставлен в приложение, передаём его как триггер
            if processWordIfNeeded(triggerChar: " ") {
                clearWordBuffer()
            }

        case 51:  // Backspace
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
            }

        case 53:  // Escape
            clearWordBuffer()

        default:
            // Обычные символы — добавляем в буфер
            for char in characters {
                // ИСПРАВЛЕНИЕ БАГ #1: Проверяем mappable символы ПЕРЕД isPunctuation
                // Символы типа `[`, `]`, `;`, `'` являются isPunctuation в Swift,
                // но должны добавляться в буфер как часть раскладки ([ → х, ] → ъ и т.д.)
                let lowercasedChar = Character(char.lowercased())
                let isMappableQWERTY = LayoutMaps.qwertyCharacters.contains(lowercasedChar) ||
                                       LayoutMaps.qwertyCharacters.contains(char)
                let isMappableRussian = LayoutMaps.russianCharacters.contains(lowercasedChar) ||
                                        LayoutMaps.russianCharacters.contains(char)
                let isMappable = isMappableQWERTY || isMappableRussian

                if char.isLetter || char.isNumber || isMappable {
                    // Новая буква — сбрасываем накопленную пунктуацию (начало нового слова)
                    pendingPunctuation = ""
                    wordBuffer.append(char)
                    // Ограничиваем размер буфера (защита от переполнения при смене приложений)
                    if wordBuffer.count > 50 {
                        wordBuffer = String(wordBuffer.suffix(30))
                    }
                } else if char.isPunctuation || char.isWhitespace {
                    // COMPOUND BUZZWORDS: проверяем может ли это быть частью составного термина (gpt-4, c++, react-native)
                    if TechBuzzwordsManager.isCompoundChar(char) &&
                       TechBuzzwordsManager.shared.mightBeCompound(wordBuffer, nextChar: char) {
                        // Продолжаем накапливать — это часть составного buzzword
                        wordBuffer.append(char)
                    } else {
                        // ВАЖНО: передаём ОРИГИНАЛЬНЫЙ триггерный символ (!, ?, & и т.д.)
                        // ИСПРАВЛЕНИЕ: очищаем буфер ТОЛЬКО если слово обработано
                        if processWordIfNeeded(triggerChar: char) {
                            clearWordBuffer()
                        }
                        // ИСПРАВЛЕНИЕ ПУНКТУАЦИИ: накапливаем для Double CMD
                        if char.isPunctuation {
                            pendingPunctuation.append(char)
                        } else {
                            pendingPunctuation = ""
                        }
                    }
                }
            }
        }
    }

    /// Обработка изменения модификаторов (Double CMD = конвертация, как Double Shift в Caramba)
    private func handleFlagsChanged(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ДИАГНОСТИКА: логируем изменение модификаторов
        NSLog("⌨️ handleFlagsChanged: modifiers=%lu, cmdHeld=%@, firstCmdReleaseTime=%@",
              modifiers.rawValue, cmdHeld ? "YES" : "NO",
              firstCmdReleaseTime?.description ?? "nil")

        // CMD нажат
        if modifiers.contains(.command) && !cmdHeld {
            cmdHeld = true
            otherKeyDuringCmd = false
            cmdPressTime = Date()
            NSLog("⌨️ CMD нажат")
            return
        }

        // CMD отпущен — проверяем Double CMD
        if !modifiers.contains(.command) && cmdHeld {
            cmdHeld = false

            // Если была другая клавиша (CMD+C, CMD+V) — НЕ Double CMD
            guard !otherKeyDuringCmd else {
                NSLog("⌨️ CMD отпущен — была другая клавиша, сбрасываем Double CMD")
                firstCmdReleaseTime = nil
                cmdPressTime = nil
                return
            }

            let now = Date()

            // Проверяем Double CMD: второе отпускание в течение 400ms
            if let firstRelease = firstCmdReleaseTime,
               now.timeIntervalSince(firstRelease) < doubleCmdThreshold {
                // DOUBLE CMD DETECTED!
                NSLog("⌨️ 🎯 DOUBLE CMD DETECTED!")
                firstCmdReleaseTime = nil
                cmdPressTime = nil

                DispatchQueue.main.async { [weak self] in
                    self?.handleDoubleCmdAction()
                }
                return
            }

            // Это первое отпускание — запоминаем время
            NSLog("⌨️ CMD отпущен — первый раз, запоминаем время")
            firstCmdReleaseTime = now
            cmdPressTime = nil
        }
    }

    // MARK: - CGEvent Handlers (Input Monitoring)

    /// Обработка нажатия клавиши через CGEvent (работает сразу после выдачи Input Monitoring!)
    private func handleKeyDownCGEvent(_ event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // Получаем символ через CGEvent API
        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        let characters = length > 0 ? String(utf16CodeUnits: chars, count: length) : nil

        // ДИАГНОСТИКА
        NSLog("⌨️ handleKeyDownCGEvent: keyCode=%d, chars='%@', flags=%llu",
              keyCode, characters ?? "nil", event.flags.rawValue)

        guard !isPaused else { return }

        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Отслеживаем раскладку на КАЖДОМ событии!
        // Это обновляет lastLayoutSwitchTime если пользователь переключил раскладку
        // Без этого Layout Bias не работает для коротких слов типа "tot" → "еще"
        _ = detectCurrentKeyboardLayout()
        // isReplacing НЕ блокирует накопление символов — только processWordIfNeeded

        let flags = event.flags

        // Cmd+Z — откат последней конвертации TextSwitcher (до 10 сек)
        // ВАЖНО: Обрабатываем ДО общего фильтра модификаторов!
        if flags.contains(.maskCommand) && keyCode == 6 {  // Z key
            handleCmdZUndo()
            return  // Не обрабатываем дальше, но CGEventTap .listenOnly — Cmd+Z всё равно пройдёт в приложение
        }

        // CMD+любая клавиша — НЕ конвертируем при Double CMD
        if cmdHeld && flags.contains(.maskCommand) {
            otherKeyDuringCmd = true
        }

        // Игнорируем события с модификаторами (Cmd+, Ctrl+, Option+)
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return
        }

        guard let characters = characters, !characters.isEmpty else { return }

        // Обработка специальных клавиш
        switch keyCode {
        case 36, 76:  // Enter, Numpad Enter
            // ИСПРАВЛЕНИЕ: очищаем буфер ТОЛЬКО если слово обработано
            if processWordIfNeeded(triggerChar: nil) {
                clearWordBuffer()
            }

        case 48:  // Tab
            if processWordIfNeeded(triggerChar: nil) {
                clearWordBuffer()
            }

        case 49:  // Space
            if processWordIfNeeded(triggerChar: " ") {
                clearWordBuffer()
            }

        case 51:  // Backspace
            if !wordBuffer.isEmpty {
                wordBuffer.removeLast()
            }

        case 53:  // Escape
            clearWordBuffer()

        default:
            // Обычные символы — добавляем в буфер
            for char in characters {
                let lowercasedChar = Character(char.lowercased())
                let isMappableQWERTY = LayoutMaps.qwertyCharacters.contains(lowercasedChar) ||
                                       LayoutMaps.qwertyCharacters.contains(char)
                let isMappableRussian = LayoutMaps.russianCharacters.contains(lowercasedChar) ||
                                        LayoutMaps.russianCharacters.contains(char)
                let isMappable = isMappableQWERTY || isMappableRussian

                if char.isLetter || char.isNumber || isMappable {
                    // Новая буква — сбрасываем накопленную пунктуацию (начало нового слова)
                    pendingPunctuation = ""
                    wordBuffer.append(char)
                    if wordBuffer.count > 50 {
                        wordBuffer = String(wordBuffer.suffix(30))
                    }
                } else if char.isPunctuation || char.isWhitespace {
                    // COMPOUND BUZZWORDS: проверяем может ли это быть частью составного термина (gpt-4, c++, react-native)
                    if TechBuzzwordsManager.isCompoundChar(char) &&
                       TechBuzzwordsManager.shared.mightBeCompound(wordBuffer, nextChar: char) {
                        // Продолжаем накапливать — это часть составного buzzword
                        wordBuffer.append(char)
                    } else {
                        // ИСПРАВЛЕНИЕ: очищаем буфер ТОЛЬКО если слово обработано
                        if processWordIfNeeded(triggerChar: char) {
                            clearWordBuffer()
                        }
                        // ИСПРАВЛЕНИЕ ПУНКТУАЦИИ: накапливаем для Double CMD
                        if char.isPunctuation {
                            pendingPunctuation.append(char)
                        } else {
                            pendingPunctuation = ""
                        }
                    }
                }
            }
        }
    }

    /// Обработка изменения модификаторов через CGEvent (Double CMD)
    private func handleFlagsChangedCGEvent(_ event: CGEvent) {
        // КРИТИЧНО: Блокируем обработку во время замены текста
        // Иначе simulateCopy/simulatePaste с .maskCommand триггерят наш монитор → каскад
        guard !isReplacing else { return }

        let flags = event.flags

        // ДИАГНОСТИКА
        NSLog("⌨️ handleFlagsChangedCGEvent: flags=%llu, cmdHeld=%@, firstCmdReleaseTime=%@",
              flags.rawValue, cmdHeld ? "YES" : "NO",
              firstCmdReleaseTime?.description ?? "nil")

        // CMD нажат
        if flags.contains(.maskCommand) && !cmdHeld {
            cmdHeld = true
            otherKeyDuringCmd = false
            cmdPressTime = Date()
            NSLog("⌨️ [CGEvent] CMD нажат")
            return
        }

        // CMD отпущен — проверяем Double CMD
        if !flags.contains(.maskCommand) && cmdHeld {
            cmdHeld = false

            guard !otherKeyDuringCmd else {
                NSLog("⌨️ [CGEvent] CMD отпущен — была другая клавиша, сбрасываем Double CMD")
                firstCmdReleaseTime = nil
                cmdPressTime = nil
                return
            }

            let now = Date()

            if let firstRelease = firstCmdReleaseTime,
               now.timeIntervalSince(firstRelease) < doubleCmdThreshold {
                // DOUBLE CMD DETECTED!
                NSLog("⌨️ 🎯 [CGEvent] DOUBLE CMD DETECTED!")
                firstCmdReleaseTime = nil
                cmdPressTime = nil

                DispatchQueue.main.async { [weak self] in
                    self?.handleDoubleCmdAction()
                }
                return
            }

            NSLog("⌨️ [CGEvent] CMD отпущен — первый раз, запоминаем время")
            firstCmdReleaseTime = now
            cmdPressTime = nil
        }
    }

    /// Обработка Double CMD — конвертация выделенного текста или последнего слова
    @MainActor
    private func handleDoubleCmdAction() {
        // БЛОКИРОВКА КАСКАДА: устанавливаем флаг ДО любых операций
        // Иначе CGEvent с .maskCommand в simulateCopy/simulatePaste триггерят наш монитор
        isReplacing = true
        firstCmdReleaseTime = nil  // Сброс состояния Double CMD
        cmdPressTime = nil
        otherKeyDuringCmd = false

        defer {
            // Разблокируем через 250ms (после завершения всех CGEvent операций)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.isReplacing = false
            }
        }

        // СЛУЧАЙ 1: Есть pending обучение → откат, отмена обучения
        if let pending = pendingLearning {
            pending.timer.cancel()
            pendingLearning = nil

            // Откатываем обратно на оригинал
            if let last = lastManualSwitch {
                TextReplacer.shared.replaceSelectedText(with: last.original)
                NSLog("⌨️ Double CMD: откат '%@' → '%@', обучение отменено", last.converted, last.original)
                logger.info("⏪ Откат: \(last.converted) → \(last.original), обучение отменено")
            }
            lastManualSwitch = nil
            return
        }

        // СЛУЧАЙ 2: Есть недавнее автоисправление → откат
        if let autoSwitch = lastAutoSwitch,
           Date().timeIntervalSince(autoSwitch.time) < autoRollbackWindow {
            TextReplacer.shared.replaceLastWord(
                oldLength: autoSwitch.converted.count,
                newText: autoSwitch.original
            )
            NSLog("⌨️ Double CMD: откат автоисправления '%@' → '%@'", autoSwitch.converted, autoSwitch.original)
            logger.info("⏪ Откат автоисправления: \(autoSwitch.converted) → \(autoSwitch.original)")
            lastAutoSwitch = nil
            return
        }

        // СЛУЧАЙ 3: Пробуем получить выделенный текст
        if let selected = TextReplacer.shared.getSelectedText(),
           selected.count >= HybridValidator.shared.minWordLength {
            NSLog("⌨️ Double CMD: конвертируем выделение '%@'", selected)
            convertSelectedText(selected)
            return
        }

        // СЛУЧАЙ 4: Нет выделения — конвертируем последнее слово
        // ИСПРАВЛЕНИЕ ПУНКТУАЦИИ: включаем накопленную пунктуацию
        let word: String
        if !wordBuffer.isEmpty {
            word = wordBuffer
        } else {
            word = lastProcessedWord + pendingPunctuation
        }
        guard word.count >= HybridValidator.shared.minWordLength else {
            NSLog("⌨️ Double CMD: нет выделения, wordBuffer='%@', lastProcessedWord='%@'",
                  wordBuffer, lastProcessedWord)
            return
        }

        NSLog("⌨️ Double CMD: конвертируем последнее слово '%@'", word)
        convertLastWord(word)
    }

    // handleManualSwitchHotkey() и performManualSwitch() УДАЛЕНЫ
    // Заменены на handleDoubleCmdAction() выше

    /// Обработка Cmd+Z — откат последней автоматической конвертации TextSwitcher
    /// ВАЖНО: Вызывается ТОЛЬКО если есть недавняя конвертация (до 10 сек)
    /// Не блокирует системный Undo — CGEventTap .listenOnly пропускает события
    private func handleCmdZUndo() {
        // Окно для отката Cmd+Z (более длинное чем Double CMD)
        let cmdZUndoWindow: TimeInterval = 10.0

        // Проверяем есть ли недавняя автоматическая конвертация
        guard let autoSwitch = lastAutoSwitch,
              Date().timeIntervalSince(autoSwitch.time) < cmdZUndoWindow else {
            NSLog("⌨️ Cmd+Z: нет недавних автоконвертаций (lastAutoSwitch=%@)",
                  lastAutoSwitch.map { String(describing: $0.time) } ?? "nil")
            return
        }

        NSLog("⌨️ Cmd+Z: откат '%@' → '%@' (%.1f сек назад)",
              autoSwitch.converted, autoSwitch.original,
              Date().timeIntervalSince(autoSwitch.time))

        // БЛОКИРОВКА: предотвращаем обработку событий во время замены
        isReplacing = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.isReplacing = false
            }
        }

        // Откатываем конвертацию
        MainActor.assumeIsolated {
            TextReplacer.shared.replaceLastWord(
                oldLength: autoSwitch.converted.count,
                newText: autoSwitch.original
            )
        }

        // САМООБУЧЕНИЕ: увеличиваем счётчик отмен для этого слова
        incrementUndoCount(for: autoSwitch.original)

        logger.info("⏪ Cmd+Z откат: \(autoSwitch.converted) → \(autoSwitch.original)")
        lastAutoSwitch = nil
    }

    // MARK: - Self-Learning (Undo Tracking)

    /// Счётчик отмен для каждого слова (для самообучения)
    /// Хранится в UserDefaults для персистентности
    private static let undoCountsKey = "textSwitcher.undoCounts"

    /// Увеличивает счётчик отмен для слова и проверяет порог самообучения
    /// - Parameter word: Оригинальное слово (до конвертации)
    private func incrementUndoCount(for word: String) {
        let lowercasedWord = word.lowercased()

        // Получаем текущие счётчики
        var undoCounts = UserDefaults.standard.dictionary(forKey: Self.undoCountsKey) as? [String: Int] ?? [:]

        // Увеличиваем счётчик
        let currentCount = (undoCounts[lowercasedWord] ?? 0) + 1
        undoCounts[lowercasedWord] = currentCount

        // Сохраняем
        UserDefaults.standard.set(undoCounts, forKey: Self.undoCountsKey)

        NSLog("🧠 Undo count: '%@' = %d", lowercasedWord, currentCount)

        // ПОРОГ САМООБУЧЕНИЯ: после 2-х отмен добавляем в исключения
        if currentCount >= 2 {
            // Добавляем в UserExceptions (чёрный список — НЕ конвертировать)
            UserExceptionsManager.shared.addException(word, reason: .autoLearned)

            // Удаляем из счётчика (уже выучено)
            undoCounts.removeValue(forKey: lowercasedWord)
            UserDefaults.standard.set(undoCounts, forKey: Self.undoCountsKey)

            NSLog("🧠 LEARNED: '%@' добавлено в исключения (отменено %d раз)", word, currentCount)
            logger.info("🧠 Самообучение: '\(word)' добавлено в исключения после \(currentCount) отмен")

            // Показываем тост
            onLearned?(word)
        }
    }

    /// Конвертирует выделенный текст
    @MainActor
    private func convertSelectedText(_ selectedText: String) {
        // Используем toggleLayout() для посимвольной конвертации
        // Это корректно обрабатывает смешанные тексты (латиница + кириллица)
        let converted = LayoutMaps.toggleLayout(selectedText)

        // Определяем целевую раскладку по РЕЗУЛЬТАТУ (куда переключились)
        let targetLayout = LayoutMaps.detectLayout(in: converted) ?? .qwerty

        // Меняем текст
        TextReplacer.shared.replaceSelectedText(with: converted)

        lastManualSwitch = (original: selectedText, converted: converted, time: Date())

        // ИСПРАВЛЕНИЕ БАГ #2: Сохраняем КОНВЕРТИРОВАННОЕ слово для toggle
        // Следующий Cmd+Cmd будет использовать converted → original
        lastProcessedWord = converted

        // ИСПРАВЛЕНИЕ БАГ #5: Переключаем системную раскладку на целевой язык
        switchKeyboardLayout(to: targetLayout)

        // Запускаем обучение ТОЛЬКО если включено в настройках
        if TextSwitcherManager.shared.isLearningEnabled {
            let wordsToLearn = extractWordsForLearning(from: selectedText, converted: converted)
            startLearningTimer(originalWords: wordsToLearn.originals, convertedWords: wordsToLearn.converted)
            logger.info("🔄 Ручная смена (выделение): \(selectedText) → \(converted), ожидание \(self.learningDelay) сек...")
        } else {
            logger.info("🔄 Ручная смена (выделение): \(selectedText) → \(converted) [обучение выключено]")
            // Статистика без обучения
            onManualSwitch?()
        }
    }

    /// Конвертирует последнее набранное слово (без выделения)
    @MainActor
    private func convertLastWord(_ word: String) {
        // Определяем раскладку ПО ТЕКСТУ
        guard let textLayout = LayoutMaps.detectLayout(in: word) else {
            logger.debug("⌨️ Cmd+Shift+Space: не удалось определить раскладку слова '\(word)'")
            return
        }

        // ВАЖНО: includeAllSymbols = true для конвертации ВСЕХ символов
        let converted = LayoutMaps.convert(word, from: textLayout, to: textLayout.opposite, includeAllSymbols: true)

        // ИСПРАВЛЕНИЕ ПУНКТУАЦИИ: используем replaceCharactersViaSelection для ТОЧНОГО количества символов
        // replaceLastWordViaSelection использует Shift+Option+Left, который останавливается на границе слова
        // и НЕ включает пунктуацию! Поэтому "ghbdtn!" → "привет" без "!"
        // replaceCharactersViaSelection использует Shift+Left × count, что выделяет ВСЕ символы включая пунктуацию
        TextReplacer.shared.replaceCharactersViaSelection(count: word.count, newText: converted)

        lastManualSwitch = (original: word, converted: converted, time: Date())

        // ИСПРАВЛЕНИЕ БАГ #2: Сохраняем КОНВЕРТИРОВАННОЕ слово для toggle
        // Следующий Cmd+Cmd будет использовать converted → original (и так бесконечно)
        // ВАЖНО: сохраняем только буквы, пунктуация идёт отдельно в pendingPunctuation
        let convertedLetters = String(converted.filter { $0.isLetter })
        lastProcessedWord = convertedLetters
        wordBuffer = ""
        pendingPunctuation = ""

        // ИСПРАВЛЕНИЕ БАГ #5: Переключаем системную раскладку на целевой язык
        switchKeyboardLayout(to: textLayout.opposite)

        // Запускаем обучение ТОЛЬКО если включено в настройках
        if TextSwitcherManager.shared.isLearningEnabled {
            startLearningTimer(originalWords: [word], convertedWords: [converted])
            logger.info("🔄 Ручная смена (wordBuffer): \(word) → \(converted), ожидание \(self.learningDelay) сек...")
        } else {
            logger.info("🔄 Ручная смена (wordBuffer): \(word) → \(converted) [обучение выключено]")
            // Статистика без обучения
            onManualSwitch?()
        }
    }

    /// Извлекает пары слов для обучения
    private func extractWordsForLearning(from original: String, converted: String) -> (originals: [String], converted: [String]) {
        let originalWords = original.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= HybridValidator.shared.minWordLength }

        let convertedWords = converted.components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= HybridValidator.shared.minWordLength }

        return (originalWords, convertedWords)
    }

    /// Запускает таймер обучения (2 секунды)
    private func startLearningTimer(originalWords: [String], convertedWords: [String]) {
        let learningTimer = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // 2 секунды прошли без отмены → сохраняем ТОЛЬКО в ForcedConversions
            // ИСПРАВЛЕНИЕ БАГ #1: НЕ добавляем в UserExceptions!
            // ForcedConversions достаточно — оно ВСЕГДА конвертирует руддщ→hello.
            // Добавление hello в исключения блокировало бы обратную конвертацию.
            for (index, originalWord) in originalWords.enumerated() {
                let convertedWord = index < convertedWords.count ? convertedWords[index] : originalWord

                // БЕЛЫЙ СПИСОК: руддщ → hello (принудительная конвертация)
                ForcedConversionsManager.shared.addConversion(original: originalWord, converted: convertedWord)
            }

            // Показываем feedback для первой пары
            if let firstOriginal = originalWords.first {
                self.onLearned?(firstOriginal)
            }

            self.pendingLearning = nil
            self.lastManualSwitch = nil

            logger.info("📚 Обучено: \(originalWords) → ForcedConversions + UserExceptions")

            // Статистика
            self.onManualSwitch?()
        }

        pendingLearning = (words: originalWords, timer: learningTimer)
        DispatchQueue.main.asyncAfter(deadline: .now() + learningDelay, execute: learningTimer)
    }

    // MARK: - Word Processing

    /// Обрабатывает слово СИНХРОННО (без debounce!)
    /// Важно: debounce убран, чтобы курсор не успел сдвинуться перед заменой
    /// - Parameter triggerChar: триггерный символ (пробел/пунктуация) или nil если триггера нет (Enter/Tab)
    /// - Returns: true если слово было обработано, false если пропущено (isReplacing)
    @discardableResult
    private func processWordIfNeeded(triggerChar: Character? = nil) -> Bool {
        // ИСПРАВЛЕНИЕ: блокируем только обработку, НЕ накопление символов
        // Если isReplacing — возвращаем false, буфер НЕ очищается, слово сохраняется для следующей попытки
        guard !isReplacing else {
            NSLog("⚡ processWord: skipped (isReplacing) — буфер СОХРАНЁН для следующей попытки")
            return false  // НЕ обработано — буфер сохранится
        }

        let word = wordBuffer
        guard HybridValidator.shared.shouldAnalyze(word) else { return true }  // Обработано (пустое/короткое)

        // ИСПРАВЛЕНИЕ БАГ #2: Сохраняем слово ПЕРЕД обработкой
        // Это позволяет двойному Cmd работать после пробела
        lastProcessedWord = word

        logger.debug("⌨️ processWordIfNeeded: word='\(word)', trigger='\(triggerChar.map { String($0) } ?? "nil")'")

        // Обрабатываем синхронно, пока курсор на месте
        processWord(word, triggerChar: triggerChar)
        return true  // Обработано
    }

    /// Обрабатывает слово через HybridValidator
    /// - Parameters:
    ///   - word: Слово для проверки
    ///   - triggerChar: Триггерный символ для восстановления после конвертации (или nil)
    private func processWord(_ word: String, triggerChar: Character? = nil) {
        NSLog("⚡ processWord: word='%@'", word)

        // КРИТИЧЕСКОЕ ИСПРАВЛЕНИЕ: Определяем раскладку ПО ТЕКСТУ, а не по системе!
        // Иначе "ntgthm" при русской системной раскладке не конвертируется в "теперь"
        guard let textLayout = LayoutMaps.detectLayout(in: word) else {
            NSLog("⚡ processWord: '%@' — не удалось определить раскладку", word)
            logger.debug("⚡ processWord: '\(word)' — не удалось определить раскладку")
            return
        }

        NSLog("⚡ processWord: '%@' textLayout=%@", word, textLayout.rawValue)

        // LAYOUT SWITCH BIAS: для коротких слов типа "tot" → "еще"
        let biasLayout = calculateLayoutBias(textLayout: textLayout)

        let result = HybridValidator.shared.validate(word, currentLayout: textLayout, biasTowardLayout: biasLayout)

        NSLog("⚡ processWord: '%@' → %@", word, String(describing: result))
        logger.debug("⚡ processWord: '\(word)' textLayout=\(textLayout.rawValue) → \(result)")

        switch result {
        case .keep:
            // Записываем в историю контекста (слово оставлено как есть)
            recordConversionDecision(originalLayout: textLayout, wasSwitched: false, targetLayout: nil)

        case .switchLayout(let targetLayout, let reason):
            let converted = LayoutMaps.convert(word, from: textLayout, to: targetLayout, includeAllSymbols: true)

            // ВАЖНО: Удаляем слово + триггерный символ (если есть)
            let totalToDelete = word.count + (triggerChar != nil ? 1 : 0)

            // ИСПРАВЛЕНИЕ БАГ #4: Конвертируем ТАКЖЕ триггерный символ
            // Пример: "Так;е" → "Также" (где ; → ж)
            let textToInsert: String
            if let trigger = triggerChar {
                // Конвертируем триггерный символ в целевую раскладку
                // ВАЖНО: includeAllSymbols: true — иначе пунктуация НЕ конвертируется!
                let convertedTrigger = LayoutMaps.convert(String(trigger), from: textLayout, to: targetLayout, includeAllSymbols: true)
                textToInsert = converted + convertedTrigger
            } else {
                textToInsert = converted
            }

            // Блокируем обработку новых событий пока идёт замена
            isReplacing = true

            // NSEvent monitors всегда на main thread, используем assumeIsolated
            MainActor.assumeIsolated {
                TextReplacer.shared.replaceLastWord(oldLength: totalToDelete, newText: textToInsert)
            }

            // Разблокируем через 150ms (достаточно для завершения замены)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.isReplacing = false
            }

            lastAutoSwitch = (original: word, converted: converted, time: Date())

            // Записываем в историю контекста (слово конвертировано)
            recordConversionDecision(originalLayout: textLayout, wasSwitched: true, targetLayout: targetLayout)

            logger.info("✨ Автоисправление (\(reason)): \(word) → \(converted) [deleted: \(totalToDelete), trigger: '\(triggerChar.map { String($0) } ?? "nil")']")

            // ИСПРАВЛЕНИЕ БАГ #5: Переключаем системную раскладку на целевой язык
            switchKeyboardLayout(to: targetLayout)

            // Статистика
            onAutoSwitch?()
        }
    }

    // MARK: - Keyboard Layout Detection

    /// Определяет текущую раскладку клавиатуры и отслеживает переключения
    private func detectCurrentKeyboardLayout() -> KeyboardLayout {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return .qwerty
        }

        guard let sourceID = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return .qwerty
        }

        let inputSourceID = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String

        // Определяем текущую раскладку
        let currentLayout: KeyboardLayout
        if inputSourceID.lowercased().contains("russian") ||
           inputSourceID.lowercased().contains("ru") {
            currentLayout = .russian
        } else {
            currentLayout = .qwerty
        }

        // LAYOUT SWITCH BIAS: отслеживаем переключение раскладки
        if currentLayout != previousSystemLayout {
            NSLog("⌨️ Layout Switch: %@ → %@", previousSystemLayout.rawValue, currentLayout.rawValue)
            lastLayoutSwitchTime = Date()
            previousSystemLayout = currentLayout
        }

        return currentLayout
    }

    /// Вычисляет биас для Layout Switch (для коротких слов типа "tot")
    /// - Parameter textLayout: Раскладка определённая по тексту
    /// - Returns: Раскладка к которой нужен биас, или nil если биаса нет
    private func calculateLayoutBias(textLayout: KeyboardLayout) -> KeyboardLayout? {
        // ПРИОРИТЕТ 1: Контекстный биас (большинство слов конвертированы в определённую раскладку)
        if let contextBias = calculateContextBias(for: textLayout) {
            return contextBias
        }

        // ПРИОРИТЕТ 2: Layout Switch биас (недавнее переключение системной раскладки)
        // Получаем текущую системную раскладку (это также обновит previousSystemLayout)
        let currentSystemLayout = detectCurrentKeyboardLayout()

        // Проверяем было ли недавнее переключение раскладки
        guard let switchTime = lastLayoutSwitchTime else { return nil }
        let timeSinceSwitch = Date().timeIntervalSince(switchTime)
        guard timeSinceSwitch < layoutBiasWindow else { return nil }

        // ИСПРАВЛЕНО: Если текст на языке ТЕКУЩЕЙ раскладки (после переключения),
        // то пользователь вероятно хотел ПРЕДЫДУЩУЮ раскладку.
        //
        // Пример: была русская раскладка, переключились на английскую, набрали "tot"
        // - currentSystemLayout = .qwerty (текущая системная)
        // - textLayout = .qwerty (буквы "tot" — английские)
        // - Совпадают! Значит пользователь набрал НА НОВОЙ раскладке
        // - Биас к ПРЕДЫДУЩЕЙ раскладке (opposite от current) = .russian
        // - Результат: "tot" → "еще" ✓

        if textLayout == currentSystemLayout {
            // Текст на языке НОВОЙ (текущей) раскладки — пользователь вероятно ошибся
            // Биас к ПРЕДЫДУЩЕЙ раскладке (opposite от current)
            let biasTarget = currentSystemLayout.opposite
            NSLog("⌨️ Layout Bias: textLayout=%@, current=%@, bias→%@",
                  textLayout.rawValue, currentSystemLayout.rawValue, biasTarget.rawValue)
            return biasTarget
        }

        // Текст на другом языке — нет несоответствия с текущей раскладкой
        return nil
    }

    // MARK: - Context Bias Methods

    /// Записывает решение о конвертации в историю
    /// - Parameters:
    ///   - originalLayout: Исходная раскладка слова
    ///   - wasSwitched: Было ли слово конвертировано
    ///   - targetLayout: Целевая раскладка (если было конвертировано)
    private func recordConversionDecision(originalLayout: KeyboardLayout, wasSwitched: Bool, targetLayout: KeyboardLayout?) {
        let now = Date()

        // Записываем результат
        let resultLayout = wasSwitched ? (targetLayout ?? originalLayout.opposite) : originalLayout
        conversionHistory.append((layout: resultLayout, wasSwitched: wasSwitched, time: now))

        // Ограничиваем размер истории
        if conversionHistory.count > maxConversionHistory {
            conversionHistory.removeFirst(conversionHistory.count - maxConversionHistory)
        }

        // Удаляем старые записи (старше contextTimeWindow)
        conversionHistory.removeAll { now.timeIntervalSince($0.time) > contextTimeWindow }

        NSLog("📊 Context: recorded %@ → %@ (history: %d items)",
              originalLayout.rawValue,
              wasSwitched ? "SWITCH to \(resultLayout.rawValue)" : "KEEP",
              conversionHistory.count)
    }

    /// Вычисляет контекстный биас на основе недавних конвертаций
    /// - Parameter currentLayout: Текущая раскладка слова
    /// - Returns: Раскладка к которой нужен биас, или nil если контекста недостаточно
    private func calculateContextBias(for currentLayout: KeyboardLayout) -> KeyboardLayout? {
        let now = Date()

        // Фильтруем только недавние записи
        let recentHistory = conversionHistory.filter { now.timeIntervalSince($0.time) <= contextTimeWindow }

        // Проверяем минимальное количество слов
        guard recentHistory.count >= minContextWords else { return nil }

        // Считаем сколько слов было конвертировано в каждую раскладку
        var switchedToRussian = 0
        var switchedToEnglish = 0
        var totalSwitched = 0

        for entry in recentHistory {
            if entry.wasSwitched {
                totalSwitched += 1
                if entry.layout == .russian {
                    switchedToRussian += 1
                } else {
                    switchedToEnglish += 1
                }
            }
        }

        // Если недостаточно конвертаций — нет биаса
        let switchRatio = Double(totalSwitched) / Double(recentHistory.count)
        guard switchRatio >= contextBiasThreshold else { return nil }

        // Определяем доминирующую раскладку
        if switchedToRussian > switchedToEnglish && currentLayout == .qwerty {
            // Большинство конвертировано в русский, а текущее слово на английском → биас к русскому
            NSLog("📊 Context Bias: %d/%d switched to RU, current=%@ → bias to RU",
                  switchedToRussian, recentHistory.count, currentLayout.rawValue)
            return .russian
        } else if switchedToEnglish > switchedToRussian && currentLayout == .russian {
            // Большинство конвертировано в английский, а текущее слово на русском → биас к английскому
            NSLog("📊 Context Bias: %d/%d switched to EN, current=%@ → bias to EN",
                  switchedToEnglish, recentHistory.count, currentLayout.rawValue)
            return .qwerty
        }

        return nil
    }

    /// Очищает историю контекста (при смене приложения, паузе и т.д.)
    private func clearContextHistory() {
        conversionHistory.removeAll()
        NSLog("📊 Context: history cleared")
    }

    // MARK: - Helpers

    /// Получает символы из NSEvent (с fallback на CGEvent API)
    /// В глобальных мониторах event.characters часто nil — используем keyboardGetUnicodeString
    private func characterFromEvent(_ event: NSEvent) -> String? {
        // Сначала пробуем стандартный способ
        if let chars = event.characters, !chars.isEmpty {
            return chars
        }

        // Fallback: получаем символ через CGEvent instance method
        guard let cgEvent = event.cgEvent else { return nil }

        var length: Int = 0
        var chars = [UniChar](repeating: 0, count: 4)
        cgEvent.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)

        guard length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    /// Очищает буфер слова
    private func clearWordBuffer() {
        wordBuffer = ""
    }

    /// Очищает всё состояние
    private func clearState() {
        clearWordBuffer()
        lastProcessedWord = ""
        pendingPunctuation = ""
        lastAutoSwitch = nil
        lastManualSwitch = nil
        pendingLearning?.timer.cancel()
        pendingLearning = nil
        isReplacing = false
        clearContextHistory()
    }

    // MARK: - Keyboard Layout Switching

    /// Переключает системную раскладку клавиатуры (ИСПРАВЛЕНИЕ БАГ #5)
    /// - Parameter targetLayout: Целевая раскладка
    private func switchKeyboardLayout(to targetLayout: KeyboardLayout) {
        // Определяем ID источника ввода для целевой раскладки
        let targetSourceID: String
        switch targetLayout {
        case .qwerty:
            targetSourceID = "com.apple.keylayout.ABC"
        case .russian:
            targetSourceID = "com.apple.keylayout.Russian"
        }

        // Создаём фильтр для поиска источника ввода
        let filter: [String: Any] = [
            kTISPropertyInputSourceID as String: targetSourceID
        ]

        // Ищем источник ввода
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

        // Переключаем раскладку
        let status = TISSelectInputSource(source)
        logger.info("⌨️ Раскладка → \(targetLayout.rawValue): \(status == noErr ? "OK" : "ERROR \(status)")")
    }
}

// MARK: - Debug Extension

extension KeyboardMonitor {
    /// Возвращает текущее состояние для отладки
    func debugState() -> String {
        var state = "=== KeyboardMonitor State ===\n"
        state += "isMonitoring: \(isMonitoring)\n"
        state += "isPaused: \(isPaused)\n"
        state += "wordBuffer: '\(wordBuffer)'\n"
        state += "lastAutoSwitch: \(lastAutoSwitch?.converted ?? "none")\n"
        state += "pendingLearning: \(pendingLearning?.words.joined(separator: ", ") ?? "none")\n"
        state += "currentLayout: \(detectCurrentKeyboardLayout().rawValue)\n"
        return state
    }
}
