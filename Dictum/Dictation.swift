//
//  Dictation.swift
//  Dictum
//
//  ASR: VolumeManager, AccessibilityHelper, Parakeet, Deepgram
//

import SwiftUI
@preconcurrency import AVFoundation
import FluidAudio

// MARK: - Sendable Bool Box (for closure capture)
private final class BoolBox: @unchecked Sendable {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}

// MARK: - Volume Manager
class VolumeManager: @unchecked Sendable {
    static let shared = VolumeManager()
    private var savedVolume: Int?

    func getCurrentVolume() -> Int? {
        let process = Process()
        let pipe = Pipe()

        defer {
            try? pipe.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
        }

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

        defer {
            if process.isRunning { process.terminate() }
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "set volume output volume \(clampedLevel)"]

        do {
            try process.run()
            process.waitUntilExit()
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

// MARK: - Permission Manager
/// Централизованное управление разрешениями macOS
/// Принципы:
/// 1. Не дублировать системные диалоги — если API показывает диалог, не открываем Settings
/// 2. Открывать Settings только когда нужно (уже отказано или нет диалога)
/// 3. Screen Recording — триггерим реальный capture чтобы появиться в списке
class PermissionManager: @unchecked Sendable {
    static let shared = PermissionManager()

    // MARK: - Check Permissions

    /// Проверка Accessibility (Универсальный доступ)
    func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Проверка Microphone
    func hasMicrophone() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Проверка Screen Recording
    func hasScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    // MARK: - Request Permissions

    /// Accessibility: Системный диалог сам открывает Settings если нужно
    /// Возвращает true если уже есть разрешение
    @discardableResult
    func requestAccessibility() -> Bool {
        // Используем строковый ключ напрямую для Swift 6 concurrency safety
        let options: NSDictionary = ["AXTrustedCheckOptionPrompt": true]
        let result = AXIsProcessTrustedWithOptions(options)
        NSLog("🔐 Accessibility request: \(result ? "granted" : "will show dialog")")
        return result
    }

    /// Microphone: Показываем системный диалог если не определено
    /// Открываем Settings только если уже отказано
    func requestMicrophone(completion: @escaping @Sendable (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        NSLog("🎤 Microphone status: \(status.rawValue)")

        switch status {
        case .notDetermined:
            // Показать системный диалог (автоматически добавит в список)
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                NSLog("🎤 Microphone dialog result: \(granted)")
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            // Уже отказано — открываем Settings
            NSLog("🎤 Microphone already denied, opening settings")
            openPrivacySettings(section: "Microphone")
            completion(false)
        case .authorized:
            completion(true)
        @unknown default:
            completion(false)
        }
    }

    /// Screen Recording: Триггерим реальный capture чтобы:
    /// 1. Приложение появилось в списке
    /// 2. Показался системный диалог (если первый раз)
    func requestScreenRecording() {
        NSLog("📹 Requesting Screen Recording permission...")

        // CGWindowListCreateImage триггерит системный диалог и добавляет приложение в список
        // Deprecated в macOS 14, но нужен для совместимости и добавления в TCC
        if #available(macOS 14.0, *) {
            // На macOS 14+ используем CGRequestScreenCaptureAccess
            // Это покажет диалог и добавит в список
            CGRequestScreenCaptureAccess()
        } else {
            // Legacy fallback
            let _ = CGWindowListCreateImage(
                CGRect(x: 0, y: 0, width: 1, height: 1),
                .optionOnScreenOnly,
                kCGNullWindowID,
                .bestResolution
            )
        }

        // Открываем Settings чтобы пользователь мог включить разрешение
        openPrivacySettings(section: "ScreenCapture")
    }

    // MARK: - Open System Settings

    /// Открыть конкретную секцию Privacy & Security
    /// section: "Accessibility", "Microphone", "ScreenCapture", etc.
    func openPrivacySettings(section: String? = nil) {
        // Определяем версию macOS
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let isTahoeOrLater = osVersion.majorVersion >= 26

        var urlString = "x-apple.systempreferences:com.apple.preference.security"

        // На macOS 26+ (Tahoe) параметры Privacy_* могут вызывать краш
        // Пробуем с параметром только на более ранних версиях
        if let section = section, !isTahoeOrLater {
            urlString += "?Privacy_\(section)"
        }

        NSLog("🔧 Opening System Settings: \(urlString) (macOS \(osVersion.majorVersion))")

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Legacy Compatibility (для существующего кода)
typealias AccessibilityHelper = PermissionManager

extension PermissionManager {
    /// Legacy: проверка accessibility
    static func checkAccessibility() -> Bool {
        shared.hasAccessibility()
    }

    /// Legacy: запрос accessibility
    static func requestAccessibility() {
        shared.requestAccessibility()
    }

    /// Legacy: проверка screen recording
    static func hasScreenRecordingPermission() -> Bool {
        shared.hasScreenRecording()
    }

    /// Legacy: запрос screen recording
    static func requestScreenRecordingPermission() {
        shared.requestScreenRecording()
    }
}

// MARK: - Parakeet Model Status
enum ParakeetModelStatus: Equatable {
    case notChecked          // Ещё не проверяли
    case checking            // Проверка наличия модели
    case notDownloaded       // Модель не скачана
    case downloading         // Идёт скачивание (~600 MB)
    case loading             // Загрузка в память (компиляция CoreML)
    case ready               // Готова к работе
    case error(String)       // Ошибка

    var displayText: String {
        switch self {
        case .notChecked: return "Проверка..."
        case .checking: return "Проверка наличия модели..."
        case .notDownloaded: return "Модель не скачана"
        case .downloading: return "Скачивание модели..."
        case .loading: return "Загрузка в память..."
        case .ready: return "Parakeet v3 готова"
        case .error(let msg): return "Ошибка: \(msg)"
        }
    }
}

// MARK: - Parakeet ASR Provider (Local)
class ParakeetASRProvider: ObservableObject, @unchecked Sendable {
    @Published var isRecording = false
    @Published var transcriptionResult: String?
    @Published var interimText: String = ""
    @Published var errorMessage: String?
    @Published var audioLevel: Float = 0.0
    @Published var isModelLoaded = false
    @Published var modelStatus: ParakeetModelStatus = .notChecked
    @Published var downloadedFilesCount: Int = 0
    @Published var totalFilesCount: Int = 0

    private var audioEngine: AVAudioEngine?
    private var asrManager: AsrManager?
    private var models: AsrModels?

    // Накопление аудио сэмплов (batch processing)
    private var audioSamples: [Float] = []
    private let samplesLock = NSLock()

    // Кешированный AVAudioConverter для 16 kHz
    private var audioConverter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var resampledBuffer: AVAudioPCMBuffer?

    // Guard для предотвращения double stop
    private var isStopInProgress = false

    init() {
        Task {
            await checkModelStatus()
            if modelStatus == .notDownloaded {
                return
            }
            await initializeModelsIfNeeded()
        }
    }

    /// Проверка наличия модели без скачивания
    func checkModelStatus() async {
        await MainActor.run {
            modelStatus = .checking
        }

        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
        let exists = AsrModels.modelsExist(at: cacheDir, version: .v3)

        await MainActor.run {
            if exists {
                modelStatus = .loading
            } else {
                modelStatus = .notDownloaded
            }
        }
    }

    deinit {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        resampledBuffer = nil
        NSLog("🗑️ ParakeetASRProvider освобождён")
    }

    /// Удаление модели из кэша
    func deleteModel() async {
        if isRecording {
            await stopRecordingAndTranscribe()
        }

        asrManager = nil
        models = nil

        await MainActor.run {
            isModelLoaded = false
            modelStatus = .notChecked
        }

        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)

        do {
            if FileManager.default.fileExists(atPath: cacheDir.path) {
                try FileManager.default.removeItem(at: cacheDir)
                NSLog("🗑️ Удалена модель Parakeet v3: \(cacheDir.path)")
            }

            await MainActor.run {
                modelStatus = .notDownloaded
            }
        } catch {
            NSLog("❌ Ошибка удаления модели: \(error.localizedDescription)")
            await MainActor.run {
                modelStatus = .error("Не удалось удалить: \(error.localizedDescription)")
            }
        }
    }

    /// Инициализация моделей (скачивает ~600 MB при первом запуске)
    func initializeModelsIfNeeded() async {
        guard !isModelLoaded else { return }

        do {
            let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
            let modelExists = AsrModels.modelsExist(at: cacheDir, version: .v3)

            if modelExists {
                await MainActor.run { modelStatus = .loading }
                NSLog("🧠 Загрузка Parakeet v3 из кэша...")
            } else {
                await MainActor.run { modelStatus = .downloading }
                NSLog("⬇️ Скачивание Parakeet v3 (~600 MB)...")
            }

            let downloadedModels = try await AsrModels.downloadAndLoad(version: .v3)

            await MainActor.run { modelStatus = .loading }
            NSLog("🧠 Компиляция CoreML моделей...")

            let manager = AsrManager(config: .default)
            try await manager.initialize(models: downloadedModels)

            self.models = downloadedModels
            self.asrManager = manager

            await MainActor.run {
                isModelLoaded = true
                modelStatus = .ready
            }

            NSLog("✅ Parakeet v3 модель готова (25 языков, ~190x real-time)")
        } catch {
            NSLog("❌ Ошибка загрузки модели: \(error.localizedDescription)")
            await MainActor.run {
                modelStatus = .error(error.localizedDescription)
                errorMessage = "Ошибка загрузки модели: \(error.localizedDescription)"
            }
        }
    }

    func startRecording() async {
        guard !isRecording else {
            NSLog("⚠️ Локальная запись уже идёт")
            return
        }

        guard isModelLoaded, asrManager != nil else {
            await MainActor.run {
                if modelStatus == .loading {
                    errorMessage = "Модель загружается..."
                } else {
                    errorMessage = "Модель не загружена. Подождите или откройте Настройки."
                }
            }
            return
        }

        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            await MainActor.run {
                errorMessage = "Нет доступа к микрофону"
            }
            return
        }

        samplesLock.withLock {
            audioSamples.removeAll()
        }

        await MainActor.run {
            interimText = ""
            transcriptionResult = nil
            isRecording = true
            audioLevel = 0.0
        }

        VolumeManager.shared.saveAndReduceVolume(targetVolume: SettingsManager.shared.volumeLevel)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            await MainActor.run {
                errorMessage = "Неверный формат входного аудио"
                isRecording = false
            }
            return
        }

        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            await MainActor.run {
                errorMessage = "Ошибка формата аудио"
                isRecording = false
            }
            return
        }
        self.outputFormat = outFmt

        guard let converter = AVAudioConverter(from: inputFormat, to: outFmt) else {
            await MainActor.run {
                errorMessage = "Ошибка создания аудио-конвертера"
                isRecording = false
            }
            return
        }
        self.audioConverter = converter

        let maxOutputFrames = AVAudioFrameCount(outFmt.sampleRate * 0.2)
        self.resampledBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: maxOutputFrames)

        engine.prepare()

        let bufferSizeForInput = AVAudioFrameCount(inputFormat.sampleRate * 0.1)
        inputNode.installTap(onBus: 0, bufferSize: bufferSizeForInput, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            NSLog("🎤 Локальный ASR запущен (Parakeet v3)")

            await MainActor.run {
                interimText = "Слушаю..."
            }

        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioConverter = nil
            self.outputFormat = nil

            await MainActor.run {
                errorMessage = "Ошибка запуска: \(error.localizedDescription)"
                isRecording = false
            }
        }
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // 1. Рассчитать уровень громкости (RMS)
        if let channelData = buffer.floatChannelData {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0.0
            for i in 0..<frameLength {
                let sample = channelData[0][i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(1, frameLength)))
            let normalizedRms = rms * 50.0
            let level = min(1.0, log10(1 + normalizedRms * 9))

            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }
        }

