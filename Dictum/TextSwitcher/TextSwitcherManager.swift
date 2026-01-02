//
//  TextSwitcherManager.swift
//  Dictum
//
//  Главный координатор TextSwitcher.
//  - Включение/выключение функциональности
//  - Показ зелёного тоста при обучении
//  - Статистика использования
//  - Пауза во время диктовки
//

import Foundation
import SwiftUI
import Combine
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "TextSwitcherManager")

// MARK: - Text Switcher Manager

/// Главный координатор TextSwitcher
@MainActor
class TextSwitcherManager: ObservableObject {

    /// Singleton
    static let shared = TextSwitcherManager()

    // MARK: - Published Properties

    /// Включён ли TextSwitcher
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "textSwitcherEnabled")
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    /// Включено ли обучение (сохранение слов в ForcedConversions)
    /// По умолчанию ВЫКЛЮЧЕНО — UserDefaults.bool() возвращает false для несуществующего ключа
    @Published var isLearningEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLearningEnabled, forKey: "textSwitcherLearningEnabled")
        }
    }

    /// Количество автоматических исправлений
    @Published private(set) var autoSwitchCount: Int {
        didSet {
            UserDefaults.standard.set(autoSwitchCount, forKey: "textSwitcherAutoCount")
        }
    }

    /// Количество ручных смен (двойной Cmd)
    @Published private(set) var manualSwitchCount: Int {
        didSet {
            UserDefaults.standard.set(manualSwitchCount, forKey: "textSwitcherManualCount")
        }
    }

    /// Текст для зелёного тоста (nil = скрыт)
    @Published var learnedToastText: String?

    /// Позиция тоста (рядом с курсором)
    @Published var toastPosition: CGPoint = .zero

    /// Статус мониторинга (для отображения в UI)
    @Published private(set) var monitoringActive: Bool = false

    // MARK: - Private Properties

    /// Подписка на уведомления о записи
    private var recordingObserver: NSObjectProtocol?

    /// Таймер для скрытия тоста
    private var toastHideTimer: DispatchWorkItem?

    // MARK: - Initialization

    private init() {
        // Загружаем состояние из UserDefaults
        self.isEnabled = UserDefaults.standard.bool(forKey: "textSwitcherEnabled")
        self.isLearningEnabled = UserDefaults.standard.bool(forKey: "textSwitcherLearningEnabled")
        // По умолчанию ВЫКЛЮЧЕНО — UserDefaults.bool() возвращает false для несуществующего ключа
        self.autoSwitchCount = UserDefaults.standard.integer(forKey: "textSwitcherAutoCount")
        self.manualSwitchCount = UserDefaults.standard.integer(forKey: "textSwitcherManualCount")

        NSLog("🔄 TextSwitcherManager.init(): isEnabled=%@, isLearningEnabled=%@, autoCount=%d, manualCount=%d",
              self.isEnabled ? "YES" : "NO",
              self.isLearningEnabled ? "YES" : "NO",
              self.autoSwitchCount,
              self.manualSwitchCount)

        setupKeyboardMonitorCallbacks()
        setupRecordingObserver()

        // Запускаем мониторинг если включён (didSet не вызывается при init)
        if self.isEnabled {
            NSLog("🔄 TextSwitcherManager: isEnabled=true, запускаем мониторинг...")
            startMonitoring()
        } else {
            NSLog("🔄 TextSwitcherManager: isEnabled=false, мониторинг НЕ запускаем")
        }

        logger.info("🔄 TextSwitcherManager инициализирован (enabled: \(self.isEnabled))")
    }

    // Singleton живёт всё время работы приложения — deinit не нужен

    // MARK: - Public API

    /// Включает TextSwitcher
    func enable() {
        isEnabled = true
        logger.info("🔄 TextSwitcher включён")
    }

    /// Выключает TextSwitcher
    func disable() {
        isEnabled = false
        logger.info("🔄 TextSwitcher выключен")
    }

    /// Переключает состояние
    func toggle() {
        isEnabled.toggle()
    }

    /// Показывает зелёный тост при обучении
    /// - Parameter word: Слово, добавленное в исключения
    func showLearnedToast(word: String) {
        // Отменяем предыдущий таймер
        toastHideTimer?.cancel()

        // Получаем позицию курсора
        toastPosition = getMousePosition()
        learnedToastText = word

        // Автоскрытие через 1.5 сек
        let hideTimer = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.learnedToastText = nil
            }
        }
        toastHideTimer = hideTimer

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: hideTimer)
    }

    /// Сбрасывает статистику
    func resetStatistics() {
        autoSwitchCount = 0
        manualSwitchCount = 0
        logger.info("🔄 TextSwitcher: статистика сброшена")
    }

    // MARK: - Private Methods

    /// Запускает мониторинг клавиатуры
    private func startMonitoring() {
        NSLog("🔄 TextSwitcherManager.startMonitoring() ВЫЗВАН")
        monitoringActive = KeyboardMonitor.shared.startMonitoring()
        NSLog("🔄 TextSwitcherManager: monitoringActive = %@", monitoringActive ? "YES" : "NO")
        if !monitoringActive {
            logger.warning("🔄 TextSwitcher: не удалось запустить (нет Accessibility?)")
        }
    }

    /// Останавливает мониторинг клавиатуры
    private func stopMonitoring() {
        KeyboardMonitor.shared.stopMonitoring()
        monitoringActive = false
    }

    /// Настраивает callbacks для KeyboardMonitor
    private func setupKeyboardMonitorCallbacks() {
        KeyboardMonitor.shared.onLearned = { [weak self] word in
            Task { @MainActor in
                self?.showLearnedToast(word: word)
            }
        }

        KeyboardMonitor.shared.onAutoSwitch = { [weak self] in
            Task { @MainActor in
                self?.autoSwitchCount += 1
            }
        }

        KeyboardMonitor.shared.onManualSwitch = { [weak self] in
            Task { @MainActor in
                self?.manualSwitchCount += 1
            }
        }
    }

    /// Подписывается на уведомления о записи голоса
    private func setupRecordingObserver() {
        // Пауза во время записи голоса
        recordingObserver = NotificationCenter.default.addObserver(
            forName: .recordingStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Извлекаем данные до входа в Task (notification не Sendable)
            let isRecording = notification.userInfo?["isRecording"] as? Bool

            Task { @MainActor in
                guard let self = self, self.isEnabled else { return }

                // userInfo содержит состояние записи
                if let isRecording = isRecording {
                    if isRecording {
                        KeyboardMonitor.shared.pause()
                    } else {
                        KeyboardMonitor.shared.resume()
                    }
                }
            }
        }
    }

    /// Получает текущую позицию курсора мыши
    private func getMousePosition() -> CGPoint {
        return NSEvent.mouseLocation
    }
}

