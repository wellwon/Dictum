
import SwiftUI
import AppKit
import Carbon
import AVFoundation
import Security

// MARK: - API Key Manager (UserDefaults, base64 encoded)
class APIKeyManager {
    static let deepgram = APIKeyManager(service: "deepgram")
    static let gemini = APIKeyManager(service: "gemini")

    private let storageKey: String
    private let serviceName: String

    init(service: String) {
        self.serviceName = service
        self.storageKey = "com.olamba.\(service)-api-key"
    }

    func saveAPIKey(_ key: String) -> Bool {
        let encoded = Data(key.utf8).base64EncodedString()
        UserDefaults.standard.set(encoded, forKey: storageKey)
        NSLog("💾 \(serviceName) API key saved")
        return true
    }

    func getAPIKey() -> String? {
        guard let encoded = UserDefaults.standard.string(forKey: storageKey),
              let data = Data(base64Encoded: encoded),
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    @discardableResult
    func deleteAPIKey() -> Bool {
        UserDefaults.standard.removeObject(forKey: storageKey)
        return true
    }
}

// MARK: - Backward Compatibility
class KeychainManager {
    static let shared = APIKeyManager.deepgram
}

class GeminiKeyManager {
    static let shared = APIKeyManager.gemini
}

// MARK: - History Manager
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

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
    @Published var preferredLanguage: String {
        didSet { UserDefaults.standard.set(preferredLanguage, forKey: "settings.preferredLanguage") }
    }
    @Published var maxHistoryItems: Int {
        didSet { UserDefaults.standard.set(maxHistoryItems, forKey: "settings.maxHistoryItems") }
    }
    @Published var toggleHotkey: HotkeyConfig {
        didSet { saveHotkey() }
    }
    @Published var audioModeEnabled: Bool {
        didSet { UserDefaults.standard.set(audioModeEnabled, forKey: "settings.audioModeEnabled") }
    }
    @Published var deepgramModel: String {
        didSet { UserDefaults.standard.set(deepgramModel, forKey: "settings.deepgramModel") }
    }
    @Published var highlightForeignWords: Bool {
        didSet { UserDefaults.standard.set(highlightForeignWords, forKey: "settings.highlightForeignWords") }
    }

    // Screenshot feature
    @Published var screenshotFeatureEnabled: Bool {
        didSet { UserDefaults.standard.set(screenshotFeatureEnabled, forKey: "settings.screenshotFeatureEnabled") }
    }
    @Published var screenshotHotkey: HotkeyConfig {
        didSet { saveScreenshotHotkey() }
    }

    // Gemini API key status
    @Published var hasGeminiAPIKey: Bool = false

    // AI функции включены/выключены
    @Published var aiEnabled: Bool {
        didSet { UserDefaults.standard.set(aiEnabled, forKey: "settings.aiEnabled") }
    }

    // Custom prompts for each language mode
    @Published var promptWB: String {
        didSet { UserDefaults.standard.set(promptWB, forKey: "com.olamba.prompt.wb") }
    }
    @Published var promptRU: String {
        didSet { UserDefaults.standard.set(promptRU, forKey: "com.olamba.prompt.ru") }
    }
    @Published var promptEN: String {
        didSet { UserDefaults.standard.set(promptEN, forKey: "com.olamba.prompt.en") }
    }
    @Published var promptCH: String {
        didSet { UserDefaults.standard.set(promptCH, forKey: "com.olamba.prompt.ch") }
    }

    init() {
        self.hotkeyEnabled = UserDefaults.standard.object(forKey: "settings.hotkeyEnabled") as? Bool ?? true
        self.soundEnabled = UserDefaults.standard.object(forKey: "settings.soundEnabled") as? Bool ?? true
        // По умолчанию "ru" - Nova-3 отлично работает с русским языком
        self.preferredLanguage = UserDefaults.standard.string(forKey: "settings.preferredLanguage") ?? "ru"
        self.maxHistoryItems = UserDefaults.standard.object(forKey: "settings.maxHistoryItems") as? Int ?? 50
        // По умолчанию режим "Текст" (не Аудио)
        self.audioModeEnabled = UserDefaults.standard.bool(forKey: "settings.audioModeEnabled")
        // По умолчанию модель Nova-3 (54% точнее Whisper, поддерживает 40+ языков)
        self.deepgramModel = UserDefaults.standard.string(forKey: "settings.deepgramModel") ?? "nova-3"
        // По умолчанию подсветка иноязычных слов включена
        self.highlightForeignWords = UserDefaults.standard.object(forKey: "settings.highlightForeignWords") as? Bool ?? true

        // Load Gemini API key status
        self.hasGeminiAPIKey = GeminiKeyManager.shared.getAPIKey() != nil

        // AI функции: по умолчанию включены
        if UserDefaults.standard.object(forKey: "settings.aiEnabled") == nil {
            self.aiEnabled = true
        } else {
            self.aiEnabled = UserDefaults.standard.bool(forKey: "settings.aiEnabled")
        }

        // Load prompts with carefully crafted defaults
        self.promptWB = UserDefaults.standard.string(forKey: "com.olamba.prompt.wb") ?? "Перефразируй этот текст на том же языке, сделав его более вежливым и профессиональным. Используй разговорный, но уважительный тон. Исправь все грамматические и пунктуационные ошибки. Текст должен показывать, что мы ценим клиента и хорошо к нему относимся. Сохрани суть сообщения, но сделай его максимально приятным для получателя:"

        self.promptRU = UserDefaults.standard.string(forKey: "com.olamba.prompt.ru") ?? "Переведи следующий текст на русский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель русского языка:"

        self.promptEN = UserDefaults.standard.string(forKey: "com.olamba.prompt.en") ?? "Переведи следующий текст на английский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель английского языка:"

        self.promptCH = UserDefaults.standard.string(forKey: "com.olamba.prompt.ch") ?? "Переведи следующий текст на китайский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель китайского языка:"

        // Загружаем хоткей
        if let data = UserDefaults.standard.data(forKey: "settings.toggleHotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.toggleHotkey = hotkey
        } else {
            self.toggleHotkey = HotkeyConfig.defaultToggle
        }

        // Screenshot feature: по умолчанию включена
        self.screenshotFeatureEnabled = UserDefaults.standard.object(forKey: "settings.screenshotFeatureEnabled") as? Bool ?? true

        // Load screenshot hotkey (default: Cmd+Shift+6)
        if let data = UserDefaults.standard.data(forKey: "settings.screenshotHotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.screenshotHotkey = hotkey
        } else {
            // Key code 22 = "6", Cmd+Shift modifiers
            self.screenshotHotkey = HotkeyConfig(keyCode: 22, modifiers: UInt32(cmdKey | shiftKey))
        }
    }

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(toggleHotkey) {
            UserDefaults.standard.set(data, forKey: "settings.toggleHotkey")
        }
    }

    private func saveScreenshotHotkey() {
        if let data = try? JSONEncoder().encode(screenshotHotkey) {
            UserDefaults.standard.set(data, forKey: "settings.screenshotHotkey")
        }
    }

    // MARK: - API Key Management
    func hasAPIKey() -> Bool {
        return KeychainManager.shared.getAPIKey() != nil
    }

    func saveAPIKey(_ key: String) -> Bool {
        return KeychainManager.shared.saveAPIKey(key)
    }

    func getAPIKey() -> String? {
        return KeychainManager.shared.getAPIKey()
    }

    func getAPIKeyMasked() -> String {
        guard let key = KeychainManager.shared.getAPIKey(), key.count > 8 else {
            return "Не установлен"
        }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }

    // MARK: - Gemini API Key Management
    func hasGeminiKey() -> Bool {
        return GeminiKeyManager.shared.getAPIKey() != nil
    }

    func saveGeminiAPIKey(_ key: String) -> Bool {
        let success = GeminiKeyManager.shared.saveAPIKey(key)
        if success {
            hasGeminiAPIKey = true
        }
        return success
    }

    func getGeminiAPIKeyMasked() -> String {
        guard let key = GeminiKeyManager.shared.getAPIKey(), key.count > 8 else {
            return "Не установлен"
        }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)...\(suffix)"
    }
}

// MARK: - Sound Manager
class SoundManager {
    static let shared = SoundManager()

    // Предзагруженные звуки для мгновенного воспроизведения
    private var openSound: NSSound?
    private var closeSound: NSSound?

