//
//  Permissions.swift
//  Dictum
//
//  Централизованный модуль управления разрешениями macOS
//
//  ⛔ ВНИМАНИЕ: ЭТОТ ФАЙЛ ЗАМОРОЖЕН! НЕ ИЗМЕНЯТЬ БЕЗ СОГЛАСОВАНИЯ!
//
//  Система разрешений ФИНАЛИЗИРОВАНА после детального исследования (январь 2026):
//  - ТОЛЬКО 3 разрешения: Accessibility, Microphone, Screen Recording
//  - Input Monitoring УДАЛЁН — Accessibility покрывает CGEventTap .listenOnly
//  - Screen Recording modal НЕИЗБЕЖЕН — это Apple security by design
//
//  Подробности: см. CLAUDE.md → "Требования и permissions"
//

import Foundation
import AVFoundation
import ApplicationServices
import AppKit
import os
@preconcurrency import ScreenCaptureKit

private let logger = Logger(subsystem: "com.dictum.app", category: "Permissions")

// MARK: - PermissionType

/// Типы разрешений, необходимых для работы Dictum
/// ВАЖНО: Input Monitoring УБРАН — Accessibility покрывает CGEventTap
enum PermissionType: String, CaseIterable {
    case accessibility
    case microphone
    case screenRecording

    /// Отображаемое название разрешения
    var displayName: String {
        switch self {
        case .accessibility: return "Универсальный доступ"
        case .microphone: return "Микрофон"
        case .screenRecording: return "Запись экрана"
        }
    }

    /// Подзаголовок с описанием назначения
    var subtitle: String {
        switch self {
        case .accessibility: return "Для вставки текста и глобальных хоткеев"
        case .microphone: return "Для записи голосовых заметок"
        case .screenRecording: return "Для создания скриншотов"
        }
    }

    /// SF Symbol для иконки
    var icon: String {
        switch self {
        case .accessibility: return "hand.raised.fill"
        case .microphone: return "mic.fill"
        case .screenRecording: return "rectangle.dashed.badge.record"
        }
    }

    /// Секция в System Settings (Privacy_XXX)
    var settingsSection: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .microphone: return "Microphone"
        case .screenRecording: return "ScreenCapture"
        }
    }

    /// Требуется ли перезапуск приложения после выдачи разрешения
    /// ВАЖНО: Только Screen Recording требует рестарт — macOS делает SIGKILL
    /// Accessibility работает СРАЗУ без рестарта
    var requiresRestart: Bool {
        return self == .screenRecording
    }
}

// MARK: - PermissionStatus

/// Статус разрешения
enum PermissionStatus: Equatable {
    case notDetermined
    case denied
    case authorized
}

// MARK: - PermissionsManager

/// Централизованный менеджер разрешений для Dictum
/// Использует @Published для мгновенного обновления SwiftUI UI
@MainActor
final class PermissionsManager: ObservableObject {

    // MARK: - Singleton

    static let shared = PermissionsManager()

    // MARK: - Published State (для SwiftUI binding)

    @Published private(set) var accessibilityStatus: PermissionStatus = .notDetermined
    @Published private(set) var microphoneStatus: PermissionStatus = .notDetermined
    @Published private(set) var screenRecordingStatus: PermissionStatus = .notDetermined

    // MARK: - Convenience Properties

    var hasAccessibility: Bool { accessibilityStatus == .authorized }
    var hasMicrophone: Bool { microphoneStatus == .authorized }
    var hasScreenRecording: Bool { screenRecordingStatus == .authorized }

    /// Все обязательные разрешения выданы (3 штуки: Accessibility, Microphone, Screen Recording)
    var hasAllRequired: Bool {
        hasAccessibility && hasMicrophone && hasScreenRecording
    }

    // MARK: - Polling

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 0.5

    // MARK: - Initialization

    private init() {
        refreshAllStatuses()
        logger.info("PermissionsManager initialized: A=\(self.hasAccessibility) M=\(self.hasMicrophone) S=\(self.hasScreenRecording)")
    }

    // MARK: - Status Checking

