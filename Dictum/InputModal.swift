//
//  InputModal.swift
//  Dictum
//
//  Главное окно ввода: InputModalView и связанные компоненты
//

import SwiftUI
import AppKit

// MARK: - Height Preference Key
struct ViewHeightPreferenceKey: PreferenceKey {
    nonisolated(unsafe) static var defaultValue: CGFloat = 150
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Input Modal View
struct InputModalView: View {
    @StateObject private var audioManager = AudioRecordingManager()  // Deepgram
    @ObservedObject private var localASRManager = ParakeetASRProvider.shared   // Локальная модель Parakeet v3
    @ObservedObject private var settings = SettingsManager.shared

    // Computed properties для текущего ASR провайдера
    private var isRecording: Bool {
        settings.asrProviderType == .local ? localASRManager.isRecording : audioManager.isRecording
    }

    private var audioLevel: Float {
        settings.asrProviderType == .local ? localASRManager.audioLevel : audioManager.audioLevel
    }

    private var interimText: String {
        settings.asrProviderType == .local ? localASRManager.interimText : audioManager.interimText
    }

    private var transcriptionResult: String? {
        settings.asrProviderType == .local ? localASRManager.transcriptionResult : audioManager.transcriptionResult
    }

    private var asrErrorMessage: String? {
        settings.asrProviderType == .local ? localASRManager.errorMessage : audioManager.errorMessage
    }
    @State private var inputText: String = ""
    @State private var textEditorHeight: CGFloat = 40
    @State private var isProcessingAI: Bool = false
    // FIX: Флаг для скрытия текстового поля ДО старта записи (устраняет визуальный "прыжок")
    @State private var pendingAudioStart: Bool = false
    @State private var currentProcessingPrompt: CustomPrompt? = nil
    @State private var showASRErrorAlert: Bool = false
    // Состояние: запись остановлена хоткеем (для 3-фазной логики)
    @State private var recordingStoppedByHotkey: Bool = false
    // Alert при отсутствии API ключа для AI функций
    @State private var showAPIKeyAlert: Bool = false
    @StateObject private var geminiService = GeminiService()
    @ObservedObject private var promptsManager = PromptsManager.shared
    @ObservedObject private var snippetsManager = SnippetsManager.shared

    @State private var showAddSnippetSheet: Bool = false // Sheet для добавления сниппета
    @State private var showAddPromptSheet: Bool = false  // Sheet для добавления промпта
    @State private var editingPrompt: CustomPrompt? = nil  // Редактируемый промпт
    @State private var editingSnippet: Snippet? = nil  // Редактируемый сниппет
    @State private var isToggling: Bool = false  // Guard для debouncing toggle записи
    @State private var lastSentHeight: CGFloat = 150  // Последняя отправленная высота (для debounce)

    // Максимум 30 строк (~600px), минимум 40px — потом скролл
    private let lineHeight: CGFloat = 20
    private let maxLines: Int = 30
    // Высота окна в режиме записи (компактная)
    private let recordingModeHeight: CGFloat = 70

    // Computed property для проверки возможности отправки
    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRecording
    }
    private var maxTextHeight: CGFloat { CGFloat(maxLines) * lineHeight }

    // Оверлей записи — отдельный computed property для упрощения body
    @ViewBuilder
    private var recordingOverlay: some View {
        if isRecording {
            VoiceOverlayView(audioLevel: audioLevel)
                .frame(maxHeight: 70)  // Ограничиваем высоту оверлея
                .clipped()  // Обрезаем если выходит за пределы
                .background(Color(red: 24/255, green: 24/255, blue: 26/255))  // #18181a
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24))
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
                // ВЕРХНЯЯ ЧАСТЬ: Ввод + Оверлеи
                VStack(spacing: 0) {
                // Поле ввода с динамической высотой
                ZStack(alignment: .topLeading) {
                    CustomTextEditor(
                        text: $inputText,
                        // Всегда вставлять текст при Enter
                        onSubmit: { submitImmediate(skipAutoPaste: false) },
                        onHeightChange: { height in
                            // Ограничиваем высоту до 30 строк
                            textEditorHeight = min(max(40, height), maxTextHeight)
                        },
                        highlightForeignWords: settings.highlightForeignWords
                    )
                    .font(.system(size: 16, weight: .regular))
                    // Сброс высоты к компактной при записи
                    .frame(height: (isRecording || pendingAudioStart) ? recordingModeHeight : textEditorHeight)
                    .padding(.leading, 20)
                    .padding(.trailing, 50)  // Увеличено для иконки "Улучшить"
                    .padding(.top, 18)
                    .padding(.bottom, 18)  // Увеличено чтобы текст не перекрывался футером
                    .background(Color.clear)
                    // FIX: Скрываем текст если идёт запись ИЛИ ожидаем старт записи
                    .opacity((isRecording || pendingAudioStart) ? 0 : 1)

                    // Placeholder или статус модели
                    if inputText.isEmpty && !isRecording && !pendingAudioStart {
                        Group {
                            if settings.asrProviderType == .local {
                                // Для локальной модели — показываем статус с анимацией
                                ModelStatusView(status: localASRManager.modelStatus)
                            } else {
                                // Для Deepgram — обычный placeholder
                                Text("Введите текст...")
                                    .foregroundColor(Color.white.opacity(0.45))
                            }
                        }
                        .font(.system(size: 16, weight: .regular, design: .default))
                        .padding(.leading, 28)
                        .padding(.top, 18)
                        .allowsHitTesting(settings.asrProviderType == .local && localASRManager.modelStatus == .notDownloaded)
                    }

                    // Live-transcription во время записи
                    if isRecording && !interimText.isEmpty {
                        Text(interimText)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.7))
                            .padding(.leading, 28)
                            .padding(.trailing, 20)
                            .padding(.top, 18)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }

                    // Иконка "Улучшить через ИИ" - появляется когда есть текст и не идёт запись
                    if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isRecording {
                        Button(action: {
                            Task {
                                await enhanceText()
                            }
                        }) {
                            Image(systemName: isProcessingAI ? "rays" : "sparkles")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                                .rotationEffect(.degrees(isProcessingAI ? 360 : 0))
                                .animation(
                                    isProcessingAI
                                        ? Animation.linear(duration: 1).repeatForever(autoreverses: false)
                                        : .default,
                                    value: isProcessingAI
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isProcessingAI)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.top, 16)
                        .padding(.trailing, 16)
                        .help(isProcessingAI ? "Обработка..." : "Улучшить через ИИ")
                    }
                }
                .background(
                    Color(red: 24/255, green: 24/255, blue: 26/255)  // #18181a
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 24))
                )
                .overlay(recordingOverlay)

            }

            // НИЖНЯЯ ЧАСТЬ: Футер (2 строки)
            VStack(spacing: 0) {
                // ROW 1: Быстрый доступ (AI промпты слева + Сниппеты справа)
                if settings.aiEnabled || !snippetsManager.snippets.isEmpty {
                    UnifiedQuickAccessRow(
                        promptsManager: promptsManager,
                        snippetsManager: snippetsManager,
                        inputText: $inputText,
                        onProcessWithGemini: { prompt in
                            Task {
                                await processWithGemini(prompt: prompt)
                            }
                        },
                        currentProcessingPrompt: currentProcessingPrompt,
                        editingPrompt: $editingPrompt,
                        editingSnippet: $editingSnippet
                    )

                    // Разделитель между ROW 1 и ROW 2
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.1), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }

                // ROW 2: Основные действия
                HStack {
                    HStack(spacing: 12) {
                        // Кнопка Голос
                        Button(action: {
                            NSLog("🔘 Нажата кнопка записи, isRecording=\(isRecording), provider=\(settings.asrProviderType)")
                            Task {
                                if isRecording {
                                    NSLog("⏹️ Останавливаем запись...")
                                    await stopASR()
                                } else {
                                    // Проверить возможность записи
                                    if !canStartASR() {
                                        NSLog("❌ canStartASR() вернул false, provider=\(settings.asrProviderType), modelStatus=\(localASRManager.modelStatus)")
                                        if settings.asrProviderType == .local {
                                            // canStartASR() вернул false = модель не скачана или ошибка
                                            switch localASRManager.modelStatus {
                                            case .downloading:
                                                setASRError("Модель скачивается...")
                                            case .error(let msg):
                                                setASRError("Ошибка модели: \(msg)")
                                            default:
                                                setASRError("Модель не скачана. Откройте Настройки → Голос")
                                            }
                                        } else {
                                            setASRError("API ключ не найден. Откройте Настройки (Cmd+,)")
                                        }
                                        return
                                    }
                                    NSLog("▶️ Запускаем запись...")
                                    // Передаём существующий текст для режима дозаписи
                                    await startASR(existingText: inputText)
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                if isRecording {
                                    Image(systemName: "stop.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(nsColor: .systemRed))
                                } else {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 14))
                                }

                                Text(isRecording ? "Stop" : "Запись")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(isRecording ? Color(nsColor: .systemRed).opacity(0.15) : Color.clear)
                            .foregroundColor(isRecording ? Color(nsColor: .systemRed) : Color.white.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider()
                            .frame(height: 16)
                            .background(Color.white.opacity(0.2))

                        // Кнопка История (открывает модалку истории)
                        Button(action: {
                            NotificationCenter.default.post(name: .toggleHistoryModal, object: nil)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                Text("История")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.clear)
                            .foregroundColor(Color.white.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Divider()
                            .frame(height: 16)
                            .background(Color.white.opacity(0.2))

                        // Кнопка Заметки (открывает модалку заметок)
                        Button(action: {
                            NotificationCenter.default.post(name: .toggleNotesModal, object: nil)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "note.text")
                                Text("Заметки")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.clear)
                            .foregroundColor(Color.white.opacity(0.8))
                            .cornerRadius(6)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()

                    // Кнопка режима Текст/Аудио — только иконки
                    Button(action: {
                        // Если переключаемся с Аудио на Текст И идёт запись - остановить
                        if settings.audioModeEnabled && isRecording {
                            Task {
                                await stopASR()
                            }
                        }
                        settings.audioModeEnabled.toggle()
                    }) {
                        Image(systemName: settings.audioModeEnabled ? "mic.fill" : "text.cursor")
                            .font(.system(size: 14))
                            .frame(width: 28, height: 28)
                            .background(settings.audioModeEnabled
                                ? DesignSystem.Colors.accent.opacity(0.2)
                                : Color.white.opacity(0.1))
                            .foregroundColor(settings.audioModeEnabled
                                ? DesignSystem.Colors.accent
                                : Color.white.opacity(0.8))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(settings.audioModeEnabled ? "Режим: Аудио (нажмите для Текст)" : "Режим: Текст (нажмите для Аудио)")

                    // Кнопка Настройки
                    Button(action: {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(Color.white.opacity(0.8))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Настройки")

                    // Кнопка Отправить (активная) - зелёный #19af87
                    // Всегда вставлять текст при нажатии OK
                    Button(action: { submitImmediate(skipAutoPaste: false) }) {
                        HStack(spacing: 6) {
                            Text("Отправить")
                                .font(.system(size: 12, weight: .medium))
                            Text("↵")
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.15))
                                .cornerRadius(4)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(!canSubmit
                            ? Color.white.opacity(0.1)
                            : DesignSystem.Colors.accent)  // #19af87
                        .foregroundColor(!canSubmit
                            ? Color.white.opacity(0.5)
                            : .white)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(DesignSystem.Colors.buttonAreaBackground)
        }
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 26))  // macOS Tahoe: 26pt
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
        )
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)  // Позволяет VStack уменьшаться по высоте
        // Отслеживание высоты контента для адаптивного окна
        .background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: ViewHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(ViewHeightPreferenceKey.self) { height in
            // Отправляем уведомление только если высота значительно изменилась (>5px)
            if abs(height - lastSentHeight) > 5 {
                lastSentHeight = height
                NotificationCenter.default.post(
                    name: .inputModalHeightChanged,
                    object: nil,
                    userInfo: ["height": height]
                )
            }
        }
        .onAppear {
            // FIX: Устанавливаем pendingAudioStart СИНХРОННО до resetView
            // Это скрывает текстовое поле мгновенно, до async запуска записи
            if settings.audioModeEnabled && canStartASR() {
                pendingAudioStart = true
            }

            resetView()

            // Мгновенный автозапуск записи в режиме Аудио (без задержки!)
            if settings.audioModeEnabled && canStartASR() && !isRecording {
                Task {
                    await startASR(existingText: "")
                    // Сбрасываем pendingAudioStart когда запись началась
                    await MainActor.run { pendingAudioStart = false }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetInputView)) { _ in
            // FIX: Устанавливаем pendingAudioStart СИНХРОННО до resetView
            if settings.audioModeEnabled && canStartASR() {
                pendingAudioStart = true
            }

            resetView()

            // Автозапуск записи при переоткрытии в audio mode
            if settings.audioModeEnabled && canStartASR() && !isRecording {
                Task {
                    await startASR(existingText: "")
                    // Сбрасываем pendingAudioStart когда запись началась
                    await MainActor.run { pendingAudioStart = false }
                }
            }
        }
        .onChange(of: settings.audioModeEnabled) { _, isAudioMode in
            // При включении режима Аудио - запустить запись
            if isAudioMode && !isRecording && canStartASR() {
                Task {
                    await startASR(existingText: inputText)
                }
            }
        }
        .onChange(of: audioManager.transcriptionResult) { _, newValue in
            if let transcription = newValue {
                // Режим дозаписи: добавляем через пробел
                if audioManager.appendMode && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = inputText.trimmingCharacters(in: .whitespacesAndNewlines) + " " + transcription
                } else {
                    inputText = transcription
                }
                audioManager.transcriptionResult = nil
            }
        }
        .onChange(of: localASRManager.transcriptionResult) { _, newValue in
            if let transcription = newValue {
                // У локальной модели нет appendMode, всегда заменяем или добавляем к существующему
                if !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = inputText.trimmingCharacters(in: .whitespacesAndNewlines) + " " + transcription
                } else {
                    inputText = transcription
                }
                localASRManager.transcriptionResult = nil
            }
        }
        .alert("Ошибка", isPresented: $showASRErrorAlert) {
            Button("OK") {
                showASRErrorAlert = false
                clearASRError()
            }
        } message: {
            Text(asrErrorMessage ?? "")
        }
        .onChange(of: asrErrorMessage) { _, error in
            showASRErrorAlert = error != nil
        }
        // Alert при отсутствии Gemini API ключа
        .alert("Требуется Gemini API ключ", isPresented: $showAPIKeyAlert) {
            Button("Открыть настройки") {
                NotificationCenter.default.post(name: .openSettings, object: nil)
                NotificationCenter.default.post(name: .openSettingsToAI, object: nil)
            }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Для использования AI функций необходимо добавить ключ в разделе Настройки → AI")
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkAndSubmit)) { _ in
            if settings.audioModeEnabled {
                // Режим аудио: 3-фазная логика хоткея
                if isRecording {
                    // Фаза 1→2: Остановить запись, НЕ закрывать модалку
                    Task {
                        await stopASR()
                        recordingStoppedByHotkey = true
                    }
                    SoundManager.shared.playStopSound()
                } else {
                    // Фаза 2→3: Запись уже остановлена → закрыть без вставки
                    SoundManager.shared.playCloseSound()
                    NSApp.keyWindow?.close()
                }
            } else {
                // Текстовый режим: оригинальная логика
                let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedText.isEmpty {
                    submitImmediate()
                } else {
                    SoundManager.shared.playCloseSound()
                    NSApp.keyWindow?.close()
                }
            }
        }
        // Sheet для редактирования промпта (из UnifiedQuickAccessRow)
        .sheet(item: $editingPrompt) { prompt in
            PromptEditView(
                prompt: prompt,
                onSave: { updatedPrompt in
                    promptsManager.updatePrompt(updatedPrompt)
                    editingPrompt = nil
                },
                onCancel: {
                    editingPrompt = nil
                }
            )
        }
        // Sheet для редактирования сниппета (из UnifiedQuickAccessRow)
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditView(
                snippet: snippet,
                onSave: { updatedSnippet in
                    snippetsManager.updateSnippet(updatedSnippet)
                    editingSnippet = nil
                },
                onCancel: {
                    editingSnippet = nil
                }
            )
        }
        // Sheet для добавления сниппета (из SlidingSnippetPanel)
        .sheet(isPresented: $showAddSnippetSheet) {
            SnippetAddView(
                onSave: { newSnippet in
                    snippetsManager.addSnippet(newSnippet)
                    showAddSnippetSheet = false
                },
                onCancel: {
                    showAddSnippetSheet = false
                }
            )
        }
        // Sheet для добавления промпта (из SlidingPromptPanel)
        .sheet(isPresented: $showAddPromptSheet) {
            PromptAddView(
                onSave: { newPrompt in
                    promptsManager.addPrompt(newPrompt)
                    showAddPromptSheet = false
                },
                onCancel: {
                    showAddPromptSheet = false
                }
            )
        }
        // Получение выбранного элемента из модалки истории
        .onReceive(NotificationCenter.default.publisher(for: .historyItemSelected)) { notification in
            if let item = notification.object as? HistoryItem {
                textEditorHeight = 40  // Сброс высоты
                inputText = item.text
            }
        }
        // Обработка выбора промпта из модального окна списка промптов
        .onReceive(NotificationCenter.default.publisher(for: .promptSelected)) { notification in
            if let prompt = notification.object as? CustomPrompt {
                Task {
                    await processWithGemini(prompt: prompt)
                }
            }
        }
        // Toggle записи по хоткею § или ` (без модификаторов)
        .onReceive(NotificationCenter.default.publisher(for: .toggleRecording)) { _ in
            // Guard от быстрых повторных нажатий
            guard !isToggling else { return }
            isToggling = true

            Task {
                if isRecording {
                    await stopASR()
                } else if canStartASR() {
                    await startASR(existingText: inputText)
                }
                // Сбрасываем isToggling ПОСЛЕ завершения операции
                // await MainActor.run гарантирует синхронное выполнение до выхода из Task
                await MainActor.run {
                    isToggling = false
                }
            }
        }
    }

    private func resetView() {
        inputText = ""
        textEditorHeight = 40
        recordingStoppedByHotkey = false
        editingPrompt = nil
        editingSnippet = nil
        // НЕ сбрасываем pendingAudioStart здесь — он управляется в onAppear/onReceive
    }

    private func submitText() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmedText, forType: .string)

        HistoryManager.shared.addNote(trimmedText)

        inputText = ""

        // Закрыть и вставить в предыдущее приложение
        NotificationCenter.default.post(name: .submitAndPaste, object: nil)
    }

    /// Немедленная отправка - работает даже во время записи
    /// skipAutoPaste: если true - только копировать в буфер, не вставлять автоматически (для аудио режима)
    private func submitImmediate(skipAutoPaste: Bool = false) {
        Task {
            // Если идёт запись - остановить и подождать результат
            if isRecording {
                await stopASR()
                // Подождать пока результат придёт
                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            await MainActor.run {
                // Собрать текст: из inputText или из только что полученного результата
                var textToSubmit: String

                if let result = transcriptionResult, !result.isEmpty {
                    // Режим дозаписи (только для Deepgram)
                    if appendMode && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        textToSubmit = inputText.trimmingCharacters(in: .whitespacesAndNewlines) + " " + result
                    } else {
                        textToSubmit = result
                    }
                    clearTranscriptionResult()
                } else {
                    textToSubmit = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                guard !textToSubmit.isEmpty else { return }

                // Копировать в буфер
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(textToSubmit, forType: .string)

                HistoryManager.shared.addNote(textToSubmit)
                inputText = ""

                if skipAutoPaste {
                    // Только копирование - без автовставки (для аудио режима)
                    SoundManager.shared.playCopySound()
                    NSApp.keyWindow?.close()
                } else {
                    // Обычное поведение - копировать и вставить
                    NotificationCenter.default.post(name: .submitAndPaste, object: nil)
                }
            }
        }
    }

    /// Process text with LLM after local ASR (automatic post-processing)
    private func processWithLLMPostASR() async {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate input
        guard !trimmedText.isEmpty else {
            NSLog("⚠️ No text to process with LLM")
            return
        }

        // Check Gemini API key
        guard SettingsManager.shared.hasGeminiKey() else {
            await MainActor.run {
                setASRError("Для LLM-обработки нужен Gemini API ключ. Откройте Настройки → AI")
            }
            return
        }

        await MainActor.run {
            isProcessingAI = true
        }

        NSLog("🤖 Auto-processing with LLM after local ASR...")

        // Собираем полный промпт
        var fullPrompt = settings.llmProcessingPrompt
        if !settings.llmAdditionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fullPrompt += "\n\nДополнительные инструкции:\n" + settings.llmAdditionalInstructions
        }

        do {
            // forAI: false — используем модель из настроек Речи
            let result = try await geminiService.generateContent(prompt: fullPrompt, userText: trimmedText, forAI: false)

            await MainActor.run {
                inputText = result
                isProcessingAI = false
            }

            NSLog("✅ LLM post-processing complete")
        } catch {
            NSLog("❌ LLM processing error: \(error.localizedDescription)")

            await MainActor.run {
                setASRError("Ошибка LLM: \(error.localizedDescription)")
                isProcessingAI = false
            }
        }
    }

    /// Process text with Gemini AI
    private func processWithGemini(prompt customPrompt: CustomPrompt) async {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate input
        guard !trimmedText.isEmpty else {
            NSLog("⚠️ No text to process")
            return
        }

        // Check API key - показать Alert вместо ошибки
        guard SettingsManager.shared.hasGeminiKey() else {
            await MainActor.run {
                showAPIKeyAlert = true
            }
            return
        }

        await MainActor.run {
            isProcessingAI = true
            currentProcessingPrompt = customPrompt
        }

        NSLog("🤖 Processing with Gemini (\(customPrompt.label))...")

        do {
            let result = try await geminiService.generateContent(prompt: customPrompt.prompt, userText: trimmedText)

            await MainActor.run {
                inputText = result
                isProcessingAI = false
                currentProcessingPrompt = nil
            }

            NSLog("✅ Gemini processing complete")
        } catch {
            NSLog("❌ Gemini error: \(error.localizedDescription)")

            await MainActor.run {
                setASRError("Ошибка Gemini: \(error.localizedDescription)")
                isProcessingAI = false
                currentProcessingPrompt = nil
            }
        }
    }

    // MARK: - Enhance Text (улучшение текста через ИИ)

    /// Улучшает текст через ИИ используя системный промпт из настроек
    private func enhanceText() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        guard SettingsManager.shared.hasGeminiKey() else {
            await MainActor.run { showAPIKeyAlert = true }
            return
        }

        await MainActor.run { isProcessingAI = true }

        NSLog("✨ Enhancing text with AI...")

        do {
            let result = try await geminiService.generateContent(
                prompt: "Улучши этот текст",
                userText: text,
                forAI: true,
                systemPrompt: SettingsManager.shared.enhanceSystemPrompt
            )

            await MainActor.run {
                inputText = result
                isProcessingAI = false
            }

            NSLog("✅ Enhance complete")
        } catch {
            NSLog("❌ Enhance error: \(error.localizedDescription)")
            await MainActor.run {
                setASRError("Ошибка AI: \(error.localizedDescription)")
                isProcessingAI = false
            }
        }
    }

    // MARK: - ASR Helper Methods

    /// Проверяет можно ли начать запись (для Deepgram нужен API key, для локальной — модель доступна)
    private func canStartASR() -> Bool {
        if settings.asrProviderType == .local {
            // Разрешаем если:
            // 1. Модель уже загружена в память, ИЛИ
            // 2. Файлы модели есть на диске (будут загружены автоматически в startRecording)
            return localASRManager.isModelLoaded || localASRManager.modelStatus == .ready
        } else {
            return SettingsManager.shared.hasAPIKey()  // Deepgram требует API key
        }
    }

    /// Запускает запись с текущим ASR провайдером
    private func startASR(existingText: String = "") async {
        if settings.asrProviderType == .local {
            await localASRManager.startRecording()
        } else {
            await audioManager.startRecording(existingText: existingText)
        }

        // Уведомляем TextSwitcher о начале записи
        NotificationCenter.default.post(
            name: .recordingStateChanged,
            object: nil,
            userInfo: ["isRecording": true]
        )
    }

    /// Останавливает запись текущего ASR провайдера
    private func stopASR() async {
        if settings.asrProviderType == .local {
            await localASRManager.stopRecordingAndTranscribe()
        } else {
            await audioManager.stopRecordingAndTranscribe(
                language: SettingsManager.shared.preferredLanguage
            )
        }

        // Уведомляем TextSwitcher об окончании записи
        NotificationCenter.default.post(
            name: .recordingStateChanged,
            object: nil,
            userInfo: ["isRecording": false]
        )
    }

    /// Устанавливает ошибку для текущего ASR провайдера
    private func setASRError(_ message: String) {
        if settings.asrProviderType == .local {
            localASRManager.errorMessage = message
        } else {
            audioManager.errorMessage = message
        }
    }

    /// Очищает ошибку текущего ASR провайдера
    private func clearASRError() {
        if settings.asrProviderType == .local {
            localASRManager.errorMessage = nil
        } else {
            audioManager.errorMessage = nil
        }
    }

    /// Очищает результат транскрипции
    private func clearTranscriptionResult() {
        if settings.asrProviderType == .local {
            localASRManager.transcriptionResult = nil
        } else {
            audioManager.transcriptionResult = nil
        }
    }

    /// Режим дозаписи (только для Deepgram, у локальной модели нет)
    private var appendMode: Bool {
        settings.asrProviderType == .local ? false : audioManager.appendMode
    }
}

