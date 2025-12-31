//
//  Settings.swift
//  Dictum
//
//  Настройки приложения: менеджер, модели и UI
//

import SwiftUI
import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Deepgram Model Type
enum DeepgramModelType: String, CaseIterable {
    case nova3 = "nova-3"
    case nova2 = "nova-2"

    var displayName: String {
        switch self {
        case .nova3: return "Nova-3"
        case .nova2: return "Nova-2"
        }
    }

    var price: String {
        switch self {
        case .nova3: return "$0.0043/мин"
        case .nova2: return "$0.0040/мин"
        }
    }

    var menuDisplayName: String {
        "\(displayName) · \(price)"
    }

    var isRecommended: Bool {
        self == .nova3
    }
}

// MARK: - Config Export/Import

struct DictumConfig: Codable {
    let version: String
    let appVersion: String
    let exportDate: Date

    var settings: ConfigSettings       // ВСЕГДА экспортируется (основные настройки + хоткеи)
    var aiSettings: AISettings?        // Опционально: AI промпты
    var prompts: ConfigPrompts?        // Опционально: сниппеты (WB/RU/EN/CH + кастомные)
    var history: [HistoryItem]?        // Опционально: история заметок

    struct ConfigSettings: Codable {
        // General
        var hotkeyEnabled: Bool
        var soundEnabled: Bool
        var preferredLanguage: String
        var maxHistoryItems: Int
        var volumeReduction: Int
        var autoCheckUpdates: Bool

        // ASR
        var deepgramModel: String
        var highlightForeignWords: Bool
        var asrProviderType: String
        var audioModeEnabled: Bool

        // AI (базовое - вкл/выкл и модели)
        var aiEnabled: Bool
        var selectedGeminiModel: String
        var selectedGeminiModelForAI: String

        // Screenshot
        var screenshotFeatureEnabled: Bool

        // Hotkeys (всегда экспортируются)
        var toggleHotkey: HotkeyConfig
        var screenshotHotkey: HotkeyConfig
    }

    struct AISettings: Codable {
        // AI промпты (опционально экспортируются)
        var enhanceSystemPrompt: String
        var llmProcessingPrompt: String
        var llmAdditionalInstructions: String
    }

    struct ConfigPrompts: Codable {
        var wb: String
        var ru: String
        var en: String
        var ch: String
        var custom: [CustomPrompt]
    }

