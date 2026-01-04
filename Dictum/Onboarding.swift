//
//  Onboarding.swift
//  Dictum
//
//  Onboarding wizard для первого запуска приложения
//

import SwiftUI
import AVFoundation
import AppKit
import Combine

// MARK: - Notification Name
extension Notification.Name {
    static let onboardingCompleted = Notification.Name("onboardingCompleted")
}

// MARK: - Onboarding Steps
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case speechSetup = 1
    case permissions = 2
    case complete = 3

    var stepNumber: Int? {
        switch self {
        case .welcome, .complete: return nil
        case .speechSetup: return 1
        case .permissions: return 2
        }
    }

    var totalSteps: Int { 2 }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    @State private var currentStep: OnboardingStep
    @ObservedObject private var localASRManager = ParakeetASRProvider.shared
    @ObservedObject private var settings = SettingsManager.shared
    @ObservedObject private var permissions = PermissionsManager.shared

    init() {
        // Восстанавливаем шаг из настроек
        let savedStep = SettingsManager.shared.currentOnboardingStep
        if let step = OnboardingStep(rawValue: savedStep) {
            _currentStep = State(initialValue: step)
        } else {
            _currentStep = State(initialValue: .welcome)
        }
    }

    // Deepgram API Key input
    @State private var deepgramKeyInput: String = ""
    @State private var showingDeepgramInput = false

    // Computed: можно ли идти дальше с шага Speech Setup
    private var canProceedFromSpeechSetup: Bool {
        let hasLocalModel: Bool
        switch localASRManager.modelStatus {
        case .ready, .loading, .downloading:
            hasLocalModel = true
        default:
            hasLocalModel = false
        }
        let hasDeepgram = settings.hasDeepgramAPIKey
        return hasLocalModel || hasDeepgram
    }

    // Computed: можно ли идти дальше с шага Permissions
    // ВАЖНО: ВСЕ 4 разрешения обязательны
    private var canProceedFromPermissions: Bool {
        permissions.hasAllRequired
    }

    var body: some View {
        VStack(spacing: 0) {
            // Контент шага
            switch currentStep {
            case .welcome:
                WelcomeStepView(
                    onNext: { currentStep = .speechSetup },
                    onClose: closeWindow
                )

            case .speechSetup:
                SpeechSetupStepView(
                    deepgramKeyInput: $deepgramKeyInput,
                    showingDeepgramInput: $showingDeepgramInput,
                    onNext: { currentStep = .permissions },
                    onBack: { currentStep = .welcome },
                    onClose: closeWindow,  // Закрыть без завершения
                    canProceed: canProceedFromSpeechSetup
                )

            case .permissions:
                PermissionsStepView(
                    onNext: { currentStep = .complete },
                    onBack: { currentStep = .speechSetup },
                    onClose: closeWindow,
                    canProceed: canProceedFromPermissions
                )

            case .complete:
                CompleteStepView(onFinish: finishOnboarding)
            }
        }
        .frame(width: 520, height: 576)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
        )
        .onChange(of: currentStep) { _, newStep in
            // Сохраняем текущий шаг при навигации
            SettingsManager.shared.currentOnboardingStep = newStep.rawValue
        }
    }

    private func finishOnboarding() {
        // Проверяем что ВСЕ разрешения выданы
        guard PermissionsManager.shared.hasAllRequired else {
            return
        }

        SettingsManager.shared.hasCompletedOnboarding = true
        SettingsManager.shared.currentOnboardingStep = 0  // Сбросить шаг
        NotificationCenter.default.post(name: .onboardingCompleted, object: nil)
    }

    private func closeWindow() {
        // Просто закрываем окно без завершения onboarding
        if let window = NSApp.windows.first(where: { $0.title == "Настройка Dictum" }) {
            window.close()
        }
    }
}

// MARK: - Welcome Step
struct WelcomeStepView: View {
    let onNext: () -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 24) {
                Spacer()

                // Иконка
                Image(systemName: "mic.fill")
                    .font(.system(size: 56))
                    .foregroundColor(DesignSystem.Colors.accent)

                // Заголовок
                Text("Добро пожаловать в Dictum")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)

                // Подзаголовок
                Text("Умный ввод текста с голосом и ИИ для macOS")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)

                // Преимущества
                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "waveform", text: "Надиктовывайте текст голосом")
                    FeatureRow(icon: "sparkles", text: "Обрабатывайте через ИИ")
                    FeatureRow(icon: "doc.on.clipboard", text: "Вставляйте в любое приложение")
                }
                .padding(.top, 16)

                Spacer()

                // Кнопка
                Button(action: onNext) {
                    HStack {
                        Text("Начать настройку")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.accent)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.bottom, 32)
            }

            // Кнопка закрытия справа вверху
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(20)
            }
        }
    }
}