// MARK: - Model Status View (Simplified)
struct ModelStatusView: View {
    let status: ParakeetModelStatus

    var body: some View {
        Group {
            switch status {
            case .notDownloaded:
                // Кнопка скачивания модели
                Button(action: {
                    Task {
                        await ParakeetASRProvider.shared.initializeModelsIfNeeded()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle")
                        Text("Скачать локальную модель")
                    }
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)

            case .error(let msg):
                Text("Ошибка: \(msg)")
                    .foregroundColor(.red)
                    .lineLimit(1)

            default:
                // Для всех остальных состояний — стандартный placeholder
                // (notChecked, checking, loading, downloading, ready)
                Text("Введите текст...")
                    .foregroundColor(Color.white.opacity(0.45))
            }
        }
        .font(.system(size: 16))
    }
}

// MARK: - Voice Overlay View
struct VoiceOverlayView: View {
    let audioLevel: Float  // 0.0 - 1.0

    private let barCount = 100
    private let recordingColor = Color(red: 254/255, green: 67/255, blue: 70/255) // #fe4346

    // Детерминированный "шум" для органичности (не меняется при ререндере)
    private func randomFactor(for index: Int) -> CGFloat {
        let seed = sin(Double(index) * 12.9898 + 78.233)
        let noise = seed - floor(seed)  // 0.0-1.0
        return 0.9 + CGFloat(noise) * 0.2  // 0.9-1.1 (меньший разброс)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 999)
                    .fill(recordingColor.opacity(opacityForIndex(index)))
                    .frame(width: 3, height: calculateBarHeight(for: index))
                    .animation(.easeInOut(duration: animationDuration(for: index)), value: audioLevel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 10)
    }

