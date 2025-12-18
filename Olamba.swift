
import SwiftUI
import AppKit
import Carbon
import AVFoundation

// MARK: - History Manager
class HistoryManager: ObservableObject {
    static var shared: HistoryManager?

    @Published var history: [HistoryItem] = []
    private let maxHistoryItems = 50
    private let historyKey = "olamba-history"

    init() {
        loadHistory()
    }

    func addNote(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let newItem = HistoryItem(text: text)
            self.history.insert(newItem, at: 0)

            if self.history.count > self.maxHistoryItems {
                self.history = Array(self.history.prefix(self.maxHistoryItems))
            }

            self.saveHistory()
        }
    }

    func getHistoryItems(limit: Int = 10, searchQuery: String = "") -> [HistoryItem] {
        let items = searchQuery.isEmpty
            ? Array(history.prefix(limit))
            : history.filter { $0.text.lowercased().contains(searchQuery.lowercased()) }
        return items
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            history = try decoder.decode([HistoryItem].self, from: data)
        } catch {
            print("Error loading history: \(error)")
            history = []
        }
    }

    private func saveHistory() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(history)
            UserDefaults.standard.set(data, forKey: historyKey)
        } catch {
            print("Error saving history: \(error)")
        }
    }
}

struct HistoryItem: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let timestamp: Date
    let charCount: Int
    let wordCount: Int

    init(text: String) {
        self.id = UUID().uuidString
        self.text = text
        self.timestamp = Date()
        self.charCount = text.count
        self.wordCount = text.split(separator: " ").count
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "Только что" }
        if interval < 3600 { return "\(Int(interval / 60)) мин" }
        if interval < 86400 { return "\(Int(interval / 3600)) ч" }
        return "\(Int(interval / 86400)) д"
    }

    static func == (lhs: HistoryItem, rhs: HistoryItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var hotkeyEnabled: Bool {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "settings.hotkeyEnabled") }
    }
    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "settings.soundEnabled") }
    }
    @Published var backendAPIURL: String {
        didSet { UserDefaults.standard.set(backendAPIURL, forKey: "settings.backendAPIURL") }
    }
    @Published var preferredLanguage: String {
        didSet { UserDefaults.standard.set(preferredLanguage, forKey: "settings.preferredLanguage") }
    }

    init() {
        self.hotkeyEnabled = UserDefaults.standard.object(forKey: "settings.hotkeyEnabled") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "settings.soundEnabled") as? Bool ?? true
        self.backendAPIURL = UserDefaults.standard.string(forKey: "settings.backendAPIURL") ?? "http://localhost:8000"
        self.preferredLanguage = UserDefaults.standard.string(forKey: "settings.preferredLanguage") ?? "ru"
    }
}

// MARK: - Sound Manager
class SoundManager {
    static let shared = SoundManager()

    func playOpenSound() {
        guard SettingsManager.shared.soundEnabled else { return }
        NSSound(named: "Pop")?.play()
    }

    func playCopySound() {
        guard SettingsManager.shared.soundEnabled else { return }
        NSSound(named: "Tink")?.play()
    }
}

// MARK: - Accessibility Helper
class AccessibilityHelper {
    static func checkAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            NSLog("⚠️ Accessibility permissions not granted")
        }
        return trusted
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

// MARK: - Audio Recording Manager
class AudioRecordingManager: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var errorMessage: String?
    @Published var transcriptionResult: String?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    private let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    func startRecording() async {
        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            await MainActor.run {
                errorMessage = "Разрешение на микрофон отклонено. Откройте Системные настройки."
            }
            return
        }

        recordingURL = createTempAudioURL()

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            await MainActor.run {
                isRecording = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "Ошибка записи: \(error.localizedDescription)"
            }
        }
    }

    func stopRecordingAndTranscribe(language: String, context: String) async {
        audioRecorder?.stop()

        await MainActor.run {
            isRecording = false
            isTranscribing = true
        }

        guard let audioURL = recordingURL else {
            await MainActor.run {
                errorMessage = "Файл записи не найден"
                isTranscribing = false
            }
            return
        }

        do {
            let service = TranscriptionService()
            let result = try await service.uploadAudioForTranscription(
                audioURL: audioURL,
                language: language,
                context: context
            )

            await MainActor.run {
                transcriptionResult = result.formatted_text
                isTranscribing = false
            }

            cleanupTempAudio()
        } catch {
            await MainActor.run {
                errorMessage = "Ошибка транскрибации: \(error.localizedDescription)"
                isTranscribing = false
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func createTempAudioURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "olamba_\(UUID().uuidString).m4a"
        return tempDir.appendingPathComponent(fileName)
    }

    private func cleanupTempAudio() {
        guard let url = recordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        recordingURL = nil
    }
}

// MARK: - Transcription Service
class TranscriptionService {
    private var baseURL: String {
        return SettingsManager.shared.backendAPIURL
    }

    func uploadAudioForTranscription(
        audioURL: URL,
        language: String,
        context: String
    ) async throws -> TranscriptionResponse {
        guard !baseURL.isEmpty else {
            throw NSError(domain: "TranscriptionService", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Backend URL не настроен"])
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/transcribe")!)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)",
                        forHTTPHeaderField: "Content-Type")

        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        data.append(try Data(contentsOf: audioURL))
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(language)\r\n".data(using: .utf8)!)
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"context\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(context)\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NSError(domain: "TranscriptionService", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Ошибка сервера"])
        }

        return try JSONDecoder().decode(TranscriptionResponse.self, from: responseData)
    }
}