    init() {
        // Загружаем кастомные звуки из бандла приложения
        if let openURL = Bundle.main.url(forResource: "open", withExtension: "wav") {
            openSound = NSSound(contentsOf: openURL, byReference: false)
            openSound?.volume = 0.7
        } else {
            NSLog("⚠️ Не найден звук open.wav в бандле")
        }

        if let closeURL = Bundle.main.url(forResource: "close", withExtension: "wav") {
            closeSound = NSSound(contentsOf: closeURL, byReference: false)
            closeSound?.volume = 0.6
        } else {
            NSLog("⚠️ Не найден звук close.wav в бандле")
        }
    }

    func playOpenSound() {
        guard SettingsManager.shared.soundEnabled else { return }
        openSound?.stop()
        openSound?.play()
    }

    func playCloseSound() {
        guard SettingsManager.shared.soundEnabled else { return }
        closeSound?.stop()
        closeSound?.play()
    }

    func playCopySound() {
        // Используем тот же звук что и для закрытия
        playCloseSound()
    }
}

// MARK: - Volume Manager
class VolumeManager {
    static let shared = VolumeManager()
    private var savedVolume: Int?

    func getCurrentVolume() -> Int? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "output volume of (get volume settings)"]
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let volume = Int(output) {
                return volume
            }
        } catch {
            NSLog("❌ Failed to get volume: \(error)")
        }
        return nil
    }

    func setVolume(_ level: Int) {
        let clampedLevel = max(0, min(100, level))
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "set volume output volume \(clampedLevel)"]

        do {
            try process.run()
            NSLog("🔊 Volume set to \(clampedLevel)")
        } catch {
            NSLog("❌ Failed to set volume: \(error)")
        }
    }

    func saveAndReduceVolume(targetVolume: Int = 15) {
        savedVolume = getCurrentVolume()
        if let current = savedVolume {
            NSLog("💾 Saved volume: \(current)")
            if current > targetVolume {
                setVolume(targetVolume)
            }
        }
    }

    func restoreVolume() {
        if let saved = savedVolume {
            setVolume(saved)
            NSLog("🔊 Restored volume to: \(saved)")
            savedVolume = nil
        }
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

// MARK: - Real-time Streaming Audio Manager (WebSocket)
class AudioRecordingManager: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var errorMessage: String?
    @Published var transcriptionResult: String?
    @Published var interimText: String = ""  // Текст в реальном времени
    @Published var appendMode: Bool = false   // Режим дозаписи
    @Published var audioLevel: Float = 0.0    // Уровень громкости 0.0-1.0

    private var audioEngine: AVAudioEngine?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var finalTranscript: String = ""
    private var audioBuffer: [Data] = []      // Буфер для pre-buffering
    private var webSocketConnected: Bool = false

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    deinit {
        urlSession?.invalidateAndCancel()
    }

    func startRecording(existingText: String = "") async {
        // Проверить API ключ
        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            await MainActor.run {
                errorMessage = "API ключ не найден. Откройте Настройки"
            }
            return
        }

        // Проверить микрофон
        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            await MainActor.run {
                errorMessage = "Нет доступа к микрофону"
            }
            return
        }

        // Режим дозаписи - если есть существующий текст
        let isAppend = !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // ВСЕГДА сбрасывать finalTranscript - append логика через inputText в onChange
        finalTranscript = ""
        audioBuffer.removeAll()
        webSocketConnected = false

        await MainActor.run {
            appendMode = isAppend
            interimText = ""
            transcriptionResult = nil
            isRecording = true
            audioLevel = 0.0
        }

        // Save current volume and reduce for recording
        VolumeManager.shared.saveAndReduceVolume(targetVolume: 15)

        // WebSocket URL
        let language = SettingsManager.shared.preferredLanguage
        let model = SettingsManager.shared.deepgramModel
        let wsURL = URL(string: "wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=16000&channels=1&model=\(model)&language=\(language)&interim_results=true&utterance_end_ms=2000&smart_format=true&punctuate=true")!

        var request = URLRequest(url: wsURL)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()

        NSLog("🔌 Подключение к Deepgram WebSocket...")

        // Слушать ответы
        receiveMessages()

        // 1. СНАЧАЛА настроить аудио (до WebSocket для минимизации задержки)
        audioEngine = AVAudioEngine()
        let inputNode = audioEngine!.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Конвертер: входной формат → 16kHz mono Int16
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            await MainActor.run { errorMessage = "Ошибка формата аудио" }
            return
        }

        // Подготовить аудио-движок (preroll для мгновенного старта)
        audioEngine?.prepare()

        // 2. Установить tap с меньшим буфером (100мс вместо 256мс)
        inputNode.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, from: inputFormat, to: outputFormat)
        }

        // 3. Запустить аудио СРАЗУ (данные буферизируются до подключения WebSocket)
        do {
            try audioEngine?.start()
            NSLog("🎤 Аудио запущен (буферизация до подключения WebSocket)")
        } catch {
            await MainActor.run {
                errorMessage = "Ошибка запуска: \(error.localizedDescription)"
                isRecording = false
            }
            return
        }

        // 4. Ждём WebSocket (данные в audioBuffer)
        // WebSocket уже запущен выше, просто ждём didOpen callback
        NSLog("🔌 Ожидание подключения WebSocket...")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        // 1. Рассчитать уровень громкости (RMS) для визуализации
        if let channelData = buffer.floatChannelData {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0.0
            for i in 0..<frameLength {
                let sample = channelData[0][i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(1, frameLength)))
            let level = min(1.0, rms * 8.0)  // Усиление для лучшей визуализации

            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }
        }

        // 2. Конвертировать в 16kHz
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        var hasData = true

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        // 3. Отправить или буферизировать данные
        if error == nil, let channelData = outputBuffer.int16ChannelData {
            let byteCount = Int(outputBuffer.frameLength) * 2
            let data = Data(bytes: channelData[0], count: byteCount)

            // Pre-buffering: буферизируем пока WebSocket не подключен
            if webSocketConnected {
                // Сначала отправить буферизованные данные
                if !audioBuffer.isEmpty {
                    for bufferedData in audioBuffer {
                        webSocket?.send(.data(bufferedData)) { _ in }
                    }
                    audioBuffer.removeAll()
                    NSLog("📤 Отправлено \(audioBuffer.count) буферизованных чанков")
                }
                // Отправить текущие данные
                webSocket?.send(.data(data)) { _ in }
            } else {
                // Буферизируем (макс. 2 секунды = ~20 чанков по 100мс)
                if audioBuffer.count < 20 {
                    audioBuffer.append(data)
                }
            }
        }
    }

    func stopRecordingAndTranscribe(language: String) async {
        // Остановить аудио
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Закрыть WebSocket
        webSocket?.send(.string("{\"type\": \"CloseStream\"}")) { _ in }
        try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms для финальных результатов
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil

        await MainActor.run {
            isRecording = false
            if !finalTranscript.isEmpty {
                transcriptionResult = finalTranscript.trimmingCharacters(in: .whitespaces)
            }
            interimText = ""
        }

        // Restore original volume
        VolumeManager.shared.restoreVolume()

        NSLog("✅ Результат: \(finalTranscript)")
    }

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleResponse(text)
                }
                self.receiveMessages()  // Продолжаем слушать

            case .failure(let error):
                NSLog("❌ WS error: \(error.localizedDescription)")
            }
        }
    }

    private func handleResponse(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String else {
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false

        DispatchQueue.main.async {
            if isFinal && !transcript.isEmpty {
                self.finalTranscript += (self.finalTranscript.isEmpty ? "" : " ") + transcript
                self.interimText = ""
                NSLog("📝 Final: \(transcript)")
            } else if !transcript.isEmpty {
                self.interimText = transcript
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        NSLog("✅ WebSocket подключен")

        // Установить флаг и отправить буферизованные данные
        webSocketConnected = true

        // Отправить все буферизованные чанки
        if !audioBuffer.isEmpty {
            let bufferedCount = audioBuffer.count
            for data in audioBuffer {
                webSocket?.send(.data(data)) { _ in }
            }
            audioBuffer.removeAll()
            NSLog("📤 Отправлено \(bufferedCount) буферизованных чанков аудио")
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        NSLog("🔌 WebSocket закрыт: \(closeCode.rawValue)")
        webSocketConnected = false
    }
}

// MARK: - Deepgram Error
enum DeepgramError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int, String)
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API ключ не найден. Откройте Настройки (Cmd+,) и введите ключ Deepgram."
        case .invalidResponse:
            return "Неверный ответ от сервера"
        case .httpError(let code, let message):
            return "Ошибка HTTP \(code): \(message)"
        case .noTranscript:
            return "Транскрипт не получен"
        }
    }
}

// MARK: - Deepgram Response
struct DeepgramResponse: Codable {
    let metadata: Metadata?
    let results: Results

