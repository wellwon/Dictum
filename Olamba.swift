
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

    func getHistoryItems(limit: Int = 50, searchQuery: String = "") -> [HistoryItem] {
        if searchQuery.isEmpty {
            return Array(history.prefix(limit))
        } else {
            let filtered = history.filter { $0.text.lowercased().contains(searchQuery.lowercased()) }
            return Array(filtered.prefix(limit))
        }
    }

    func getHistoryCount() -> Int {
        return history.count
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

// MARK: - Hotkey Configuration
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32  // Carbon modifiers

    // Отображаемое имя клавиши
    var keyName: String {
        switch keyCode {
        case 10: return "§"
        case 50: return "`"
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        default:
            if let char = keyCodeToChar(keyCode) {
                return String(char).uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    var modifierNames: String {
        var names: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { names.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { names.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { names.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { names.append("⌃") }
        return names.joined()
    }

    var displayString: String {
        if modifiers == 0 {
            return keyName
        }
        return modifierNames + keyName
    }

    private func keyCodeToChar(_ code: UInt16) -> Character? {
        let keyMap: [UInt16: Character] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: "."
        ]
        return keyMap[code]
    }

    static let defaultToggle = HotkeyConfig(keyCode: 10, modifiers: 0) // § без модификаторов
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
    @Published var toggleHotkey: HotkeyConfig {
        didSet { saveHotkey() }
    }

    init() {
        self.hotkeyEnabled = UserDefaults.standard.object(forKey: "settings.hotkeyEnabled") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "settings.soundEnabled") as? Bool ?? true
        self.backendAPIURL = UserDefaults.standard.string(forKey: "settings.backendAPIURL") ?? "http://localhost:8000"
        self.preferredLanguage = UserDefaults.standard.string(forKey: "settings.preferredLanguage") ?? "ru"

        // Загружаем хоткей
        if let data = UserDefaults.standard.data(forKey: "settings.toggleHotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.toggleHotkey = hotkey
        } else {
            self.toggleHotkey = HotkeyConfig.defaultToggle
        }
    }

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(toggleHotkey) {
            UserDefaults.standard.set(data, forKey: "settings.toggleHotkey")
        }
    }
}

// MARK: - Sound Manager
class SoundManager {
    static let shared = SoundManager()

    // Предзагруженные звуки для мгновенного воспроизведения
    private var openSound: NSSound?
    private var closeSound: NSSound?
    private var copySound: NSSound?

    init() {
        // Загружаем звуки заранее - более басовитые
        openSound = NSSound(named: "Basso")      // Глубокий басовый звук
        closeSound = NSSound(named: "Funk")      // Funkу звук для закрытия
        copySound = NSSound(named: "Hero")       // Героический звук для отправки

        // Устанавливаем громкость
        openSound?.volume = 0.4
        closeSound?.volume = 0.3
        copySound?.volume = 0.5
    }

    func playOpenSound() {
        guard SettingsManager.shared.soundEnabled else { return }
        // Останавливаем если играет, чтобы можно было повторно воспроизвести
        openSound?.stop()
        openSound?.play()
    }

    func playCloseSound() {
        guard SettingsManager.shared.soundEnabled else { return }
        closeSound?.stop()
        closeSound?.play()
    }

    func playCopySound() {
        guard SettingsManager.shared.soundEnabled else { return }
        copySound?.stop()
        copySound?.play()
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
    @State private var textEditorHeight: CGFloat = 40

    // Максимум 30 строк (~600px), минимум 40px
    private let lineHeight: CGFloat = 20
    private let maxLines: Int = 30
    private var maxTextHeight: CGFloat { CGFloat(maxLines) * lineHeight }

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
                    // Поле ввода с динамической высотой
                    ZStack(alignment: .topLeading) {
                        CustomTextEditor(
                            text: $inputText,
                            onSubmit: submitText,
                            onHeightChange: { height in
                                // Ограничиваем высоту до 30 строк
                                textEditorHeight = min(max(40, height), maxTextHeight)
                            }
                        )
                        .font(.system(size: 16, weight: .regular))
                        .frame(height: textEditorHeight)
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
            resetView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetInputView)) { _ in
            resetView()
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

    private func resetView() {
        inputText = ""
        showHistory = false
        searchQuery = ""
        historyItems = []
        textEditorHeight = 40
    }

    private func loadHistory(searchQuery: String) {
        guard let manager = HistoryManager.shared else {
            historyItems = []
            return
        }
        historyItems = manager.getHistoryItems(limit: 50, searchQuery: searchQuery)
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

            // Результаты (10 видимых строк, прокрутка до 50)
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: searchQuery.isEmpty ? "clock" : "magnifyingglass")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(searchQuery.isEmpty ? "История пуста" : "Ничего не найдено")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .frame(height: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            HistoryRowView(item: item, onTap: {
                                onSelect(item)
                            })
                        }
                    }
                }
                .frame(height: min(CGFloat(items.count) * 44, 10 * 44)) // max 10 строк видно
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
    var onHeightChange: ((CGFloat) -> Void)?

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
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
            // Пересчитываем высоту при изменении текста извне
            DispatchQueue.main.async {
                context.coordinator.updateHeight(textView)
            }
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onHeightChange = onHeightChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        var onSubmit: () -> Void
        var onHeightChange: ((CGFloat) -> Void)?

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
            self.onHeightChange = parent.onHeightChange
        }

        func updateHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = max(40, usedRect.height + 10) // +10 для padding

            onHeightChange?(newHeight)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
                self.updateHeight(textView)
            }
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
    static let resetInputView = Notification.Name("resetInputView")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}