    /// Проверить текущий статус разрешения
    func checkStatus(for type: PermissionType) -> PermissionStatus {
        switch type {
        case .accessibility:
            return AXIsProcessTrusted() ? .authorized : .notDetermined

        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .authorized
            case .denied, .restricted: return .denied
            case .notDetermined: return .notDetermined
            @unknown default: return .notDetermined
            }

        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .authorized : .notDetermined
        }
    }

    /// Обновить все статусы
    func refreshAllStatuses() {
        accessibilityStatus = checkStatus(for: .accessibility)
        microphoneStatus = checkStatus(for: .microphone)
        screenRecordingStatus = checkStatus(for: .screenRecording)
    }

    // MARK: - Permission Requests

    /// Запросить разрешение
    /// - Parameters:
    ///   - type: Тип разрешения
    ///   - completion: Callback с результатом (true = выдано сразу, false = нужно открыть Settings)
    func request(_ type: PermissionType, completion: ((Bool) -> Void)? = nil) {
        logger.info("Requesting permission: \(type.rawValue)")

        switch type {
        case .accessibility:
            // Accessibility не показывает диалог, только открывает Settings
            // Используем строковый ключ для Swift 6 concurrency safety
            let options: NSDictionary = ["AXTrustedCheckOptionPrompt": false]
            _ = AXIsProcessTrustedWithOptions(options)
            openSettings(for: .accessibility)
            completion?(false)

        case .microphone:
            let status = AVCaptureDevice.authorizationStatus(for: .audio)
            if status == .notDetermined {
                // Первый раз — показать системный диалог
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    Task { @MainActor in
                        self.refreshAllStatuses()
                        completion?(granted)
                    }
                }
            } else {
                // Уже denied — открыть Settings
                openSettings(for: .microphone)
                completion?(false)
            }

        case .screenRecording:
            if !hasScreenRecording {
                // Запланировать авто-рестарт ПЕРЕД открытием Settings
                // Потому что macOS делает SIGKILL при выдаче этого разрешения
                scheduleAppRestart()

                // ScreenCaptureKit — надёжно регистрирует приложение в TCC
                // CGRequestScreenCaptureAccess() показывает диалог только один раз за установку,
                // а SCShareableContent.current работает всегда
                // Модалка macOS уже содержит кнопку "Open System Settings" — не дублируем
                Task {
                    do {
                        let _ = try await SCShareableContent.current
                        logger.info("ScreenCaptureKit: triggered TCC registration")
                    } catch {
                        logger.info("ScreenCaptureKit: \(error.localizedDescription)")
                    }
                }
            }
            completion?(false)
        }
    }

    /// Открыть System Settings на соответствующей секции
    func openSettings(for type: PermissionType) {
        let section = type.settingsSection
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_\(section)"

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            logger.info("Opened Settings: Privacy_\(section)")
        } else {
            logger.error("Failed to create URL for Settings: \(section)")
        }
    }

    // MARK: - Polling

    /// Начать polling для отслеживания изменений разрешений
    func startPolling() {
        stopPolling()

        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollPermissions()
            }
        }

        logger.info("Started permission polling (interval: \(self.pollingInterval)s)")
    }

    /// Остановить polling
    func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        logger.info("Stopped permission polling")
    }

    /// Проверить изменения разрешений
    private func pollPermissions() {
        let oldStates = (accessibilityStatus, microphoneStatus, screenRecordingStatus)
        refreshAllStatuses()
        let newStates = (accessibilityStatus, microphoneStatus, screenRecordingStatus)

        if oldStates != newStates {
            logger.info("Permissions changed: A=\(self.hasAccessibility) M=\(self.hasMicrophone) S=\(self.hasScreenRecording)")

            // Общее уведомление об изменении разрешений
            NotificationCenter.default.post(name: .permissionsChanged, object: nil)

            // Для перерегистрации хоткеев (Accessibility изменился)
            if oldStates.0 != newStates.0 {
                NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
            }
        }
    }

    // MARK: - Auto-Restart (только для Screen Recording)

    /// Запланировать перезапуск приложения
    /// ВАЖНО: Нужен ТОЛЬКО для Screen Recording!
    /// macOS делает SIGKILL при выдаче этого разрешения
    private func scheduleAppRestart() {
        let appPath = Bundle.main.bundlePath

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "nohup sh -c 'sleep 3; open \"\(appPath)\"' >/dev/null 2>&1 &"]

        do {
            try task.run()
            logger.info("Scheduled app restart in 3 seconds (Screen Recording)")
        } catch {
            logger.error("Failed to schedule restart: \(error.localizedDescription)")
        }
    }

}

// MARK: - Notifications

extension Notification.Name {
    /// Общее уведомление об изменении любого разрешения
    static let permissionsChanged = Notification.Name("permissionsChanged")

    /// Уведомление об изменении Accessibility (для перерегистрации хоткеев и CGEventTap)
    static let accessibilityStatusChanged = Notification.Name("accessibilityStatusChanged")
}

// MARK: - Legacy Compatibility

/// Typealias для обратной совместимости с AccessibilityHelper
typealias AccessibilityHelper = PermissionsManager