    // Пирамидальная высота — центр высокий, края низкие
    private func calculateBarHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let center = CGFloat(barCount) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center // 0.0 (центр) - 1.0 (край)

        // Пирамидальный множитель высоты
        let heightMultiplier: CGFloat
        if distanceFromCenter > 0.9 { // края (1-10, 91-100)
            heightMultiplier = 0.075
        } else if distanceFromCenter > 0.7 { // (11-20, 81-90)
            heightMultiplier = 0.15
        } else if distanceFromCenter > 0.5 { // (21-30, 71-80)
            heightMultiplier = 0.275
        } else if distanceFromCenter > 0.3 { // (31-40, 61-70)
            heightMultiplier = 0.44
        } else if distanceFromCenter > 0.1 { // (41-45, 56-60)
            heightMultiplier = 0.69
        } else { // центр (46-55)
            heightMultiplier = 1.0
        }

        let maxHeight: CGFloat = 36  // Ограничено чтобы не выходить за пределы контейнера 40px
        let animatedHeight = maxHeight * CGFloat(audioLevel) * heightMultiplier * randomFactor(for: index)
        return max(baseHeight, animatedHeight)
    }

    // Прозрачность по зонам — края более прозрачные
    private func opacityForIndex(_ index: Int) -> Double {
        let center = CGFloat(barCount) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center

        if distanceFromCenter > 0.9 { return 0.4 }
        if distanceFromCenter > 0.7 { return 0.6 }
        if distanceFromCenter > 0.5 { return 0.8 }
        return 1.0
    }