// MARK: - Hotkey Recorder View
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: HotkeyConfig
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onHotkeyRecorded = { keyCode, modifiers in
            DispatchQueue.main.async {
                self.hotkey = HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
                self.isRecording = false
            }
        }
        view.onCancel = {
            DispatchQueue.main.async {
                self.isRecording = false
            }
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.isRecording = isRecording
    }
}

class HotkeyRecorderNSView: NSView {
    var isRecording = false
    var onHotkeyRecorded: ((UInt16, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Esc отменяет запись
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        // Конвертируем NSEvent модификаторы в Carbon модификаторы
        var carbonMods: UInt32 = 0
        if event.modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }

        onHotkeyRecorded?(event.keyCode, carbonMods)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled
    @State private var soundEnabled: Bool = SettingsManager.shared.soundEnabled
    @State private var hasAccessibility: Bool = AccessibilityHelper.checkAccessibility()
    @State private var currentHotkey: HotkeyConfig = SettingsManager.shared.toggleHotkey
    @State private var isRecordingHotkey: Bool = false

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
                        VStack(spacing: 16) {
                            // Настраиваемый хоткей
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Открыть/закрыть окно")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                    Text("Нажмите для записи нового хоткея")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                Button(action: {
                                    isRecordingHotkey = true
                                }) {
                                    ZStack {
                                        if isRecordingHotkey {
                                            HotkeyRecorderView(hotkey: $currentHotkey, isRecording: $isRecordingHotkey)
                                                .frame(width: 120, height: 28)
                                        }

                                        Text(isRecordingHotkey ? "Нажмите клавишу..." : currentHotkey.displayString)
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundColor(isRecordingHotkey ? .orange : .white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(isRecordingHotkey ? Color.orange.opacity(0.2) : Color.white.opacity(0.15))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isRecordingHotkey ? Color.orange : Color.clear, lineWidth: 1)
                                            )
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .onChange(of: currentHotkey) { newValue in
                                    SettingsManager.shared.toggleHotkey = newValue
                                    // Уведомляем о необходимости перерегистрации хоткеев
                                    NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                                }
                            }

                            Divider().background(Color.white.opacity(0.1))

                            // Остальные хоткеи (только отображение)
                            HotkeyDisplayRow(action: "Скопировать и закрыть", keys: "Enter")
                            HotkeyDisplayRow(action: "Новая строка", keys: "⇧ + Enter")
                            HotkeyDisplayRow(action: "Закрыть без копирования", keys: "Esc")
                        }
                        .padding(.vertical, 8)
                    }

                    // Кнопка сброса
                    SettingsSection(title: "") {
                        Button(action: {
                            currentHotkey = HotkeyConfig.defaultToggle
                            SettingsManager.shared.toggleHotkey = HotkeyConfig.defaultToggle
                            NotificationCenter.default.post(name: .hotkeyChanged, object: nil)
                        }) {
                            Text("Сбросить хоткей по умолчанию (§)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
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
        .frame(width: 450, height: 550)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.9))
        )
    }
}

// MARK: - Hotkey Display Row
struct HotkeyDisplayRow: View {
    let action: String
    let keys: String

    var body: some View {
        HStack {
            Text(action)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))

            Spacer()