struct TranscriptionResponse: Codable {
    let raw_text: String
    let formatted_text: String
    let language: String
    let context: String
}

// MARK: - Main View
struct InputModalView: View {
    @StateObject private var audioManager = AudioRecordingManager()
    @State private var inputText: String = ""
    @State private var showHistory: Bool = false
    @State private var searchQuery: String = ""
    @State private var historyItems: [HistoryItem] = []

    var body: some View {
        VStack(spacing: 0) {
            // ВЕРХНЯЯ ЧАСТЬ: Ввод + Оверлеи
            ZStack(alignment: .top) {
                // Оверлей записи голоса
                if audioManager.isRecording || audioManager.isTranscribing {
                    VoiceOverlayView(
                        status: audioManager.isRecording ? "СЛУШАЮ..." : "ТРАНСКРИБИРУЮ..."
                    )
                    .background(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.9))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                    .zIndex(2)
                }

                VStack(spacing: 0) {
                    // Поле ввода
                    ZStack(alignment: .topLeading) {
                        CustomTextEditor(text: $inputText, onSubmit: submitText)
                            .font(.system(size: 16, weight: .regular))
                            .frame(minHeight: 40, maxHeight: 400)
                            .padding(.leading, 20)
                            .padding(.trailing, 20)
                            .padding(.top, 18)
                            .padding(.bottom, 12)
                            .background(Color.clear)

                        if inputText.isEmpty {
                            Text("Введите текст...")
                                .font(.system(size: 16, weight: .regular, design: .default))
                                .foregroundColor(Color.white.opacity(0.45))
                                .padding(.leading, 28)
                                .padding(.top, 18)
                                .allowsHitTesting(false)
                        }
                    }

                    // Список истории (упрощённый)
                    if showHistory {
                        HistoryListView(
                            items: historyItems,
                            searchQuery: $searchQuery,
                            onSelect: { item in
                                inputText = item.text
                                searchQuery = ""
                                showHistory = false
                            },
                            onSearch: { query in
                                loadHistory(searchQuery: query)
                            }
                        )
                    }
                }
            }

            // Разделитель
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.1), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            // НИЖНЯЯ ЧАСТЬ: Футер
            HStack {
                HStack(spacing: 12) {
                    // Кнопка Голос
                    Button(action: {
                        Task {
                            if audioManager.isRecording {
                                await audioManager.stopRecordingAndTranscribe(
                                    language: SettingsManager.shared.preferredLanguage,
                                    context: "general"
                                )
                            } else {
                                await audioManager.startRecording()
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            if audioManager.isRecording {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(nsColor: .systemRed))
                            } else {
                                Image(systemName: "mic")
                                    .font(.system(size: 14))
                            }

                            Text(audioManager.isRecording ? "Stop" : "Голос")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(audioManager.isRecording ? Color(nsColor: .systemRed).opacity(0.15) : Color.clear)
                        .foregroundColor(audioManager.isRecording ? Color(nsColor: .systemRed) : Color.white.opacity(0.8))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider()
                        .frame(height: 16)
                        .background(Color.white.opacity(0.2))

                    // Кнопка История
                    Button(action: {
                        if !showHistory {
                            loadHistory(searchQuery: "")
                        }
                        showHistory.toggle()
                        if !showHistory {
                            searchQuery = ""
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                            Text("История")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(showHistory ? Color.white.opacity(0.15) : Color.clear)
                        .foregroundColor(showHistory ? .white : Color.white.opacity(0.8))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider()
                        .frame(height: 16)
                        .background(Color.white.opacity(0.2))

                    // Кнопка Настройки
                    Button(action: {
                        NotificationCenter.default.post(name: .openSettings, object: nil)
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Настройки")
                }

                Spacer()

                // Кнопка Отправить (активная)
                Button(action: submitText) {
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
                    .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.white.opacity(0.1)
                        : Color(red: 1.0, green: 0.4, blue: 0.2))
                    .foregroundColor(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.white.opacity(0.5)
                        : .white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
        }
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.85))
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.65), radius: 27, x: 0, y: 24)
        .frame(width: 680)
        .onAppear {
            inputText = ""
            showHistory = false
            searchQuery = ""
        }
        .onChange(of: audioManager.transcriptionResult) { newValue in
            if let transcription = newValue {
                inputText = transcription
                audioManager.transcriptionResult = nil
            }
        }
        .alert("Ошибка", isPresented: .constant(audioManager.errorMessage != nil)) {
            Button("OK") { audioManager.errorMessage = nil }
        } message: {
            Text(audioManager.errorMessage ?? "")
        }
    }

    private func loadHistory(searchQuery: String) {
        guard let manager = HistoryManager.shared else {
            historyItems = []
            return
        }
        historyItems = manager.getHistoryItems(limit: 10, searchQuery: searchQuery)
    }

    private func submitText() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(trimmedText, forType: .string)

        HistoryManager.shared?.addNote(trimmedText)
        SoundManager.shared.playCopySound()

        inputText = ""
        NSApp.keyWindow?.close()
    }
}

// MARK: - History List View (отдельный компонент для стабильности)
struct HistoryListView: View {
    let items: [HistoryItem]
    @Binding var searchQuery: String
    let onSelect: (HistoryItem) -> Void
    let onSearch: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.1))

            // Поле поиска
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                TextField("Поиск в истории...", text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .onChange(of: searchQuery) { newValue in
                        onSearch(newValue)
                    }

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        onSearch("")
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))