        // 2. Ресэмплирование в 16 kHz
        guard let converter = audioConverter,
              let outFmt = outputFormat,
              let outputBuffer = resampledBuffer else {
            return
        }

        guard buffer.format.sampleRate > 0 else { return }

        let ratio = outFmt.sampleRate / Double(buffer.format.sampleRate)
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard outputFrameCount <= outputBuffer.frameCapacity else {
            NSLog("⚠️ Buffer overflow: need \(outputFrameCount), have \(outputBuffer.frameCapacity)")
            return
        }
        outputBuffer.frameLength = outputFrameCount

        var conversionError: NSError?
        let hasDataBox = BoolBox(true)

        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if hasDataBox.value {
                outStatus.pointee = .haveData
                hasDataBox.value = false
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if let error = conversionError {
            NSLog("❌ Audio conversion error: \(error.localizedDescription)")
            return
        }

        // 3. Накопление сэмплов
        if let channelData = outputBuffer.floatChannelData {
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
            samplesLock.withLock {
                audioSamples.append(contentsOf: samples)
            }
        }
    }

    func stopRecordingAndTranscribe() async {
        guard !isStopInProgress else {
            NSLog("⚠️ stopRecording already in progress, skipping")
            return
        }
        isStopInProgress = true
        defer { isStopInProgress = false }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        audioConverter?.reset()
        audioConverter = nil
        outputFormat = nil
        resampledBuffer = nil

        await MainActor.run {
            interimText = "Обрабатываю..."
        }

        let samplesToProcess = samplesLock.withLock { audioSamples }

        guard let asrManager = asrManager, !samplesToProcess.isEmpty else {
            await MainActor.run {
                isRecording = false
                interimText = ""
            }
            VolumeManager.shared.restoreVolume()
            return
        }

        do {
            NSLog("🔄 Транскрибация \(samplesToProcess.count) сэмплов (~\(String(format: "%.1f", Double(samplesToProcess.count) / 16000))s аудио)...")

            let result = try await asrManager.transcribe(samplesToProcess)
            let text = result.text.trimmingCharacters(in: .whitespaces)

            await MainActor.run {
                transcriptionResult = text.isEmpty ? nil : text
                isRecording = false
                interimText = ""
            }

            NSLog("✅ Результат (Parakeet): \(text)")

        } catch {
            let errorDesc = error.localizedDescription
            NSLog("❌ Ошибка транскрибации: \(errorDesc)")

            if !errorDesc.contains("Must be at least 1 second") {
                await MainActor.run {
                    errorMessage = "Ошибка транскрибации: \(errorDesc)"
                    isRecording = false
                    interimText = ""
                }
            } else {
                NSLog("ℹ️ Запись слишком короткая, пропускаем")
                await MainActor.run {
                    isRecording = false
                    interimText = ""
                }
            }
        }

        samplesLock.withLock {
            audioSamples.removeAll()
        }

        VolumeManager.shared.restoreVolume()
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

// MARK: - Alias for backward compatibility
typealias SherpaASRProvider = ParakeetASRProvider

// MARK: - Real-time Streaming Audio Manager (WebSocket)
class AudioRecordingManager: NSObject, ObservableObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var errorMessage: String?
    @Published var transcriptionResult: String?
    @Published var interimText: String = ""
    @Published var appendMode: Bool = false
    @Published var audioLevel: Float = 0.0

    private var audioEngine: AVAudioEngine?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var finalTranscript: String = ""
    private var audioBuffer: [Data] = []

    private var _webSocketConnected: Bool = false
    private let webSocketConnectedLock = NSLock()
    private var webSocketConnected: Bool {
        get { webSocketConnectedLock.withLock { _webSocketConnected } }
        set { webSocketConnectedLock.withLock { _webSocketConnected = newValue } }
    }

    private var isClosingWebSocket: Bool = false
    private var finalResponseReceived: Bool = false
    private var connectionTimeoutWorkItem: DispatchWorkItem?
    private let transcriptLock = NSLock()
    private let audioBufferQueue = DispatchQueue(label: "com.dictum.audioBuffer")

    private var cachedConverter: AVAudioConverter?
    private var cachedInputFormat: AVAudioFormat?
    private var cachedOutputFormat: AVAudioFormat?

    override init() {
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    deinit {
        urlSession?.invalidateAndCancel()
    }

    func startRecording(existingText: String = "") async {
        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            await MainActor.run {
                errorMessage = "API ключ не найден. Откройте Настройки"
            }
            return
        }

        let hasPermission = await requestMicrophonePermission()
        guard hasPermission else {
            await MainActor.run {
                errorMessage = "Нет доступа к микрофону"
            }
            return
        }

        let isAppend = !existingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        transcriptLock.withLock { finalTranscript = "" }
        audioBufferQueue.sync { audioBuffer.removeAll() }
        webSocketConnected = false
        finalResponseReceived = false

        await MainActor.run {
            appendMode = isAppend
            interimText = ""
            transcriptionResult = nil
            isRecording = true
            audioLevel = 0.0
        }

        VolumeManager.shared.saveAndReduceVolume(targetVolume: SettingsManager.shared.volumeLevel)

        let language = SettingsManager.shared.preferredLanguage
        let model = SettingsManager.shared.deepgramModel
        guard let wsURL = URL(string: "wss://api.deepgram.com/v1/listen?encoding=linear16&sample_rate=16000&channels=1&model=\(model)&language=\(language)&interim_results=true&utterance_end_ms=2000&smart_format=true&punctuate=true") else {
            await MainActor.run { errorMessage = "Ошибка создания WebSocket URL" }
            return
        }

        var request = URLRequest(url: wsURL)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        webSocket = urlSession.webSocketTask(with: request)
        webSocket?.resume()

        NSLog("🔌 Подключение к Deepgram WebSocket... model=\(model), language=\(language)")

        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if !self.webSocketConnected && self.isRecording {
                NSLog("⚠️ WebSocket timeout - нет подключения за 5 секунд")
                self.webSocket?.cancel(with: .goingAway, reason: nil)
                self.webSocket = nil
                DispatchQueue.main.async {
                    self.errorMessage = "Timeout подключения к серверу. Проверьте интернет."
                    self.isRecording = false
                }
                VolumeManager.shared.restoreVolume()
            }
        }
        if let workItem = connectionTimeoutWorkItem {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        }

        receiveMessages()

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            await MainActor.run { errorMessage = "Ошибка инициализации аудио" }
            return
        }
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            await MainActor.run { errorMessage = "Аудио устройство недоступно" }
            return
        }

        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            await MainActor.run { errorMessage = "Ошибка формата аудио" }
            return
        }

        audioEngine?.prepare()

        inputNode.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer, from: inputFormat, to: outputFormat)
        }

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

        NSLog("🔌 Ожидание подключения WebSocket...")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, from inputFormat: AVAudioFormat, to outputFormat: AVAudioFormat) {
        // 1. Рассчитать уровень громкости
        if let channelData = buffer.floatChannelData {
            let frameLength = Int(buffer.frameLength)
            var sum: Float = 0.0
            for i in 0..<frameLength {
                let sample = channelData[0][i]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(max(1, frameLength)))
            let normalizedRms = rms * 50.0
            let level = min(1.0, log10(1 + normalizedRms * 9))

            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }
        }

        // 2. Конвертировать в 16kHz
        let converter: AVAudioConverter
        if let cached = cachedConverter,
           cachedInputFormat == inputFormat,
           cachedOutputFormat == outputFormat {
            converter = cached
        } else {
            guard let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return }
            cachedConverter = newConverter
            cachedInputFormat = inputFormat
            cachedOutputFormat = outputFormat
            converter = newConverter
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        let hasDataBox = BoolBox(true)

        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if hasDataBox.value {
                outStatus.pointee = .haveData
                hasDataBox.value = false
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        // 3. Отправить или буферизировать данные
        if error == nil, let channelData = outputBuffer.int16ChannelData {
            let byteCount = Int(outputBuffer.frameLength) * 2
            let data = Data(bytes: channelData[0], count: byteCount)

            audioBufferQueue.async { [weak self] in
                guard let self = self else { return }

                if self.webSocketConnected {
                    if !self.audioBuffer.isEmpty {
                        let count = self.audioBuffer.count
                        for bufferedData in self.audioBuffer {
                            self.webSocket?.send(.data(bufferedData)) { error in
                                if let error = error {
                                    NSLog("❌ Ошибка отправки буферизованного аудио: \(error.localizedDescription)")
                                }
                            }
                        }
                        self.audioBuffer.removeAll()
                        NSLog("📤 Отправлено \(count) буферизованных чанков")
                    }
                    self.webSocket?.send(.data(data)) { error in
                        if let error = error {
                            NSLog("❌ Ошибка отправки аудио: \(error.localizedDescription)")
                        }
                    }
                } else {
                    if self.audioBuffer.count < 30 {
                        self.audioBuffer.append(data)
                    } else {
                        NSLog("⚠️ Буфер аудио переполнен! WebSocket не подключается более 3 сек")
                    }
                }
            }
        }
    }

    func stopRecordingAndTranscribe(language: String) async {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        cachedConverter = nil
        cachedInputFormat = nil
        cachedOutputFormat = nil

        webSocket?.send(.string("{\"type\": \"CloseStream\"}")) { _ in }

        let deadline = Date().addingTimeInterval(2.0)
        while !finalResponseReceived && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        if finalResponseReceived {
            NSLog("✅ Получен финальный ответ от Deepgram (speech_final или UtteranceEnd)")
        } else {
            NSLog("⚠️ Timeout ожидания финального ответа (2 сек)")
        }

        isClosingWebSocket = true
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        webSocketConnected = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isClosingWebSocket = false
        }

        let finalText = transcriptLock.withLock { finalTranscript }

        await MainActor.run {
            isRecording = false
            if !finalText.isEmpty {
                transcriptionResult = finalText.trimmingCharacters(in: .whitespaces)
            }
            interimText = ""
        }

        VolumeManager.shared.restoreVolume()

        NSLog("✅ Результат: \(finalText)")
    }

    private func receiveMessages() {
        guard let webSocket = webSocket, !isClosingWebSocket else { return }

        webSocket.receive { [weak self] result in
            guard let self = self, self.webSocket != nil, !self.isClosingWebSocket else { return }

            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleResponse(text)
                }
                if !self.isClosingWebSocket {
                    self.receiveMessages()
                }

            case .failure(let error):
                guard !self.isClosingWebSocket else { return }
                NSLog("❌ WS error: \(error.localizedDescription)")
                self.isClosingWebSocket = true
                self.webSocket?.cancel(with: .goingAway, reason: nil)
                self.webSocket = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.isClosingWebSocket = false
                }
            }
        }
    }

    private func handleResponse(_ text: String) {
        NSLog("📥 Deepgram: \(text.prefix(500))...")

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("⚠️ Deepgram: не удалось распарсить JSON")
            return
        }

        let messageType = json["type"] as? String ?? "unknown"

        if messageType == "Metadata" || messageType == "SpeechStarted" {
            NSLog("📋 Deepgram: служебное сообщение типа \(messageType)")
            return
        }

        if messageType == "UtteranceEnd" {
            if !finalResponseReceived {
                finalResponseReceived = true
                NSLog("🎯 UtteranceEnd received (fallback для speech_final)")
            }
            return
        }

        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String else {
            NSLog("⚠️ Deepgram: неизвестный формат ответа, type=\(messageType), keys=\(json.keys.joined(separator: ", "))")
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let speechFinal = json["speech_final"] as? Bool ?? false

        DispatchQueue.main.async {
            if isFinal && !transcript.isEmpty {
                self.transcriptLock.withLock {
                    self.finalTranscript += (self.finalTranscript.isEmpty ? "" : " ") + transcript
                }
                self.interimText = ""
                NSLog("📝 Final: \(transcript)")
            } else if !transcript.isEmpty {
                self.interimText = transcript
                NSLog("📝 Interim: \(transcript)")
            }

            if speechFinal {
                self.finalResponseReceived = true
                NSLog("🎯 Speech final received!")
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

        webSocketConnected = true

        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil

        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }

            if !self.audioBuffer.isEmpty {
                let bufferedCount = self.audioBuffer.count
                for data in self.audioBuffer {
                    self.webSocket?.send(.data(data)) { error in
                        if let error = error {
                            NSLog("❌ Ошибка отправки буферизованного аудио: \(error.localizedDescription)")
                        }
                    }
                }
                self.audioBuffer.removeAll()
                NSLog("📤 Отправлено \(bufferedCount) буферизованных чанков аудио")
            }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        NSLog("🔌 WebSocket закрыт: \(closeCode.rawValue)")
        webSocketConnected = false
    }
}