    struct Metadata: Codable {
        let request_id: String?
        let duration: Double?
    }

    struct Results: Codable {
        let channels: [Channel]
    }

    struct Channel: Codable {
        let alternatives: [Alternative]
    }

    struct Alternative: Codable {
        let transcript: String
        let confidence: Double
    }

    var transcript: String? {
        return results.channels.first?.alternatives.first?.transcript
    }
}

// MARK: - Deepgram Service (REST - более надёжный)
class DeepgramService {
    private let baseURL = "https://api.deepgram.com/v1/listen"

    func transcribe(audioURL: URL, language: String = "ru") async throws -> String {
        // 1. Получить API ключ
        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            throw DeepgramError.noAPIKey
        }

        // 2. Прочитать аудио
        let audioData = try Data(contentsOf: audioURL)
        NSLog("📤 Отправляем: \(audioData.count) байт, язык: \(language)")

        if audioData.count < 1000 {
            throw DeepgramError.noTranscript
        }

        // 3. URL с параметрами (по документации)
        let model = SettingsManager.shared.deepgramModel
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true")
        ]

        // 4. Создать запрос
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 30

        NSLog("📡 Отправляем в Deepgram...")
        let startTime = Date()

        // 5. Отправить
        let (data, response) = try await URLSession.shared.data(for: request)

        let elapsed = Date().timeIntervalSince(startTime)
        NSLog("⏱️ Ответ за \(String(format: "%.2f", elapsed)) сек")

        // 6. Проверить статус
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
            NSLog("❌ HTTP \(httpResponse.statusCode): \(errorMsg)")
            throw DeepgramError.httpError(httpResponse.statusCode, errorMsg)
        }

        // 7. Распарсить
        let deepgramResponse = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        guard let transcript = deepgramResponse.transcript, !transcript.isEmpty else {
            NSLog("⚠️ Пустой транскрипт")
            throw DeepgramError.noTranscript
        }

        NSLog("✅ Результат: \(transcript)")
        return transcript
    }
}

// MARK: - Gemini Error
enum GeminiError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int, String)
    case noContent
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Gemini API ключ не найден. Откройте Настройки"
        case .invalidResponse:
            return "Неверный ответ от Gemini API"
        case .httpError(let code, let message):
            return "Ошибка HTTP \(code): \(message)"
        case .noContent:
            return "Gemini не вернул текст"
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        }
    }
}

// MARK: - Gemini Response
struct GeminiResponse: Codable {
    let candidates: [Candidate]?

    struct Candidate: Codable {
        let content: Content
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case finishReason = "finish_reason"
        }
    }

    struct Content: Codable {
        let parts: [Part]
    }

    struct Part: Codable {
        let text: String
    }

    var generatedText: String? {
        return candidates?.first?.content.parts.first?.text
    }
}

// MARK: - Gemini Service
class GeminiService: ObservableObject {
    private let model = "gemini-2.0-flash-exp"

    func generateContent(prompt: String, userText: String) async throws -> String {
        guard let apiKey = GeminiKeyManager.shared.getAPIKey(), !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        var components = URLComponents(string: baseURL)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            throw GeminiError.invalidResponse
        }

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": "\(prompt)\n\n\(userText)"]]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 500,
                "topP": 0.95
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            throw GeminiError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        NSLog("🤖 Sending to Gemini API...")
        let startTime = Date()

        let (data, response) = try await URLSession.shared.data(for: request)

        let elapsed = Date().timeIntervalSince(startTime)
        NSLog("⏱️ Gemini response in \(String(format: "%.2f", elapsed))s")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
            NSLog("❌ HTTP \(httpResponse.statusCode): \(errorMsg)")
            throw GeminiError.httpError(httpResponse.statusCode, errorMsg)
        }

        let geminiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)

        guard let generatedText = geminiResponse.generatedText, !generatedText.isEmpty else {
            NSLog("⚠️ Empty response from Gemini")
            throw GeminiError.noContent
        }

        NSLog("✅ Gemini result: \(generatedText.prefix(100))...")
        return generatedText
    }
}

// MARK: - Deepgram Management API Error
enum DeepgramManagementError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int, String)
    case noProjectFound
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API ключ не найден. Добавьте ключ в разделе Deepgram"
        case .noProjectFound:
            return "Проект не найден. Проверьте API ключ"
        case .httpError(let code, _):
            if code == 403 {
                return "Ошибка 403: API ключ не имеет прав на Management API.\n\nСоздайте новый ключ с правами Member или Owner в консоли Deepgram:\nconsole.deepgram.com → API Keys → Create New Key"
            }
            return "Ошибка сервера (\(code)). Проверьте API ключ и соединение"
        case .networkError:
            return "Ошибка сети. Проверьте подключение к интернету"
        case .invalidResponse:
            return "Неверный ответ от сервера"
        }
    }
}

// MARK: - Deepgram Management API Models
struct DeepgramProject: Codable {
    let project_id: String
    let name: String
}

struct DeepgramProjectsResponse: Codable {
    let projects: [DeepgramProject]
}

struct DeepgramBalance: Codable {
    let balance_id: String
    let amount: Double      // USD
    let units: String
}

struct DeepgramBalancesResponse: Codable {
    let balances: [DeepgramBalance]
}

struct DeepgramUsageRequest: Codable {
    let request_id: String
    let created: String     // ISO8601 timestamp
    let response: UsageResponse

    struct UsageResponse: Codable {
        let duration_seconds: Double?
        let model_name: String?
        let details: UsageDetails?

        struct UsageDetails: Codable {
            let usd: Double?
        }
    }
}

struct DeepgramUsageResponse: Codable {
    let requests: [DeepgramUsageRequest]
}

// MARK: - Deepgram Management Service
class DeepgramManagementService {
    private let baseURL = "https://api.deepgram.com/v1"

    // GET /v1/projects
    func getProjects(apiKey: String) async throws -> [DeepgramProject] {
        guard !apiKey.isEmpty else {
            throw DeepgramManagementError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/projects")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        NSLog("🔍 Management API Request: GET \(url)")
        NSLog("🔑 API Key (masked): \(String(apiKey.prefix(8)))...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeepgramManagementError.invalidResponse
            }

            NSLog("📡 Response Status: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
                NSLog("❌ Management API Error (\(httpResponse.statusCode)): \(errorMsg)")
                throw DeepgramManagementError.httpError(httpResponse.statusCode, errorMsg)
            }

            let projectsResponse = try JSONDecoder().decode(DeepgramProjectsResponse.self, from: data)
            NSLog("✅ Projects loaded: \(projectsResponse.projects.count)")
            return projectsResponse.projects
        } catch let error as DeepgramManagementError {
            throw error
        } catch {
            NSLog("❌ Network error: \(error.localizedDescription)")
            throw DeepgramManagementError.networkError(error)
        }
    }

    // GET /v1/projects/{project_id}/balances
    func getBalances(apiKey: String, projectId: String) async throws -> [DeepgramBalance] {
        guard !apiKey.isEmpty else {
            throw DeepgramManagementError.noAPIKey
        }

        let url = URL(string: "\(baseURL)/projects/\(projectId)/balances")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeepgramManagementError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
                throw DeepgramManagementError.httpError(httpResponse.statusCode, errorMsg)
            }

            let balancesResponse = try JSONDecoder().decode(DeepgramBalancesResponse.self, from: data)
            return balancesResponse.balances
        } catch let error as DeepgramManagementError {
            throw error
        } catch {
            throw DeepgramManagementError.networkError(error)
        }
    }

    // GET /v1/projects/{project_id}/requests?limit=10
    func getUsageRequests(apiKey: String, projectId: String, limit: Int = 10) async throws -> [DeepgramUsageRequest] {
        guard !apiKey.isEmpty else {
            throw DeepgramManagementError.noAPIKey
        }

        var components = URLComponents(string: "\(baseURL)/projects/\(projectId)/requests")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw DeepgramManagementError.invalidResponse
            }

            if httpResponse.statusCode != 200 {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
                throw DeepgramManagementError.httpError(httpResponse.statusCode, errorMsg)
            }

            let usageResponse = try JSONDecoder().decode(DeepgramUsageResponse.self, from: data)
            return usageResponse.requests
        } catch let error as DeepgramManagementError {
            throw error
        } catch {
            throw DeepgramManagementError.networkError(error)
        }
    }
}

// MARK: - Billing Manager
class BillingManager: ObservableObject {
    @Published var projectId: String?
    @Published var projectName: String?
    @Published var currentBalance: Double = 0.0
    @Published var recentRequests: [DeepgramUsageRequest] = []
    @Published var totalUsage: Double = 0.0
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let service = DeepgramManagementService()