            Divider().background(Color.white.opacity(0.1))

            // Заголовок
            HStack {
                Text("НЕДАВНИЕ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                if !searchQuery.isEmpty {
                    Text("(\(items.count))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 5)

            // Результаты
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: searchQuery.isEmpty ? "clock" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(searchQuery.isEmpty ? "История пуста" : "Ничего не найдено")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(40)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            HistoryRowView(item: item, onTap: {
                                onSelect(item)
                            })
                        }
                    }
                }
                .frame(maxHeight: 300)
                .padding(.bottom, 8)
            }
        }
        .background(Color.black.opacity(0.2))
    }
}

// MARK: - History Row View
struct HistoryRowView: View {
    let item: HistoryItem
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(isHovered ? .white : .gray)
                .font(.system(size: 14))

            Text(item.text)
                .foregroundColor(.white)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer()

            Text(item.timeAgo)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isHovered ? Color.white.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Subviews
struct VoiceOverlayView: View {
    let status: String
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0..<10, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: 4, height: isAnimating ? CGFloat.random(in: 10...40) : 4)
                        .animation(
                            Animation.easeInOut(duration: 0.4)
                                .repeatForever()
                                .speed(Double.random(in: 0.8...1.5))
                                .delay(Double(index) * 0.05),
                            value: isAnimating
                        )
                }
            }
            .frame(height: 48)
            .onAppear { isAnimating = true }

            Text(status)
                .font(.system(size: 12, weight: .semibold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Custom Text Editor
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.onSubmit = onSubmit
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        var onSubmit: () -> Void

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
            }
        }

        // Перехватываем ввод символов § и ` для хоткея
        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            guard let str = replacementString else { return true }

            // Проверяем § или ` - это хоткеи для закрытия
            if str == "§" || str == "`" {
                NSApp.keyWindow?.close()
                return false
            }

            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // ESC - закрыть окно без сохранения
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                textView.string = ""
                NSApp.keyWindow?.close()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard let event = NSApp.currentEvent else {
                    return false
                }

                // Любой модификатор + Enter = новая строка
                let hasModifier = !event.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty

                if hasModifier {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }

                // Просто Enter - отправить
                onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Visual Effect Background
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 24
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Custom Floating Panel
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Menu Bar Icon Creator
func createMenuBarIcon() -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    let font = NSFont.systemFont(ofSize: 14, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]

    let text = "O"
    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: (size - textSize.width) / 2 - 1,
        y: (size - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)

    let dotSize: CGFloat = 5
    let dotX = size - dotSize - 1
    let dotY = size - dotSize - 2
    let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
    let dotPath = NSBezierPath(ovalIn: dotRect)
    NSColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1.0).setFill()
    dotPath.fill()

    image.unlockFocus()
    image.isTemplate = false
    return image
}