            Text(keys)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .cornerRadius(4)
        }
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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeyDidChange), name: .hotkeyChanged, object: nil)

        // Показываем окно при первом запуске
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showWindow()
        }

        NSLog("✅ Инициализация завершена")
    }

    @objc func hotkeyDidChange() {
        // Перерегистрируем хоткеи с новыми настройками
        unregisterHotKeys()
        setupHotKeys()
        NSLog("🔄 Хоткеи перерегистрированы")
    }

    func unregisterHotKeys() {
        // Убираем старые Carbon хоткеи
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        // Убираем мониторы
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
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

        let hotkey = SettingsManager.shared.toggleHotkey
        NSLog("⌨️ Настроенный хоткей: keyCode=\(hotkey.keyCode), mods=\(hotkey.modifiers)")

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

        // Регистрируем настроенный хоткей с модификаторами (если есть)
        if hotkey.modifiers != 0 {
            registerCarbonHotKey(keyCode: UInt32(hotkey.keyCode), modifiers: hotkey.modifiers, id: 1)
        }

        // Также регистрируем дефолтные комбинации для удобства
        registerCarbonHotKey(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(cmdKey), id: 2)
        registerCarbonHotKey(keyCode: UInt32(kVK_ISO_Section), modifiers: UInt32(cmdKey), id: 3)
        registerCarbonHotKey(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(cmdKey | shiftKey), id: 4)
        registerCarbonHotKey(keyCode: UInt32(kVK_ISO_Section), modifiers: UInt32(cmdKey | shiftKey), id: 5)

        // Локальный монитор (когда окно активно)
        // Перехватываем настроенный хоткей ДО того как символ попадёт в текстовое поле
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventKeyCode = event.keyCode
            let hotkeyKeyCode = SettingsManager.shared.toggleHotkey.keyCode
            let hotkeyMods = SettingsManager.shared.toggleHotkey.modifiers

            // Проверяем модификаторы
            var eventCarbonMods: UInt32 = 0
            if event.modifierFlags.contains(.command) { eventCarbonMods |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift) { eventCarbonMods |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.option) { eventCarbonMods |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { eventCarbonMods |= UInt32(controlKey) }

            // Проверяем совпадение с настроенным хоткеем
            if eventKeyCode == hotkeyKeyCode && eventCarbonMods == hotkeyMods {
                self?.hideWindow()
                return nil
            }

            // Также проверяем § и ` без модификаторов (дефолт)
            if (eventKeyCode == 10 || eventKeyCode == 50) && eventCarbonMods == 0 {
                self?.hideWindow()
                return nil
            }

            return event
        }

        // Глобальный монитор (требует Accessibility)
        if hasAccess {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let eventKeyCode = event.keyCode
                let hotkeyKeyCode = SettingsManager.shared.toggleHotkey.keyCode
                let hotkeyMods = SettingsManager.shared.toggleHotkey.modifiers

                // Проверяем модификаторы
                var eventCarbonMods: UInt32 = 0
                if event.modifierFlags.contains(.command) { eventCarbonMods |= UInt32(cmdKey) }
                if event.modifierFlags.contains(.shift) { eventCarbonMods |= UInt32(shiftKey) }
                if event.modifierFlags.contains(.option) { eventCarbonMods |= UInt32(optionKey) }
                if event.modifierFlags.contains(.control) { eventCarbonMods |= UInt32(controlKey) }

                // Проверяем совпадение с настроенным хоткеем
                if eventKeyCode == hotkeyKeyCode && eventCarbonMods == hotkeyMods {
                    DispatchQueue.main.async {
                        self?.toggleWindow()
                    }
                    return
                }

                // Также проверяем § и ` без модификаторов (дефолт)
                if (eventKeyCode == 10 || eventKeyCode == 50) && eventCarbonMods == 0 {
                    DispatchQueue.main.async {
                        self?.toggleWindow()
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
            hideWindow()
        } else {
            showWindow()
        }
    }

    func hideWindow() {
        guard let window = window else { return }
        SoundManager.shared.playCloseSound()
        window.close()
    }

    @objc func showWindow() {
        guard let window = window else { return }

        // Сбрасываем состояние View (история закрыта, текст пустой)
        NotificationCenter.default.post(name: .resetInputView, object: nil)

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
        // Если настройки уже открыты - закрываем и показываем основное окно
        if let sw = settingsWindow, sw.isVisible {
            sw.close()
            showWindow()
            return
        }

        // Скрываем основное окно
        window?.orderOut(nil)

        if settingsWindow == nil {
            let settingsView = SettingsView()

            let sw = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            sw.title = "Настройки Olamba"
            sw.titlebarAppearsTransparent = true
            sw.titleVisibility = .hidden
            sw.backgroundColor = .clear
            sw.isOpaque = false
            sw.delegate = self

            let hostingView = NSHostingView(rootView: settingsView)
            hostingView.wantsLayer = true
            hostingView.layer?.cornerRadius = 12
            hostingView.layer?.masksToBounds = true
            sw.contentView = hostingView

            settingsWindow = sw
        }

        // Позиционируем настройки на том же экране, где был курсор
        if let sw = settingsWindow {
            let mouseLocation = NSEvent.mouseLocation
            var targetScreen: NSScreen? = nil

            for screen in NSScreen.screens {
                if screen.frame.contains(mouseLocation) {
                    targetScreen = screen
                    break
                }
            }

            let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first
            if let screen = screen {
                let screenFrame = screen.visibleFrame
                let windowFrame = sw.frame
                let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
                let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) / 2
                sw.setFrameOrigin(NSPoint(x: x, y: y))
            }

            NSApp.activate(ignoringOtherApps: true)
            sw.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        // Если закрылись настройки - показываем основное окно
        if let closedWindow = notification.object as? NSWindow,
           closedWindow == settingsWindow {
            showWindow()
        }
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