    // Загрузить все данные
    @MainActor
    func loadAllData(apiKey: String) async {
        isLoading = true
        errorMessage = nil

        do {
            // 1. Получить проекты
            let projects = try await service.getProjects(apiKey: apiKey)

            guard let firstProject = projects.first else {
                errorMessage = "Проекты не найдены. Создайте проект на deepgram.com"
                isLoading = false
                return
            }

            projectId = firstProject.project_id
            projectName = firstProject.name

            // 2. Получить балансы
            let balances = try await service.getBalances(apiKey: apiKey, projectId: firstProject.project_id)
            currentBalance = balances.reduce(0.0) { $0 + $1.amount }

            // 3. Получить историю запросов
            recentRequests = try await service.getUsageRequests(apiKey: apiKey, projectId: firstProject.project_id, limit: 10)

            // 4. Вычислить статистику
            calculateStatistics()

            isLoading = false
        } catch let error as DeepgramManagementError {
            errorMessage = error.errorDescription
            isLoading = false
        } catch {
            errorMessage = "Неизвестная ошибка: \(error.localizedDescription)"
            isLoading = false
        }
    }

    // Вычислить общую статистику
    private func calculateStatistics() {
        totalUsage = recentRequests.reduce(0.0) { sum, request in
            sum + (request.response.details?.usd ?? 0.0)
        }
    }

    // Загрузить баланс (wrapper для удобства вызова из UI)
    @MainActor
    func loadBalance() {
        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            errorMessage = "API ключ не найден"
            return
        }

        Task {
            await loadAllData(apiKey: apiKey)
        }
    }
}

// MARK: - Main View
struct InputModalView: View {
    @StateObject private var audioManager = AudioRecordingManager()
    @ObservedObject private var settings = SettingsManager.shared
    @State private var inputText: String = ""
    @State private var showHistory: Bool = false
    @State private var searchQuery: String = ""
    @State private var historyItems: [HistoryItem] = []
    @State private var textEditorHeight: CGFloat = 40
    @State private var isProcessingAI: Bool = false
    @State private var currentProcessingType: PromptType? = nil
    @StateObject private var geminiService = GeminiService()

    enum PromptType: Equatable {
        case wb, ru, en, ch

        func getPrompt(from settings: SettingsManager) -> String {
            switch self {
            case .wb: return settings.promptWB
            case .ru: return settings.promptRU
            case .en: return settings.promptEN
            case .ch: return settings.promptCH
            }
        }

        var label: String {
            switch self {
            case .wb: return "WB"
            case .ru: return "RU"
            case .en: return "EN"
            case .ch: return "CH"
            }
        }

        var tooltip: String {
            switch self {
            case .wb: return "Вежливый Бот"
            case .ru: return "Русский"
            case .en: return "English"
            case .ch: return "中文"
            }
        }
    }

    // Максимум 30 строк (~600px), минимум 40px
    private let lineHeight: CGFloat = 20
    private let maxLines: Int = 30

    // Computed property для проверки возможности отправки
    private var canSubmit: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || audioManager.isRecording
    }
    private var maxTextHeight: CGFloat { CGFloat(maxLines) * lineHeight }

    var body: some View {
        VStack(spacing: 0) {
            // ВЕРХНЯЯ ЧАСТЬ: Ввод + Оверлеи
            ZStack(alignment: .top) {
                // Оверлей записи голоса - amplitude-индикатор
                if audioManager.isRecording {
                    VoiceOverlayView(audioLevel: audioManager.audioLevel)
                    .background(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.95))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
                    .allowsHitTesting(false)  // Пропускать события к TextEditor
                    .zIndex(2)
                }

                VStack(spacing: 0) {
                    // Поле ввода с динамической высотой
                    ZStack(alignment: .topLeading) {
                        CustomTextEditor(
                            text: $inputText,
                            onSubmit: submitImmediate,
                            onHeightChange: { height in
                                // Ограничиваем высоту до 30 строк
                                textEditorHeight = min(max(40, height), maxTextHeight)
                            },
                            highlightForeignWords: settings.highlightForeignWords
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
                    // AI Processing buttons (WB, RU, EN, CH) - только если включено
                    if settings.aiEnabled {
                        HStack(spacing: 6) {
                            ForEach([PromptType.wb, .ru, .en, .ch], id: \.label) { promptType in
                                LoadingLanguageButton(
                                    label: promptType.label,
                                    tooltip: promptType.tooltip,
                                    isLoading: currentProcessingType == promptType
                                ) {
                                    Task {
                                        await processWithGemini(promptType: promptType)
                                    }
                                }
                            }
                        }

                        Divider()
                            .frame(height: 16)
                            .background(Color.white.opacity(0.2))
                    }

                    // Кнопка Голос
                    Button(action: {
                        Task {
                            if audioManager.isRecording {
                                await audioManager.stopRecordingAndTranscribe(
                                    language: SettingsManager.shared.preferredLanguage
                                )
                            } else {
                                // Проверить наличие API ключа перед записью
                                if !SettingsManager.shared.hasAPIKey() {
                                    audioManager.errorMessage = "API ключ не найден. Откройте Настройки (Cmd+,)"
                                    return
                                }
                                // Передаём существующий текст для режима дозаписи
                                await audioManager.startRecording(existingText: inputText)
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
                }

                Spacer()

                // Кнопка режима Текст/Аудио - показывает ДЕЙСТВИЕ (куда переключиться)
                Button(action: {
                    // Если переключаемся с Аудио на Текст И идёт запись - остановить
                    if settings.audioModeEnabled && audioManager.isRecording {
                        Task {
                            await audioManager.stopRecordingAndTranscribe(
                                language: SettingsManager.shared.preferredLanguage
                            )
                        }
                    }
                    settings.audioModeEnabled.toggle()
                }) {
                    HStack(spacing: 4) {
                        // Показываем куда переключиться (инвертировано)
                        Image(systemName: settings.audioModeEnabled ? "text.cursor" : "waveform")
                            .font(.system(size: 12))
                        Text(settings.audioModeEnabled ? "Текст" : "Аудио")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    // Подсветка когда НЕ в этом режиме (т.е. кнопка активна для переключения)
                    .background(!settings.audioModeEnabled
                        ? Color(red: 0.098, green: 0.686, blue: 0.529).opacity(0.2)
                        : Color.white.opacity(0.1))
                    .foregroundColor(!settings.audioModeEnabled
                        ? Color(red: 0.098, green: 0.686, blue: 0.529)
                        : Color.white.opacity(0.8))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .help(settings.audioModeEnabled ? "Переключить на Текст" : "Переключить на Аудио")

                // Кнопка Отправить (активная) - зелёный #19af87
                Button(action: submitImmediate) {
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
                        : Color(red: 0.098, green: 0.686, blue: 0.529))  // #19af87
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

            // Автозапуск записи в режиме Аудио
            if settings.audioModeEnabled && SettingsManager.shared.hasAPIKey() && !audioManager.isRecording {
                Task {
                    // Небольшая задержка чтобы UI успел отрисоваться
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await audioManager.startRecording(existingText: "")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetInputView)) { _ in
            resetView()

            // Автозапуск при сбросе в режиме Аудио
            if settings.audioModeEnabled && SettingsManager.shared.hasAPIKey() && !audioManager.isRecording {
                Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    await audioManager.startRecording(existingText: "")
                }
            }
        }
        .onChange(of: settings.audioModeEnabled) { isAudioMode in
            // При включении режима Аудио - запустить запись
            if isAudioMode && !audioManager.isRecording && SettingsManager.shared.hasAPIKey() {
                Task {
                    await audioManager.startRecording(existingText: inputText)
                }
            }
        }
        .onChange(of: audioManager.transcriptionResult) { newValue in
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
        .alert("Ошибка", isPresented: .constant(audioManager.errorMessage != nil)) {
            Button("OK") { audioManager.errorMessage = nil }
        } message: {
            Text(audioManager.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .checkAndSubmit)) { _ in
            // Закрытие по хоткею: если есть текст или идёт запись - отправить и вставить, иначе просто закрыть
            let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedText.isEmpty || audioManager.isRecording {
                submitImmediate()  // Остановит запись если нужно, отправит и вставит
            } else {
                // Просто закрыть без вставки
                SoundManager.shared.playCloseSound()
                NSApp.keyWindow?.close()
            }
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
        historyItems = HistoryManager.shared.getHistoryItems(limit: 50, searchQuery: searchQuery)
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
    private func submitImmediate() {
        Task {
            // Если идёт запись - остановить и подождать результат
            if audioManager.isRecording {
                await audioManager.stopRecordingAndTranscribe(
                    language: SettingsManager.shared.preferredLanguage
                )
                // Подождать пока результат придёт
                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            await MainActor.run {
                // Собрать текст: из inputText или из только что полученного результата
                var textToSubmit: String

                if let result = audioManager.transcriptionResult, !result.isEmpty {
                    // Режим дозаписи
                    if audioManager.appendMode && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        textToSubmit = inputText.trimmingCharacters(in: .whitespacesAndNewlines) + " " + result
                    } else {
                        textToSubmit = result
                    }
                    audioManager.transcriptionResult = nil
                } else {
                    textToSubmit = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                }

                guard !textToSubmit.isEmpty else { return }

                // Копировать и отправить
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(textToSubmit, forType: .string)

                HistoryManager.shared.addNote(textToSubmit)
                inputText = ""

                NotificationCenter.default.post(name: .submitAndPaste, object: nil)
            }
        }
    }

    /// Process text with Gemini AI
    private func processWithGemini(promptType: PromptType) async {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate input
        guard !trimmedText.isEmpty else {
            NSLog("⚠️ No text to process")
            return
        }

        // Check API key
        guard SettingsManager.shared.hasGeminiKey() else {
            await MainActor.run {
                audioManager.errorMessage = "Gemini API ключ не найден. Откройте Настройки (AI → Добавить ключ)"
            }
            return
        }

        await MainActor.run {
            isProcessingAI = true
            currentProcessingType = promptType
        }

        NSLog("🤖 Processing with Gemini (\(promptType.label))...")

        do {
            let prompt = promptType.getPrompt(from: settings)
            let result = try await geminiService.generateContent(prompt: prompt, userText: trimmedText)

            await MainActor.run {
                inputText = result
                isProcessingAI = false
                currentProcessingType = nil
            }

            NSLog("✅ Gemini processing complete")
        } catch {
            NSLog("❌ Gemini error: \(error.localizedDescription)")

            await MainActor.run {
                audioManager.errorMessage = "Ошибка Gemini: \(error.localizedDescription)"
                isProcessingAI = false
                currentProcessingType = nil
            }
        }
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
    let audioLevel: Float  // 0.0 - 1.0

    // Предварительно сгенерированные случайные факторы (один раз при создании)
    private let randomFactors: [CGFloat] = (0..<10).map { _ in CGFloat.random(in: 0.85...1.15) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<10, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(nsColor: .systemRed))
                    .frame(width: 4, height: calculateBarHeight(for: index))
                    .animation(.easeOut(duration: 0.08), value: audioLevel)
            }
        }
        .frame(height: 40)  // Совпадает с minHeight TextEditor
        .frame(maxWidth: .infinity)
        .padding(.leading, 20)
        .padding(.trailing, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)  // Те же отступы что у TextEditor
    }

    private func calculateBarHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let maxAddition: CGFloat = 32

        // Волновой эффект - центральные полосы выше
        let centerDistance = abs(CGFloat(index) - 4.5) / 4.5
        let centerMultiplier = 1.0 - (centerDistance * 0.4)

        let height = baseHeight + (maxAddition * CGFloat(audioLevel) * centerMultiplier * randomFactors[index])
        return max(baseHeight, min(36, height))
    }
}

// MARK: - Screenshot Notification View
struct ScreenshotNotificationView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Путь скопирован")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Готово к вставке")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.95))
        )
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

// MARK: - Loading Language Button
struct LoadingLanguageButton: View {
    let label: String
    let tooltip: String
    let isLoading: Bool
    let action: () -> Void

    @State private var trimOffset: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Фон кнопки
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isLoading ? Color(red: 0.102, green: 0.686, blue: 0.529) : .white.opacity(0.8))
                    .frame(width: 28, height: 24)
                    .background(
                        ZStack {
                            // Основной фон
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(isLoading ? 0.05 : 0.1))

                            // Полупрозрачная рамка при загрузке (как "колея")
                            if isLoading {
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color(red: 0.102, green: 0.686, blue: 0.529).opacity(0.2), lineWidth: 1)
                            }
                        }
                    )
                    .shadow(
                        color: isLoading ? Color(red: 0.102, green: 0.686, blue: 0.529).opacity(0.3) : .clear,
                        radius: 8
                    )

                // Бегающая точка (индикатор загрузки)
                if isLoading {
                    RoundedRectangle(cornerRadius: 4)
                        .trim(from: trimOffset, to: trimOffset + 0.12)
                        .stroke(
                            Color(red: 0.102, green: 0.686, blue: 0.529),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 28, height: 24)
                        .shadow(color: Color(red: 0.102, green: 0.686, blue: 0.529).opacity(0.8), radius: 4)
                        .shadow(color: Color(red: 0.102, green: 0.686, blue: 0.529), radius: 2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isLoading)
        .help(tooltip)
        .onChange(of: isLoading) { loading in
            if loading {
                trimOffset = 0
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    trimOffset = 1.0
                }
            } else {
                withAnimation(.linear(duration: 0)) {
                    trimOffset = 0
                }
            }
        }
    }
}