// MARK: - Launch At Login Manager
class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let launchAgentPath: String
    private let bundleIdentifier = "com.olamba.app"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        launchAgentPath = home.appendingPathComponent("Library/LaunchAgents/\(bundleIdentifier).plist").path
    }

    var isEnabled: Bool {
        get { FileManager.default.fileExists(atPath: launchAgentPath) }
        set { newValue ? enableLaunchAtLogin() : disableLaunchAtLogin() }
    }

    private func enableLaunchAtLogin() {
        guard let appPath = Bundle.main.executablePath else { return }

        let plistContent = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>\(bundleIdentifier)</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(appPath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""

        let launchAgentsDir = (launchAgentPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        try? plistContent.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", launchAgentPath]
        try? process.run()
    }

    private func disableLaunchAtLogin() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentPath]
        try? process.run()
        process.waitUntilExit()

        try? FileManager.default.removeItem(atPath: launchAgentPath)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let toggleWindow = Notification.Name("toggleWindow")
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled
    @State private var soundEnabled: Bool = SettingsManager.shared.soundEnabled
    @State private var hasAccessibility: Bool = AccessibilityHelper.checkAccessibility()

    var body: some View {
        VStack(spacing: 0) {
            // Заголовок
            HStack {
                Text("Настройки")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 0) {
                    // Секция: Разрешения
                    if !hasAccessibility {
                        SettingsSection(title: "⚠️ ТРЕБУЮТСЯ РАЗРЕШЕНИЯ") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Для работы глобальных хоткеев нужно разрешение Accessibility")
                                    .font(.system(size: 13))
                                    .foregroundColor(.orange)

                                Button(action: {
                                    AccessibilityHelper.requestAccessibility()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        hasAccessibility = AccessibilityHelper.checkAccessibility()
                                    }
                                }) {
                                    Text("Открыть настройки доступа")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(Color(red: 1.0, green: 0.4, blue: 0.2))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())

                                Text("После включения перезапустите приложение")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    // Секция: Автозапуск
                    SettingsSection(title: "ЗАПУСК") {
                        SettingsRow(
                            title: "Запускать при входе в систему",
                            subtitle: "Olamba будет автоматически запускаться при старте macOS"
                        ) {
                            Toggle("", isOn: $launchAtLogin)
                                .toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.4, blue: 0.2)))
                                .labelsHidden()
                                .onChange(of: launchAtLogin) { newValue in
                                    LaunchAtLoginManager.shared.isEnabled = newValue
                                }
                        }
                    }

                    // Секция: Звуки
                    SettingsSection(title: "ЗВУКИ") {
                        SettingsRow(
                            title: "Звук при появлении окна",
                            subtitle: "Воспроизводить звук при открытии и копировании"
                        ) {
                            Toggle("", isOn: $soundEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.4, blue: 0.2)))
                                .labelsHidden()
                                .onChange(of: soundEnabled) { newValue in
                                    SettingsManager.shared.soundEnabled = newValue
                                }
                        }
                    }

                    // Секция: Горячие клавиши
                    SettingsSection(title: "ГОРЯЧИЕ КЛАВИШИ") {
                        VStack(spacing: 12) {
                            HotkeyRow(action: "Открыть/закрыть окно", keys: ["§", "или", "`"], note: "(в любом месте)")
                            HotkeyRow(action: "Глобальный хоткей", keys: ["⌘", "+", "§"], note: hasAccessibility ? "✓" : "⚠️")
                            HotkeyRow(action: "Скопировать и закрыть", keys: ["Enter"], note: nil)
                            HotkeyRow(action: "Новая строка", keys: ["⇧", "+", "Enter"], note: nil)
                            HotkeyRow(action: "Закрыть без копирования", keys: ["Esc"], note: nil)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            Divider()
                .background(Color.white.opacity(0.1))

            // Информация о версии
            HStack {
                Text("Olamba v1.0")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                Spacer()
                Button("Проверить разрешения") {
                    hasAccessibility = AccessibilityHelper.checkAccessibility()
                }
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 450, height: 500)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.9))
        )
    }
}

// MARK: - Settings Helper Views
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.gray)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 20)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            accessory
        }
        .padding(.vertical, 8)
    }
}