    // Разная скорость анимации — плавный переход без резких скачков
    private func animationDuration(for index: Int) -> Double {
        let center = CGFloat(barCount) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center

        if distanceFromCenter > 0.9 { return 0.5 }
        if distanceFromCenter > 0.7 { return 0.45 }
        if distanceFromCenter > 0.5 { return 0.4 }
        return 0.35 // центр и около — одинаковая скорость (без дыр)
    }
}

// MARK: - No Fade Button Style
struct NoFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Loading Language Button
struct LoadingLanguageButton: View {
    let label: String
    let tooltip: String
    let isLoading: Bool
    let action: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSystem: Bool = false

    // Trail configuration (как в React референсе)
    private let trailLayers = 14
    private let segmentLength: CGFloat = 0.12
    private let delayStep: CGFloat = 0.04
    private let cycleDuration: Double = 2.0

    var body: some View {
        Button(action: action) {
            // Text with background
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isLoading ? DesignSystem.Colors.accent : .white.opacity(0.8))
                .padding(.horizontal, 6)
                .frame(height: 24)
                .frame(minWidth: 28)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(isLoading ? 0.05 : 0.1))

                        // Полупрозрачная рамка-"колея" при загрузке
                        if isLoading {
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(DesignSystem.Colors.accent.opacity(0.2), lineWidth: 1)
                        }
                    }
                )
                .shadow(
                    color: isLoading ? DesignSystem.Colors.accent.opacity(0.3) : .clear,
                    radius: 8
                )
                // Animated fade trail (14 слоёв с затуханием) — overlay адаптируется к размеру текста
                .overlay {
                    if isLoading {
                        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
                            let elapsed = timeline.date.timeIntervalSinceReferenceDate
                            let progress = CGFloat(elapsed.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration)

                            Canvas { context, size in
                                let rect = CGRect(origin: .zero, size: size)
                                let path = RoundedRectangle(cornerRadius: 4).path(in: rect.insetBy(dx: 1, dy: 1))

                                // Draw layers back to front (хвост → голова)
                                for i in (0..<trailLayers).reversed() {
                                    let delay = CGFloat(i) * delayStep
                                    var start = progress - delay
                                    if start < 0 { start += 1.0 }
                                    let opacity = 1.0 - Double(i) / Double(trailLayers)

                                    // Main segment
                                    let end = min(start + segmentLength, 1.0)
                                    let trimmedPath = path.trimmedPath(from: start, to: end)

                                    // First layer gets glow
                                    if i == 0 {
                                        context.drawLayer { ctx in
                                            ctx.addFilter(.shadow(color: DesignSystem.Colors.accent.opacity(0.8), radius: 4))
                                            ctx.addFilter(.shadow(color: DesignSystem.Colors.accent, radius: 2))
                                            ctx.stroke(
                                                trimmedPath,
                                                with: .color(DesignSystem.Colors.accent),
                                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                            )
                                        }
                                    } else {
                                        context.stroke(
                                            trimmedPath,
                                            with: .color(DesignSystem.Colors.accent.opacity(opacity)),
                                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                        )
                                    }

                                    // Wrap-around (когда сегмент пересекает границу 0/1)
                                    let fullEnd = start + segmentLength
                                    if fullEnd > 1.0 {
                                        let wrapPath = path.trimmedPath(from: 0, to: fullEnd - 1.0)
                                        if i == 0 {
                                            context.drawLayer { ctx in
                                                ctx.addFilter(.shadow(color: DesignSystem.Colors.accent.opacity(0.8), radius: 4))
                                                ctx.stroke(
                                                    wrapPath,
                                                    with: .color(DesignSystem.Colors.accent),
                                                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                                )
                                            }
                                        } else {
                                            context.stroke(
                                                wrapPath,
                                                with: .color(DesignSystem.Colors.accent.opacity(opacity)),
                                                style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
        }
        .buttonStyle(NoFadeButtonStyle())
        .disabled(isLoading)
        .help(tooltip)
        .contextMenu {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Редактировать", systemImage: "pencil")
                }
            }
            if let onDelete = onDelete, !isSystem {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Snippet Button
struct SnippetButton: View {
    let shortcut: String
    let tooltip: String
    let action: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .frame(minWidth: 28)
                .frame(height: 24)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DesignSystem.Colors.accent.opacity(isHovered ? 0.25 : 0.15))
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
        .contextMenu {
            if let onEdit = onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Редактировать", systemImage: "pencil")
                }
            }
            if let onDelete = onDelete {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Unified Quick Access Row (промпты слева, сниппеты справа)
struct UnifiedQuickAccessRow: View {
    @ObservedObject var promptsManager: PromptsManager
    @ObservedObject var snippetsManager: SnippetsManager
    @Binding var inputText: String
    let onProcessWithGemini: (CustomPrompt) -> Void
    let currentProcessingPrompt: CustomPrompt?

    // Для редактирования
    @Binding var editingPrompt: CustomPrompt?
    @Binding var editingSnippet: Snippet?

    // Для подтверждения удаления
    @State private var promptToDelete: CustomPrompt? = nil
    @State private var snippetToDelete: Snippet? = nil

    // Только избранные элементы для быстрого доступа
    private var favoritePrompts: [CustomPrompt] {
        promptsManager.prompts.filter { $0.isFavorite }.sorted { $0.order < $1.order }
    }

    private var favoriteSnippets: [Snippet] {
        snippetsManager.snippets.filter { $0.isFavorite }.sorted { $0.order < $1.order }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Кнопка меню всех промптов (фиксирована)
            Button(action: {
                NotificationCenter.default.post(name: .togglePromptsModal, object: nil)
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(Color.white.opacity(0.6))
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Все промпты (⌘1)")

            // Избранные промпты с горизонтальным скроллом
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(favoritePrompts) { prompt in
                        LoadingLanguageButton(
                            label: prompt.label,
                            tooltip: prompt.description,
                            isLoading: currentProcessingPrompt?.id == prompt.id,
                            action: {
                                onProcessWithGemini(prompt)
                            },
                            onEdit: {
                                editingPrompt = prompt
                            },
                            onDelete: prompt.isSystem ? nil : {
                                promptToDelete = prompt
                            },
                            isSystem: prompt.isSystem
                        )
                    }
                }
            }

            Spacer(minLength: 12)

            // Избранные сниппеты с горизонтальным скроллом
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(favoriteSnippets) { snippet in
                        SnippetButton(
                            shortcut: snippet.shortcut,
                            tooltip: snippet.title,
                            action: {
                                inputText += snippet.content
                            },
                            onEdit: {
                                editingSnippet = snippet
                            },
                            onDelete: {
                                snippetToDelete = snippet
                            }
                        )
                    }
                }
            }

            // Кнопка меню всех сниппетов (фиксирована)
            Button(action: {
                NotificationCenter.default.post(name: .toggleSnippetsModal, object: nil)
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(Color.white.opacity(0.6))
                    .cornerRadius(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Все сниппеты (⌘2)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Alert для удаления промпта
        .alert("Удалить промпт?", isPresented: .init(
            get: { promptToDelete != nil },
            set: { if !$0 { promptToDelete = nil } }
        )) {
            Button("Отмена", role: .cancel) { promptToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let prompt = promptToDelete {
                    promptsManager.deletePrompt(prompt)
                }
                promptToDelete = nil
            }
        } message: {
            Text("Вы уверены? Это действие нельзя отменить")
        }
        // Alert для удаления сниппета
        .alert("Удалить сниппет?", isPresented: .init(
            get: { snippetToDelete != nil },
            set: { if !$0 { snippetToDelete = nil } }
        )) {
            Button("Отмена", role: .cancel) { snippetToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let snippet = snippetToDelete {
                    snippetsManager.deleteSnippet(snippet)
                }
                snippetToDelete = nil
            }
        } message: {
            Text("Вы уверены? Это действие нельзя отменить")
        }
    }
}

// MARK: - FlowLayout (для автоматического переноса кнопок)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (CGSize(width: totalWidth, height: currentY + lineHeight), positions)
    }
}