// MARK: - Speech Setup Step
struct SpeechSetupStepView: View {
    @Binding var deepgramKeyInput: String
    @Binding var showingDeepgramInput: Bool

    let onNext: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let canProceed: Bool

    @ObservedObject private var localASRManager = ParakeetASRProvider.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            OnboardingHeader(step: 1, total: 2, onBack: onBack, onClose: onClose)

            VStack(spacing: 20) {
                // Заголовок
                Text("Выберите способ распознавания речи")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 24)

                // Локальная модель
                LocalModelCard()

                // Deepgram
                DeepgramCard(
                    keyInput: $deepgramKeyInput,
                    showingInput: $showingDeepgramInput
                )

                // Подсказка
                if !canProceed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Нужен хотя бы один способ для диктовки")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding(.horizontal, 32)

            // Footer
            OnboardingFooter(
                canProceed: canProceed,
                onNext: onNext
            )
        }
    }
}

// MARK: - Local Model Card
struct LocalModelCard: View {
    @ObservedObject private var localASRManager = ParakeetASRProvider.shared

    private var statusIcon: String {
        switch localASRManager.modelStatus {
        case .ready: return "checkmark.circle.fill"
        case .downloading, .loading: return "arrow.down.circle"
        case .error: return "exclamationmark.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch localASRManager.modelStatus {
        case .ready: return DesignSystem.Colors.accent
        case .downloading, .loading: return .orange
        case .error: return .red
        default: return .gray
        }
    }

    private var statusText: String {
        switch localASRManager.modelStatus {
        case .notChecked, .checking: return "Проверка..."
        case .notDownloaded: return "Не скачана"
        case .downloading: return "Скачивание..."
        case .loading: return "Загрузка..."
        case .ready: return "Готова к работе"
        case .error(let msg): return "Ошибка: \(msg)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 20))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Локальная модель")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                        Text("(рекомендуется)")
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }

                Spacer()
            }

            // Преимущества
            VStack(alignment: .leading, spacing: 4) {
                Text("• Бесплатно, работает офлайн")
                Text("• Требует ~600 MB места")
                Text("• Apple Silicon (M1/M2/M3/M4)")
            }
            .font(.system(size: 12))
            .foregroundColor(.gray)

            Divider()
                .background(Color.white.opacity(0.1))

            // Статус и кнопка
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .foregroundColor(statusColor)
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                Spacer()

                // Кнопка скачивания
                if case .notDownloaded = localASRManager.modelStatus {
                    Button(action: {
                        Task {
                            await localASRManager.initializeModelsIfNeeded()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12))
                            Text("Скачать бесплатно")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                // Прогресс скачивания
                if case .downloading = localASRManager.modelStatus {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        if localASRManager.totalFilesCount > 0 {
                            Text("\(localASRManager.downloadedFilesCount)/\(localASRManager.totalFilesCount)")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Повторить при ошибке
                if case .error = localASRManager.modelStatus {
                    Button("Повторить") {
                        Task {
                            await localASRManager.initializeModelsIfNeeded()
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Deepgram Card
struct DeepgramCard: View {
    @Binding var keyInput: String
    @Binding var showingInput: Bool

    @ObservedObject private var settings = SettingsManager.shared

    private let accentColor = Color(red: 1.0, green: 0.4, blue: 0.2)  // #ff6633

    private var isConnected: Bool {
        settings.hasDeepgramAPIKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cloud")
                    .font(.system(size: 20))
                    .foregroundColor(accentColor)
                    .frame(width: 28)

                Text("Облачная модель Deepgram")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                Spacer()
            }

            // Преимущества
            VStack(alignment: .leading, spacing: 4) {
                Text("• Лучшее качество распознавания")
                Text("• Требует интернет и API ключ")
                Text("• Бесплатный тариф: 200 минут/месяц")
            }
            .font(.system(size: 12))
            .foregroundColor(.gray)

            Divider()
                .background(Color.white.opacity(0.1))

            // Статус и кнопка
            if showingInput {
                // Поле ввода API ключа
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("API ключ Deepgram", text: $keyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )

                        Button("Сохранить") {
                            if !keyInput.isEmpty {
                                _ = settings.saveDeepgramAPIKey(keyInput)
                                showingInput = false
                                keyInput = ""
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                        .disabled(keyInput.isEmpty)
                    }

                    Button("Получить API ключ на deepgram.com") {
                        if let url = URL(string: "https://console.deepgram.com/signup") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                    .buttonStyle(.plain)
                }
            } else {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: isConnected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isConnected ? accentColor : .gray)
                        Text(isConnected ? "Подключено" : "Не подключено")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    if !isConnected {
                        Button(action: { showingInput = true }) {
                            Text("Подключить Deepgram")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(accentColor)
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Permissions Step
struct PermissionsStepView: View {
    @ObservedObject private var permissions = PermissionsManager.shared

    let onNext: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void
    let canProceed: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            OnboardingHeader(step: 2, total: 2, onBack: onBack, onClose: onClose)

            VStack(spacing: 20) {
                // Заголовок
                Text("Предоставьте необходимые разрешения")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.top, 24)

                VStack(spacing: 12) {
                    // 1. Accessibility — обязательный
                    OnboardingPermissionRow(
                        icon: "hand.raised.fill",
                        title: "Универсальный доступ",
                        subtitle: "Для вставки текста в другие приложения",
                        isGranted: permissions.hasAccessibility,
                        isRequired: true,
                        action: {
                            permissions.request(.accessibility)
                        }
                    )

                    // 2. Microphone — обязательный
                    OnboardingPermissionRow(
                        icon: "mic.fill",
                        title: "Микрофон",
                        subtitle: "Для записи голосовых заметок",
                        isGranted: permissions.hasMicrophone,
                        isRequired: true,
                        action: {
                            permissions.request(.microphone)
                        }
                    )

                    // 3. Screen Recording — обязательный
                    OnboardingPermissionRow(
                        icon: "rectangle.dashed.badge.record",
                        title: "Запись экрана",
                        subtitle: "Для создания скриншотов",
                        isGranted: permissions.hasScreenRecording,
                        isRequired: true,
                        action: {
                            permissions.request(.screenRecording)
                        }
                    )

                    // Предупреждение о перезапуске для Screen Recording
                    if !permissions.hasScreenRecording {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                            Text("После включения «Запись экрана» приложение перезапустится автоматически")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, -4)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 32)

            // Footer
            OnboardingFooter(
                canProceed: canProceed,
                onNext: onNext
            )
        }
        .onAppear {
            // Начать polling для отслеживания изменений разрешений
            permissions.startPolling()
        }
        .onDisappear {
            // Остановить polling при уходе со страницы
            permissions.stopPolling()
        }
    }
}

// MARK: - Onboarding Permission Row
struct OnboardingPermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    let isRequired: Bool
    let action: () -> Void

    private let warningColor = Color(red: 1.0, green: 0.4, blue: 0.2)  // #ff6633

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isGranted ? DesignSystem.Colors.accent : warningColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    if !isRequired {
                        Text("(опционально)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.accent)
                    .font(.system(size: 18))
            } else {
                Button(action: action) {
                    Text("Разрешить")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color(red: 1.0, green: 0.4, blue: 0.2))
                        .contentShape(Rectangle())
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Complete Step
struct CompleteStepView: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Иконка
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundColor(DesignSystem.Colors.accent)

            // Заголовок
            Text("Dictum готов к работе!")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            // Быстрые советы
            VStack(alignment: .leading, spacing: 16) {
                Text("Быстрые советы:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 12) {
                    HotkeyTip(keys: ["⌘", "§"], description: "Открыть/закрыть окно диктовки")
                    HotkeyTip(keys: ["⌘", "K"], description: "История заметок")
                    HotkeyTip(keys: ["⌘", ","], description: "Настройки")
                }
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .cornerRadius(8)

            // Подсказка
            HStack(spacing: 6) {
                Image(systemName: "menubar.arrow.up.rectangle")
                    .foregroundColor(.gray)
                Text("Иконка Dictum появится в строке меню")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.top, 8)

            Spacer()

            // Кнопка
            Button(action: onFinish) {
                HStack {
                    Text("Начать работу")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DesignSystem.Colors.accent)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Helper Views

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.white)
        }
    }
}

struct HotkeyTip: View {
    let keys: [String]
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            Text(description)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

struct OnboardingHeader: View {
    let step: Int
    let total: Int
    let onBack: () -> Void
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Назад")
                }
                .font(.system(size: 13))
                .foregroundColor(.gray)
            }
            .buttonStyle(.plain)

            Spacer()

            // Progress dots
            HStack(spacing: 8) {
                ForEach(1...total, id: \.self) { s in
                    Circle()
                        .fill(s <= step ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            Spacer()

            // Шаг X из Y + кнопка закрытия
            HStack(spacing: 12) {
                Text("Шаг \(step) из \(total)")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)

                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.2))
    }
}

struct OnboardingFooter: View {
    let canProceed: Bool
    let onNext: () -> Void

    var body: some View {
        HStack {
            Spacer()

            Button(action: onNext) {
                HStack {
                    Text("Далее")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(canProceed ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(!canProceed)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
        .background(DesignSystem.Colors.buttonAreaBackground)
    }
}

// MARK: - Visual Effect View
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