    static let currentVersion = "1.0"
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject, @unchecked Sendable {
    static let shared = SettingsManager()

    // Fix 7: Async UserDefaults saves to prevent UI blocking
    @Published var hotkeyEnabled: Bool {
        didSet {
            let value = hotkeyEnabled
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.hotkeyEnabled")
            }
        }
    }
    @Published var soundEnabled: Bool {
        didSet {
            let value = soundEnabled
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.soundEnabled")
            }
        }
    }
    @Published var preferredLanguage: String {
        didSet {
            let value = preferredLanguage
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.preferredLanguage")
            }
        }
    }
    @Published var maxHistoryItems: Int {
        didSet {
            let value = maxHistoryItems
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.maxHistoryItems")
            }
        }
    }
    @Published var toggleHotkey: HotkeyConfig {
        didSet { saveHotkey() }
    }
    @Published var audioModeEnabled: Bool {
        didSet {
            // Синхронная запись — критическая настройка, должна сохраняться немедленно
            UserDefaults.standard.set(audioModeEnabled, forKey: "settings.audioModeEnabled")
            UserDefaults.standard.synchronize()
        }
    }
    @Published var deepgramModel: String {
        didSet {
            let value = deepgramModel
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.deepgramModel")
            }
        }
    }
    @Published var highlightForeignWords: Bool {
        didSet {
            let value = highlightForeignWords
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.highlightForeignWords")
            }
        }
    }

    // Screenshot feature
    @Published var screenshotFeatureEnabled: Bool {
        didSet {
            let value = screenshotFeatureEnabled
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.screenshotFeatureEnabled")
            }
        }
    }
    @Published var screenshotHotkey: HotkeyConfig {
        didSet { saveScreenshotHotkey() }
    }
    @Published var screenshotSavePath: String {
        didSet {
            UserDefaults.standard.set(screenshotSavePath, forKey: "settings.screenshotSavePath")
        }
    }

    // Gemini API key status
    @Published var hasGeminiAPIKey: Bool = false

    // AI функции включены/выключены
    @Published var aiEnabled: Bool {
        didSet {
            let value = aiEnabled
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.aiEnabled")
            }
        }
    }

    @Published var selectedGeminiModel: GeminiModel {
        didSet {
            let value = selectedGeminiModel.rawValue
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.geminiModel")
            }
        }
    }

    @Published var selectedGeminiModelForAI: GeminiModel {
        didSet {
            let value = selectedGeminiModelForAI.rawValue
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.geminiModelForAI")
            }
        }
    }

    // Дефолтный системный промпт для "Улучшить через ИИ"
    static let defaultEnhanceSystemPrompt = """
Ты - помощник для улучшения текста. Пользователь дает тебе текст и инструкции как его обработать.

Правила:
1. Верни ТОЛЬКО обработанный текст
2. Не добавляй пояснения, комментарии или кавычки
3. Сохраняй форматирование если не просят иначе
"""

    // Системный промпт для "Улучшить через ИИ"
    @Published var enhanceSystemPrompt: String {
        didSet {
            let value = enhanceSystemPrompt
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.enhanceSystemPrompt")
            }
        }
    }

    @Published var volumeReduction: Int {
        didSet {
            let value = volumeReduction
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.volumeReduction")
            }
        }
    }

    // Settings window state
    @Published var settingsWindowWasOpen: Bool {
        didSet {
            let value = settingsWindowWasOpen
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.windowWasOpen")
            }
        }
    }
    @Published var lastSettingsTab: String {
        didSet {
            let value = lastSettingsTab
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.lastTab")
            }
        }
    }

    // Onboarding completed flag
    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "settings.onboardingCompleted")
        }
    }

    // Текущий шаг onboarding (для восстановления при перезапуске)
    @Published var currentOnboardingStep: Int {
        didSet {
            UserDefaults.standard.set(currentOnboardingStep, forKey: "settings.currentOnboardingStep")
        }
    }

    // Custom prompts for each language mode
    @Published var promptWB: String {
        didSet {
            let value = promptWB
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "com.dictum.prompt.wb")
            }
        }
    }
    @Published var promptRU: String {
        didSet {
            let value = promptRU
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "com.dictum.prompt.ru")
            }
        }
    }
    @Published var promptEN: String {
        didSet {
            let value = promptEN
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "com.dictum.prompt.en")
            }
        }
    }
    @Published var promptCH: String {
        didSet {
            let value = promptCH
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "com.dictum.prompt.ch")
            }
        }
    }

    // ASR провайдер: локальная модель или Deepgram
    @Published var asrProviderType: ASRProviderType {
        didSet {
            let value = asrProviderType.rawValue
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.asrProviderType")
            }
        }
    }

    // LLM обработка для локальной модели
    @Published var llmProcessingPrompt: String {
        didSet {
            let value = llmProcessingPrompt
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.llmProcessingPrompt")
            }
        }
    }

    @Published var llmAdditionalInstructions: String {
        didSet {
            let value = llmAdditionalInstructions
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.llmAdditionalInstructions")
            }
        }
    }

    // Максимальное количество токенов в ответе LLM (512-8192)
    @Published var maxOutputTokens: Int {
        didSet {
            let value = maxOutputTokens
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.maxOutputTokens")
            }
        }
    }

    // Автопроверка обновлений
    @Published var autoCheckUpdates: Bool {
        didSet {
            let value = autoCheckUpdates
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.autoCheckUpdates")
            }
        }
    }

    static let defaultLLMPrompt = """
Ты — профессиональный редактор текста, полученного через систему распознавания речи (ASR). Твоя задача — превратить поток слов в чистовой, структурированный текст.

Следуй строгим правилам:
1. ПУНКТУАЦИЯ И ГРАММАТИКА: Расставь знаки препинания, исправь орфографические ошибки и опечатки. Начало предложений пиши с заглавной буквы.
2. ИНОСТРАННЫЕ СЛОВА: Если встречаются английские слова в русской транскрипции (например, "халло", "ворк", "джейсон"), пиши их на английском ("Hello", "work", "JSON"), если это уместно по контексту.
3. СТРУКТУРА: Если в тексте есть логическое перечисление задач или пунктов, оформляй их нумерованным списком (1., 2., 3.).
4. ТЕХНИЧЕСКИЕ ДАННЫЕ: Если диктуется код, JSON или SQL, форматируй их в соответствующие блоки кода или валидный синтаксис.
5. ФОРМАТ ВЫВОДА: Верни ТОЛЬКО обработанный текст. Не добавляй никаких вступлений ("Вот ваш текст"), комментариев или markdown-кавычек, если они не являются частью кода.
"""

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
        self.promptWB = UserDefaults.standard.string(forKey: "com.dictum.prompt.wb") ?? "Перефразируй этот текст на том же языке, сделав его более вежливым и профессиональным. Используй разговорный, но уважительный тон. Исправь все грамматические и пунктуационные ошибки. Текст должен показывать, что мы ценим клиента и хорошо к нему относимся. Сохрани суть сообщения, но сделай его максимально приятным для получателя:"

        self.promptRU = UserDefaults.standard.string(forKey: "com.dictum.prompt.ru") ?? "Переведи следующий текст на русский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель русского языка:"

        self.promptEN = UserDefaults.standard.string(forKey: "com.dictum.prompt.en") ?? "Переведи следующий текст на английский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель английского языка:"

        self.promptCH = UserDefaults.standard.string(forKey: "com.dictum.prompt.ch") ?? "Переведи следующий текст на китайский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель китайского языка:"

        // Загружаем хоткей
        if let data = UserDefaults.standard.data(forKey: "settings.toggleHotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.toggleHotkey = hotkey
        } else {
            self.toggleHotkey = HotkeyConfig.defaultToggle
        }

        // Screenshot feature: по умолчанию включена
        self.screenshotFeatureEnabled = UserDefaults.standard.object(forKey: "settings.screenshotFeatureEnabled") as? Bool ?? true

        // Load screenshot hotkey (default: Cmd+Shift+D)
        if let data = UserDefaults.standard.data(forKey: "settings.screenshotHotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.screenshotHotkey = hotkey
        } else {
            // Key code 2 = "D", Cmd+Shift modifiers
            self.screenshotHotkey = HotkeyConfig(keyCode: 2, modifiers: UInt32(cmdKey | shiftKey))
        }

        // Screenshot save path: по умолчанию ~/Documents/Screenshots
        self.screenshotSavePath = UserDefaults.standard.string(forKey: "settings.screenshotSavePath") ?? "~/Documents/Screenshots"

        // Settings window state
        self.settingsWindowWasOpen = UserDefaults.standard.bool(forKey: "settings.windowWasOpen")
        self.lastSettingsTab = UserDefaults.standard.string(forKey: "settings.lastTab") ?? "general"

        // Onboarding: по умолчанию не пройден (false)
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "settings.onboardingCompleted")
        self.currentOnboardingStep = UserDefaults.standard.integer(forKey: "settings.currentOnboardingStep")

        // ASR провайдер: по умолчанию локальная модель (работает офлайн)
        if let rawValue = UserDefaults.standard.string(forKey: "settings.asrProviderType"),
           let providerType = ASRProviderType(rawValue: rawValue) {
            self.asrProviderType = providerType
        } else {
            self.asrProviderType = .local  // По умолчанию локальная модель
        }

        // LLM обработка для локальной модели
        self.llmProcessingPrompt = UserDefaults.standard.string(forKey: "settings.llmProcessingPrompt") ?? Self.defaultLLMPrompt
        self.llmAdditionalInstructions = UserDefaults.standard.string(forKey: "settings.llmAdditionalInstructions") ?? ""

        // Максимальное количество токенов в ответе LLM: по умолчанию 10000
        self.maxOutputTokens = UserDefaults.standard.object(forKey: "settings.maxOutputTokens") as? Int ?? 10000

        // Gemini model для локальной модели (Speech): по умолчанию 2.5 Flash
        if let rawValue = UserDefaults.standard.string(forKey: "settings.geminiModel"),
           let model = GeminiModel(rawValue: rawValue) {
            self.selectedGeminiModel = model
        } else {
            self.selectedGeminiModel = .gemini25Flash
        }

        // Gemini model для AI функций: по умолчанию 2.5 Flash
        if let rawValue = UserDefaults.standard.string(forKey: "settings.geminiModelForAI"),
           let model = GeminiModel(rawValue: rawValue) {
            self.selectedGeminiModelForAI = model
        } else {
            self.selectedGeminiModelForAI = .gemini25Flash
        }

        // Системный промпт для "Улучшить через ИИ"
        self.enhanceSystemPrompt = UserDefaults.standard.string(forKey: "settings.enhanceSystemPrompt") ?? Self.defaultEnhanceSystemPrompt

        // Volume reduction: процент снижения громкости (по умолчанию 50%)
        self.volumeReduction = UserDefaults.standard.object(forKey: "settings.volumeReduction") as? Int ?? 50

        // Автопроверка обновлений: по умолчанию включена
        self.autoCheckUpdates = UserDefaults.standard.object(forKey: "settings.autoCheckUpdates") as? Bool ?? true
    }

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(toggleHotkey) {
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(data, forKey: "settings.toggleHotkey")
            }
        }
    }

    private func saveScreenshotHotkey() {
        if let data = try? JSONEncoder().encode(screenshotHotkey) {
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(data, forKey: "settings.screenshotHotkey")
            }
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

    // MARK: - Deepgram API Key (wrappers for UI)
    var hasDeepgramAPIKey: Bool {
        return hasAPIKey()
    }

    func saveDeepgramAPIKey(_ key: String) -> Bool {
        return saveAPIKey(key)
    }

    func getDeepgramAPIKeyMasked() -> String {
        return getAPIKeyMasked()
    }

    // MARK: - Export/Import Config

    func exportConfig(
        includeHistory: Bool = true,
        includeAIFunctions: Bool = true,
        includeSnippets: Bool = true
    ) -> DictumConfig {
        return DictumConfig(
            version: DictumConfig.currentVersion,
            appVersion: "1.9",
            exportDate: Date(),
            // Основные настройки + хоткеи (ВСЕГДА экспортируются)
            settings: DictumConfig.ConfigSettings(
                hotkeyEnabled: hotkeyEnabled,
                soundEnabled: soundEnabled,
                preferredLanguage: preferredLanguage,
                maxHistoryItems: maxHistoryItems,
                volumeReduction: volumeReduction,
                autoCheckUpdates: autoCheckUpdates,
                deepgramModel: deepgramModel,
                highlightForeignWords: highlightForeignWords,
                asrProviderType: asrProviderType.rawValue,
                audioModeEnabled: audioModeEnabled,
                aiEnabled: aiEnabled,
                selectedGeminiModel: selectedGeminiModel.rawValue,
                selectedGeminiModelForAI: selectedGeminiModelForAI.rawValue,
                screenshotFeatureEnabled: screenshotFeatureEnabled,
                toggleHotkey: toggleHotkey,
                screenshotHotkey: screenshotHotkey
            ),
            // AI промпты (опционально)
            aiSettings: includeAIFunctions ? DictumConfig.AISettings(
                enhanceSystemPrompt: enhanceSystemPrompt,
                llmProcessingPrompt: llmProcessingPrompt,
                llmAdditionalInstructions: llmAdditionalInstructions
            ) : nil,
            // Сниппеты (опционально)
            prompts: includeSnippets ? DictumConfig.ConfigPrompts(
                wb: promptWB,
                ru: promptRU,
                en: promptEN,
                ch: promptCH,
                custom: PromptsManager.shared.prompts.filter { !$0.isSystem }
            ) : nil,
            // История (опционально)
            history: includeHistory ? HistoryManager.shared.history : nil
        )
    }

    func importConfig(_ config: DictumConfig) {
        // === ОСНОВНЫЕ НАСТРОЙКИ (ВСЕГДА применяются) ===

        // General
        hotkeyEnabled = config.settings.hotkeyEnabled
        soundEnabled = config.settings.soundEnabled
        preferredLanguage = config.settings.preferredLanguage
        maxHistoryItems = config.settings.maxHistoryItems
        volumeReduction = config.settings.volumeReduction
        autoCheckUpdates = config.settings.autoCheckUpdates

        // ASR
        deepgramModel = config.settings.deepgramModel
        highlightForeignWords = config.settings.highlightForeignWords
        if let asr = ASRProviderType(rawValue: config.settings.asrProviderType) {
            asrProviderType = asr
        }
        audioModeEnabled = config.settings.audioModeEnabled

        // AI (базовое)
        aiEnabled = config.settings.aiEnabled
        if let model = GeminiModel(rawValue: config.settings.selectedGeminiModel) {
            selectedGeminiModel = model
        }
        if let modelAI = GeminiModel(rawValue: config.settings.selectedGeminiModelForAI) {
            selectedGeminiModelForAI = modelAI
        }

        // Screenshot
        screenshotFeatureEnabled = config.settings.screenshotFeatureEnabled

        // Hotkeys (теперь в settings)
        toggleHotkey = config.settings.toggleHotkey
        screenshotHotkey = config.settings.screenshotHotkey

        // === AI ПРОМПТЫ (опционально) ===
        if let ai = config.aiSettings {
            enhanceSystemPrompt = ai.enhanceSystemPrompt
            llmProcessingPrompt = ai.llmProcessingPrompt
            llmAdditionalInstructions = ai.llmAdditionalInstructions
        }

        // === СНИППЕТЫ (опционально) ===
        if let prompts = config.prompts {
            promptWB = prompts.wb
            promptRU = prompts.ru
            promptEN = prompts.en
            promptCH = prompts.ch

            // Custom prompts — мержим с существующими
            for customPrompt in prompts.custom {
                if PromptsManager.shared.prompts.contains(where: { $0.id == customPrompt.id }) {
                    PromptsManager.shared.updatePrompt(customPrompt)
                } else {
                    PromptsManager.shared.addPrompt(customPrompt)
                }
            }
        }

        // === ИСТОРИЯ (опционально) ===
        if let history = config.history {
            HistoryManager.shared.history = history
        }
    }

    @MainActor func saveConfigToFile(
        includeHistory: Bool = true,
        includeAIFunctions: Bool = true,
        includeSnippets: Bool = true
    ) -> URL? {
        let config = exportConfig(
            includeHistory: includeHistory,
            includeAIFunctions: includeAIFunctions,
            includeSnippets: includeSnippets
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(config) else { return nil }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "dictum-config-\(dateStr).json"
        panel.title = "Экспорт конфигурации"
        panel.message = "Выберите место для сохранения"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try data.write(to: url)
            return url
        } catch {
            print("❌ Ошибка сохранения: \(error)")
            return nil
        }
    }

    @MainActor func loadConfigFromFile() -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Импорт конфигурации"
        panel.message = "Выберите файл конфигурации"

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(DictumConfig.self, from: data)
            importConfig(config)
            return true
        } catch {
            print("❌ Ошибка загрузки: \(error)")
            return false
        }
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
class DeepgramManagementService: @unchecked Sendable {
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