struct HotkeyRow: View {
    let action: String
    let keys: [String]
    let note: String?

    var body: some View {
        HStack {
            Text(action)
                .font(.system(size: 13))
                .foregroundColor(.white)

            Spacer()

            if let note = note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundColor(note.contains("⚠️") ? .orange : .green)
                    .padding(.trailing, 8)
            }

            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    if key == "+" || key == "или" {
                        Text(key)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    } else {
                        Text(key)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var hotKeyRefs: [EventHotKeyRef] = []
    var localEventMonitor: Any?
    var globalEventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("🚀 Olamba запущен")

        // Инициализация менеджеров
        HistoryManager.shared = HistoryManager()
        _ = SettingsManager.shared

        // Menu bar
        setupMenuBar()

        // Хоткеи
        setupHotKeys()

        // Окно
        setupWindow()

        // Notifications
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)

        // Показываем окно при первом запуске
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showWindow()
        }

        NSLog("✅ Инициализация завершена")
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = createMenuBarIcon()
            button.action = #selector(statusBarClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Правый клик - показать меню
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Открыть Olamba", action: #selector(showWindow), keyEquivalent: ""))
            menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ","))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q"))

            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            // Левый клик - toggle окно
            toggleWindow()
        }
    }

    func setupHotKeys() {
        // Проверяем Accessibility
        let hasAccess = AccessibilityHelper.checkAccessibility()
        NSLog("🔐 Accessibility: \(hasAccess)")

        // Carbon API для глобальных хоткеев
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
                appDelegate.toggleWindow()
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        // Регистрируем несколько комбинаций
        registerCarbonHotKey(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(cmdKey), id: 1)
        registerCarbonHotKey(keyCode: UInt32(kVK_ISO_Section), modifiers: UInt32(cmdKey), id: 2)
        registerCarbonHotKey(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(cmdKey | shiftKey), id: 3)
        registerCarbonHotKey(keyCode: UInt32(kVK_ISO_Section), modifiers: UInt32(cmdKey | shiftKey), id: 4)

        // Локальный монитор (когда окно активно) - для § и ` без модификаторов
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 10 || event.keyCode == 50 { // § и `
                if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    // Без модификаторов - закрыть окно
                    self?.toggleWindow()
                    return nil
                }
            }
            return event
        }

        // Глобальный монитор (требует Accessibility)
        if hasAccess {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // § (keyCode 10) или ` (keyCode 50) без модификаторов
                if event.keyCode == 10 || event.keyCode == 50 {
                    if event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                        DispatchQueue.main.async {
                            self?.toggleWindow()
                        }
                    }
                }
            }
            NSLog("✅ Глобальный монитор событий установлен")
        } else {
            NSLog("⚠️ Глобальный монитор недоступен без Accessibility")
        }
    }

    func registerCarbonHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4F4C4142) // "OLAB"
        hotKeyID.id = id

        var eventHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )

        if status == noErr, let ref = eventHotKeyRef {
            hotKeyRefs.append(ref)
            NSLog("✅ Carbon хоткей: id=\(id), code=\(keyCode), mod=\(modifiers)")
        } else {
            NSLog("❌ Ошибка Carbon хоткея: \(status)")
        }
    }

    func setupWindow() {
        let contentView = InputModalView()

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 150),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 24
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView

        self.window = panel
        panel.close()
    }

    func centerWindowOnActiveScreen() {
        guard let window = window else { return }

        let width: CGFloat = 680
        let height: CGFloat = 150

        // Находим экран с курсором мыши
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen: NSScreen? = nil

        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                targetScreen = screen
                break
            }
        }

        // Fallback на главный экран
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first

        if let screen = screen {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - height) / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    @objc func toggleWindow() {
        guard let window = window else { return }

        if window.isVisible {
            window.close()
        } else {
            showWindow()
        }
    }

    @objc func showWindow() {
        guard let window = window else { return }

        // Центрируем на активном экране
        centerWindowOnActiveScreen()

        // Звук
        SoundManager.shared.playOpenSound()

        // Показываем
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        // Фокус на текстовое поле
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let textView = self.findTextView(in: window.contentView) {
                window.makeFirstResponder(textView)
            }
        }
    }

    func findTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }

        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }

        return nil
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            window.title = "Настройки Olamba"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.isOpaque = false
            window.center()

            let hostingView = NSHostingView(rootView: settingsView)
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 12
            hostingView.layer?.masksToBounds = true
            window.contentView = hostingView

            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func quitApp() {
        // Убираем мониторы
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main App
@main
struct OlambaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