// MARK: - Toast Overlay View

/// Зелёный тост при обучении слова
struct LearnedToastView: View {
    let word: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))

            Text("\"\(word)\" добавлено")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.accent)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
    }
}

// MARK: - Toast Window Controller

/// Контроллер окна для показа тоста
class ToastWindowController: @unchecked Sendable {

    /// Singleton
    static let shared = ToastWindowController()

    /// Окно тоста
    private var toastWindow: NSWindow?

    /// Таймер скрытия
    private var hideTimer: DispatchWorkItem?

    private init() {}

    /// Показывает тост рядом с курсором
    @MainActor
    func showToast(word: String) {
        // Скрываем предыдущий
        hideToast()

        // Создаём окно
        let toastView = LearnedToastView(word: word)
        let hostingView = NSHostingView(rootView: toastView)
        hostingView.frame = CGRect(x: 0, y: 0, width: 200, height: 40)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.ignoresMouseEvents = true
        window.contentView = hostingView

        // Позиционируем рядом с курсором
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = CGRect(
            x: mouseLocation.x + 20,
            y: mouseLocation.y - 10,
            width: hostingView.fittingSize.width,
            height: hostingView.fittingSize.height
        )
        window.setFrame(windowFrame, display: true)
        window.orderFrontRegardless()

        self.toastWindow = window

        // Автоскрытие
        hideTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            self?.hideToast()
        }
        hideTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: timer)

        logger.debug("🟢 Toast: показан для '\(word)'")
    }

    /// Скрывает тост
    @MainActor
    func hideToast() {
        hideTimer?.cancel()
        hideTimer = nil

        toastWindow?.orderOut(nil)
        toastWindow = nil
    }
}

// MARK: - Notification.Name Extension

// Уведомления определены в Settings.swift:
// - .recordingStateChanged — для паузы TextSwitcher во время записи голоса
// - .textSwitcherToggled — для уведомления об изменении состояния (если понадобится)