        guard var components = URLComponents(string: "\(baseURL)/projects/\(projectId)/requests") else {
            throw DeepgramManagementError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]

        guard let url = components.url else {
            throw DeepgramManagementError.invalidResponse
        }
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

    // Fix 17: Track async tasks for cancellation
    private var loadTask: Task<Void, Never>?

    deinit {
        loadTask?.cancel()
    }

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

        // Fix 17: Cancel previous task and track new one
        loadTask?.cancel()
        loadTask = Task {
            await loadAllData(apiKey: apiKey)
        }
    }
}

// MARK: - Launch At Login Manager
class LaunchAtLoginManager: @unchecked Sendable {
    static let shared = LaunchAtLoginManager()

    private let launchAgentPath: String
    private let bundleIdentifier = "com.dictum.app"

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

        // H2: Логируем ошибки FileManager
        do {
            try FileManager.default.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        } catch {
            NSLog("❌ Ошибка создания LaunchAgents: %@", error.localizedDescription)
            return
        }

        do {
            try plistContent.write(toFile: launchAgentPath, atomically: true, encoding: .utf8)
        } catch {
            NSLog("❌ Ошибка записи plist: %@", error.localizedDescription)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", launchAgentPath]
        do {
            try process.run()
        } catch {
            NSLog("❌ Ошибка launchctl load: %@", error.localizedDescription)
        }
    }

    private func disableLaunchAtLogin() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchAgentPath]
        try? process.run()

        // Fix 14: Polling with timeout instead of waitUntilExit()
        let timeout: TimeInterval = 5.0
        let start = Date()
        while process.isRunning && Date().timeIntervalSince(start) < timeout {
            usleep(100_000) // 100ms
        }
        if process.isRunning {
            NSLog("⚠️ launchctl timeout, terminating")
            process.terminate()
        }

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
    static let openSettingsToAI = Notification.Name("openSettingsToAI")
    static let toggleHistoryModal = Notification.Name("toggleHistoryModal")
    static let historyItemSelected = Notification.Name("historyItemSelected")
    static let toggleRecording = Notification.Name("toggleRecording")
    static let recordingStateChanged = Notification.Name("recordingStateChanged")
    // Модалки CMD+1/2/3/4
    static let togglePromptsModal = Notification.Name("togglePromptsModal")
    static let toggleSnippetsModal = Notification.Name("toggleSnippetsModal")
    static let toggleNotesModal = Notification.Name("toggleNotesModal")
    static let promptSelected = Notification.Name("promptSelected")
    static let snippetSelected = Notification.Name("snippetSelected")
    static let noteSelected = Notification.Name("noteSelected")
    // TextSwitcher
    static let textSwitcherToggled = Notification.Name("textSwitcherToggled")
    // Адаптивная высота окна
    static let inputModalHeightChanged = Notification.Name("inputModalHeightChanged")
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

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        // Модификаторы как отдельные клавиши (keyCode без модификаторов)
        // Правый Option: 61, Левый Option: 58
        // Правый Shift: 60, Левый Shift: 56
        // Правый Command: 54, Левый Command: 55
        // Правый Control: 62, Левый Control: 59
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

        // Проверяем что это нажатие (флаг появился), а не отпускание
        let hasModifier = event.modifierFlags.contains(.command) ||
                          event.modifierFlags.contains(.shift) ||
                          event.modifierFlags.contains(.option) ||
                          event.modifierFlags.contains(.control)

        if modifierKeyCodes.contains(event.keyCode) && hasModifier {
            // Записываем модификатор как отдельную клавишу (modifiers = 0)
            onHotkeyRecorded?(event.keyCode, 0)
        }
    }
}

// MARK: - Settings View