// MARK: - ASR Provider Type
enum ASRProviderType: String, CaseIterable {
    case local = "local"
    case deepgram = "deepgram"

    var displayName: String {
        switch self {
        case .local: return "Parakeet v3 (локальная)"
        case .deepgram: return "Deepgram (облако)"
        }
    }

    var description: String {
        switch self {
        case .local: return "25 языков, офлайн, ~190x real-time"
        case .deepgram: return "Streaming в реальном времени"
        }
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

// MARK: - Deepgram Service (REST)
class DeepgramService {
    private let baseURL = "https://api.deepgram.com/v1/listen"

    func transcribe(audioURL: URL, language: String = "ru") async throws -> String {
        guard let apiKey = KeychainManager.shared.getAPIKey(), !apiKey.isEmpty else {
            throw DeepgramError.noAPIKey
        }

        let audioData = try Data(contentsOf: audioURL)
        NSLog("📤 Отправляем: \(audioData.count) байт, язык: \(language)")

        if audioData.count < 1000 {
            throw DeepgramError.noTranscript
        }

        let model = SettingsManager.shared.deepgramModel
        guard var components = URLComponents(string: baseURL) else {
            throw DeepgramError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true")
        ]

        guard let url = components.url else {
            throw DeepgramError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 30

        NSLog("📡 Отправляем в Deepgram...")
        let startTime = Date()

        let (data, response) = try await URLSession.shared.data(for: request)

        let elapsed = Date().timeIntervalSince(startTime)
        NSLog("⏱️ Ответ за \(String(format: "%.2f", elapsed)) сек")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepgramError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown"
            NSLog("❌ HTTP \(httpResponse.statusCode): \(errorMsg)")
            throw DeepgramError.httpError(httpResponse.statusCode, errorMsg)
        }

        let deepgramResponse = try JSONDecoder().decode(DeepgramResponse.self, from: data)

        guard let transcript = deepgramResponse.transcript, !transcript.isEmpty else {
            NSLog("⚠️ Пустой транскрипт")
            throw DeepgramError.noTranscript
        }

        NSLog("✅ Результат: \(transcript)")
        return transcript
    }
}

// MARK: - SwiftUI Previews
#Preview("ParakeetModelStatus") {
    VStack(alignment: .leading, spacing: 8) {
        Text(ParakeetModelStatus.notChecked.displayText)
        Text(ParakeetModelStatus.notDownloaded.displayText)
        Text(ParakeetModelStatus.downloading.displayText)
        Text(ParakeetModelStatus.loading.displayText)
        Text(ParakeetModelStatus.ready.displayText)
        Text(ParakeetModelStatus.error("Test error").displayText)
    }
    .padding()
    .background(Color.black)
    .foregroundColor(.white)
}

#Preview("ASRProviderType") {
    VStack(alignment: .leading, spacing: 8) {
        ForEach(ASRProviderType.allCases, id: \.rawValue) { provider in
            VStack(alignment: .leading) {
                Text(provider.displayName)
                    .font(.headline)
                Text(provider.description)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
    .padding()
    .background(Color.black)
    .foregroundColor(.white)
}