// MARK: - Custom Text Editor
enum TextLanguage {
    case cyrillic  // Русский
    case latin     // Английский
    case mixed     // Смешанный, не подсвечиваем
}

struct ForeignWord {
    let range: NSRange
}

struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onHeightChange: ((CGFloat) -> Void)?
    var highlightForeignWords: Bool = true

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
            // Сохраняем видимую область
            let visibleRect = textView.visibleRect
            let shouldPreserveScroll = textView.string.count > 0 && text.count > textView.string.count

            // Флаг что текст заменен извне (для подсветки)
            context.coordinator.textWasReplacedExternally = true

            // Заменяем текст
            textView.string = text

            // Курсор в конец
            let endPosition = (text as NSString).length
            textView.setSelectedRange(NSRange(location: endPosition, length: 0))

            // Блокируем автопрокрутку к курсору - восстанавливаем видимую область
            if shouldPreserveScroll {
                textView.scroll(visibleRect.origin)
            }

            // Пересчитываем высоту и применяем подсветку
            DispatchQueue.main.async {
                context.coordinator.updateHeight(textView)
                context.coordinator.applyForeignWordHighlighting(textView)
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
        private var isApplyingHighlight = false
        var textWasReplacedExternally = false  // Флаг для различения внешней замены текста (Gemini) и обычного ввода

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
            self.onHeightChange = parent.onHeightChange
        }

        // MARK: - Language Detection
        private func detectPrimaryLanguage(_ text: String) -> TextLanguage {
            var cyrillicCount = 0
            var latinCount = 0

            for char in text where char.isLetter {
                if ("а"..."я").contains(char.lowercased()) || ("А"..."Я").contains(char) {
                    cyrillicCount += 1
                } else if ("a"..."z").contains(char.lowercased()) {
                    latinCount += 1
                }
            }

            let total = cyrillicCount + latinCount
            guard total > 0 else { return .mixed }

            let cyrillicRatio = Double(cyrillicCount) / Double(total)

            if cyrillicRatio > 0.55 { return .cyrillic }
            else if cyrillicRatio < 0.45 { return .latin }
            else { return .mixed }
        }

        private func findForeignWords(in text: String, primaryLanguage: TextLanguage) -> [ForeignWord] {
            guard primaryLanguage != .mixed else { return [] }

            guard let regex = try? NSRegularExpression(pattern: "[\\p{L}]+") else { return [] }
            let nsText = text as NSString
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            return matches.compactMap { match in
                let word = nsText.substring(with: match.range)
                return isWordForeign(word, primaryLanguage) ? ForeignWord(range: match.range) : nil
            }
        }

        private func isWordForeign(_ word: String, _ primaryLanguage: TextLanguage) -> Bool {
            let hasCyrillic = word.unicodeScalars.contains { ("а"..."я").contains($0) || ("А"..."Я").contains($0) }
            let hasLatin = word.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }

            if primaryLanguage == .cyrillic {
                return hasLatin && !hasCyrillic
            } else {
                return hasCyrillic && !hasLatin
            }
        }

        // MARK: - Foreign Word Highlighting
        func applyForeignWordHighlighting(_ textView: NSTextView) {
            guard parent.highlightForeignWords else { return }
            guard let textStorage = textView.textStorage else { return }

            isApplyingHighlight = true
            defer { isApplyingHighlight = false }

            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            // Сохраняем курсор
            let selectedRanges = textView.selectedRanges

            // Сброс атрибутов
            textStorage.setAttributes([
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.white
            ], range: fullRange)

            // Определяем язык и подсвечиваем
            let language = detectPrimaryLanguage(text)
            let foreignWords = findForeignWords(in: text, primaryLanguage: language)

            let highlightColor = NSColor(red: 1.0, green: 0.26, blue: 0.27, alpha: 1.0) // #ff4246

            for foreignWord in foreignWords {
                textStorage.addAttribute(.foregroundColor, value: highlightColor, range: foreignWord.range)
            }

            // Восстанавливаем курсор
            if textWasReplacedExternally {
                // Текст был заменен извне (Gemini) - НЕ восстанавливаем старую позицию
                // Курсор уже установлен в конец в updateNSView
                textWasReplacedExternally = false
            } else {
                // Обычная подсветка при вводе - восстанавливаем позицию
                textView.selectedRanges = selectedRanges
            }
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
            guard !isApplyingHighlight else { return }
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
                self.updateHeight(textView)
                self.applyForeignWordHighlighting(textView)
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
    static let screenshotHotkeyChanged = Notification.Name("screenshotHotkeyChanged")
    static let submitAndPaste = Notification.Name("submitAndPaste")
    static let checkAndSubmit = Notification.Name("checkAndSubmit")
    static let disableGlobalHotkeys = Notification.Name("disableGlobalHotkeys")
    static let enableGlobalHotkeys = Notification.Name("enableGlobalHotkeys")
    static let accessibilityStatusChanged = Notification.Name("accessibilityStatusChanged")
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
    var isRecording = false {
        didSet {
            if isRecording {
                // Получить фокус для захвата клавиш
                DispatchQueue.main.async {
                    self.window?.makeFirstResponder(self)
                }
                // Отключить глобальные хоткеи
                NotificationCenter.default.post(name: .disableGlobalHotkeys, object: nil)
            } else {
                // Включить глобальные хоткеи обратно
                NotificationCenter.default.post(name: .enableGlobalHotkeys, object: nil)
            }
        }
    }
    var onHotkeyRecorded: ((UInt16, UInt32) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

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

enum SettingsTab: String, CaseIterable {
    case general = "Основные"
    case hotkeys = "Хоткеи"
    case features = "Фитчи"
    case deepgram = "Deepgram"
    case ai = "AI"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .features: return "camera.fill"
        case .deepgram: return "mic"
        case .ai: return "sparkles"
        }
    }
}

struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .foregroundColor(isSelected ? .white : .gray)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled
    @State private var soundEnabled: Bool = SettingsManager.shared.soundEnabled
    @State private var hasAccessibility: Bool = AccessibilityHelper.checkAccessibility()
    @State private var currentHotkey: HotkeyConfig = SettingsManager.shared.toggleHotkey
    @State private var isRecordingHotkey: Bool = false
    @State private var isRecordingScreenshotHotkey: Bool = false
    @State private var screenshotHotkey: HotkeyConfig = SettingsManager.shared.screenshotHotkey
    @State private var aiEnabled: Bool = SettingsManager.shared.aiEnabled
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        HStack(spacing: 0) {
            // === SIDEBAR (слева) ===
            VStack(alignment: .leading, spacing: 4) {
                Text("НАСТРОЙКИ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }

                Spacer()

                // Версия и проверка разрешений
                VStack(alignment: .leading, spacing: 8) {
                    Button("Проверить разрешения") {
                        hasAccessibility = AccessibilityHelper.checkAccessibility()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .buttonStyle(PlainButtonStyle())

                    Text("Olamba v1.0")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .padding(.horizontal, 12)
            }
            .frame(width: 160)
            .padding(.vertical, 20)
            .background(Color.black.opacity(0.3))

            // Разделитель
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)

            // === CONTENT (справа) ===
            VStack(spacing: 0) {
                // Заголовок таба
                HStack {
                    Image(systemName: selectedTab.icon)
                        .font(.system(size: 16))
                    Text(selectedTab.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider().background(Color.white.opacity(0.1))

                // Контент таба
                ScrollView {
                    tabContent
                        .padding(24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 30/255, green: 30/255, blue: 32/255))
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .general: generalTabContent
        case .hotkeys: hotkeysTabContent
        case .features: featuresTabContent
        case .deepgram: deepgramTabContent
        case .ai: aiTabContent
        }
    }

    // === TAB: ОСНОВНЫЕ ===
    var generalTabContent: some View {
        VStack(spacing: 0) {
            // Секция: Разрешения
            if !hasAccessibility {
                SettingsSection(title: "⚠️ ТРЕБУЮТСЯ РАЗРЕШЕНИЯ") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Настройки системы → Конфиденциальность и безопасность → Универсальный доступ")
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

            // Секция: Подсветка текста
            SettingsSection(title: "ТЕКСТОВЫЙ РЕДАКТОР") {
                SettingsRow(
                    title: "Подсветка иноязычных слов",
                    subtitle: "Выделять слова на другом языке для проверки распознавания"
                ) {
                    Toggle("", isOn: .init(
                        get: { SettingsManager.shared.highlightForeignWords },
                        set: { SettingsManager.shared.highlightForeignWords = $0 }
                    ))
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.4, blue: 0.2)))
                        .labelsHidden()
                }
            }
        }
    }

    // === TAB: ХОТКЕИ ===
    var hotkeysTabContent: some View {
        VStack(spacing: 0) {
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

    // === TAB: ФИТЧИ ===
    var featuresTabContent: some View {
        VStack(spacing: 0) {
            SettingsSection(title: "СКРИНШОТЫ") {
                VStack(spacing: 16) {
                    // Toggle для включения/выключения
                    SettingsRow(
                        title: "Быстрые скриншоты",
                        subtitle: "Глобальный хоткей для создания скриншота с автоматическим копированием пути в буфер обмена"
                    ) {
                        Toggle("", isOn: .init(
                            get: { SettingsManager.shared.screenshotFeatureEnabled },
                            set: { SettingsManager.shared.screenshotFeatureEnabled = $0 }
                        ))
                            .toggleStyle(SwitchToggleStyle(tint: Color(red: 1.0, green: 0.4, blue: 0.2)))
                            .labelsHidden()
                    }

                    // Hotkey recorder (только если фича включена)
                    if SettingsManager.shared.screenshotFeatureEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Горячая клавиша для скриншота")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                Text("Нажмите для записи нового хоткея")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }

                            Spacer()

                            Button(action: {
                                isRecordingScreenshotHotkey = true
                            }) {
                                ZStack {
                                    if isRecordingScreenshotHotkey {
                                        HotkeyRecorderView(
                                            hotkey: $screenshotHotkey,
                                            isRecording: $isRecordingScreenshotHotkey
                                        )
                                        .frame(width: 120, height: 28)
                                    }

                                    Text(isRecordingScreenshotHotkey ? "Нажмите клавишу..." : screenshotHotkey.displayString)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(isRecordingScreenshotHotkey ? .orange : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isRecordingScreenshotHotkey ? Color.orange.opacity(0.2) : Color.white.opacity(0.15))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(isRecordingScreenshotHotkey ? Color.orange : Color.clear, lineWidth: 1)
                                        )
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onChange(of: screenshotHotkey) { newValue in
                                SettingsManager.shared.screenshotHotkey = newValue
                                NotificationCenter.default.post(name: .screenshotHotkeyChanged, object: nil)
                            }
                        }

                        // Описание
                        Text("Скриншоты сохраняются в ~/Library/Screenshots/\nПуть к файлу автоматически копируется в буфер обмена")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // === TAB: DEEPGRAM ===
    var deepgramTabContent: some View {
        VStack(spacing: 0) {
            DeepgramAPISection()
            LanguageSettingsSection()
        }
    }

    // === TAB: AI ===
    var aiTabContent: some View {
        VStack(spacing: 0) {
            AISettingsSection(aiEnabled: $aiEnabled)
            if aiEnabled {
                AIPromptsSection()
            }
        }
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

// MARK: - Deepgram API Section
struct DeepgramAPISection: View {
    @State private var apiKeyInput: String = ""
    @State private var showSaveSuccess: Bool = false
    @State private var hasKey: Bool = SettingsManager.shared.hasAPIKey()
    @StateObject private var billingManager = BillingManager()

    var body: some View {
        SettingsSection(title: "DEEPGRAM API") {
            VStack(alignment: .leading, spacing: 12) {
                // Статус API ключа
                HStack {
                    Image(systemName: hasKey ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundColor(hasKey ? .green : .orange)
                    Text(hasKey ? "API ключ установлен" : "API ключ не установлен")
                        .font(.system(size: 13))
                        .foregroundColor(hasKey ? .green : .orange)

                    if hasKey {
                        Text("(\(SettingsManager.shared.getAPIKeyMasked()))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }

                // Баланс (если ключ есть)
                if hasKey {
                    HStack {
                        Text("Баланс:")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        if billingManager.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else if let error = billingManager.errorMessage {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        } else {
                            Text(String(format: "$%.2f", billingManager.currentBalance))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.green)
                        }

                        Button {
                            Task { @MainActor in
                                Task { await billingManager.loadAllData(apiKey: KeychainManager.shared.getAPIKey() ?? "") }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .task {
                        Task { await billingManager.loadAllData(apiKey: KeychainManager.shared.getAPIKey() ?? "") }
                    }
                }

                // Поле ввода API ключа
                HStack {
                    SecureField("Введите API ключ Deepgram...", text: $apiKeyInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13))
                        .padding(8)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)

                    Button(action: saveAPIKey) {
                        Text("Сохранить")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(apiKeyInput.isEmpty ? Color.gray.opacity(0.3) : Color(red: 1.0, green: 0.4, blue: 0.2))
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(apiKeyInput.isEmpty)
                }

                if showSaveSuccess {
                    Text("Ключ успешно сохранён!")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }

                // Ссылка на получение ключа
                Button(action: {
                    NSWorkspace.shared.open(URL(string: "https://console.deepgram.com/")!)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 11))
                        Text("Получить API ключ на deepgram.com")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
        }
    }

    private func saveAPIKey() {
        if SettingsManager.shared.saveAPIKey(apiKeyInput) {
            hasKey = true
            showSaveSuccess = true
            apiKeyInput = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showSaveSuccess = false
            }
        }
    }
}

// MARK: - Language Settings Section
struct LanguageSettingsSection: View {
    @State private var preferredLanguage: String = SettingsManager.shared.preferredLanguage

    var body: some View {
        SettingsSection(title: "ЯЗЫК РАСПОЗНАВАНИЯ") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(languageOptions, id: \.value) { option in
                    LanguageOptionRow(
                        title: option.title,
                        subtitle: option.subtitle,
                        value: option.value,
                        isSelected: preferredLanguage == option.value
                    ) {
                        preferredLanguage = option.value
                        SettingsManager.shared.preferredLanguage = option.value
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var languageOptions: [(title: String, subtitle: String, value: String)] {
        [
            ("Русский (рекомендуется)", "Оптимизировано для русского языка", "ru"),
            ("Английский", "Оптимизировано для английского языка", "en")
        ]
    }
}

struct LanguageOptionRow: View {
    let title: String
    let subtitle: String
    let value: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.2) : .gray)
                    .font(.system(size: 18))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - AI Settings Section
struct AISettingsSection: View {
    @Binding var aiEnabled: Bool
    @State private var geminiAPIKeyInput: String = ""
    @State private var showGeminiAPIKeyInput: Bool = false
    @State private var showSaveSuccess: Bool = false
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        SettingsSection(title: "AI ОБРАБОТКА") {
            VStack(alignment: .leading, spacing: 16) {
                // Тумблер включения
                SettingsRow(
                    title: "Включить AI функции",
                    subtitle: "Кнопки WB, RU, EN, CH для обработки текста через Gemini AI"
                ) {
                    Toggle("", isOn: $aiEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                        .labelsHidden()
                        .onChange(of: aiEnabled) { newValue in
                            SettingsManager.shared.aiEnabled = newValue
                        }
                }

                // Gemini API Key (только если включено)
                if aiEnabled {
                    Divider().background(Color.white.opacity(0.1))

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: settings.hasGeminiAPIKey ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                                    .foregroundColor(settings.hasGeminiAPIKey ? .green : .orange)
                                Text("Gemini API Key")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                            if settings.hasGeminiAPIKey {
                                Text(settings.getGeminiAPIKeyMasked())
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)
                            } else {
                                Text("Требуется для работы AI функций")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()

                        Button(settings.hasGeminiAPIKey ? "Изменить" : "Добавить") {
                            showGeminiAPIKeyInput.toggle()
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(6)
                        .buttonStyle(PlainButtonStyle())
                    }

                    if showGeminiAPIKeyInput {
                        HStack {
                            TextField("AIzaSy...", text: $geminiAPIKeyInput)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 12, design: .monospaced))
                                .padding(8)
                                .background(Color.white.opacity(0.05))
                                .cornerRadius(6)

                            Button("Сохранить") {
                                if settings.saveGeminiAPIKey(geminiAPIKeyInput) {
                                    showSaveSuccess = true
                                    geminiAPIKeyInput = ""
                                    showGeminiAPIKeyInput = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        showSaveSuccess = false
                                    }
                                }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(geminiAPIKeyInput.isEmpty ? Color.gray : Color(red: 1.0, green: 0.4, blue: 0.2))
                            .cornerRadius(6)
                            .buttonStyle(PlainButtonStyle())
                            .disabled(geminiAPIKeyInput.isEmpty)
                        }
                    }

                    if showSaveSuccess {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Ключ сохранён")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                        }
                    }

                    Button(action: {
                        NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/app/apikey")!)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                            Text("Получить Gemini API ключ")
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - AI Prompts Section
struct AIPromptsSection: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var selectedPrompt: String = "wb"

    var body: some View {
        SettingsSection(title: "AI ПРОМПТЫ") {
            VStack(alignment: .leading, spacing: 12) {
                // Выбор промпта
                HStack(spacing: 8) {
                    ForEach(["wb", "ru", "en", "ch"], id: \.self) { key in
                        Button(action: { selectedPrompt = key }) {
                            Text(key.uppercased())
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(selectedPrompt == key ? .white : .gray)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedPrompt == key ? Color.white.opacity(0.15) : Color.clear)
                                .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    Spacer()
                }

                // Описание
                Text(promptDescription(for: selectedPrompt))
                    .font(.system(size: 11))
                    .foregroundColor(.gray)

                // Редактор промпта
                TextEditor(text: promptBinding(for: selectedPrompt))
                    .font(.system(size: 12))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(6)

                // Кнопка сброса
                Button(action: { resetPrompt(for: selectedPrompt) }) {
                    Text("Сбросить по умолчанию")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
        }
    }

    private func promptBinding(for key: String) -> Binding<String> {
        switch key {
        case "wb": return $settings.promptWB
        case "ru": return $settings.promptRU
        case "en": return $settings.promptEN
        case "ch": return $settings.promptCH
        default: return $settings.promptWB
        }
    }

    private func promptDescription(for key: String) -> String {
        switch key {
        case "wb": return "WB: Вежливый Бот — перефразирует текст, делая его вежливым и профессиональным"
        case "ru": return "RU: Перевод на русский язык как носитель"
        case "en": return "EN: Translation to native English"
        case "ch": return "CH: 翻译成地道的中文"
        default: return ""
        }
    }

    private func resetPrompt(for key: String) {
        switch key {
        case "wb":
            settings.promptWB = "Перефразируй этот текст на том же языке, сделав его более вежливым и профессиональным. Используй разговорный, но уважительный тон. Исправь все грамматические и пунктуационные ошибки. Текст должен показывать, что мы ценим клиента и хорошо к нему относимся. Сохрани суть сообщения, но сделай его максимально приятным для получателя:"
        case "ru":
            settings.promptRU = "Переведи следующий текст на русский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель русского языка:"
        case "en":
            settings.promptEN = "Переведи следующий текст на английский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель английского языка:"
        case "ch":
            settings.promptCH = "Переведи следующий текст на китайский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель китайского языка:"
        default: break
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
    var previousApp: NSRunningApplication?  // Предыдущее активное приложение для авто-вставки

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("🚀 Olamba запущен")

        // Запросить Accessibility при первом запуске (добавит в список автоматически)
        if !AccessibilityHelper.checkAccessibility() {
            AccessibilityHelper.requestAccessibility()
        }

        // Инициализация менеджеров
        _ = HistoryManager.shared
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
        NotificationCenter.default.addObserver(self, selector: #selector(screenshotHotkeyDidChange), name: .screenshotHotkeyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubmitAndPaste), name: .submitAndPaste, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(disableGlobalHotkeys), name: .disableGlobalHotkeys, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enableGlobalHotkeys), name: .enableGlobalHotkeys, object: nil)

        // Авто-проверка Accessibility при возврате в приложение
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Показываем окно при первом запуске
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showWindow()
        }

        NSLog("✅ Инициализация завершена")
    }

    @objc func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }

        // Приложение стало активным — проверить Accessibility
        NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
    }

    @objc func hotkeyDidChange() {
        // Перерегистрируем хоткеи с новыми настройками
        unregisterHotKeys()
        setupHotKeys()
        NSLog("🔄 Хоткеи перерегистрированы")
    }

    @objc func screenshotHotkeyDidChange() {
        NSLog("📸 Screenshot hotkey changed, re-registering...")
        unregisterHotKeys()
        setupHotKeys()
    }

    @objc func handleScreenshotHotkey() {
        guard SettingsManager.shared.screenshotFeatureEnabled else {
            NSLog("⚠️ Screenshot feature is disabled")
            return
        }

        NSLog("📸 Screenshot hotkey pressed")

        // Создаём директорию если не существует
        let screenshotsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Screenshots")

        do {
            try FileManager.default.createDirectory(
                at: screenshotsDir,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            NSLog("❌ Failed to create screenshots directory: \(error)")
            return
        }

        // Генерируем AI-friendly имя файла
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "screenshot-\(timestamp).png"
        let filepath = screenshotsDir.appendingPathComponent(filename).path

        // Запускаем screencapture с интерактивным выбором
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", filepath]  // -i = interactive mode

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                // Проверяем что файл создан (пользователь мог отменить)
                if FileManager.default.fileExists(atPath: filepath) {
                    NSLog("✅ Screenshot saved: \(filepath)")

                    // Копируем путь в буфер обмена
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(filepath, forType: .string)

                    // Показываем временное уведомление
                    showScreenshotNotification()
                } else {
                    NSLog("⚠️ Screenshot cancelled by user")
                }
            } else {
                NSLog("❌ screencapture failed with status: \(process.terminationStatus)")
            }
        } catch {
            NSLog("❌ Failed to execute screencapture: \(error)")
        }
    }

    func showScreenshotNotification() {
        // Создаём временное floating уведомление
        let notification = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        notification.isOpaque = false
        notification.backgroundColor = .clear
        notification.level = .floating
        notification.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // SwiftUI контент
        let hostingView = NSHostingView(rootView: ScreenshotNotificationView())
        notification.contentView = hostingView

        // Позиционируем в правом верхнем углу активного экрана
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 240
            let y = screenFrame.maxY - 70
            notification.setFrameOrigin(NSPoint(x: x, y: y))
        }

        notification.orderFrontRegardless()

        // Автоматически скрываем через 2 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            notification.orderOut(nil)
            notification.close()
        }
    }

    @objc func handleSubmitAndPaste() {
        submitAndPaste()
    }

    @objc func disableGlobalHotkeys() {
        // Временно отключить локальный монитор (для записи хоткеев в настройках)
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        NSLog("⌨️ Глобальные хоткеи отключены")
    }

    @objc func enableGlobalHotkeys() {
        // Восстановить хоткеи
        if localEventMonitor == nil {
            setupHotKeys()
        }
        NSLog("⌨️ Глобальные хоткеи включены")
    }

    func submitAndPaste() {
        guard let prevApp = previousApp else {
            // Нет предыдущего приложения - просто закрыть
            NSLog("⚠️ previousApp is nil, just closing")
            SoundManager.shared.playCopySound()
            window?.close()
            return
        }

        NSLog("📱 Вставка в приложение: \(prevApp.localizedName ?? "unknown")")

        // Закрыть окно
        SoundManager.shared.playCopySound()
        window?.close()

        // Сохраняем ссылку перед обнулением
        let targetApp = prevApp
        previousApp = nil

        // Активировать предыдущее приложение с force
        targetApp.activate(options: .activateIgnoringOtherApps)

        // Вставить через Cmd+V с достаточной задержкой
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            // Проверить что приложение активировалось
            let currentApp = NSWorkspace.shared.frontmostApplication
            if currentApp?.processIdentifier == targetApp.processIdentifier {
                NSLog("✅ Приложение активно, вставляем")
                self?.simulatePaste()
            } else {
                NSLog("⚠️ Приложение не активировалось (\(currentApp?.localizedName ?? "nil")), повторная попытка")
                targetApp.activate(options: .activateIgnoringOtherApps)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.simulatePaste()
                }
            }
        }
    }

    func simulatePaste() {
        // CGEvent метод (как Raycast) - требует только Accessibility
        let source = CGEventSource(stateID: .hidSystemState)

        // V key = 0x09
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            NSLog("❌ Не удалось создать CGEvent")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        usleep(10000)  // 10ms между нажатием и отпусканием
        keyUp.post(tap: .cghidEventTap)

        NSLog("📋 Cmd+V отправлен через CGEvent")
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

            // "Открыть Olamba" with play icon
            let openItem = NSMenuItem(title: "Открыть Olamba", action: #selector(showWindow), keyEquivalent: "")
            openItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Open Olamba")
            menu.addItem(openItem)

            // "Настройки..." with gear icon
            let settingsItem = NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ",")
            settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: "Settings")
            menu.addItem(settingsItem)

            // Separator
            menu.addItem(NSMenuItem.separator())

            // "Выход" with power icon
            let quitItem = NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q")
            quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
            menu.addItem(quitItem)

            // Показать меню под иконкой (безопасный способ без краша)
            if let button = statusItem?.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
            }
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
            { _, inEvent, userData -> OSStatus in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()

                // Получаем ID хоткея
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    inEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                // Обрабатываем в зависимости от ID
                if hotKeyID.id == 6 {
                    // Screenshot hotkey
                    appDelegate.handleScreenshotHotkey()
                } else {
                    // Toggle window hotkeys (1-5)
                    appDelegate.toggleWindow()
                }

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

        // Register screenshot hotkey (ID=6) if feature is enabled
        if SettingsManager.shared.screenshotFeatureEnabled {
            let screenshotHotkey = SettingsManager.shared.screenshotHotkey
            registerCarbonHotKey(
                keyCode: UInt32(screenshotHotkey.keyCode),
                modifiers: screenshotHotkey.modifiers,
                id: 6
            )
            NSLog("📸 Screenshot hotkey registered: \(screenshotHotkey.displayString)")
        }

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
            // Закрытие по хоткею - проверить есть ли текст для вставки
            NotificationCenter.default.post(name: .checkAndSubmit, object: nil)
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

        // Сохраняем предыдущее активное приложение (до активации нашего)
        // Только если окно ещё не видно
        if !window.isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSLog("📱 Сохранено предыдущее приложение: \(previousApp?.localizedName ?? "nil")")
        }

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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if let textView = self?.findTextView(in: window.contentView) {
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
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )

            sw.title = "Настройки Olamba"
            sw.titlebarAppearsTransparent = false
            sw.titleVisibility = .visible
            sw.backgroundColor = NSColor(red: 30/255, green: 30/255, blue: 32/255, alpha: 1.0)
            sw.isOpaque = true
            sw.delegate = self

            let hostingView = NSHostingView(rootView: settingsView)
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
        guard let closedWindow = notification.object as? NSWindow else { return }

        // Не реагировать на закрытие основного окна
        if closedWindow == window {
            return
        }

        // Если закрылись настройки - показываем основное окно
        if closedWindow == settingsWindow {
            settingsWindow = nil  // Очищаем ссылку для пересоздания
            // С задержкой чтобы избежать проблем с UI
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showWindow()
            }
        }
    }

    @objc func quitApp() {
        // Убираем NotificationCenter observers
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        // Убираем мониторы событий
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Deepgram Settings UI Components
struct ModelOptionRow: View {
    let model: String
    let title: String
    let description: String
    let isSelected: Bool
    let badge: String?
    let onSelect: () -> Void

    init(model: String, title: String, description: String, isSelected: Bool, badge: String? = nil, onSelect: @escaping () -> Void) {
        self.model = model
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.badge = badge
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let badge = badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(8)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct RequestRow: View {
    let request: DeepgramUsageRequest

    var body: some View {
        HStack(spacing: 8) {
            Text(formatDate(request.created))
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Text("•")
                .foregroundColor(.secondary)

            Text(request.response.model_name ?? "N/A")
                .font(.system(size: 11))
                .foregroundColor(.white)

            if let duration = request.response.duration_seconds {
                Text("•")
                    .foregroundColor(.secondary)

                Text("\(String(format: "%.1f", duration))с")
                    .font(.system(size: 11))
                    .foregroundColor(.white)
            }

            Spacer()

            if let usd = request.response.details?.usd {
                Text("$\(String(format: "%.3f", usd))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoString) else {
            return isoString
        }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "dd MMM, HH:mm"
        displayFormatter.locale = Locale(identifier: "ru_RU")
        return displayFormatter.string(from: date)
    }
}

struct BillingErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            Text("Ошибка загрузки данных")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            Button("Попробовать снова") {
                retry()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