enum SettingsTab: String, CaseIterable {
    case general = "Основные"
    case hotkeys = "Хоткеи"
    case textSwitcher = "Свитчер"
    case features = "Инструменты"
    case speech = "Диктовка"
    case enhancer = "Улучшайзер"
    case ai = "AI промпты"
    case snippets = "Сниппеты"
    case updates = "Обновления"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .textSwitcher: return "keyboard.badge.ellipsis"
        case .features: return "camera.fill"
        case .speech: return "waveform"
        case .enhancer: return "wand.and.stars"
        case .ai: return "sparkles"
        case .snippets: return "text.quote"
        case .updates: return "arrow.triangle.2.circlepath"
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
            .background(isSelected ? DesignSystem.Colors.hoverBackground : Color.clear)
            .cornerRadius(8)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 8)
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = {
        let savedTab = SettingsManager.shared.lastSettingsTab
        return SettingsTab.allCases.first { $0.rawValue == savedTab } ?? .general
    }()
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled
    @State private var hasInputMonitoring: Bool = PermissionManager.shared.hasInputMonitoring()
    @State private var hasAccessibility: Bool = PermissionManager.shared.hasAccessibility()
    @State private var hasMicrophonePermission: Bool = PermissionManager.shared.hasMicrophone()
    @State private var hasScreenRecordingPermission: Bool = PermissionManager.shared.hasScreenRecording()
    @State private var currentHotkey: HotkeyConfig = SettingsManager.shared.toggleHotkey
    @State private var isRecordingHotkey: Bool = false
    @State private var isRecordingScreenshotHotkey: Bool = false
    @State private var screenshotHotkey: HotkeyConfig = SettingsManager.shared.screenshotHotkey
    @ObservedObject private var settings = SettingsManager.shared
    @StateObject private var textSwitcherManager = TextSwitcherManager.shared
    @StateObject private var userExceptionsManager = UserExceptionsManager.shared
    @StateObject private var forcedConversionsManager = ForcedConversionsManager.shared
    // Config export/import (все опции включены по умолчанию)
    @State private var exportHistory: Bool = true         // История заметок
    @State private var exportAIFunctions: Bool = true     // AI промпты
    @State private var exportSnippets: Bool = true        // Сниппеты (WB/RU/EN/CH + кастомные)
    @State private var exportMessage: String = ""

    // Функции проверки теперь в PermissionManager

    var body: some View {
        HStack(spacing: 0) {
            // === SIDEBAR (слева) ===
            VStack(alignment: .leading, spacing: 4) {
                // Отступ сверху для titlebar
                Spacer().frame(height: 36)

                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                        SettingsManager.shared.lastSettingsTab = tab.rawValue
                    }
                }

                Spacer()

                // Версия и проверка разрешений
                VStack(alignment: .leading, spacing: 8) {
                    Button("Проверить разрешения") {
                        hasInputMonitoring = PermissionManager.shared.hasInputMonitoring()
                        hasAccessibility = PermissionManager.shared.hasAccessibility()
                        hasMicrophonePermission = PermissionManager.shared.hasMicrophone()
                        hasScreenRecordingPermission = PermissionManager.shared.hasScreenRecording()
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .buttonStyle(PlainButtonStyle())

                    #if DEBUG
                    let buildType = "Debug"
                    #else
                    let buildType = "Release"
                    #endif
                    Text("Dictum v\(AppConfig.version) (\(buildType))")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .frame(width: 180)
            .background(Color.black.opacity(0.3))
            .overlay(alignment: .trailing) {
                // Разделитель (от края до края по высоте)
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
            }

            // === CONTENT (справа) ===
            VStack(spacing: 0) {
                // Заголовок таба (справа)
                HStack {
                    Spacer()
                    Image(systemName: selectedTab.icon)
                        .font(.system(size: 16))
                    Text(selectedTab.rawValue)
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.top, 36)
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
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.window))
        .ignoresSafeArea(.all, edges: .top)
        .onAppear {
            hasInputMonitoring = PermissionManager.shared.hasInputMonitoring()
            hasAccessibility = PermissionManager.shared.hasAccessibility()
            hasMicrophonePermission = PermissionManager.shared.hasMicrophone()
            hasScreenRecordingPermission = PermissionManager.shared.hasScreenRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let newInputMonitoring = PermissionManager.shared.hasInputMonitoring()
            let newAccessibility = PermissionManager.shared.hasAccessibility()
            NSLog("🪟 SettingsView.onReceive(didBecomeActive): inputMonitoring=%@, accessibility=%@",
                  newInputMonitoring ? "true" : "false",
                  newAccessibility ? "true" : "false")

            // Если Input Monitoring изменился с false на true — уведомить для перезапуска CGEventTap
            if newInputMonitoring && !hasInputMonitoring {
                NSLog("📢 SettingsView: Input Monitoring granted! Отправляю accessibilityStatusChanged")
                NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
            }
            // Если Accessibility изменился с false на true — уведомить DictumApp для перерегистрации хоткеев
            if newAccessibility && !hasAccessibility {
                NSLog("📢 SettingsView: отправляю accessibilityStatusChanged")
                NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
            }

            hasInputMonitoring = newInputMonitoring
            hasAccessibility = newAccessibility
            hasMicrophonePermission = PermissionManager.shared.hasMicrophone()
            hasScreenRecordingPermission = PermissionManager.shared.hasScreenRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsToAI)) { _ in
            selectedTab = .ai
        }
    }

    @ViewBuilder
    var tabContent: some View {
        switch selectedTab {
        case .general: generalTabContent
        case .hotkeys: hotkeysTabContent
        case .textSwitcher: textSwitcherTabContent
        case .features: featuresTabContent
        case .speech: speechTabContent
        case .enhancer: enhancerTabContent
        case .ai: aiTabContent
        case .snippets: snippetsTabContent
        case .updates: updatesTabContent
        }
    }

    // === TAB: ОСНОВНЫЕ ===
    var generalTabContent: some View {
        VStack(spacing: 0) {
            // Секция: Разрешения
            SettingsSection(title: "РАЗРЕШЕНИЯ") {
                VStack(alignment: .leading, spacing: 12) {
                    // 1. Accessibility — обязательный
                    PermissionRow(
                        icon: "hand.raised.fill",
                        title: "Универсальный доступ",
                        subtitle: "Для вставки текста в другие приложения",
                        isGranted: hasAccessibility,
                        action: {
                            // Системный диалог сам откроет Settings если нужно
                            // Не дублируем открытие Settings вручную!
                            PermissionManager.shared.requestAccessibility()

                            // Polling каждую секунду в течение 30 секунд
                            for delay in stride(from: 1.0, through: 30.0, by: 1.0) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    let newState = PermissionManager.shared.hasAccessibility()
                                    // Если статус изменился с false на true — уведомить DictumApp для перерегистрации хоткеев
                                    if newState && !hasAccessibility {
                                        NSLog("📢 Settings polling (%.0f сек): отправляю accessibilityStatusChanged", delay)
                                        NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
                                    }
                                    hasAccessibility = newState
                                }
                            }
                        }
                    )

                    Divider().background(Color.white.opacity(0.1))

                    // 2. Microphone — обязательный
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Микрофон",
                        subtitle: "Для записи голосовых заметок",
                        isGranted: hasMicrophonePermission,
                        action: {
                            // Умный запрос: диалог если не определено, Settings если отказано
                            PermissionManager.shared.requestMicrophone { granted in
                                Task { @MainActor in
                                    hasMicrophonePermission = granted
                                }
                            }

                            // Polling если юзер даст разрешение через System Settings
                            for delay in stride(from: 1.0, through: 30.0, by: 1.0) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    Task { @MainActor in
                                        hasMicrophonePermission = PermissionManager.shared.hasMicrophone()
                                    }
                                }
                            }
                        }
                    )

                    Divider().background(Color.white.opacity(0.1))

                    // 3. Input Monitoring — после основных (системный диалог о рестарте можно игнорировать)
                    PermissionRow(
                        icon: "keyboard",
                        title: "Мониторинг ввода",
                        subtitle: "Для глобальных хоткеев (работает сразу!)",
                        isGranted: hasInputMonitoring,
                        action: {
                            PermissionManager.shared.requestInputMonitoring()

                            // Polling каждую секунду в течение 30 секунд
                            for delay in stride(from: 1.0, through: 30.0, by: 1.0) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    let newState = PermissionManager.shared.hasInputMonitoring()
                                    // Если Input Monitoring изменился с false на true — уведомить для перезапуска CGEventTap
                                    if newState && !hasInputMonitoring {
                                        NSLog("📢 Settings polling (%.0f сек): Input Monitoring granted!", delay)
                                        NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
                                    }
                                    hasInputMonitoring = newState
                                }
                            }
                        }
                    )

                    // 4. Screen Recording — опциональный (только если Screenshots feature включена)
                    if SettingsManager.shared.screenshotFeatureEnabled {
                        Divider().background(Color.white.opacity(0.1))

                        PermissionRow(
                            icon: "camera.metering.matrix",
                            title: "Запись экрана",
                            subtitle: "Для создания скриншотов",
                            isGranted: hasScreenRecordingPermission,
                            action: {
                                // Триггерим capture чтобы приложение появилось в списке
                                // + открываем Settings
                                PermissionManager.shared.requestScreenRecording()

                                // Polling для проверки реального статуса разрешения
                                for delay in stride(from: 1.0, through: 30.0, by: 1.0) {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                        hasScreenRecordingPermission = PermissionManager.shared.hasScreenRecording()
                                    }
                                }
                            }
                        )
                    }

                    if !hasInputMonitoring || !hasAccessibility || !hasMicrophonePermission ||
                       (SettingsManager.shared.screenshotFeatureEnabled && !hasScreenRecordingPermission) {
                        Divider().background(Color.white.opacity(0.1))

                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                            Text("Некоторые функции могут работать некорректно без необходимых разрешений")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(DesignSystem.Colors.deepgramOrange)
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
            }

            // Секция: Автозапуск
            SettingsSection(title: "ЗАПУСК") {
                SettingsRow(
                    title: "Запускать при входе в систему",
                    subtitle: "Dictum будет автоматически запускаться при старте macOS"
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(TahoeToggleStyle())
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in
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
                    Toggle("", isOn: $settings.soundEnabled)
                        .toggleStyle(TahoeToggleStyle())
                        .labelsHidden()
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
                        .toggleStyle(TahoeToggleStyle())
                        .labelsHidden()
                }
            }

            // Секция: Громкость при записи голоса (слайдер)
            SettingsSection(title: "ГРОМКОСТЬ ПРИ ЗАПИСИ ГОЛОСА") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Text("0%")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)

                        Slider(
                            value: Binding(
                                get: { Double(settings.volumeReduction) },
                                set: { settings.volumeReduction = Int($0) }
                            ),
                            in: 0...100
                        )
                        .tint(DesignSystem.Colors.accent)

                        Text("100%")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }

                    Text("0% = не глушить, 100% = полная тишина")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.7))
                }
                .padding(.vertical, 12)
            }

            // Секция: Бекап конфигурации (ПОСЛЕДНЯЯ)
            SettingsSection(title: "БЕКАП КОНФИГУРАЦИИ") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Экспортируйте конфигурацию в JSON-файл. Основные настройки и хоткеи всегда включены. API ключи не сохраняются.")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)

                    // Чекбоксы для дополнительных секций
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("История заметок", isOn: $exportHistory)
                            .toggleStyle(CheckboxToggleStyle())
                        Toggle("AI функции", isOn: $exportAIFunctions)
                            .toggleStyle(CheckboxToggleStyle())
                        Toggle("Сниппеты", isOn: $exportSnippets)
                            .toggleStyle(CheckboxToggleStyle())
                    }
                    .font(.system(size: 13))

                    HStack(spacing: 12) {
                        Button(action: {
                            if let url = settings.saveConfigToFile(
                                includeHistory: exportHistory,
                                includeAIFunctions: exportAIFunctions,
                                includeSnippets: exportSnippets
                            ) {
                                exportMessage = "✓ Сохранено: \(url.lastPathComponent)"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    exportMessage = ""
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Экспорт")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(DesignSystem.Colors.accent)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            if settings.loadConfigFromFile() {
                                exportMessage = "✓ Конфигурация загружена"
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    exportMessage = ""
                                }
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Импорт")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Spacer()

                        if !exportMessage.isEmpty {
                            Text(exportMessage)
                                .font(.system(size: 11))
                                .foregroundColor(DesignSystem.Colors.accent)
                        }
                    }
                }
                .padding(.vertical, 8)
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
                            Text("Открыть/закрыть приложение")
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
                        .onChange(of: currentHotkey) { _, newValue in
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
                    Text("Сбросить (Right ⌥)")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // === TAB: СВИТЧЕР ===
    var textSwitcherTabContent: some View {
        VStack(spacing: 0) {
            // Главный тумблер
            SettingsSection(title: "АВТОИСПРАВЛЕНИЕ РАСКЛАДКИ") {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TextSwitcher")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            Text("Автоматически исправляет текст, набранный в неправильной раскладке (ghbdtn → привет)")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: $textSwitcherManager.isEnabled)
                        .toggleStyle(TahoeToggleStyle())
                        .labelsHidden()
                    }
                    .padding(.vertical, 8)

                    if textSwitcherManager.isEnabled {
                        Divider().background(Color.white.opacity(0.1))

                        // Тумблер обучения
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Обучение")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                Text("Сохранять слова при ручной смене раскладки (⌘+⇧+Space)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Toggle("", isOn: $textSwitcherManager.isLearningEnabled)
                                .toggleStyle(TahoeToggleStyle())
                                .labelsHidden()
                        }
                        .padding(.vertical, 4)

                        Divider().background(Color.white.opacity(0.1))

                        // Инструкция
                        HStack {
                            Image(systemName: "keyboard")
                                .font(.system(size: 14))
                                .foregroundColor(DesignSystem.Colors.accent)
                            Text("⌘+⇧+Space — ручная смена раскладки текста")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Статистика (только если включено)
            if textSwitcherManager.isEnabled {
                SettingsSection(title: "СТАТИСТИКА") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Автоисправлений")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(textSwitcherManager.autoSwitchCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.accent)
                        }

                        HStack {
                            Text("Ручных смен (⌘⌘)")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(textSwitcherManager.manualSwitchCount)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.accent)
                        }

                        HStack {
                            Text("Слов в обучении")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(userExceptionsManager.count)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.accent)
                        }

                        Divider().background(Color.white.opacity(0.1))

                        Button(action: {
                            textSwitcherManager.resetStatistics()
                        }) {
                            Text("Сбросить статистику")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.vertical, 8)
                }
            }

            // Принудительные конвертации (белый список)
            if textSwitcherManager.isEnabled {
                SettingsSection(title: "ПРИНУДИТЕЛЬНЫЕ КОНВЕРТАЦИИ") {
                    VStack(spacing: 12) {
                        // Описание
                        Text("Слова в этом списке ВСЕГДА конвертируются. Приоритет выше словаря. 🔒 = жёсткое знание (3+ подтверждения)")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Список конвертаций (макс 10)
                        if !forcedConversionsManager.conversions.isEmpty {
                            ScrollView {
                                VStack(spacing: 4) {
                                    ForEach(forcedConversionsManager.conversions.prefix(10)) { conversion in
                                        HStack {
                                            // Иконка жёсткого знания
                                            if conversion.isHardKnowledge {
                                                Text("🔒")
                                                    .font(.system(size: 12))
                                            }

                                            // originalWord → convertedWord
                                            Text(conversion.originalWord)
                                                .font(.system(size: 13, design: .monospaced))
                                                .foregroundColor(.gray)

                                            Text("→")
                                                .font(.system(size: 13))
                                                .foregroundColor(.gray.opacity(0.5))

                                            Text(conversion.convertedWord)
                                                .font(.system(size: 13, design: .monospaced))
                                                .foregroundColor(DesignSystem.Colors.accent)

                                            Spacer()

                                            // Счётчик подтверждений
                                            Text("×\(conversion.confirmationCount)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray.opacity(0.6))

                                            Button(action: {
                                                forcedConversionsManager.removeConversion(id: conversion.id)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.gray.opacity(0.6))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)

                            if forcedConversionsManager.count > 10 {
                                Text("...и ещё \(forcedConversionsManager.count - 10) конвертаций")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Text("Пока нет принудительных конвертаций")
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.6))
                                .padding(.vertical, 8)
                        }

                        Divider().background(Color.white.opacity(0.1))

                        // Кнопка очистки
                        HStack {
                            Text("\(forcedConversionsManager.count) конвертаций (\(forcedConversionsManager.hardKnowledgeCount) 🔒)")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)

                            Spacer()

                            if !forcedConversionsManager.conversions.isEmpty {
                                Button(action: {
                                    forcedConversionsManager.clearAll()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Очистить")
                                    }
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            // Исключения (чёрный список)
            if textSwitcherManager.isEnabled {
                SettingsSection(title: "ИСКЛЮЧЕНИЯ (ЧЁРНЫЙ СПИСОК)") {
                    VStack(spacing: 12) {
                        // Описание
                        Text("Слова в этом списке НЕ конвертируются автоматически. Добавляются как результат ручного переключения (двойной ⌘).")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Список исключений (макс 10)
                        if !userExceptionsManager.exceptions.isEmpty {
                            ScrollView {
                                VStack(spacing: 4) {
                                    ForEach(userExceptionsManager.exceptions.prefix(10)) { exception in
                                        HStack {
                                            Text(exception.word)
                                                .font(.system(size: 13, design: .monospaced))
                                                .foregroundColor(.white)

                                            Spacer()

                                            Text(exception.reason == .autoLearned ? "авто" : "вручную")
                                                .font(.system(size: 10))
                                                .foregroundColor(.gray)

                                            Button(action: {
                                                userExceptionsManager.removeException(id: exception.id)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.gray.opacity(0.6))
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)

                            if userExceptionsManager.count > 10 {
                                Text("...и ещё \(userExceptionsManager.count - 10) слов")
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Text("Пока нет исключений")
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.6))
                                .padding(.vertical, 8)
                        }

                        Divider().background(Color.white.opacity(0.1))

                        // Кнопки экспорта/импорта/очистки
                        HStack(spacing: 12) {
                            Button(action: {
                                _ = userExceptionsManager.exportToFile()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Экспорт")
                                }
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Button(action: {
                                _ = userExceptionsManager.importFromFile()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Импорт")
                                }
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())

                            Spacer()

                            if !userExceptionsManager.exceptions.isEmpty {
                                Button(action: {
                                    // TODO: Показать подтверждение
                                    userExceptionsManager.clearAll()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "trash")
                                        Text("Очистить")
                                    }
                                    .font(.system(size: 12))
                                    .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // === TAB: ФИТЧИ ===
    var featuresTabContent: some View {
        VStack(spacing: 0) {
            SettingsSection(title: "СКРИНШОТЫ") {
                VStack(spacing: 16) {
                    // Toggle для включения/выключения
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Быстрые скриншоты")
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                            Text("Глобальный хоткей для создания скриншота. Путь копируется в буфер обмена")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: .init(
                            get: { SettingsManager.shared.screenshotFeatureEnabled },
                            set: { SettingsManager.shared.screenshotFeatureEnabled = $0 }
                        ))
                            .toggleStyle(TahoeToggleStyle())
                            .labelsHidden()
                    }
                    .padding(.vertical, 8)

                    // Выбор папки для сохранения (только если фича включена)
                    if SettingsManager.shared.screenshotFeatureEnabled {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Папка для сохранения")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                                Text(SettingsManager.shared.screenshotSavePath)
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignSystem.Colors.accent)
                                    .onTapGesture {
                                        let path = NSString(string: SettingsManager.shared.screenshotSavePath).expandingTildeInPath
                                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                    }
                            }
                            Spacer()
                            Button("Изменить") {
                                selectScreenshotFolder()
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                        }
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
                            .onChange(of: screenshotHotkey) { _, newValue in
                                SettingsManager.shared.screenshotHotkey = newValue
                                NotificationCenter.default.post(name: .screenshotHotkeyChanged, object: nil)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // === TAB: РЕЧЬ ===
    var speechTabContent: some View {
        VStack(spacing: 0) {
            ASRProviderSection()
        }
    }

    // === TAB: УЛУЧШАЙЗЕР ===
    var enhancerTabContent: some View {
        VStack(spacing: 0) {
            EnhancerSettingsSection()
        }
    }

    // === TAB: AI ===
    var aiTabContent: some View {
        VStack(spacing: 0) {
            AISettingsSection(aiEnabled: $settings.aiEnabled)
            if settings.aiEnabled {
                AIPromptsSection()
            }
        }
    }

    // === TAB: СНИППЕТЫ ===
    var snippetsTabContent: some View {
        VStack(spacing: 0) {
            SnippetsSettingsSection()
        }
    }

    // === TAB: ОБНОВЛЕНИЯ ===
    var updatesTabContent: some View {
        VStack(spacing: 0) {
            UpdatesSettingsSection()
        }
    }

    // MARK: - Screenshot Folder Picker
    @MainActor
    private func selectScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Выберите папку для скриншотов"
        panel.message = "Скриншоты будут сохраняться в выбранную папку"
        panel.prompt = "Выбрать"

        // Устанавливаем текущую папку как начальную
        let currentPath = NSString(string: SettingsManager.shared.screenshotSavePath).expandingTildeInPath
        panel.directoryURL = URL(fileURLWithPath: currentPath)

        if panel.runModal() == .OK, let url = panel.url {
            // Сохраняем путь с тильдой если это домашняя директория
            let homePath = FileManager.default.homeDirectoryForCurrentUser.path
            var newPath = url.path
            if newPath.hasPrefix(homePath) {
                newPath = "~" + newPath.dropFirst(homePath.count)
            }
            SettingsManager.shared.screenshotSavePath = newPath
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

// MARK: - ASR Provider Card
struct ASRProviderCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let badge: String?
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? accentColor : .gray)

                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    // Радио-индикатор
                    ZStack {
                        Circle()
                            .stroke(isSelected ? accentColor : Color.gray.opacity(0.5), lineWidth: 2)
                            .frame(width: 16, height: 16)

                        if isSelected {
                            Circle()
                                .fill(accentColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                }

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .lineLimit(2)

                if let badge = badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.8))
                        .cornerRadius(4)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(isSelected ? accentColor.opacity(0.15) : Color.white.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Parakeet Model Status View
struct ParakeetModelStatusView: View {
    @ObservedObject private var localASRManager = ParakeetASRProvider.shared
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Иконка статуса
                statusIcon

                // Текст статуса
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)

                    Text(statusSubtitle)
                        .font(.system(size: 11))
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
                            Text("Скачать")
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.accent)
                    .cornerRadius(6)
                }

                // Кнопка удаления (когда модель готова)
                if case .ready = localASRManager.modelStatus {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(DesignSystem.Colors.accent.opacity(0.3))
                    .cornerRadius(6)
                    .buttonStyle(PlainButtonStyle())
                    .help("Удалить модель")
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
                    .background(Color.red.opacity(0.8))
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
        .background(statusBackgroundColor.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusBackgroundColor.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
        // Диалог подтверждения удаления
        .alert("Удалить модель Parakeet?", isPresented: $showDeleteConfirmation) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                Task {
                    await localASRManager.deleteModel()
                }
            }
        } message: {
            Text("Модель (~600 MB) будет удалена из кэша.\nВы сможете скачать её снова в любой момент.")
        }
    }

    // MARK: - Computed Properties

    @ViewBuilder
    private var statusIcon: some View {
        switch localASRManager.modelStatus {
        case .notChecked, .checking:
            ProgressView()
                .scaleEffect(0.7)
                .progressViewStyle(CircularProgressViewStyle(tint: .gray))

        case .notDownloaded:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 18))
                .foregroundColor(.orange)

        case .downloading:
            // Анимированный индикатор загрузки
            ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.accent))

        case .loading:
            // Пульсирующий индикатор компиляции
            ProgressView()
                .scaleEffect(0.8)
                .progressViewStyle(CircularProgressViewStyle(tint: .cyan))

        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(DesignSystem.Colors.accent)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(.red)
        }
    }

    private var statusTitle: String {
        switch localASRManager.modelStatus {
        case .notChecked, .checking:
            return "Проверка..."
        case .notDownloaded:
            return "Модель не установлена"
        case .downloading:
            return "Скачивание модели..."
        case .loading:
            return "Компиляция для Neural Engine..."
        case .ready:
            return "Parakeet v3 готова"
        case .error(let msg):
            return "Ошибка: \(msg.prefix(40))"
        }
    }

    private var statusSubtitle: String {
        switch localASRManager.modelStatus {
        case .notChecked, .checking:
            return "Проверяем наличие модели..."
        case .notDownloaded:
            return "Нажмите «Скачать» (~600 MB)"
        case .downloading:
            return "~600 MB • HuggingFace → ~/.cache/fluidaudio/"
        case .loading:
            return "Оптимизация под Apple Neural Engine..."
        case .ready:
            return "25 языков • Офлайн • ~190× real-time"
        case .error:
            return "Проверьте интернет-соединение"
        }
    }

    private var statusBackgroundColor: Color {
        switch localASRManager.modelStatus {
        case .ready:
            return DesignSystem.Colors.accent
        case .downloading, .loading:
            return DesignSystem.Colors.accent
        case .notDownloaded:
            return .orange
        case .error:
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Deepgram Settings Panel (оранжевая рамка)
struct DeepgramSettingsPanel: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var showKeyInput: Bool = false
    @State private var showSuccess: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // API Key статус
            HStack {
                if settings.hasDeepgramAPIKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.deepgramOrange)
                    Text("API ключ установлен")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.deepgramOrange)
                    Text("•")
                        .foregroundColor(.gray)
                    Text(settings.getDeepgramAPIKeyMasked())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Требуется API ключ")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }

                Spacer()

                Button(settings.hasDeepgramAPIKey ? "Изменить" : "Добавить") {
                    showKeyInput.toggle()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.deepgramOrange.opacity(0.3))
                .cornerRadius(6)
                .buttonStyle(PlainButtonStyle())
            }

            if showKeyInput {
                HStack(spacing: 8) {
                    TextField("Введите Deepgram API ключ...", text: $apiKeyInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)

                    Button("Сохранить") {
                        if settings.saveDeepgramAPIKey(apiKeyInput) {
                            showSuccess = true
                            apiKeyInput = ""
                            showKeyInput = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSuccess = false
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(apiKeyInput.isEmpty ? Color.gray : DesignSystem.Colors.deepgramOrange)
                    .cornerRadius(6)
                    .disabled(apiKeyInput.isEmpty)
                }
            }

            if showSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.deepgramOrange)
                    Text("Ключ сохранён")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.deepgramOrange)
                }
            }

            Link("Получить API ключ Deepgram →", destination: URL(string: "https://console.deepgram.com/signup")!)
                .font(.system(size: 11))
                .foregroundColor(.gray)

            // Только если ключ установлен
            if settings.hasDeepgramAPIKey {
                Divider().background(Color.white.opacity(0.1))

                // Модель Deepgram
                HStack {
                    Text("Модель")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { DeepgramModelType(rawValue: settings.deepgramModel) ?? .nova3 },
                        set: { settings.deepgramModel = $0.rawValue }
                    )) {
                        ForEach(DeepgramModelType.allCases, id: \.self) { model in
                            Text(model.menuDisplayName + (model.isRecommended ? " ✓" : ""))
                                .tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }

                Divider().background(Color.white.opacity(0.1))

                // Язык распознавания
                HStack {
                    Text("Язык")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Picker("", selection: $settings.preferredLanguage) {
                        Text("Русский").tag("ru")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 120)
                }
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.deepgramOrange.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DesignSystem.Colors.deepgramOrange.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// MARK: - Deepgram Billing Panel (серая плашка со статистикой)
struct DeepgramBillingPanel: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var balance: Double?
    @State private var totalDuration: Double = 0
    @State private var totalCost: Double = 0
    @State private var requestCount: Int = 0
    @State private var recentRequests: [DeepgramUsageRequest] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var lastUpdated: Date?

    private let service = DeepgramManagementService()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Заголовок + кнопка обновить
            HStack {
                Text("Статистика")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Button {
                        Task { await loadStats() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            if let error = error {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .lineLimit(3)
            } else {
                // Баланс
                HStack {
                    Text("Баланс")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                    if let balance = balance {
                        Text(String(format: "$%.2f", balance))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                    } else {
                        Text("—")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Последние запросы: количество
                HStack {
                    Text("Запросов")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(requestCount)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }

                // Общая длительность
                HStack {
                    Text("Распознано")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(formatDuration(totalDuration))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }

                // Общая стоимость
                HStack {
                    Text("Потрачено")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "$%.4f", totalCost))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }

                // Последние запросы
                if !recentRequests.isEmpty {
                    Divider().background(Color.white.opacity(0.1))

                    Text("Последние запросы")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.top, 2)

                    ForEach(recentRequests, id: \.request_id) { req in
                        HStack {
                            Text(formatRequestDate(req.created))
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(formatDuration(req.response.duration_seconds ?? 0))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white)
                            Text(String(format: "$%.4f", req.response.details?.usd ?? 0))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 55, alignment: .trailing)
                        }
                    }
                }

                // Последнее обновление
                if let lastUpdated = lastUpdated {
                    HStack {
                        Spacer()
                        Text("Обновлено: \(formatTime(lastUpdated))")
                            .font(.system(size: 9))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
        }
        .onAppear {
            Task { await loadStats() }
        }
    }

    private func loadStats() async {
        guard let apiKey = SettingsManager.shared.getAPIKey(), !apiKey.isEmpty else {
            error = "API ключ не найден"
            return
        }

        isLoading = true
        error = nil

        do {
            // Получаем проекты
            let projects = try await service.getProjects(apiKey: apiKey)
            guard let project = projects.first else {
                error = "Проект не найден"
                isLoading = false
                return
            }

            // Получаем баланс
            let balances = try await service.getBalances(apiKey: apiKey, projectId: project.project_id)
            balance = balances.first?.amount

            // Получаем последние запросы
            let requests = try await service.getUsageRequests(apiKey: apiKey, projectId: project.project_id, limit: 100)
            requestCount = requests.count
            totalDuration = requests.compactMap { $0.response.duration_seconds }.reduce(0, +)
            totalCost = requests.compactMap { $0.response.details?.usd }.reduce(0, +)
            recentRequests = Array(requests.prefix(5))

            lastUpdated = Date()
        } catch let err as DeepgramManagementError {
            error = err.errorDescription ?? "Ошибка загрузки"
        } catch {
            self.error = "Ошибка: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins) мин \(secs) сек"
        } else {
            return "\(secs) сек"
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatRequestDate(_ isoString: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        guard let date = isoFormatter.date(from: isoString) else {
            // Попробуем без миллисекунд
            isoFormatter.formatOptions = [.withInternetDateTime]
            guard let date = isoFormatter.date(from: isoString) else {
                return isoString.prefix(10).description
            }
            return formatShortDate(date)
        }
        return formatShortDate(date)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - ASR Provider Section
struct ASRProviderSection: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        SettingsSection(title: "ДИКТОВКА") {
            VStack(alignment: .leading, spacing: 16) {
                // Горизонтальные карточки провайдеров
                HStack(spacing: 12) {
                    // Parakeet v3 (локальная модель)
                    ASRProviderCard(
                        icon: "cpu",
                        title: "Parakeet v3",
                        subtitle: "25 языков • ~190× RT",
                        badge: "Офлайн",
                        isSelected: settings.asrProviderType == .local,
                        accentColor: DesignSystem.Colors.accent,
                        action: { settings.asrProviderType = .local }
                    )

                    // Deepgram (облако)
                    ASRProviderCard(
                        icon: "cloud.fill",
                        title: "Deepgram",
                        subtitle: "Streaming • ~200мс",
                        badge: nil,
                        isSelected: settings.asrProviderType == .deepgram,
                        accentColor: DesignSystem.Colors.deepgramOrange,
                        action: { settings.asrProviderType = .deepgram }
                    )
                }

                // Настройки выбранного провайдера
                if settings.asrProviderType == .local {
                    LLMSettingsInlineView()
                } else {
                    DeepgramSettingsPanel()

                    // Статистика Deepgram
                    if settings.hasDeepgramAPIKey {
                        DeepgramBillingPanel()
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - LLM Settings Inline View (статус модели под локальной моделью)
struct LLMSettingsInlineView: View {
    @ObservedObject private var localASRManager = ParakeetASRProvider.shared

    var body: some View {
        VStack(spacing: 12) {
            // Статус модели Parakeet
            ParakeetModelStatusView()

            // Описание локальной модели (показывать только когда модель готова)
            // Полная ширина без вложенной карточки
            if case .ready = localASRManager.modelStatus {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Как работает локальная модель")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)

                    Text("Parakeet v3 — нейросетевая модель от NVIDIA, работающая полностью на вашем устройстве. Использует Apple Neural Engine для ускорения (~190× real-time). Модель занимает ~600 MB и поддерживает 25 европейских языков. Интернет не требуется.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Enhancer Settings Section (отдельный таб для улучшайзера)
struct EnhancerSettingsSection: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // API ключ + Модель (зелёная плашка — БЕЗ вложенности в SettingsSection)
            VStack(alignment: .leading, spacing: 8) {
                Text("GEMINI API KEY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 14) {
                    GeminiAPIKeyStatus()

                    if settings.hasGeminiAPIKey {
                        Divider().background(Color.white.opacity(0.1))
                        GeminiModelPicker(selection: $settings.selectedGeminiModel, label: "Модель")
                    }
                }
                .padding(14)
                .background(DesignSystem.Colors.accent.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DesignSystem.Colors.accent.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            // Промпт улучшайзера
            SettingsSection(title: "ПРОМПТ УЛУЧШЕНИЯ") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Промпт для LLM обработки текста")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Spacer()
                        if settings.llmProcessingPrompt != SettingsManager.defaultLLMPrompt {
                            Button("Сбросить") {
                                settings.llmProcessingPrompt = SettingsManager.defaultLLMPrompt
                            }
                            .font(.system(size: 11))
                            .foregroundColor(DesignSystem.Colors.accent)
                        }
                    }

                    TextEditor(text: $settings.llmProcessingPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80, maxHeight: 220)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }

            // Дополнительные инструкции
            SettingsSection(title: "ДОПОЛНИТЕЛЬНЫЕ ИНСТРУКЦИИ") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Добавляются к системному промпту")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)

                    let lineCount = max(1, settings.llmAdditionalInstructions.components(separatedBy: "\n").count)
                    let dynamicHeight = min(CGFloat(lineCount) * 18 + 16, 180)

                    TextEditor(text: $settings.llmAdditionalInstructions)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: dynamicHeight)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }
        }
    }
}

// MARK: - Gemini Model Picker (Dropdown)
struct GeminiModelPicker: View {
    @Binding var selection: GeminiModel
    var label: String = "Модель Gemini"

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Picker("", selection: $selection) {
                ForEach(GeminiModel.allCases, id: \.self) { model in
                    Text(model.menuDisplayName + (model.isNew ? " ✦" : ""))
                        .tag(model)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 336)
        }
    }
}

// MARK: - Gemini API Key Status
struct GeminiAPIKeyStatus: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var apiKeyInput: String = ""
    @State private var showKeyInput: Bool = false
    @State private var showSuccess: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // API Key статус
            HStack {
                if settings.hasGeminiAPIKey {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text("API ключ установлен")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text("•")
                        .foregroundColor(.gray)
                    Text(settings.getGeminiAPIKeyMasked())
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Требуется API ключ")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }

                Spacer()

                Button(settings.hasGeminiAPIKey ? "Изменить" : "Добавить") {
                    showKeyInput.toggle()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DesignSystem.Colors.accent.opacity(0.3))
                .cornerRadius(6)
                .buttonStyle(PlainButtonStyle())
            }

            if showKeyInput {
                HStack(spacing: 8) {
                    TextField("Введите Gemini API ключ...", text: $apiKeyInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 11, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)

                    Button("Сохранить") {
                        if settings.saveGeminiAPIKey(apiKeyInput) {
                            showSuccess = true
                            apiKeyInput = ""
                            showKeyInput = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showSuccess = false
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(apiKeyInput.isEmpty ? Color.gray : DesignSystem.Colors.accent)
                    .cornerRadius(6)
                    .disabled(apiKeyInput.isEmpty)
                }
            }

            if showSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text("Ключ сохранён")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }

            Link("Получить API ключ Google AI Studio →", destination: URL(string: "https://aistudio.google.com/apikey")!)
                .font(.system(size: 11))
                .foregroundColor(.gray)
        }
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
        VStack(spacing: 0) {
            // Карточка 1: Включение AI функций
            SettingsSection(title: "AI ОБРАБОТКА") {
                SettingsRow(
                    title: "Включить AI функции",
                    subtitle: "Обработка текста через Gemini AI"
                ) {
                    Toggle("", isOn: $aiEnabled)
                        .toggleStyle(TahoeToggleStyle())
                        .labelsHidden()
                }
                .padding(.vertical, 8)
            }

            // Gemini API Key (только если включено) - БЕЗ двойной вложенности
            if aiEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GEMINI API KEY")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.gray)
                        .textCase(.uppercase)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        // API Key статус
                        HStack {
                            if settings.hasGeminiAPIKey {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.accent)
                                Text("API ключ установлен")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignSystem.Colors.accent)
                                Text("•")
                                    .foregroundColor(.gray)
                                Text(settings.getGeminiAPIKeyMasked())
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Требуется API ключ")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }

                            Spacer()

                            Button(settings.hasGeminiAPIKey ? "Изменить" : "Добавить") {
                                showGeminiAPIKeyInput.toggle()
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(DesignSystem.Colors.accent.opacity(0.3))
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
                                .background(geminiAPIKeyInput.isEmpty ? Color.gray : DesignSystem.Colors.deepgramOrange)
                                .cornerRadius(6)
                                .buttonStyle(PlainButtonStyle())
                                .disabled(geminiAPIKeyInput.isEmpty)
                            }
                        }

                        if showSaveSuccess {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(DesignSystem.Colors.accent)
                                Text("Ключ сохранён")
                                    .font(.system(size: 11))
                                    .foregroundColor(DesignSystem.Colors.accent)
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

                        if settings.hasGeminiAPIKey {
                            Divider().background(Color.white.opacity(0.1))

                            // Model Picker для AI функций
                            GeminiModelPicker(selection: $settings.selectedGeminiModelForAI, label: "Модель для AI")

                            Divider().background(Color.white.opacity(0.1))

                            // Max Output Tokens Slider
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Макс. длина ответа")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text("\(settings.maxOutputTokens) токенов")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.gray)
                                }

                                HStack(spacing: 12) {
                                    Text("512")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)

                                    Slider(
                                        value: Binding(
                                            get: { Double(settings.maxOutputTokens) },
                                            set: { settings.maxOutputTokens = Int($0) }
                                        ),
                                        in: 512...20000
                                    )
                                    .tint(DesignSystem.Colors.accent)

                                    Text("20K")
                                        .font(.system(size: 10))
                                        .foregroundColor(.gray)
                                }

                                Text("Больше токенов = длиннее ответы AI, но медленнее и дороже")
                                    .font(.system(size: 10))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                        }
                    }
                    .padding(14)
                    .background(DesignSystem.Colors.accent.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DesignSystem.Colors.accent.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
            }
        }
    }
}

// MARK: - AI Prompts Section
struct AIPromptsSection: View {
    @ObservedObject private var promptsManager = PromptsManager.shared
    @State private var editingPrompt: CustomPrompt? = nil
    @State private var showAddSheet: Bool = false

    var body: some View {
        SettingsSection(title: "AI ПРОМПТЫ") {
            VStack(alignment: .leading, spacing: 12) {
                // Описание
                Text("Промпты для обработки текста. Избранные отображаются в главном окне.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)

                // Список промптов с drag-n-drop
                List {
                    ForEach(promptsManager.prompts.sorted { $0.order < $1.order }) { prompt in
                        SettingsPromptRowView(
                            prompt: prompt,
                            onToggleFavorite: {
                                promptsManager.toggleFavorite(prompt)
                            },
                            onEdit: {
                                editingPrompt = prompt
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in
                        promptsManager.movePrompt(from: from, to: to)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150, maxHeight: 300)

                // Кнопки добавления и восстановления
                HStack(spacing: 16) {
                    Button(action: { showAddSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                            Text("Добавить промпт")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(DesignSystem.Colors.accent)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: { promptsManager.resetToDefaults() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                            Text("Восстановить базовые")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAddSheet) {
            AddPromptSheet { newPrompt in
                promptsManager.addPrompt(newPrompt)
            }
        }
        .sheet(item: $editingPrompt) { prompt in
            EditPromptSheet(
                prompt: prompt,
                onSave: { updatedPrompt in
                    promptsManager.updatePrompt(updatedPrompt)
                },
                onDelete: {
                    promptsManager.deletePrompt(prompt)
                    editingPrompt = nil
                }
            )
        }
    }
}

// MARK: - Settings Prompt Row View (для настроек)
struct SettingsPromptRowView: View {
    let prompt: CustomPrompt
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            // Иконка избранного (звезда)
            Button(action: onToggleFavorite) {
                Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundColor(prompt.isFavorite ? DesignSystem.Colors.accent : .gray.opacity(0.5))
                    .frame(width: 16)
            }
            .buttonStyle(PlainButtonStyle())

            // Label кнопки (растягивается по содержимому)
            Text(prompt.label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.cardBackground)
                .cornerRadius(DesignSystem.CornerRadius.button)

            // Описание
            Text(prompt.description)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(1)

            Spacer()

            // Кнопка редактирования
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.02))
        .cornerRadius(4)
    }
}

// MARK: - Add Prompt Sheet (Tahoe Style)
struct AddPromptSheet: View {
    let onAdd: (CustomPrompt) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var label: String = ""
    @State private var description: String = ""
    @State private var promptText: String = ""

    private var isValid: Bool {
        !label.isEmpty && label.count >= 1 && label.count <= 10 &&
        !description.isEmpty &&
        !promptText.isEmpty
    }

    private func addPrompt() {
        guard isValid else { return }
        let newPrompt = CustomPrompt(
            id: UUID(),
            label: label,
            description: description,
            prompt: promptText,
            isVisible: true,
            isFavorite: true,
            isSystem: false,
            order: 0
        )
        onAdd(newPrompt)
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text("Новый промпт")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // CONTENT
            VStack(alignment: .leading, spacing: 20) {
                // Label
                VStack(alignment: .leading, spacing: 6) {
                    Text("Кнопка (до 10 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $label)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .frame(width: 140)
                        .onChange(of: label) { _, newValue in
                            label = String(newValue.prefix(10)).uppercased()
                        }
                        .onSubmit { addPrompt() }
                }

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Описание")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $description)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .onSubmit { addPrompt() }
                }

                // Prompt text
                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст промпта")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $promptText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .frame(minHeight: 160)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()

            // FOOTER
            HStack {
                Button(action: { dismiss() }) {
                    Text("Отмена")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)

                Spacer()

                Button(action: addPrompt) {
                    Text("Добавить")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(isValid ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(DesignSystem.Colors.buttonAreaBackground)
        }
        .frame(width: 520, height: 500)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Edit Prompt Sheet (Tahoe Style)
struct EditPromptSheet: View {
    let prompt: CustomPrompt
    let onSave: (CustomPrompt) -> Void
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) var dismiss

    @State private var label: String
    @State private var description: String
    @State private var promptText: String
    @State private var isFavorite: Bool
    @State private var showDeleteConfirmation: Bool = false

    init(prompt: CustomPrompt, onSave: @escaping (CustomPrompt) -> Void, onDelete: (() -> Void)? = nil) {
        self.prompt = prompt
        self.onSave = onSave
        self.onDelete = onDelete
        _label = State(initialValue: prompt.label)
        _description = State(initialValue: prompt.description)
        _promptText = State(initialValue: prompt.prompt)
        _isFavorite = State(initialValue: prompt.isFavorite)
    }

    private var isValid: Bool {
        !label.isEmpty && label.count >= 1 && label.count <= 10 &&
        !description.isEmpty &&
        !promptText.isEmpty
    }

    private func saveChanges() {
        guard isValid else { return }
        var updated = prompt
        updated.label = label
        updated.description = description
        updated.prompt = promptText
        updated.isFavorite = isFavorite
        onSave(updated)
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text("Редактировать промпт")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // CONTENT
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Label
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Кнопка (до 10 символов)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        TextField("", text: $label)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .frame(width: 140)
                            .onChange(of: label) { _, newValue in
                                label = String(newValue.prefix(10)).uppercased()
                            }
                            .onSubmit { saveChanges() }
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Описание")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        TextField("", text: $description)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .onSubmit { saveChanges() }
                    }

                    // Prompt text
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Текст промпта")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        TextEditor(text: $promptText)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .frame(minHeight: 160)
                    }

                    // Favorite toggle
                    Toggle(isOn: $isFavorite) {
                        Text("Показывать в быстром доступе")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(TahoeToggleStyle())

                    // Reset button for system prompts
                    if prompt.isSystem {
                        Button(action: {
                            if let defaultPrompt = CustomPrompt.defaultSystemPrompts.first(where: { $0.label == prompt.label }) {
                                promptText = defaultPrompt.prompt
                                label = defaultPrompt.label
                                description = defaultPrompt.description
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Сбросить по умолчанию")
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }

            Spacer()

            // FOOTER
            HStack {
                Button(action: { dismiss() }) {
                    Text("Отмена")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)

                // Кнопка удаления (если есть callback)
                if onDelete != nil {
                    Button(action: { showDeleteConfirmation = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Удалить")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: saveChanges) {
                    Text("Сохранить")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(isValid ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(DesignSystem.Colors.buttonAreaBackground)
        }
        .frame(width: 520, height: 540)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
        )
        .alert("Удалить промпт?", isPresented: $showDeleteConfirmation) {
            Button("Отмена", role: .cancel) { }
            Button("Да, удалить", role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text("Промпт \"\(prompt.label)\" будет удалён")
        }
    }
}

// MARK: - Snippets Settings Section
struct SnippetsSettingsSection: View {
    @ObservedObject private var snippetsManager = SnippetsManager.shared
    @State private var editingSnippet: Snippet? = nil
    @State private var showAddSheet: Bool = false

    var body: some View {
        SettingsSection(title: "СНИППЕТЫ") {
            VStack(alignment: .leading, spacing: 12) {
                // Описание
                Text("Быстрые текстовые вставки. Избранные отображаются в главном окне.")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)

                // Список сниппетов
                if snippetsManager.snippets.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 24))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Нет сниппетов")
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(snippetsManager.snippets.sorted { $0.order < $1.order }) { snippet in
                            SettingsSnippetRowView(
                                snippet: snippet,
                                onToggleFavorite: {
                                    snippetsManager.toggleFavorite(snippet)
                                },
                                onEdit: {
                                    editingSnippet = snippet
                                },
                                onDelete: {
                                    snippetsManager.deleteSnippet(snippet)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove { from, to in
                            snippetsManager.moveSnippet(from: from, to: to)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100, maxHeight: 250)
                }

                // Кнопка добавления
                Button(action: { showAddSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Добавить сниппет")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 4)
            }
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showAddSheet) {
            AddSnippetSheet { newSnippet in
                snippetsManager.addSnippet(newSnippet)
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            EditSnippetSheet(
                snippet: snippet,
                onSave: { updatedSnippet in
                    snippetsManager.updateSnippet(updatedSnippet)
                },
                onDelete: {
                    snippetsManager.deleteSnippet(snippet)
                }
            )
        }
    }
}

// MARK: - Settings Snippet Row View
struct SettingsSnippetRowView: View {
    let snippet: Snippet
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Иконка избранного (звезда)
                Button(action: onToggleFavorite) {
                    Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundColor(snippet.isFavorite ? DesignSystem.Colors.accent : .gray.opacity(0.5))
                        .frame(width: 16)
                }
                .buttonStyle(PlainButtonStyle())

                // Shortcut
                Text(snippet.shortcut)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DesignSystem.Colors.cardBackground)
                    .cornerRadius(DesignSystem.CornerRadius.button)

                // Title
                Text(snippet.title)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)

                Spacer()

                // Edit (показывается при наведении)
                if isHovered {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Content preview (всегда видно)
            Text(snippet.content)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
                .lineLimit(2)
                .padding(.leading, 24) // Выравнивание с title
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.02))
        .cornerRadius(4)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Add Snippet Sheet (Tahoe Style)
struct AddSnippetSheet: View {
    let onAdd: (Snippet) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var shortcut: String = ""
    @State private var title: String = ""
    @State private var content: String = ""
    @State private var isFavorite: Bool = true

    private var isValid: Bool {
        shortcut.count >= 2 && shortcut.count <= 6 &&
        !title.isEmpty &&
        !content.isEmpty
    }

    private func addSnippet() {
        guard isValid else { return }
        let newSnippet = Snippet.create(
            shortcut: shortcut,
            title: title,
            content: content
        )
        var snippet = newSnippet
        snippet.isFavorite = isFavorite
        onAdd(snippet)
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text("Новый сниппет")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // CONTENT
            VStack(alignment: .leading, spacing: 20) {
                // Shortcut
                VStack(alignment: .leading, spacing: 6) {
                    Text("Код (2-6 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $shortcut)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .frame(width: 120)
                        .onChange(of: shortcut) { _, newValue in
                            shortcut = String(newValue.prefix(6)).lowercased()
                        }
                        .onSubmit { addSnippet() }
                }

                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Название")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .onSubmit { addSnippet() }
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст сниппета")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $content)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .frame(minHeight: 160)
                }

                // Favorite toggle
                Toggle(isOn: $isFavorite) {
                    Text("Показывать в быстром доступе")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                .toggleStyle(TahoeToggleStyle())
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)

            Spacer()

            // FOOTER
            HStack {
                Button(action: { dismiss() }) {
                    Text("Отмена")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)

                Spacer()

                Button(action: addSnippet) {
                    Text("Добавить")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(isValid ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(DesignSystem.Colors.buttonAreaBackground)
        }
        .frame(width: 520, height: 500)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Edit Snippet Sheet (Tahoe Style)
struct EditSnippetSheet: View {
    let snippet: Snippet
    let onSave: (Snippet) -> Void
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    @State private var shortcut: String
    @State private var title: String
    @State private var content: String
    @State private var isFavorite: Bool
    @State private var showDeleteConfirm = false

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onDelete: (() -> Void)? = nil) {
        self.snippet = snippet
        self.onSave = onSave
        self.onDelete = onDelete
        _shortcut = State(initialValue: snippet.shortcut)
        _title = State(initialValue: snippet.title)
        _content = State(initialValue: snippet.content)
        _isFavorite = State(initialValue: snippet.isFavorite)
    }

    private var isValid: Bool {
        shortcut.count >= 2 && shortcut.count <= 6 &&
        !title.isEmpty &&
        !content.isEmpty
    }

    private func saveChanges() {
        guard isValid else { return }
        var updated = snippet
        updated.shortcut = shortcut
        updated.title = title
        updated.content = content
        updated.isFavorite = isFavorite
        onSave(updated)
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            // HEADER
            HStack {
                Text("Редактировать сниппет")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            // CONTENT
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Shortcut
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Код (2-6 символов)")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        TextField("", text: $shortcut)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .frame(width: 120)
                            .onChange(of: shortcut) { _, newValue in
                                shortcut = String(newValue.prefix(6)).lowercased()
                            }
                            .onSubmit { saveChanges() }
                    }

                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Название")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .onSubmit { saveChanges() }
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Текст сниппета")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        TextEditor(text: $content)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .frame(minHeight: 160)
                    }

                    // Favorite toggle
                    Toggle(isOn: $isFavorite) {
                        Text("Показывать в быстром доступе")
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                    }
                    .toggleStyle(TahoeToggleStyle())
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }

            Spacer()

            // FOOTER
            HStack {
                Button(action: { dismiss() }) {
                    Text("Отмена")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape)

                // Кнопка удаления (если есть callback)
                if onDelete != nil {
                    Button(action: { showDeleteConfirm = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                            Text("Удалить")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button(action: saveChanges) {
                    Text("Сохранить")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(isValid ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 20)
            .background(DesignSystem.Colors.buttonAreaBackground)
        }
        .frame(width: 520, height: 540)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
        )
        .alert("Удалить сниппет?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                onDelete?()
                dismiss()
            }
        } message: {
            Text("Это действие нельзя отменить")
        }
    }
}

