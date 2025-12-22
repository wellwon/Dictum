
import SwiftUI
import AppKit
import Carbon
import AVFoundation
import FluidAudio

// MARK: - Color Extension for Hex
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Design System
enum DesignSystem {
    enum Colors {
        // Accent — единый зеленый цвет #1AAF87 для всего приложения
        static let accent = Color(red: 0.102, green: 0.686, blue: 0.529)
        static let accentSecondary = Color(red: 0.204, green: 0.596, blue: 0.859)  // #3498DB

        // Deepgram Orange — для облачного провайдера #FF6633
        static let deepgramOrange = Color(hex: "#FF6633")

        // Backgrounds
        static let panelBackground = Color.black.opacity(0.3)
        static let cardBackground = Color.white.opacity(0.05)
        static let hoverBackground = Color.white.opacity(0.1)
        static let selectedBackground = Color.white.opacity(0.15)

        // Modal/Panel elements
        static let buttonAreaBackground = Color(red: 39/255, green: 39/255, blue: 41/255)  // #272729
        static let borderColor = Color(red: 76/255, green: 77/255, blue: 77/255)           // #4c4d4d

        // Text
        static let textPrimary = Color.white
        static let textSecondary = Color.gray
        static let textMuted = Color.white.opacity(0.6)

        // States
        static let toggleActive = accent  // Зеленый для тумблеров
        static let destructive = Color(red: 1.0, green: 0.231, blue: 0.188)  // #FF3B30
        static let warning = Color.orange
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
    }

    enum CornerRadius {
        static let button: CGFloat = 4
        static let card: CGFloat = 6
        static let panel: CGFloat = 8
    }

    enum Typography {
        static let sectionHeader = Font.system(size: 11, weight: .semibold)
        static let body = Font.system(size: 12)
        static let label = Font.system(size: 11, weight: .medium)
        static let caption = Font.system(size: 10)
    }
}

// MARK: - App Config
enum AppConfig {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - API Key Manager (UserDefaults, base64 encoded)
class APIKeyManager: @unchecked Sendable {
    static let deepgram = APIKeyManager(service: "deepgram")
    static let gemini = APIKeyManager(service: "gemini")

    private let storageKey: String
    private let serviceName: String

    init(service: String) {
        self.serviceName = service
        self.storageKey = "com.dictum.\(service)-api-key"
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

// MARK: - Update Manager
class UpdateManager: ObservableObject, @unchecked Sendable {
    static let shared = UpdateManager()

    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadURL: String?
    @Published var releaseNotes: String?
    @Published var isChecking = false
    @Published var lastCheckDate: Date?
    @Published var checkError: String?

    private let feedURL: String
    private let checkIntervalSeconds: TimeInterval = 86400  // 24 hours

    init() {
        // Read feed URL from Info.plist or use default
        self.feedURL = Bundle.main.infoDictionary?["SUFeedURL"] as? String
            ?? "https://raw.githubusercontent.com/wellwon/Dictum/main/appcast.xml"

        // Load last check date
        if let timestamp = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date {
            self.lastCheckDate = timestamp
        }
    }

    /// Check for updates (can be called manually or automatically)
    func checkForUpdates(force: Bool = false) {
        // Skip if already checking
        guard !isChecking else { return }

        // Skip if checked recently (unless forced)
        if !force, let lastCheck = lastCheckDate {
            let timeSinceLastCheck = Date().timeIntervalSince(lastCheck)
            if timeSinceLastCheck < checkIntervalSeconds {
                NSLog("⏭️ Skipping update check (last check: \(Int(timeSinceLastCheck/60)) min ago)")
                return
            }
        }

        isChecking = true
        checkError = nil

        Task {
            await performUpdateCheck()
        }
    }

    private func performUpdateCheck() async {
        NSLog("🔄 Checking for updates...")

        guard let url = URL(string: feedURL) else {
            await MainActor.run {
                self.checkError = "Invalid feed URL"
                self.isChecking = false
            }
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw UpdateError.serverError
            }

            // Parse appcast XML
            let parser = AppcastParser(data: data)
            let items = parser.parse()

            guard let latestItem = items.first else {
                throw UpdateError.noUpdatesFound
            }

            let currentVersion = AppConfig.version
            let isNewer = compareVersions(latestItem.version, currentVersion) > 0

            await MainActor.run {
                self.latestVersion = latestItem.version
                self.downloadURL = latestItem.downloadURL
                self.releaseNotes = latestItem.releaseNotes
                self.updateAvailable = isNewer
                self.lastCheckDate = Date()
                self.isChecking = false

                // Save last check date
                UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")

                if isNewer {
                    NSLog("✅ Update available: \(latestItem.version) (current: \(currentVersion))")
                } else {
                    NSLog("✅ App is up to date (\(currentVersion))")
                }
            }

        } catch {
            await MainActor.run {
                self.checkError = error.localizedDescription
                self.isChecking = false
                NSLog("❌ Update check failed: \(error)")
            }
        }
    }

    /// Compare two version strings (e.g., "1.9.1" vs "1.10")
    /// Returns: >0 if v1 > v2, <0 if v1 < v2, 0 if equal
    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(parts1.count, parts2.count)

        for i in 0..<maxLen {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 > p2 { return 1 }
            if p1 < p2 { return -1 }
        }

        return 0
    }

    /// Open download URL in browser
    func openDownloadPage() {
        guard let urlString = downloadURL, let url = URL(string: urlString) else {
            // Fallback to GitHub releases page
            if let url = URL(string: "https://github.com/wellwon/Dictum/releases") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        NSWorkspace.shared.open(url)
    }

    enum UpdateError: LocalizedError {
        case serverError
        case noUpdatesFound
        case parseError

        var errorDescription: String? {
            switch self {
            case .serverError: return "Server error"
            case .noUpdatesFound: return "No updates found"
            case .parseError: return "Failed to parse update feed"
            }
        }
    }
}

// MARK: - Appcast Parser (Sparkle-compatible XML)
class AppcastParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    struct AppcastItem {
        var version: String = ""
        var shortVersion: String = ""
        var downloadURL: String = ""
        var releaseNotes: String = ""
        var pubDate: String = ""
    }

    private var items: [AppcastItem] = []
    private var currentItem: AppcastItem?
    private var currentElement = ""
    private var currentText = ""

    private let data: Data

    init(data: Data) {
        self.data = data
    }

    func parse() -> [AppcastItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()

        // Sort by version descending
        return items.sorted { item1, item2 in
            let v1 = item1.shortVersion.isEmpty ? item1.version : item1.shortVersion
            let v2 = item2.shortVersion.isEmpty ? item2.version : item2.shortVersion
            return compareVersions(v1, v2) > 0
        }
    }

    private func compareVersions(_ v1: String, _ v2: String) -> Int {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        let maxLen = max(parts1.count, parts2.count)

        for i in 0..<maxLen {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0

            if p1 > p2 { return 1 }
            if p1 < p2 { return -1 }
        }

        return 0
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        if elementName == "item" {
            currentItem = AppcastItem()
        } else if elementName == "enclosure" {
            currentItem?.downloadURL = attributes["url"] ?? ""
            if let version = attributes["sparkle:version"] {
                currentItem?.version = version
            }
            if let shortVersion = attributes["sparkle:shortVersionString"] {
                currentItem?.shortVersion = shortVersion
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "sparkle:version":
            currentItem?.version = trimmed
        case "sparkle:shortVersionString":
            currentItem?.shortVersion = trimmed
        case "description":
            currentItem?.releaseNotes = trimmed
        case "pubDate":
            currentItem?.pubDate = trimmed
        case "item":
            if var item = currentItem {
                // Use shortVersion as primary version if available
                if item.shortVersion.isEmpty {
                    item.shortVersion = item.version
                }
                items.append(item)
            }
            currentItem = nil
        default:
            break
        }

        currentText = ""
    }
}

// MARK: - History Manager
class HistoryManager: ObservableObject, @unchecked Sendable {
    static let shared = HistoryManager()

    @Published var history: [HistoryItem] = []
    private let maxHistoryItems = 50
    private let historyKey = "dictum-history"
    private let oldHistoryKey = "olamba-history"  // Для миграции

    init() {
        migrateFromOldKey()
        loadHistory()
    }

    /// Миграция данных из старого ключа Olamba
    private func migrateFromOldKey() {
        let defaults = UserDefaults.standard
        // Если есть старые данные и нет новых — мигрируем
        if let oldData = defaults.data(forKey: oldHistoryKey),
           defaults.data(forKey: historyKey) == nil {
            defaults.set(oldData, forKey: historyKey)
            defaults.removeObject(forKey: oldHistoryKey)
            NSLog("✅ История мигрирована из olamba-history в dictum-history")
        }
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
            // Fix 22: Cache lowercased query outside filter loop
            let lowercasedQuery = searchQuery.lowercased()
            let filtered = history.filter { $0.text.lowercased().contains(lowercasedQuery) }
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
            // Fix 16: NSLog for error visibility
            NSLog("❌ Error loading history: \(error.localizedDescription)")
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
            // Fix 16: NSLog for error visibility
            NSLog("❌ Error saving history: \(error.localizedDescription)")
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
        return names.joined(separator: " ")
    }

    var displayString: String {
        if modifiers == 0 {
            return keyName
        }
        return modifierNames + " " + keyName
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

    static let defaultToggle = HotkeyConfig(keyCode: 10, modifiers: UInt32(cmdKey)) // ⌘ + §
}

// MARK: - Gemini Model
enum GeminiModel: String, CaseIterable {
    case gemini3FlashPreview = "gemini-3-flash-preview"
    case gemini25Flash = "gemini-2.5-flash"
    case gemini25FlashLite = "gemini-2.5-flash-lite"
    case gemini20Flash = "gemini-2.0-flash"
    case gemini20FlashLite = "gemini-2.0-flash-lite"

    var displayName: String {
        switch self {
        case .gemini3FlashPreview: return "Gemini 3 Flash Preview"
        case .gemini25Flash: return "Gemini 2.5 Flash"
        case .gemini25FlashLite: return "Gemini 2.5 Flash-Lite"
        case .gemini20Flash: return "Gemini 2.0 Flash"
        case .gemini20FlashLite: return "Gemini 2.0 Flash-Lite"
        }
    }

    var price: String {
        switch self {
        case .gemini3FlashPreview: return "$0.50 / $3.00"
        case .gemini25Flash: return "$0.30 / $2.50"
        case .gemini25FlashLite: return "$0.10 / $0.40"
        case .gemini20Flash: return "$0.10 / $0.40"
        case .gemini20FlashLite: return "$0.075 / $0.30"
        }
    }

    /// Для выпадающего меню: "Gemini 2.5 Flash · 1m · $0.30 / $2.50"
    var menuDisplayName: String {
        "\(displayName) · 1m · \(price)"
    }

    var isNew: Bool {
        self == .gemini3FlashPreview
    }
}

// MARK: - Deepgram Model
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
        var volumeLevel: Int
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

    @Published var volumeLevel: Int {
        didSet {
            let value = volumeLevel
            DispatchQueue.global(qos: .utility).async {
                UserDefaults.standard.set(value, forKey: "settings.volumeLevel")
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

        // Load screenshot hotkey (default: Cmd+Shift+6)
        if let data = UserDefaults.standard.data(forKey: "settings.screenshotHotkey"),
           let hotkey = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.screenshotHotkey = hotkey
        } else {
            // Key code 2 = "D", Cmd+Shift modifiers
            self.screenshotHotkey = HotkeyConfig(keyCode: 2, modifiers: UInt32(cmdKey | shiftKey))
        }

        // Settings window state
        self.settingsWindowWasOpen = UserDefaults.standard.bool(forKey: "settings.windowWasOpen")
        self.lastSettingsTab = UserDefaults.standard.string(forKey: "settings.lastTab") ?? "general"

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

        // Volume level: по умолчанию 10%
        self.volumeLevel = UserDefaults.standard.object(forKey: "settings.volumeLevel") as? Int ?? 10

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
                volumeLevel: volumeLevel,
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
        volumeLevel = config.settings.volumeLevel
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

    func saveConfigToFile(
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

    func loadConfigFromFile() -> Bool {
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

// MARK: - Custom Prompt Model
struct CustomPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String           // "WB", "FR" (2-4 символа)
    var description: String     // "Вежливый Бот" (описание на русском)
    var prompt: String          // Текст промпта
    var isVisible: Bool         // Показывать в UI (legacy, используется вместе с isFavorite)
    var isFavorite: Bool        // Показывать в строке быстрого доступа (ROW 1)
    var isSystem: Bool          // true для 4 стандартных
    var order: Int              // Порядок отображения

    // CodingKeys для обратной совместимости (isFavorite может отсутствовать в старых данных)
    enum CodingKeys: String, CodingKey {
        case id, label, description, prompt, isVisible, isFavorite, isSystem, order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        description = try container.decode(String.self, forKey: .description)
        prompt = try container.decode(String.self, forKey: .prompt)
        isVisible = try container.decode(Bool.self, forKey: .isVisible)
        // Миграция: если isFavorite отсутствует, используем isVisible
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? isVisible
        isSystem = try container.decode(Bool.self, forKey: .isSystem)
        order = try container.decode(Int.self, forKey: .order)
    }

    init(id: UUID, label: String, description: String, prompt: String, isVisible: Bool, isFavorite: Bool, isSystem: Bool, order: Int) {
        self.id = id
        self.label = label
        self.description = description
        self.prompt = prompt
        self.isVisible = isVisible
        self.isFavorite = isFavorite
        self.isSystem = isSystem
        self.order = order
    }

    // Создание системного промпта со стабильным UUID
    static func system(label: String, description: String, prompt: String, order: Int) -> CustomPrompt {
        // Создаем стабильный UUID на основе label
        let uuidString = "00000000-0000-0000-0000-\(String(format: "%012d", label.hashValue & 0xFFFFFFFF))"
        let stableId = UUID(uuidString: uuidString) ?? UUID()
        return CustomPrompt(
            id: stableId,
            label: label,
            description: description,
            prompt: prompt,
            isVisible: true,
            isFavorite: true,  // Системные промпты по умолчанию в избранном
            isSystem: true,
            order: order
        )
    }

    // Дефолтные системные промпты
    static let defaultSystemPrompts: [CustomPrompt] = [
        .system(
            label: "WB",
            description: "Вежливый Бот — перефразирует текст вежливо и профессионально",
            prompt: "Перефразируй этот текст на том же языке, сделав его более вежливым и профессиональным. Используй разговорный, но уважительный тон. Исправь все грамматические и пунктуационные ошибки. Текст должен показывать, что мы ценим клиента и хорошо к нему относимся. Сохрани суть сообщения, но сделай его максимально приятным для получателя:",
            order: 0
        ),
        .system(
            label: "RU",
            description: "Перевод на русский язык как носитель",
            prompt: "Переведи следующий текст на русский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель русского языка:",
            order: 1
        ),
        .system(
            label: "EN",
            description: "Перевод на английский язык как носитель",
            prompt: "Переведи следующий текст на английский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель английского языка:",
            order: 2
        ),
        .system(
            label: "CH",
            description: "Перевод на китайский язык как носитель",
            prompt: "Переведи следующий текст на китайский язык. Верни ТОЛЬКО перевод, ничего больше. Никаких объяснений, вариантов или дополнительного текста. Только прямой перевод так, как написал бы носитель китайского языка:",
            order: 3
        )
    ]
}

// MARK: - Prompts Manager
class PromptsManager: ObservableObject, @unchecked Sendable {
    static let shared = PromptsManager()

    private let userDefaultsKey = "com.dictum.customPrompts"
    private let migrationKey = "com.dictum.promptsMigrationV1"

    @Published var prompts: [CustomPrompt] = [] {
        didSet { savePrompts() }
    }

    // Только видимые, отсортированные по order
    var visiblePrompts: [CustomPrompt] {
        prompts.filter { $0.isVisible }.sorted { $0.order < $1.order }
    }

    // Избранные промпты для строки быстрого доступа (ROW 1)
    var favoritePrompts: [CustomPrompt] {
        prompts.filter { $0.isFavorite }.sorted { $0.order < $1.order }
    }

    init() {
        migrateIfNeeded()
        loadPrompts()
    }

    // MARK: - Persistence
    private func savePrompts() {
        if let data = try? JSONEncoder().encode(prompts) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadPrompts() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([CustomPrompt].self, from: data) {
            prompts = decoded
        } else {
            prompts = CustomPrompt.defaultSystemPrompts
        }
    }

    // MARK: - Migration from old system
    private func migrateIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        var migratedPrompts = CustomPrompt.defaultSystemPrompts

        // Перенос кастомизированных текстов промптов из старой системы
        let oldKeys: [(String, String)] = [
            ("WB", "com.dictum.prompt.wb"),
            ("RU", "com.dictum.prompt.ru"),
            ("EN", "com.dictum.prompt.en"),
            ("CH", "com.dictum.prompt.ch")
        ]

        for (label, key) in oldKeys {
            if let customText = UserDefaults.standard.string(forKey: key),
               let idx = migratedPrompts.firstIndex(where: { $0.label == label }) {
                migratedPrompts[idx].prompt = customText
            }
        }

        // Сохранение в новом формате
        if let data = try? JSONEncoder().encode(migratedPrompts) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }

        // Отметка о миграции
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - CRUD Operations
    func addPrompt(_ prompt: CustomPrompt) {
        var newPrompt = prompt
        newPrompt.order = (prompts.map { $0.order }.max() ?? -1) + 1
        prompts.append(newPrompt)
    }

    func updatePrompt(_ prompt: CustomPrompt) {
        if let idx = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[idx] = prompt
        }
    }

    func deletePrompt(_ prompt: CustomPrompt) {
        prompts.removeAll { $0.id == prompt.id }
    }

    func toggleVisibility(_ prompt: CustomPrompt) {
        if let idx = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[idx].isVisible.toggle()
        }
    }

    func toggleFavorite(_ prompt: CustomPrompt) {
        if let idx = prompts.firstIndex(where: { $0.id == prompt.id }) {
            prompts[idx].isFavorite.toggle()
        }
    }

    func movePrompt(from source: IndexSet, to destination: Int) {
        var sorted = prompts.sorted { $0.order < $1.order }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, prompt) in sorted.enumerated() {
            if let idx = prompts.firstIndex(where: { $0.id == prompt.id }) {
                prompts[idx].order = index
            }
        }
    }

    func resetToDefaults() {
        prompts = CustomPrompt.defaultSystemPrompts
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    /// Восстанавливает удалённые системные промпты (WB/RU/EN/CH) без затирания пользовательских
    func restoreDefaultPrompts() {
        let existingLabels = Set(prompts.map { $0.label })

        for defaultPrompt in CustomPrompt.defaultSystemPrompts {
            if !existingLabels.contains(defaultPrompt.label) {
                let newOrder = (prompts.map { $0.order }.max() ?? -1) + 1
                let newPrompt = CustomPrompt(
                    id: UUID(),
                    label: defaultPrompt.label,
                    description: defaultPrompt.description,
                    prompt: defaultPrompt.prompt,
                    isVisible: defaultPrompt.isVisible,
                    isFavorite: defaultPrompt.isFavorite,
                    isSystem: defaultPrompt.isSystem,
                    order: newOrder
                )
                prompts.append(newPrompt)
            }
        }
    }

    func getPrompt(by label: String) -> CustomPrompt? {
        prompts.first { $0.label == label }
    }
}

// MARK: - Snippet Model
struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var shortcut: String        // "addr", "sig" (2-6 символов для быстрого доступа)
    var title: String           // "Домашний адрес" (описание)
    var content: String         // Текст сниппета (может быть многострочным)
    var isFavorite: Bool        // Показывать в строке быстрого доступа (ROW 1)
    var order: Int              // Порядок сортировки среди избранных

    static func create(shortcut: String, title: String, content: String) -> Snippet {
        Snippet(
            id: UUID(),
            shortcut: shortcut,
            title: title,
            content: content,
            isFavorite: false,
            order: 0
        )
    }

    // Дефолтные примеры сниппетов
    static let defaultSnippets: [Snippet] = []
}

// MARK: - Snippets Manager
class SnippetsManager: ObservableObject, @unchecked Sendable {
    static let shared = SnippetsManager()

    private let userDefaultsKey = "com.dictum.snippets"

    @Published var snippets: [Snippet] = [] {
        didSet { saveSnippets() }
    }

    // Избранные сниппеты для строки быстрого доступа (ROW 1)
    var favoriteSnippets: [Snippet] {
        snippets.filter { $0.isFavorite }.sorted { $0.order < $1.order }
    }

    // Все сниппеты отсортированные
    var allSnippets: [Snippet] {
        snippets.sorted { $0.order < $1.order }
    }

    init() {
        loadSnippets()
    }

    // MARK: - Persistence
    private func saveSnippets() {
        if let data = try? JSONEncoder().encode(snippets) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadSnippets() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = decoded
        } else {
            snippets = Snippet.defaultSnippets
        }
    }

    // MARK: - CRUD Operations
    func addSnippet(_ snippet: Snippet) {
        var newSnippet = snippet
        newSnippet.order = (snippets.map { $0.order }.max() ?? -1) + 1
        snippets.append(newSnippet)
    }

    func updateSnippet(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
        }
    }

    func deleteSnippet(_ snippet: Snippet) {
        snippets.removeAll { $0.id == snippet.id }
    }

    func toggleFavorite(_ snippet: Snippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx].isFavorite.toggle()
        }
    }

    func moveSnippet(from source: IndexSet, to destination: Int) {
        var sorted = snippets.sorted { $0.order < $1.order }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (index, snippet) in sorted.enumerated() {
            if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
                snippets[idx].order = index
            }
        }
    }

    func getSnippet(by shortcut: String) -> Snippet? {
        snippets.first { $0.shortcut == shortcut }
    }
}

// MARK: - Sound Manager
class SoundManager: @unchecked Sendable {
    static let shared = SoundManager()

    // Предзагруженные звуки для мгновенного воспроизведения
    private var openSound: NSSound?
    private var closeSound: NSSound?

    init() {
        // Загружаем кастомные звуки из бандла приложения
        if let openURL = Bundle.main.url(forResource: "open", withExtension: "wav", subdirectory: "sound") {
            openSound = NSSound(contentsOf: openURL, byReference: false)
            openSound?.volume = 0.7
        } else {
            NSLog("⚠️ Не найден звук open.wav в бандле")
        }

        if let closeURL = Bundle.main.url(forResource: "close", withExtension: "wav", subdirectory: "sound") {
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

    func playStopSound() {
        // Звук остановки записи - используем openSound как индикацию
        guard SettingsManager.shared.soundEnabled else { return }
        openSound?.stop()
        openSound?.play()
    }
}

// MARK: - Volume Manager
class VolumeManager: @unchecked Sendable {
    static let shared = VolumeManager()
    private var savedVolume: Int?

    func getCurrentVolume() -> Int? {
        let process = Process()
        let pipe = Pipe()

        // Fix 2: defer для cleanup Process/Pipe при любом выходе
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

        // Fix 2: defer для cleanup Process при любом выходе
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

// MARK: - Accessibility Helper
class AccessibilityHelper: @unchecked Sendable {
    static func checkAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            NSLog("⚠️ Accessibility permissions not granted")
        }
        return trusted
    }

    static func requestAccessibility() {
        // Значение kAXTrustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"
        // Используем строку напрямую для Swift 6 concurrency safety
        let options: [String: Bool] = ["AXTrustedCheckOptionPrompt": true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Проверяет, есть ли разрешение Screen Recording
    /// Надёжный способ: пытаемся получить список окон с именами
    /// Если нет Screen Recording - имена окон будут пустыми
    static func hasScreenRecordingPermission() -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        // Проверяем можем ли мы видеть имена окон других приложений
        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               let windowName = window[kCGWindowName as String] as? String,
               ownerName != "Dictum" && !windowName.isEmpty {
                return true  // Есть разрешение - видим имена окон
            }
        }
        return false
    }
}

// MARK: - Local ASR Provider (FluidAudio Parakeet v3)
// @unchecked Sendable: thread-safety обеспечивается через async/await и NSLock
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
        // Сначала проверяем наличие модели, потом загружаем
        Task {
            await checkModelStatus()
            if modelStatus == .notDownloaded {
                // Если модель не скачана, ждём явного запроса пользователя
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
                modelStatus = .loading  // Модель есть, нужно только загрузить
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
        // Останавливаем запись если идёт
        if isRecording {
            await stopRecordingAndTranscribe()
        }

        // Очищаем загруженные модели из памяти
        asrManager = nil
        models = nil

        await MainActor.run {
            isModelLoaded = false
            modelStatus = .notChecked
        }

        // Удаляем файлы модели
        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)

        do {
            // Удаляем папку parakeet-v3
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
            // Проверяем наличие модели
            let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
            let modelExists = AsrModels.modelsExist(at: cacheDir, version: .v3)

            if modelExists {
                // Модель уже скачана — только загружаем
                await MainActor.run { modelStatus = .loading }
                NSLog("🧠 Загрузка Parakeet v3 из кэша...")
            } else {
                // Модель нужно скачать
                await MainActor.run { modelStatus = .downloading }
                NSLog("⬇️ Скачивание Parakeet v3 (~600 MB)...")
            }

            // downloadAndLoad: скачивает если нужно, потом загружает
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
        // Guard против двойного вызова
        guard !isRecording else {
            NSLog("⚠️ Локальная запись уже идёт")
            return
        }

        // Проверить модель
        guard isModelLoaded, asrManager != nil else {
            await MainActor.run {
                errorMessage = "Модель не загружена. Подождите или откройте Настройки для загрузки."
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

        // Сброс накопленных сэмплов
        samplesLock.withLock {
            audioSamples.removeAll()
        }

        await MainActor.run {
            interimText = ""
            transcriptionResult = nil
            isRecording = true
            audioLevel = 0.0
        }

        // Уменьшить громкость до настроенного уровня
        VolumeManager.shared.saveAndReduceVolume(targetVolume: SettingsManager.shared.volumeLevel)

        // Создаём audio engine
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Валидация inputFormat
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            await MainActor.run {
                errorMessage = "Неверный формат входного аудио"
                isRecording = false
            }
            return
        }

        // Parakeet требует 16 kHz mono Float32
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
            await MainActor.run {
                errorMessage = "Ошибка формата аудио"
                isRecording = false
            }
            return
        }
        self.outputFormat = outFmt

        // Создаём converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outFmt) else {
            await MainActor.run {
                errorMessage = "Ошибка создания аудио-конвертера"
                isRecording = false
            }
            return
        }
        self.audioConverter = converter

        // Pre-allocated buffer (200ms capacity)
        let maxOutputFrames = AVAudioFrameCount(outFmt.sampleRate * 0.2)
        self.resampledBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: maxOutputFrames)

        engine.prepare()

        // Буфер 100ms для отзывчивого UI (audioLevel визуализация)
        let bufferSizeForInput = AVAudioFrameCount(inputFormat.sampleRate * 0.1)
        inputNode.installTap(onBus: 0, bufferSize: bufferSizeForInput, format: inputFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
            self.audioEngine = engine
            NSLog("🎤 Локальный ASR запущен (Parakeet v3)")

            // Показываем "Слушаю..." пока идёт запись (нет streaming у Parakeet)
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
            // Логарифмическая шкала + высокая чувствительность для шепота
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
        var hasData = true

        converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if hasData {
                outStatus.pointee = .haveData
                hasData = false
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        if let error = conversionError {
            NSLog("❌ Audio conversion error: \(error.localizedDescription)")
            return
        }

        // 3. Накопление сэмплов (batch processing - НЕ streaming)
        if let channelData = outputBuffer.floatChannelData {
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: Int(outputBuffer.frameLength)))
            samplesLock.withLock {
                audioSamples.append(contentsOf: samples)
            }
        }
    }

    func stopRecordingAndTranscribe() async {
        // Предотвращаем double stop
        guard !isStopInProgress else {
            NSLog("⚠️ stopRecording already in progress, skipping")
            return
        }
        isStopInProgress = true
        defer { isStopInProgress = false }

        // Остановить аудио
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        audioConverter?.reset()
        audioConverter = nil
        outputFormat = nil
        resampledBuffer = nil

        await MainActor.run {
            interimText = "Обрабатываю..."  // UI feedback
        }

        // Batch транскрибация накопленного аудио
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

            // Не показываем ошибку "слишком короткое аудио" — это нормальная ситуация
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

        // Очистка
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
    @Published var interimText: String = ""  // Текст в реальном времени
    @Published var appendMode: Bool = false   // Режим дозаписи
    @Published var audioLevel: Float = 0.0    // Уровень громкости 0.0-1.0

    private var audioEngine: AVAudioEngine?
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var finalTranscript: String = ""
    private var audioBuffer: [Data] = []      // Буфер для pre-buffering

    // Fix 20: Thread-safe webSocketConnected
    private var _webSocketConnected: Bool = false
    private let webSocketConnectedLock = NSLock()
    private var webSocketConnected: Bool {
        get { webSocketConnectedLock.withLock { _webSocketConnected } }
        set { webSocketConnectedLock.withLock { _webSocketConnected = newValue } }
    }

    // Fix 9: Флаг для предотвращения использования закрывающегося WebSocket
    private var isClosingWebSocket: Bool = false

    // Fix 11: Флаг получения финального ответа от Deepgram (speech_final или UtteranceEnd)
    private var finalResponseReceived: Bool = false

    // C1: WorkItem для отмены timeout при успешном подключении
    private var connectionTimeoutWorkItem: DispatchWorkItem?

    // Fix 4: NSLock для защиты finalTranscript от data race
    private let transcriptLock = NSLock()

    // Fix 5: Serial queue для thread-safe доступа к audioBuffer
    private let audioBufferQueue = DispatchQueue(label: "com.dictum.audioBuffer")

    // C2: Кешированный AudioConverter для производительности
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
        // Fix 4: Защита finalTranscript локом
        transcriptLock.withLock { finalTranscript = "" }
        // Fix 5: Защита audioBuffer через serial queue
        audioBufferQueue.sync { audioBuffer.removeAll() }
        webSocketConnected = false
        // Fix 11: Сброс флага финального ответа
        finalResponseReceived = false

        await MainActor.run {
            appendMode = isAppend
            interimText = ""
            transcriptionResult = nil
            isRecording = true
            audioLevel = 0.0
        }

        // Save current volume and reduce for recording
        VolumeManager.shared.saveAndReduceVolume(targetVolume: SettingsManager.shared.volumeLevel)

        // WebSocket URL
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
        NSLog("🔌 URL: \(wsURL.absoluteString)")

        // Fix 6 + C1: Timeout для WebSocket подключения (5 секунд)
        connectionTimeoutWorkItem?.cancel()  // Отменить предыдущий если есть
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

        // Слушать ответы
        receiveMessages()

        // 1. СНАЧАЛА настроить аудио (до WebSocket для минимизации задержки)
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            await MainActor.run { errorMessage = "Ошибка инициализации аудио" }
            return
        }
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Проверяем валидность формата (как в LocalASR)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            await MainActor.run { errorMessage = "Аудио устройство недоступно" }
            return
        }

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
            // Логарифмическая шкала + высокая чувствительность для шепота
            let normalizedRms = rms * 50.0
            let level = min(1.0, log10(1 + normalizedRms * 9))  // log10(1..10) = 0..1

            DispatchQueue.main.async { [weak self] in
                self?.audioLevel = level
            }
        }

        // 2. Конвертировать в 16kHz (C2: используем кешированный converter)
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

            // Fix 5: Защита audioBuffer через serial queue
            audioBufferQueue.async { [weak self] in
                guard let self = self else { return }

                // Pre-buffering: буферизируем пока WebSocket не подключен
                if self.webSocketConnected {
                    // Сначала отправить буферизованные данные
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
                    // Отправить текущие данные
                    self.webSocket?.send(.data(data)) { error in
                        if let error = error {
                            NSLog("❌ Ошибка отправки аудио: \(error.localizedDescription)")
                        }
                    }
                } else {
                    // Fix 35: Буферизируем (макс. 3 секунды = ~30 чанков по 100мс)
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
        // Остановить аудио
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // C2: Сбросить кешированный converter
        cachedConverter = nil
        cachedInputFormat = nil
        cachedOutputFormat = nil

        // Отправляем сигнал закрытия потока (НЕ устанавливаем isClosingWebSocket ещё!)
        webSocket?.send(.string("{\"type\": \"CloseStream\"}")) { _ in }

        // Fix 11: Ждём finalResponseReceived вместо фиксированной задержки
        // isClosingWebSocket остаётся false, чтобы receiveMessages() продолжал работать
        // Polling с таймаутом 2 сек (safety fallback)
        let deadline = Date().addingTimeInterval(2.0)
        while !finalResponseReceived && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms poll
        }

        if finalResponseReceived {
            NSLog("✅ Получен финальный ответ от Deepgram (speech_final или UtteranceEnd)")
        } else {
            NSLog("⚠️ Timeout ожидания финального ответа (2 сек)")
        }

        // Fix 9: Только теперь устанавливаем флаг закрытия
        isClosingWebSocket = true
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        webSocketConnected = false
        // Fix: Сбрасываем флаг с задержкой, чтобы избежать race condition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isClosingWebSocket = false
        }

        // Fix 4: Защита finalTranscript локом при чтении
        let finalText = transcriptLock.withLock { finalTranscript }

        await MainActor.run {
            isRecording = false
            if !finalText.isEmpty {
                transcriptionResult = finalText.trimmingCharacters(in: .whitespaces)
            }
            interimText = ""
        }

        // Restore original volume
        VolumeManager.shared.restoreVolume()

        NSLog("✅ Результат: \(finalText)")
    }

    private func receiveMessages() {
        // Fix 3: Guard на состояние webSocket
        // Fix 9: Также проверяем isClosingWebSocket
        // Fix 10: НЕ проверяем isRecording — нужно получать финальные результаты после остановки записи!
        guard let webSocket = webSocket, !isClosingWebSocket else { return }

        webSocket.receive { [weak self] result in
            guard let self = self, self.webSocket != nil, !self.isClosingWebSocket else { return }

            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleResponse(text)
                }
                // Продолжаем слушать пока WebSocket не закрывается
                // (даже после остановки записи - чтобы получить финальные результаты)
                if !self.isClosingWebSocket {
                    self.receiveMessages()
                }

            case .failure(let error):
                // Fix 9: Игнорируем ошибки если уже закрываемся
                guard !self.isClosingWebSocket else { return }
                NSLog("❌ WS error: \(error.localizedDescription)")
                // Fix 3: Закрываем WebSocket при ошибке
                self.isClosingWebSocket = true
                self.webSocket?.cancel(with: .goingAway, reason: nil)
                self.webSocket = nil
                // Fix: Сбрасываем флаг с задержкой
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.isClosingWebSocket = false
                }
            }
        }
    }

    private func handleResponse(_ text: String) {
        // Логируем сырой ответ для диагностики
        NSLog("📥 Deepgram: \(text.prefix(500))...")

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("⚠️ Deepgram: не удалось распарсить JSON")
            return
        }

        // Проверяем тип сообщения
        let messageType = json["type"] as? String ?? "unknown"

        // Обрабатываем служебные сообщения
        if messageType == "Metadata" || messageType == "SpeechStarted" {
            NSLog("📋 Deepgram: служебное сообщение типа \(messageType)")
            return
        }

        // Fix 11: UtteranceEnd — fallback если speech_final не пришёл
        if messageType == "UtteranceEnd" {
            if !finalResponseReceived {
                finalResponseReceived = true
                NSLog("🎯 UtteranceEnd received (fallback для speech_final)")
            }
            return
        }

        // Парсим Results
        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let transcript = alternatives.first?["transcript"] as? String else {
            NSLog("⚠️ Deepgram: неизвестный формат ответа, type=\(messageType), keys=\(json.keys.joined(separator: ", "))")
            return
        }

        let isFinal = json["is_final"] as? Bool ?? false
        let speechFinal = json["speech_final"] as? Bool ?? false  // Fix 11: Конец речи

        DispatchQueue.main.async {
            if isFinal && !transcript.isEmpty {
                // Fix 4: Защита finalTranscript локом
                self.transcriptLock.withLock {
                    self.finalTranscript += (self.finalTranscript.isEmpty ? "" : " ") + transcript
                }
                self.interimText = ""
                NSLog("📝 Final: \(transcript)")
            } else if !transcript.isEmpty {
                self.interimText = transcript
                NSLog("📝 Interim: \(transcript)")
            }

            // Fix 11: speech_final=true означает конец речи — сигнал для stopRecording
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

        // Установить флаг
        webSocketConnected = true

        // C1: Отменить timeout - подключение успешно
        connectionTimeoutWorkItem?.cancel()
        connectionTimeoutWorkItem = nil

        // Fix 5: Защита audioBuffer через serial queue
        audioBufferQueue.async { [weak self] in
            guard let self = self else { return }

            // Отправить все буферизованные чанки
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
    case local = "local"     // Локальная модель (Parakeet v3)
    case deepgram = "deepgram"  // Deepgram (облако)

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
        // Fix R4-M1: guard let вместо force unwrap
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

        // 4. Создать запрос
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
class GeminiService: ObservableObject, @unchecked Sendable {
    /// Модель для LLM-обработки после локального ASR
    private var modelForSpeech: String {
        SettingsManager.shared.selectedGeminiModel.rawValue
    }

    /// Модель для AI функций (кнопки WB, RU, EN, CH)
    private var modelForAI: String {
        SettingsManager.shared.selectedGeminiModelForAI.rawValue
    }

    /// Генерация контента с указанием контекста использования
    func generateContent(prompt: String, userText: String, forAI: Bool = true, systemPrompt: String? = nil) async throws -> String {
        guard let apiKey = GeminiKeyManager.shared.getAPIKey(), !apiKey.isEmpty else {
            throw GeminiError.noAPIKey
        }

        let model = forAI ? modelForAI : modelForSpeech

        // Fix R4-M1: guard let вместо force unwrap
        let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"
        guard var components = URLComponents(string: baseURL) else {
            throw GeminiError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let url = components.url else {
            throw GeminiError.invalidResponse
        }

        // Формируем тело запроса
        var requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": "Инструкции: \(prompt)\n\nТекст:\n\(userText)"]]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": SettingsManager.shared.maxOutputTokens,
                "topP": 0.95
            ]
        ]

        // Добавляем системный промпт если есть
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            requestBody["systemInstruction"] = [
                "parts": [["text": systemPrompt]]
            ]
        }

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

        // Fix R4-M1: guard let вместо force unwrap
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

// MARK: - Main View
struct InputModalView: View {
    @StateObject private var audioManager = AudioRecordingManager()  // Deepgram
    @StateObject private var localASRManager = SherpaASRProvider()   // Локальная модель Parakeet v3
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
    @State private var showHistory: Bool = false
    @State private var searchQuery: String = ""
    @State private var historyItems: [HistoryItem] = []
    @State private var textEditorHeight: CGFloat = 40
    @State private var isProcessingAI: Bool = false
    @State private var currentProcessingPrompt: CustomPrompt? = nil
    // Fix 25: Proper @State for alert instead of .constant()
    @State private var showASRErrorAlert: Bool = false
    // Состояние: запись остановлена хоткеем (для 3-фазной логики)
    @State private var recordingStoppedByHotkey: Bool = false
    // Alert при отсутствии API ключа для AI функций
    @State private var showAPIKeyAlert: Bool = false
    @StateObject private var geminiService = GeminiService()
    @ObservedObject private var promptsManager = PromptsManager.shared
    @ObservedObject private var snippetsManager = SnippetsManager.shared

    // Панели управления (mutual exclusivity с showHistory)
    @State private var showAIPanel: Bool = false
    @State private var showSnippetsPanel: Bool = false
    @State private var showLeftPanel: Bool = false       // Sliding panel для промптов слева
    @State private var showRightPanel: Bool = false      // Sliding panel для сниппетов справа
    @State private var showAddSnippetSheet: Bool = false // Sheet для добавления сниппета
    @State private var showAddPromptSheet: Bool = false  // Sheet для добавления промпта
    @State private var editingPrompt: CustomPrompt? = nil  // Редактируемый промпт
    @State private var editingSnippet: Snippet? = nil  // Редактируемый сниппет

    // Максимум 30 строк (~600px), минимум 40px
    private let lineHeight: CGFloat = 20
    private let maxLines: Int = 30

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
                .background(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .allowsHitTesting(false)
        }
    }

    // Константы для layout панелей
    private let mainModalWidth: CGFloat = 680
    private let panelWidth: CGFloat = 180
    private let panelGap: CGFloat = 8

    // Offset от центра: половина модалки + половина панели + отступ
    private var panelOffset: CGFloat {
        (mainModalWidth / 2) + (panelWidth / 2) + panelGap
    }

    var body: some View {
        ZStack(alignment: .center) {
            // СЛЕВА: Выезжающая панель промптов (под модалкой)
            SlidingPromptPanel(
                promptsManager: promptsManager,
                onProcessWithGemini: { prompt in
                    Task {
                        await processWithGemini(prompt: prompt)
                    }
                },
                currentProcessingPrompt: currentProcessingPrompt,
                onAdd: { showAddPromptSheet = true },
                editingPrompt: $editingPrompt
            )
            .offset(x: showLeftPanel ? -panelOffset : -panelOffset - 200)  // Скрыта слева
            .opacity(showLeftPanel ? 1 : 0)
            .zIndex(0)

            // СПРАВА: Выезжающая панель сниппетов (под модалкой)
            SlidingSnippetPanel(
                snippetsManager: snippetsManager,
                inputText: $inputText,
                onAdd: { showAddSnippetSheet = true },
                editingSnippet: $editingSnippet
            )
            .offset(x: showRightPanel ? panelOffset : panelOffset + 200)  // Скрыта справа
            .opacity(showRightPanel ? 1 : 0)
            .zIndex(0)

            // ОСНОВНАЯ МОДАЛКА (поверх панелей)
            VStack(spacing: 0) {
                // ВЕРХНЯЯ ЧАСТЬ: Ввод + Оверлеи
                VStack(spacing: 0) {
                // Поле ввода с динамической высотой
                ZStack(alignment: .topLeading) {
                    CustomTextEditor(
                        text: $inputText,
                        // В аудио режиме: только копировать в буфер, без автовставки
                        onSubmit: { submitImmediate(skipAutoPaste: settings.audioModeEnabled) },
                        onHeightChange: { height in
                            // Ограничиваем высоту до 30 строк
                            textEditorHeight = min(max(40, height), maxTextHeight)
                        },
                        highlightForeignWords: settings.highlightForeignWords
                    )
                    .font(.system(size: 16, weight: .regular))
                    .frame(height: textEditorHeight)
                    .padding(.leading, 20)
                    .padding(.trailing, 50)  // Увеличено для иконки "Улучшить"
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                    .background(Color.clear)

                    if inputText.isEmpty && !isRecording {
                        Text("Введите текст...")
                            .font(.system(size: 16, weight: .regular, design: .default))
                            .foregroundColor(Color.white.opacity(0.45))
                            .padding(.leading, 28)
                            .padding(.top, 18)
                            .allowsHitTesting(false)
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

                // Список истории (упрощённый)
                // Раскрывающиеся панели (mutual exclusivity)
                if showHistory {
                    HistoryListView(
                        items: historyItems,
                        searchQuery: $searchQuery,
                        onSelect: { item in
                            textEditorHeight = 40  // Сброс высоты перед вставкой текста
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
            .overlay(recordingOverlay)

            // НИЖНЯЯ ЧАСТЬ: Футер (2 строки)
            VStack(spacing: 0) {
                // ROW 1: Быстрый доступ (AI промпты слева + Сниппеты справа)
                if settings.aiEnabled || !snippetsManager.snippets.isEmpty {
                    // ROW 1: Только основная строка (панели вынесены в ZStack снаружи модалки)
                    UnifiedQuickAccessRow(
                        promptsManager: promptsManager,
                        snippetsManager: snippetsManager,
                        inputText: $inputText,
                        showLeftPanel: $showLeftPanel,
                        showRightPanel: $showRightPanel,
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
                                        NSLog("❌ canStartASR() вернул false")
                                        setASRError("API ключ не найден. Откройте Настройки (Cmd+,)")
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

                        // Кнопка История
                        Button(action: {
                            // Закрыть sliding panels при открытии истории
                            showLeftPanel = false
                            showRightPanel = false
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

                    // Кнопка Отправить (активная) - зелёный #19af87
                    // В аудио режиме: только копировать в буфер, без автовставки
                    Button(action: { submitImmediate(skipAutoPaste: settings.audioModeEnabled) }) {
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
                .clipShape(RoundedRectangle(cornerRadius: 24))  // Скругление применяется к подложке
        )
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(DesignSystem.Colors.borderColor, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.65), radius: 27, x: 0, y: 24)
        .frame(width: 680)
        .zIndex(1)  // Модалка поверх панелей
        } // ZStack
        .frame(width: 1060)  // Ширина окна: модалка + панели
        .animation(.easeInOut(duration: 0.25), value: showLeftPanel)
        .animation(.easeInOut(duration: 0.25), value: showRightPanel)
        .onAppear {
            resetView()

            // Мгновенный автозапуск записи в режиме Аудио (без задержки!)
            if settings.audioModeEnabled && canStartASR() && !isRecording {
                Task {
                    await startASR(existingText: "")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetInputView)) { _ in
            resetView()
            // Автозапуск только в .onAppear чтобы избежать race condition
        }
        .onChange(of: settings.audioModeEnabled) { isAudioMode in
            // При включении режима Аудио - запустить запись
            if isAudioMode && !isRecording && canStartASR() {
                Task {
                    await startASR(existingText: inputText)
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
        .onChange(of: localASRManager.transcriptionResult) { newValue in
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
        // Fix 25: Use proper @State binding for alert
        .alert("Ошибка", isPresented: $showASRErrorAlert) {
            Button("OK") {
                showASRErrorAlert = false
                clearASRError()
            }
        } message: {
            Text(asrErrorMessage ?? "")
        }
        .onChange(of: asrErrorMessage) { error in
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
        // Sheet для редактирования промпта (из SlidingPromptPanel)
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
    }

    private func resetView() {
        inputText = ""
        showHistory = false
        showLeftPanel = false
        showRightPanel = false
        searchQuery = ""
        historyItems = []
        textEditorHeight = 40
        recordingStoppedByHotkey = false
        editingPrompt = nil
        editingSnippet = nil
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

    /// Проверяет можно ли начать запись (для Deepgram нужен API key)
    private func canStartASR() -> Bool {
        if settings.asrProviderType == .local {
            return true  // Локальная модель всегда доступна
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
                .frame(height: min(CGFloat(items.count) * 44, 5 * 44)) // max 5 строк видно
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

    private let barCount = 100
    private let recordingColor = Color(red: 254/255, green: 67/255, blue: 70/255) // #fe4346

    // Предварительно сгенерированные случайные факторы для органичности
    private let randomFactors: [CGFloat] = (0..<100).map { _ in CGFloat.random(in: 0.85...1.15) }

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

        let maxHeight: CGFloat = 50  // Ограничено чтобы не выходить за пределы поля ввода
        let animatedHeight = maxHeight * CGFloat(audioLevel) * heightMultiplier * randomFactors[index]
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

    // Разная скорость анимации — центр быстрее
    private func animationDuration(for index: Int) -> Double {
        let center = CGFloat(barCount) / 2.0
        let distanceFromCenter = abs(CGFloat(index) - center) / center

        if distanceFromCenter > 0.9 { return 0.7 }
        if distanceFromCenter > 0.7 { return 0.6 }
        if distanceFromCenter > 0.5 { return 0.5 }
        if distanceFromCenter > 0.3 { return 0.4 }
        if distanceFromCenter > 0.1 { return 0.3 }
        return 0.25 // центр — быстрее всего
    }
}

// MARK: - Screenshot Notification View
struct ScreenshotNotificationView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(DesignSystem.Colors.accent)

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
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSystem: Bool = false  // Системные промпты нельзя удалить

    @State private var trimOffset: CGFloat = 0

    var body: some View {
        Button(action: action) {
            ZStack {
                // Фон кнопки
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isLoading ? DesignSystem.Colors.accent : .white.opacity(0.8))
                    .frame(width: 28, height: 24)
                    .background(
                        ZStack {
                            // Основной фон
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(isLoading ? 0.05 : 0.1))

                            // Полупрозрачная рамка при загрузке (как "колея")
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

                // Бегающая точка (индикатор загрузки)
                if isLoading {
                    RoundedRectangle(cornerRadius: 4)
                        .trim(from: trimOffset, to: trimOffset + 0.12)
                        .stroke(
                            DesignSystem.Colors.accent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: 28, height: 24)
                        .shadow(color: DesignSystem.Colors.accent.opacity(0.8), radius: 4)
                        .shadow(color: DesignSystem.Colors.accent, radius: 2)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
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
    @Binding var showLeftPanel: Bool      // Панель промптов слева
    @Binding var showRightPanel: Bool     // Панель сниппетов справа
    let onProcessWithGemini: (CustomPrompt) -> Void
    let currentProcessingPrompt: CustomPrompt?

    // Для редактирования
    @Binding var editingPrompt: CustomPrompt?
    @Binding var editingSnippet: Snippet?

    // Только избранные элементы для быстрого доступа
    private var favoritePrompts: [CustomPrompt] {
        promptsManager.prompts.filter { $0.isFavorite }.sorted { $0.order < $1.order }
    }

    private var favoriteSnippets: [Snippet] {
        snippetsManager.snippets.filter { $0.isFavorite }.sorted { $0.order < $1.order }
    }

    private var hasNonFavoritePrompts: Bool {
        promptsManager.prompts.contains { !$0.isFavorite }
    }

    private var hasNonFavoriteSnippets: Bool {
        snippetsManager.snippets.contains { !$0.isFavorite }
    }

    var body: some View {
        HStack(spacing: 6) {
            // LEFT: Кнопка раскрытия панели промптов "<"
            if hasNonFavoritePrompts {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showLeftPanel.toggle()
                        if showLeftPanel { showRightPanel = false }
                    }
                }) {
                    Image(systemName: showLeftPanel ? "chevron.right" : "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(showLeftPanel ? Color.white.opacity(0.15) : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("Дополнительные промпты")
            }

            // Избранные промпты
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
                        promptsManager.deletePrompt(prompt)
                    },
                    isSystem: prompt.isSystem
                )
            }

            Spacer()

            // Избранные сниппеты
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
                        snippetsManager.deleteSnippet(snippet)
                    }
                )
            }

            // RIGHT: Кнопка раскрытия панели сниппетов ">"
            if hasNonFavoriteSnippets {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRightPanel.toggle()
                        if showRightPanel { showLeftPanel = false }
                    }
                }) {
                    Image(systemName: showRightPanel ? "chevron.left" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(showRightPanel ? Color.white.opacity(0.15) : Color.white.opacity(0.1))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .help("Дополнительные сниппеты")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Sliding Prompt Panel (левая панель с non-favorite промптами)
struct SlidingPromptPanel: View {
    @ObservedObject var promptsManager: PromptsManager
    let onProcessWithGemini: (CustomPrompt) -> Void
    let currentProcessingPrompt: CustomPrompt?
    let onAdd: () -> Void
    @Binding var editingPrompt: CustomPrompt?

    private var nonFavoritePrompts: [CustomPrompt] {
        promptsManager.prompts.filter { !$0.isFavorite }.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок с кнопкой добавления
            HStack {
                Text("Промпты")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Добавить промпт")
            }

            // Список non-favorite промптов
            if nonFavoritePrompts.isEmpty {
                Text("Нет дополнительных промптов")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(nonFavoritePrompts) { prompt in
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
                                promptsManager.deletePrompt(prompt)
                            },
                            isSystem: prompt.isSystem
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 180)
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Sliding Snippet Panel (правая панель с non-favorite сниппетами)
struct SlidingSnippetPanel: View {
    @ObservedObject var snippetsManager: SnippetsManager
    @Binding var inputText: String
    let onAdd: () -> Void
    @Binding var editingSnippet: Snippet?

    private var nonFavoriteSnippets: [Snippet] {
        snippetsManager.snippets.filter { !$0.isFavorite }.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Заголовок с кнопкой добавления
            HStack {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Добавить сниппет")
                Spacer()
                Text("Сниппеты")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }

            // Список non-favorite сниппетов
            if nonFavoriteSnippets.isEmpty {
                Text("Нет дополнительных сниппетов")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(nonFavoriteSnippets) { snippet in
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
                                snippetsManager.deleteSnippet(snippet)
                            }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 180)
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
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

// MARK: - AI Prompts Panel (раскрывающаяся панель управления промптами)
struct AIPromptsPanel: View {
    @ObservedObject var promptsManager: PromptsManager
    @Binding var inputText: String
    let onProcessWithGemini: (CustomPrompt) -> Void
    let currentProcessingPrompt: CustomPrompt?

    @State private var editingPrompt: CustomPrompt? = nil
    @State private var showAddSheet: Bool = false

    private let maxVisibleRows = 5
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            // Заголовок с кнопкой добавления
            HStack {
                Text("AI ПРОМПТЫ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))

                Spacer()

                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Добавить промпт")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()
                .background(Color.white.opacity(0.1))

            // Список промптов
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(promptsManager.prompts.sorted { $0.order < $1.order }) { prompt in
                        PromptRowView(
                            prompt: prompt,
                            isProcessing: currentProcessingPrompt?.id == prompt.id,
                            onToggleFavorite: {
                                promptsManager.toggleFavorite(prompt)
                            },
                            onEdit: {
                                editingPrompt = prompt
                            },
                            onDelete: {
                                if !prompt.isSystem {
                                    promptsManager.deletePrompt(prompt)
                                }
                            },
                            onTap: {
                                onProcessWithGemini(prompt)
                            }
                        )
                    }
                }
            }
            .frame(maxHeight: CGFloat(maxVisibleRows) * rowHeight)
        }
        .background(Color.black.opacity(0.2))
        .sheet(item: $editingPrompt) { prompt in
            PromptEditView(
                prompt: prompt,
                onSave: { updated in
                    promptsManager.updatePrompt(updated)
                    editingPrompt = nil
                },
                onCancel: {
                    editingPrompt = nil
                }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            PromptAddView(
                onSave: { newPrompt in
                    promptsManager.addPrompt(newPrompt)
                    showAddSheet = false
                },
                onCancel: {
                    showAddSheet = false
                }
            )
        }
    }
}

// MARK: - Prompt Row View
struct PromptRowView: View {
    let prompt: CustomPrompt
    let isProcessing: Bool
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Звезда избранного
            Button(action: onToggleFavorite) {
                Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(prompt.isFavorite ? .yellow : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            // Label badge
            Text(prompt.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 32, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )

            // Description
            Text(prompt.description)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)

            Spacer()

            // Actions (показываются при наведении)
            if isHovered {
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.gray)

                    if !prompt.isSystem {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.red.opacity(0.7))
                    }
                }
            }

            // Loading indicator
            if isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Prompt Edit View (Sheet)
struct PromptEditView: View {
    let prompt: CustomPrompt
    let onSave: (CustomPrompt) -> Void
    let onCancel: () -> Void

    @State private var editedLabel: String
    @State private var editedDescription: String
    @State private var editedPrompt: String

    init(prompt: CustomPrompt, onSave: @escaping (CustomPrompt) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        _editedLabel = State(initialValue: prompt.label)
        _editedDescription = State(initialValue: prompt.description)
        _editedPrompt = State(initialValue: prompt.prompt)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Редактировать промпт")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Label (2-4 символа)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("WB", text: $editedLabel)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .disabled(prompt.isSystem)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Описание")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("Описание промпта", text: $editedDescription)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Текст промпта")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $editedPrompt)
                        .font(.system(size: 13))
                        .frame(height: 120)
                        .border(Color.gray.opacity(0.3), width: 1)
                }
            }

            HStack {
                Button("Отмена") { onCancel() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Сохранить") {
                    var updated = prompt
                    updated.label = editedLabel
                    updated.description = editedDescription
                    updated.prompt = editedPrompt
                    onSave(updated)
                }
                .keyboardShortcut(.return)
                .disabled(editedLabel.isEmpty || editedPrompt.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Prompt Add View (Sheet)
struct PromptAddView: View {
    let onSave: (CustomPrompt) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var description: String = ""
    @State private var promptText: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Новый AI промпт")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Label (2-4 символа)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("FIX", text: $label)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Описание")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("Исправить ошибки", text: $description)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Текст промпта")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $promptText)
                        .font(.system(size: 13))
                        .frame(height: 120)
                        .border(Color.gray.opacity(0.3), width: 1)
                }
            }

            HStack {
                Button("Отмена") { onCancel() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Добавить") {
                    let newPrompt = CustomPrompt(
                        id: UUID(),
                        label: label,
                        description: description,
                        prompt: promptText,
                        isVisible: true,
                        isFavorite: false,
                        isSystem: false,
                        order: 0
                    )
                    onSave(newPrompt)
                }
                .keyboardShortcut(.return)
                .disabled(label.isEmpty || promptText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Snippets Panel (раскрывающаяся панель управления сниппетами)
struct SnippetsPanel: View {
    @ObservedObject var snippetsManager: SnippetsManager
    @Binding var inputText: String

    @State private var editingSnippet: Snippet? = nil
    @State private var showAddSheet: Bool = false

    private let maxVisibleRows = 5
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            // Заголовок с кнопкой добавления
            HStack {
                Text("СНИППЕТЫ")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.5))

                Spacer()

                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Добавить сниппет")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()
                .background(Color.white.opacity(0.1))

            if snippetsManager.snippets.isEmpty {
                // Пустое состояние
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(.gray)
                    Text("Нет сниппетов")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Text("Нажмите + чтобы создать")
                        .font(.system(size: 11))
                        .foregroundColor(.gray.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                // Список сниппетов
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snippetsManager.allSnippets) { snippet in
                            SnippetRowView(
                                snippet: snippet,
                                onToggleFavorite: {
                                    snippetsManager.toggleFavorite(snippet)
                                },
                                onEdit: {
                                    editingSnippet = snippet
                                },
                                onDelete: {
                                    snippetsManager.deleteSnippet(snippet)
                                },
                                onInsert: {
                                    inputText += snippet.content
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: CGFloat(maxVisibleRows) * rowHeight)
            }
        }
        .background(Color.black.opacity(0.2))
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditView(
                snippet: snippet,
                onSave: { updated in
                    snippetsManager.updateSnippet(updated)
                    editingSnippet = nil
                },
                onCancel: {
                    editingSnippet = nil
                }
            )
        }
        .sheet(isPresented: $showAddSheet) {
            SnippetAddView(
                onSave: { newSnippet in
                    snippetsManager.addSnippet(newSnippet)
                    showAddSheet = false
                },
                onCancel: {
                    showAddSheet = false
                }
            )
        }
    }
}

// MARK: - Snippet Row View
struct SnippetRowView: View {
    let snippet: Snippet
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onInsert: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                // Звезда избранного
                Button(action: onToggleFavorite) {
                    Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundColor(snippet.isFavorite ? .yellow : .gray)
                }
                .buttonStyle(PlainButtonStyle())

                // Shortcut badge
                Text(snippet.shortcut)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.Colors.accent.opacity(0.2))
                    )

                // Title
                Text(snippet.title)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)

                Spacer()

                // Expand/collapse
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())

                // Actions
                if isHovered {
                    HStack(spacing: 8) {
                        Button(action: onEdit) {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.gray)

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: onInsert)
            .onHover { hovering in
                isHovered = hovering
            }

            // Expanded content
            if isExpanded {
                Text(snippet.content)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(3)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
    }
}

// MARK: - Snippet Edit View (Sheet)
struct SnippetEditView: View {
    let snippet: Snippet
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @State private var editedShortcut: String
    @State private var editedTitle: String
    @State private var editedContent: String

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        self.onCancel = onCancel
        _editedShortcut = State(initialValue: snippet.shortcut)
        _editedTitle = State(initialValue: snippet.title)
        _editedContent = State(initialValue: snippet.content)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Редактировать сниппет")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcut (2-6 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("addr", text: $editedShortcut)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Название")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("Домашний адрес", text: $editedTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Текст сниппета")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $editedContent)
                        .font(.system(size: 13))
                        .frame(height: 120)
                        .border(Color.gray.opacity(0.3), width: 1)
                }
            }

            HStack {
                Button("Отмена") { onCancel() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Сохранить") {
                    var updated = snippet
                    updated.shortcut = editedShortcut
                    updated.title = editedTitle
                    updated.content = editedContent
                    onSave(updated)
                }
                .keyboardShortcut(.return)
                .disabled(editedShortcut.isEmpty || editedContent.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Snippet Add View (Sheet)
struct SnippetAddView: View {
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @State private var shortcut: String = ""
    @State private var title: String = ""
    @State private var content: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Новый сниппет")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shortcut (2-6 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("addr", text: $shortcut)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Название")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("Домашний адрес", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Текст сниппета")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $content)
                        .font(.system(size: 13))
                        .frame(height: 120)
                        .border(Color.gray.opacity(0.3), width: 1)
                }
            }

            HStack {
                Button("Отмена") { onCancel() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Добавить") {
                    let newSnippet = Snippet.create(
                        shortcut: shortcut,
                        title: title,
                        content: content
                    )
                    onSave(newSnippet)
                }
                .keyboardShortcut(.return)
                .disabled(shortcut.isEmpty || content.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
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

        // Fix 11: Кешированный regex (компилируется один раз)
        private static let wordRegex = try! NSRegularExpression(pattern: "[\\p{L}]+")

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

            // Fix 11: Используем кешированный regex
            let nsText = text as NSString
            let matches = Self.wordRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

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

    let scale = size / 100.0

    // Хелпер для конвертации SVG координат в Core Graphics
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x * scale, y: size - y * scale)
    }

    // Создаём путь буквы D
    func createDPath() -> NSBezierPath {
        let path = NSBezierPath()

        // Внешний контур
        path.move(to: point(20, 20))
        path.line(to: point(50, 20))
        path.curve(to: point(80, 50),
                   controlPoint1: point(67, 20),
                   controlPoint2: point(80, 33))
        path.curve(to: point(50, 80),
                   controlPoint1: point(80, 67),
                   controlPoint2: point(67, 80))
        path.line(to: point(20, 80))
        path.close()

        // Внутреннее отверстие
        path.move(to: point(37, 35))
        path.line(to: point(37, 65))
        path.line(to: point(47, 65))
        path.curve(to: point(62, 50),
                   controlPoint1: point(55, 65),
                   controlPoint2: point(62, 58))
        path.curve(to: point(47, 35),
                   controlPoint1: point(62, 42),
                   controlPoint2: point(55, 35))
        path.close()

        path.windingRule = .evenOdd
        return path
    }

    // Clipping path для верхней части
    func createTopClip() -> NSBezierPath {
        let clip = NSBezierPath()
        clip.move(to: point(-10, -10))
        clip.line(to: point(110, -10))
        clip.line(to: point(110, 34))
        clip.line(to: point(-10, 60))
        clip.close()
        return clip
    }

    // Clipping path для нижней части
    func createBottomClip() -> NSBezierPath {
        let clip = NSBezierPath()
        clip.move(to: point(-10, 68))
        clip.line(to: point(110, 42))
        clip.line(to: point(110, 110))
        clip.line(to: point(-10, 110))
        clip.close()
        return clip
    }

    // Рисуем верхнюю часть (белая, сдвинутая)
    NSGraphicsContext.saveGraphicsState()
    createTopClip().addClip()

    let transform1 = AffineTransform(translationByX: -1.5 * scale, byY: 1.5 * scale)
    let upperPath = createDPath()
    upperPath.transform(using: transform1)

    NSColor.white.setFill()
    upperPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Рисуем нижнюю часть (серая, сдвинутая)
    NSGraphicsContext.saveGraphicsState()
    createBottomClip().addClip()

    let transform2 = AffineTransform(translationByX: 1.5 * scale, byY: -1.5 * scale)
    let lowerPath = createDPath()
    lowerPath.transform(using: transform2)

    NSColor(red: 0x9a / 255.0, green: 0x9a / 255.0, blue: 0x9c / 255.0, alpha: 1.0).setFill()
    lowerPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Красная точка (такие же пропорции как в основной иконке)
    let dotRadius = 8 * scale
    let dotCenter = point(82, 17)
    let dotRect = NSRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    let dotPath = NSBezierPath(ovalIn: dotRect)
    NSColor(red: 0xd9 / 255.0, green: 0x3f / 255.0, blue: 0x41 / 255.0, alpha: 1.0).setFill()
    dotPath.fill()

    image.unlockFocus()
    image.isTemplate = false
    return image
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
    case features = "Инструменты"
    case speech = "Диктовка"
    case ai = "AI"
    case snippets = "Сниппеты"
    case updates = "Обновления"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .features: return "camera.fill"
        case .speech: return "waveform"
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

// Кастомный стиль тумблера с цветом #1aaf87
// Остается зеленым даже при потере фокуса окна (не серый как стандартный SwitchToggleStyle)
struct GreenToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                Capsule()
                    .fill(configuration.isOn ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                    .frame(width: 51, height: 31)

                Circle()
                    .fill(Color.white)
                    .frame(width: 27, height: 27)
                    .offset(x: configuration.isOn ? 10 : -10)
                    .animation(.easeInOut(duration: 0.2), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

// MARK: - Checkbox Toggle Style (для экспорта настроек)
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundColor(configuration.isOn ? DesignSystem.Colors.accent : .gray.opacity(0.5))
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = {
        let savedTab = SettingsManager.shared.lastSettingsTab
        return SettingsTab.allCases.first { $0.rawValue == savedTab } ?? .general
    }()
    @State private var launchAtLogin: Bool = LaunchAtLoginManager.shared.isEnabled
    // Fix 13: Removed @State soundEnabled duplicate - use settings.soundEnabled directly
    @State private var hasAccessibility: Bool = AccessibilityHelper.checkAccessibility()
    @State private var hasMicrophonePermission: Bool = Self.checkMicrophonePermission()
    @State private var hasScreenRecordingPermission: Bool = Self.checkScreenRecordingPermission()
    @State private var currentHotkey: HotkeyConfig = SettingsManager.shared.toggleHotkey
    @State private var isRecordingHotkey: Bool = false
    @State private var isRecordingScreenshotHotkey: Bool = false
    @State private var screenshotHotkey: HotkeyConfig = SettingsManager.shared.screenshotHotkey
    // Fix 13: Removed @State aiEnabled duplicate - use settings.aiEnabled directly
    @ObservedObject private var settings = SettingsManager.shared
    // Config export/import (все опции включены по умолчанию)
    @State private var exportHistory: Bool = true         // История заметок
    @State private var exportAIFunctions: Bool = true     // AI промпты
    @State private var exportSnippets: Bool = true        // Сниппеты (WB/RU/EN/CH + кастомные)
    @State private var exportMessage: String = ""

    private static func checkMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .authorized
    }

    private static func checkScreenRecordingPermission() -> Bool {
        return AccessibilityHelper.hasScreenRecordingPermission()
    }

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
                        SettingsManager.shared.lastSettingsTab = tab.rawValue
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

                    Text("Dictum v\(AppConfig.version)")
                        .font(.system(size: 10))
                        .foregroundColor(.gray.opacity(0.6))
                }
                .padding(.horizontal, 12)
            }
            .frame(width: 180)
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
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .onAppear {
            hasAccessibility = AccessibilityHelper.checkAccessibility()
            hasMicrophonePermission = Self.checkMicrophonePermission()
            hasScreenRecordingPermission = Self.checkScreenRecordingPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasAccessibility = AccessibilityHelper.checkAccessibility()
            hasMicrophonePermission = Self.checkMicrophonePermission()
            hasScreenRecordingPermission = Self.checkScreenRecordingPermission()
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
        case .features: featuresTabContent
        case .speech: speechTabContent
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
                    // Accessibility - ВСЕГДА
                    PermissionRow(
                        icon: "hand.raised.fill",
                        title: "Универсальный доступ",
                        subtitle: "Для вставки текста в другие приложения",
                        isGranted: hasAccessibility,
                        action: {
                            AccessibilityHelper.requestAccessibility()
                            // Polling каждую секунду в течение 10 секунд
                            for delay in stride(from: 1.0, through: 10.0, by: 1.0) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    hasAccessibility = AccessibilityHelper.checkAccessibility()
                                }
                            }
                        }
                    )

                    Divider().background(Color.white.opacity(0.1))

                    // Microphone - ВСЕГДА
                    PermissionRow(
                        icon: "mic.fill",
                        title: "Микрофон",
                        subtitle: "Для записи голосовых заметок",
                        isGranted: hasMicrophonePermission,
                        action: {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async {
                                    hasMicrophonePermission = granted
                                }
                            }
                            // Polling если юзер даст разрешение через System Settings
                            for delay in stride(from: 1.0, through: 10.0, by: 1.0) {
                                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                    hasMicrophonePermission = Self.checkMicrophonePermission()
                                }
                            }
                        }
                    )

                    // Screen Recording - только если Screenshots feature включена
                    if SettingsManager.shared.screenshotFeatureEnabled {
                        Divider().background(Color.white.opacity(0.1))

                        PermissionRow(
                            icon: "camera.metering.matrix",
                            title: "Запись экрана",
                            subtitle: "Для создания скриншотов",
                            isGranted: hasScreenRecordingPermission,
                            action: {
                                // Открыть System Preferences
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                                UserDefaults.standard.set(true, forKey: "screenRecordingRequested")
                                // Polling для проверки реального статуса разрешения
                                for delay in stride(from: 1.0, through: 15.0, by: 1.0) {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                        hasScreenRecordingPermission = Self.checkScreenRecordingPermission()
                                    }
                                }
                            }
                        )
                    }

                    if !hasAccessibility || !hasMicrophonePermission ||
                       (SettingsManager.shared.screenshotFeatureEnabled && !hasScreenRecordingPermission) {
                        Divider().background(Color.white.opacity(0.1))

                        Text("⚠️ Некоторые функции могут работать некорректно без необходимых разрешений")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
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
                        .toggleStyle(GreenToggleStyle())
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
                    // Fix 13: Use settings binding directly
                    Toggle("", isOn: $settings.soundEnabled)
                        .toggleStyle(GreenToggleStyle())
                        .labelsHidden()
                }
            }

            // Секция: Громкость при записи
            SettingsSection(title: "ГРОМКОСТЬ ПРИ ЗАПИСИ") {
                SettingsRow(
                    title: "Снижать громкость ПК",
                    subtitle: "Автоматически уменьшать громкость системы во время записи"
                ) {
                    Picker("", selection: $settings.volumeLevel) {
                        Text("10%").tag(10)
                        Text("20%").tag(20)
                        Text("30%").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
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
                        .toggleStyle(GreenToggleStyle())
                        .labelsHidden()
                }
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
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
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
                    Text("Сбросить (⌘ §)")
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
                        subtitle: "Глобальный хоткей для создания скриншота. Сохраняется в ~/Library/Screenshots/, путь копируется в буфер обмена"
                    ) {
                        Toggle("", isOn: .init(
                            get: { SettingsManager.shared.screenshotFeatureEnabled },
                            set: { SettingsManager.shared.screenshotFeatureEnabled = $0 }
                        ))
                            .toggleStyle(GreenToggleStyle())
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
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // === TAB: РЕЧЬ ===
    var speechTabContent: some View {
        VStack(spacing: 0) {
            ASRProviderSection()
            // Настройки API ключа Deepgram теперь внутри DeepgramSettingsPanel (оранжевая плашка)
        }
    }

    // === TAB: AI ===
    var aiTabContent: some View {
        VStack(spacing: 0) {
            // Fix 13: Use settings binding directly
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
}

// MARK: - Updates Settings Section
struct UpdatesSettingsSection: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        SettingsSection(title: "ОБНОВЛЕНИЯ") {
            VStack(alignment: .leading, spacing: 16) {
                // Текущая версия
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Текущая версия")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Text("Dictum v\(AppConfig.version) (build \(AppConfig.build))")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    // Кнопка проверки
                    Button(action: {
                        updateManager.checkForUpdates(force: true)
                    }) {
                        HStack(spacing: 6) {
                            if updateManager.isChecking {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12))
                            }
                            Text(updateManager.isChecking ? "Проверка..." : "Проверить")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(updateManager.isChecking)
                }

                Divider().background(Color.white.opacity(0.1))

                // Статус обновления
                if updateManager.updateAvailable, let latestVersion = updateManager.latestVersion {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(DesignSystem.Colors.accent)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Доступна новая версия \(latestVersion)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white)
                            Text("Нажмите чтобы скачать")
                                .font(.system(size: 12))
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        Button("Скачать") {
                            updateManager.openDownloadPage()
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .padding(12)
                    .background(DesignSystem.Colors.accent.opacity(0.15))
                    .cornerRadius(8)
                } else if let error = updateManager.checkError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                } else if updateManager.lastCheckDate != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(DesignSystem.Colors.accent)
                        Text("Установлена последняя версия")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                    }
                }

                Divider().background(Color.white.opacity(0.1))

                // Автопроверка
                SettingsRow(
                    title: "Автоматически проверять обновления",
                    subtitle: "Проверять раз в день при запуске"
                ) {
                    Toggle("", isOn: $settings.autoCheckUpdates)
                        .toggleStyle(GreenToggleStyle())
                        .labelsHidden()
                }

                // Последняя проверка
                if let lastCheck = updateManager.lastCheckDate {
                    HStack {
                        Text("Последняя проверка:")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(formatDate(lastCheck))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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
    @StateObject private var localASRManager = ParakeetASRProvider()
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
}

// MARK: - ASR Provider Section
struct ASRProviderSection: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        SettingsSection(title: "РАСПОЗНАВАНИЕ РЕЧИ") {
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

                    // Статистика Deepgram (отдельная серая плашка)
                    if settings.hasDeepgramAPIKey {
                        DeepgramBillingPanel()
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                            .cornerRadius(8)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - LLM Settings Inline View (в рамке под локальной моделью)
struct LLMSettingsInlineView: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(spacing: 12) {
            // === ПЛАШКА 0: Статус модели Parakeet (если не загружена) ===
            ParakeetModelStatusView()

            // === ПЛАШКА 1: API ключ + Модель (зелёная рамка) ===
            VStack(alignment: .leading, spacing: 14) {
                // API Key Status
                GeminiAPIKeyStatus()

                // Model Picker (только если ключ есть)
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

            // === ПЛАШКА 2: Системный промпт + Инструкции (нейтральная рамка) ===
            VStack(alignment: .leading, spacing: 16) {
                // Системный промпт
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Системный промпт")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Text("— инструкции для LLM обработки")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
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

                Divider().background(Color.white.opacity(0.1))

                // Дополнительные инструкции
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Дополнительные инструкции")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                        Text("— добавляются к системному промпту")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }

                    TextEditor(text: $settings.llmAdditionalInstructions)
                        .font(.system(size: 11, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44, maxHeight: 132)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            // === ПЛАШКА 3: Промпт "Улучшить через ИИ" (нейтральная рамка) ===
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(DesignSystem.Colors.accent)
                        .font(.system(size: 12))
                    Text("Улучшить через ИИ")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Text("— инструкции для кнопки ✨")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    Spacer()
                    if settings.enhanceSystemPrompt != SettingsManager.defaultEnhanceSystemPrompt {
                        Button("Сбросить") {
                            settings.enhanceSystemPrompt = SettingsManager.defaultEnhanceSystemPrompt
                        }
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.accent)
                    }
                }

                TextEditor(text: $settings.enhanceSystemPrompt)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 220)
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
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
            .frame(maxWidth: 336)  // 280 × 1.2 = 336 (на 20% шире)
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

// MARK: - LLM Processing Section
struct LLMProcessingSection: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var isEditingPrompt: Bool = false

    var body: some View {
        SettingsSection(title: "LLM-ОБРАБОТКА") {
            VStack(alignment: .leading, spacing: 16) {
                // API Key Status
                GeminiAPIKeyStatus()

                Divider().background(Color.white.opacity(0.1))

                // Model Picker
                GeminiModelPicker(selection: $settings.selectedGeminiModel, label: "Модель для обработки")

                Divider().background(Color.white.opacity(0.1))

                // Описание
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(DesignSystem.Colors.accent)
                    Text("После распознавания текст автоматически обрабатывается выбранной моделью")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }

                // Основной промпт
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Системный промпт")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()

                        if settings.llmProcessingPrompt != SettingsManager.defaultLLMPrompt {
                            Button("Сбросить") {
                                settings.llmProcessingPrompt = SettingsManager.defaultLLMPrompt
                            }
                            .font(.system(size: 10))
                            .foregroundColor(DesignSystem.Colors.accent)
                        }
                    }

                    TextEditor(text: $settings.llmProcessingPrompt)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 120)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }

                // Дополнительные инструкции
                VStack(alignment: .leading, spacing: 6) {
                    Text("Дополнительные инструкции")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)

                    Text("Добавляются к системному промпту")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)

                    TextEditor(text: $settings.llmAdditionalInstructions)
                        .font(.system(size: 11))
                        .frame(height: 60)
                        .padding(8)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Deepgram API Section
struct DeepgramAPISection: View {
    @State private var apiKeyInput: String = ""
    @State private var showSaveSuccess: Bool = false
    @State private var hasKey: Bool = SettingsManager.shared.hasAPIKey()
    @State private var isEditingKey: Bool = false
    @StateObject private var billingManager = BillingManager()

    var body: some View {
        VStack(spacing: 0) {
            // СЕКЦИЯ 1: API КЛЮЧ
            SettingsSection(title: "DEEPGRAM API") {
                VStack(alignment: .leading, spacing: 12) {
                    if hasKey && !isEditingKey {
                        // Статус + кнопка "Изменить" в одной строке
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(DesignSystem.Colors.accent)
                            Text("API ключ установлен")
                                .font(.system(size: 13))
                                .foregroundColor(DesignSystem.Colors.accent)
                            Text("(\(SettingsManager.shared.getAPIKeyMasked()))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.gray)

                            Spacer()

                            Button(action: {
                                isEditingKey = true
                                apiKeyInput = ""
                            }) {
                                Text("Изменить")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(DesignSystem.Colors.deepgramOrange.opacity(0.3))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        // Поле ввода + кнопка "Сохранить"
                        VStack(alignment: .leading, spacing: 8) {
                            if !hasKey {
                                HStack {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.orange)
                                    Text("API ключ не установлен")
                                        .font(.system(size: 13))
                                        .foregroundColor(.orange)
                                }
                            }

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

                            if isEditingKey {
                                Button(action: {
                                    isEditingKey = false
                                    apiKeyInput = ""
                                }) {
                                    Text("Отменить")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if showSaveSuccess {
                                Text("Ключ успешно сохранён!")
                                    .font(.system(size: 12))
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }
                        }
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

            // СЕКЦИЯ 2: НАСТРОЙКИ (только если ключ установлен)
            if hasKey {
                // Выбор модели
                DeepgramModelSection()

                // Язык распознавания
                LanguageSettingsSection()
            }

            // СЕКЦИЯ 3: БАЛАНС И РАСХОДЫ (внизу, только если ключ установлен)
            if hasKey {
                SettingsSection(title: "БАЛАНС И РАСХОДЫ") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Текущий баланс:")
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
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }

                            Button {
                                Task { @MainActor in
                                    await billingManager.loadAllData(apiKey: KeychainManager.shared.getAPIKey() ?? "")
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .padding(6)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                    .task {
                        await billingManager.loadAllData(apiKey: KeychainManager.shared.getAPIKey() ?? "")
                    }
                }
            }
        }
    }

    private func saveAPIKey() {
        if SettingsManager.shared.saveAPIKey(apiKeyInput) {
            hasKey = true
            isEditingKey = false
            showSaveSuccess = true
            apiKeyInput = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showSaveSuccess = false
            }
        }
    }
}

// MARK: - Deepgram Model Section
struct DeepgramModelSection: View {
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        SettingsSection(title: "МОДЕЛЬ DEEPGRAM") {
            VStack(spacing: 8) {
                ModelOptionRow(
                    model: "nova-3",
                    title: "Nova-3",
                    description: "Последняя модель с улучшенной точностью",
                    badge: "Рекомендуется",
                    isSelected: settings.deepgramModel == "nova-3",
                    onSelect: {
                        settings.deepgramModel = "nova-3"
                    }
                )

                Divider().background(Color.white.opacity(0.1))

                ModelOptionRow(
                    model: "nova-2",
                    title: "Nova-2",
                    description: "Предыдущая версия с поддержкой русского языка",
                    badge: nil,
                    isSelected: settings.deepgramModel == "nova-2",
                    onSelect: {
                        settings.deepgramModel = "nova-2"
                    }
                )
            }
            .padding(.vertical, 8)
        }
    }
}

struct ModelOptionRow: View {
    let model: String
    let title: String
    let description: String
    let badge: String?
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? Color(red: 1.0, green: 0.4, blue: 0.2) : .gray)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(.white)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 1.0, green: 0.4, blue: 0.2))
                                .cornerRadius(4)
                        }
                    }

                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
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
                    // Fix 13: Binding already connected to settings, no onChange needed
                    Toggle("", isOn: $aiEnabled)
                        .toggleStyle(GreenToggleStyle())
                        .labelsHidden()
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
                            .background(geminiAPIKeyInput.isEmpty ? Color.gray : Color(red: 1.0, green: 0.4, blue: 0.2))
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
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
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
                VStack(spacing: 4) {
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
                    }
                    .onMove { from, to in
                        promptsManager.movePrompt(from: from, to: to)
                    }
                }

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

                    Button(action: { promptsManager.restoreDefaultPrompts() }) {
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

// MARK: - Add Prompt Sheet
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Новый промпт")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 14) {
                // Label
                VStack(alignment: .leading, spacing: 6) {
                    Text("Кнопка (до 10 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $label)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(10)
                        .background(Color(hex: "#1a1a1b"))
                        .cornerRadius(6)
                        .frame(width: 140)
                        .onChange(of: label) { newValue in
                            label = String(newValue.prefix(10)).uppercased()
                        }
                }

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Описание")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $description)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(10)
                        .background(Color(hex: "#1a1a1b"))
                        .cornerRadius(6)
                }

                // Prompt text
                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст промпта")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $promptText)
                        .font(.system(size: 12))
                        .frame(height: 160)
                        .padding(6)
                        .scrollContentBackground(.hidden)
                        .background(Color(hex: "#1a1a1b"))
                        .cornerRadius(6)
                }
            }

            HStack {
                Spacer()

                Button("Отмена") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Добавить") {
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
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520, height: 455)
        .background(Color(red: 30/255, green: 30/255, blue: 32/255))
    }
}

// MARK: - Edit Prompt Sheet
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

    // Цвет фона полей ввода
    private let fieldBackground = Color(red: 26/255, green: 26/255, blue: 27/255)  // #1a1a1b

    var body: some View {
        VStack(spacing: 20) {
            Text("Редактировать промпт")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 14) {
                // Label (редактируется для всех промптов)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Кнопка (до 10 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $label)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(fieldBackground)
                        .cornerRadius(6)
                        .frame(width: 140)
                        .onChange(of: label) { newValue in
                            label = String(newValue.prefix(10)).uppercased()
                        }
                }

                // Description (редактируется для всех промптов)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Описание")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $description)
                        .font(.system(size: 13))
                        .padding(10)
                        .background(fieldBackground)
                        .cornerRadius(6)
                }

                // Prompt text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Текст промпта")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $promptText)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(fieldBackground)
                        .cornerRadius(6)
                        .frame(minHeight: 200)
                }

                // Favorite toggle
                Toggle(isOn: $isFavorite) {
                    Text("Показывать в быстром доступе")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                }
                .toggleStyle(GreenToggleStyle())

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
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Кнопки: [Удалить] — Spacer — [Отмена] [Сохранить]
            HStack {
                // Кнопка удаления (если есть callback)
                if onDelete != nil {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Удалить")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.destructive)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.destructive.opacity(0.15))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                Button("Отмена") {
                    dismiss()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(6)
                .buttonStyle(PlainButtonStyle())

                Button(action: {
                    var updated = prompt
                    updated.label = label
                    updated.description = description
                    updated.prompt = promptText
                    updated.isFavorite = isFavorite
                    onSave(updated)
                    dismiss()
                }) {
                    Text("Сохранить")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(isValid ? DesignSystem.Colors.accent : Color.gray)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520, height: 580)  // +30% от 400x450
        .background(Color(red: 30/255, green: 30/255, blue: 32/255))
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
                    VStack(spacing: 4) {
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
                        }
                        .onMove { from, to in
                            snippetsManager.moveSnippet(from: from, to: to)
                        }
                    }
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
            EditSnippetSheet(snippet: snippet) { updatedSnippet in
                snippetsManager.updateSnippet(updatedSnippet)
            }
        }
    }
}

// MARK: - Settings Snippet Row View
struct SettingsSnippetRowView: View {
    let snippet: Snippet
    let onToggleFavorite: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

                // Expand/Collapse
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())

                // Edit
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())

                // Delete
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(DesignSystem.Colors.destructive.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.02))
            .cornerRadius(4)

            // Expanded content preview
            if isExpanded {
                Text(snippet.content)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(4)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Add Snippet Sheet
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Новый сниппет")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                // Shortcut
                VStack(alignment: .leading, spacing: 4) {
                    Text("Код (2-6 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $shortcut)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)
                        .onChange(of: shortcut) { newValue in
                            shortcut = String(newValue.prefix(6)).lowercased()
                        }
                }

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Название")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Текст сниппета")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $content)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 120)
                        .padding(4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }

                // Favorite toggle
                Toggle(isOn: $isFavorite) {
                    Text("Показывать в быстром доступе")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .toggleStyle(GreenToggleStyle())
            }

            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Добавить") {
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
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 400, height: 400)
        .background(Color(red: 30/255, green: 30/255, blue: 32/255))
    }
}

// MARK: - Edit Snippet Sheet
struct EditSnippetSheet: View {
    let snippet: Snippet
    let onSave: (Snippet) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var shortcut: String
    @State private var title: String
    @State private var content: String
    @State private var isFavorite: Bool

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void) {
        self.snippet = snippet
        self.onSave = onSave
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

    var body: some View {
        VStack(spacing: 16) {
            Text("Редактировать сниппет")
                .font(.headline)
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 12) {
                // Shortcut
                VStack(alignment: .leading, spacing: 4) {
                    Text("Код (2-6 символов)")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $shortcut)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)
                        .onChange(of: shortcut) { newValue in
                            shortcut = String(newValue.prefix(6)).lowercased()
                        }
                }

                // Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Название")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextField("", text: $title)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text("Текст сниппета")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                    TextEditor(text: $content)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 120)
                        .padding(4)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(6)
                }

                // Favorite toggle
                Toggle(isOn: $isFavorite) {
                    Text("Показывать в быстром доступе")
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                }
                .toggleStyle(GreenToggleStyle())
            }

            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Сохранить") {
                    var updated = snippet
                    updated.shortcut = shortcut
                    updated.title = title
                    updated.content = content
                    updated.isFavorite = isFavorite
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 400, height: 400)
        .background(Color(red: 30/255, green: 30/255, blue: 32/255))
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

struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isGranted ? DesignSystem.Colors.accent : .orange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
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
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, @unchecked Sendable {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var hotKeyRefs: [EventHotKeyRef] = []
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    private var _previousApp: NSRunningApplication?  // Предыдущее активное приложение для авто-вставки
    // Fix 10: NSLock для thread-safe доступа к previousApp
    private let previousAppLock = NSLock()
    var previousApp: NSRunningApplication? {
        get { previousAppLock.withLock { _previousApp } }
        set { previousAppLock.withLock { _previousApp = newValue } }
    }
    var screenshotNotificationWindow: NSWindow?  // Окно уведомления о скриншоте

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("🚀 Dictum запущен")

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

        // Показываем окно при первом запуске (уменьшена задержка для быстрого старта)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if SettingsManager.shared.settingsWindowWasOpen {
                self?.openSettings()
            } else {
                self?.showWindow()
            }
        }

        // Автоматическая проверка обновлений при запуске (если включена)
        if SettingsManager.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                UpdateManager.shared.checkForUpdates()
            }
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

        // Проверяем Screen Recording permission
        if !AccessibilityHelper.hasScreenRecordingPermission() {
            NSLog("❌ Screen Recording permission not granted")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Нужно разрешение"
                alert.informativeText = "Для создания скриншотов нужно разрешение Screen Recording.\n\nОткройте Системные настройки → Конфиденциальность → Запись экрана и включите Dictum."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Открыть настройки")
                alert.addButton(withTitle: "Отмена")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return
        }

        NSLog("📸 Screenshot hotkey pressed")

        // Используем /tmp/ — гарантированно доступна для записи на всех версиях macOS
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "dictum-screenshot-\(timestamp).png"
        let filepath = "/tmp/\(filename)"

        // Запускаем screencapture с интерактивным выбором
        // Fix R4-H1: Выполняем в background thread чтобы не блокировать UI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", filepath]  // -i = interactive mode

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    // Диагностика
                    NSLog("📸 screencapture exit status: \(process.terminationStatus)")
                    NSLog("📸 Expected file: \(filepath)")
                    NSLog("📸 File exists: \(FileManager.default.fileExists(atPath: filepath))")

                    if process.terminationStatus == 0 {
                        if FileManager.default.fileExists(atPath: filepath) {
                            NSLog("✅ Screenshot saved: \(filepath)")

                            // Копируем путь в буфер обмена
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(filepath, forType: .string)

                            // Показываем уведомление
                            Task { @MainActor [weak self] in
                                self?.showScreenshotNotification()
                            }
                        } else {
                            NSLog("⚠️ Screenshot cancelled by user (file not created)")
                        }
                    } else {
                        NSLog("❌ screencapture failed with status: \(process.terminationStatus)")
                    }
                }
            } catch {
                NSLog("❌ Failed to execute screencapture: \(error)")
            }
        }
    }

    @MainActor
    func showScreenshotNotification() {
        // @MainActor гарантирует выполнение на main thread

        // Закрываем предыдущее уведомление если оно еще видимо
        if let existingWindow = screenshotNotificationWindow {
            existingWindow.orderOut(nil)
            existingWindow.close()
            screenshotNotificationWindow = nil
        }

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
        notification.isReleasedWhenClosed = false  // Предотвращает краш при закрытии

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

        // Сохраняем ссылку на окно
        screenshotNotificationWindow = notification

        // Автоматически скрываем через 2 секунды с weak self для предотвращения retain cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            // Проверяем что это все еще то же окно (может быть заменено новым)
            if let currentWindow = self?.screenshotNotificationWindow, currentWindow === notification {
                currentWindow.orderOut(nil)
                currentWindow.close()
                self?.screenshotNotificationWindow = nil
            }
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
        // AppleScript через System Events — надёжнее CGEvent для всех приложений
        // + поддерживает undo stack целевого приложения
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
            if let error = error {
                NSLog("❌ AppleScript paste error: \(error)")
            } else {
                NSLog("✅ Paste выполнен через AppleScript")
            }
        } else {
            NSLog("❌ Не удалось создать AppleScript")
        }
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

            // "Открыть Dictum" with play icon
            let openItem = NSMenuItem(title: "Открыть Dictum", action: #selector(showWindow), keyEquivalent: "")
            openItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Open Dictum")
            menu.addItem(openItem)

            // "Проверить обновления..." with arrow icon (перед настройками)
            let updateItem = NSMenuItem(title: "Проверить обновления...", action: #selector(checkForUpdatesMenu), keyEquivalent: "")
            updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Check for Updates")
            menu.addItem(updateItem)

            // "Настройки..." with gear icon (под проверкой обновлений)
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

            // Если это § или ` — регистрируем также альтернативную клавишу
            // для совместимости с разными раскладками клавиатуры (ISO vs ANSI)
            if hotkey.keyCode == 10 { // § (ISO)
                registerCarbonHotKey(keyCode: 50, modifiers: hotkey.modifiers, id: 2) // ` (ANSI)
            } else if hotkey.keyCode == 50 { // ` (ANSI)
                registerCarbonHotKey(keyCode: 10, modifiers: hotkey.modifiers, id: 2) // § (ISO)
            }
        }

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
                    Task { @MainActor [weak self] in
                        self?.toggleWindow()
                    }
                    return
                }

                // ESC закрывает окно если оно видно (работает без фокуса)
                if eventKeyCode == 53 && self?.window?.isVisible == true {
                    Task { @MainActor [weak self] in
                        self?.hideWindow()
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

        // Ширина: 680 (модалка) + 2*(180 + 8) (боковые панели + отступы)
        let windowWidth: CGFloat = 1060

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 150),
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
        // cornerRadius не нужен - модалка и панели имеют свои clipShape
        hostingView.layer?.masksToBounds = false  // Не обрезать выезжающие панели
        panel.contentView = hostingView

        self.window = panel
        panel.orderOut(nil)  // Скрыть, но НЕ закрывать (close() вызывает applicationShouldTerminateAfterLastWindowClosed)
    }

    func centerWindowOnActiveScreen() {
        guard let window = window else { return }

        // Ширина включает боковые панели: 680 + 2*(180 + 8)
        let width: CGFloat = 1060
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

        // Сначала активируем предыдущее приложение (курсор вернётся в исходное поле)
        if let prevApp = previousApp {
            prevApp.activate(options: .activateIgnoringOtherApps)
            previousApp = nil
        }

        // Потом закрываем окно (небольшая задержка для активации)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak window] in
            window?.close()
        }
    }

    @objc func showWindow() {
        // Создаём окно если его нет (защита от краша)
        if window == nil {
            setupWindow()
        }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
            guard let self = self, let window = window, window.isVisible else { return }
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
        // Скрываем главное модальное окно если оно открыто
        if let mainWindow = window, mainWindow.isVisible {
            mainWindow.close()
        }

        // Проверяем, не открыто ли уже окно настроек
        if let sw = settingsWindow, sw.isVisible {
            sw.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Фиксированный размер окна
        let windowWidth: CGFloat = 900
        let windowHeight: CGFloat = 700

        let sw = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        sw.title = "Настройки Dictum"
        sw.contentView = NSHostingView(rootView: SettingsView())
        sw.center()
        sw.minSize = NSSize(width: 800, height: 600)

        // H6: isReleasedWhenClosed = false - мы сами управляем lifecycle через settingsWindow = nil
        sw.isReleasedWhenClosed = false
        sw.delegate = self
        settingsWindow = sw

        SettingsManager.shared.settingsWindowWasOpen = true

        sw.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func checkForUpdatesMenu() {
        UpdateManager.shared.checkForUpdates(force: true)

        // Показать уведомление через 2 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let updateManager = UpdateManager.shared

            if updateManager.updateAvailable, let version = updateManager.latestVersion {
                let alert = NSAlert()
                alert.messageText = "Доступна новая версия"
                alert.informativeText = "Dictum \(version) доступна для скачивания.\nТекущая версия: \(AppConfig.version)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Скачать")
                alert.addButton(withTitle: "Позже")

                if alert.runModal() == .alertFirstButtonReturn {
                    updateManager.openDownloadPage()
                }
            } else if !updateManager.isChecking && updateManager.checkError == nil {
                let alert = NSAlert()
                alert.messageText = "Обновлений нет"
                alert.informativeText = "Вы используете последнюю версию Dictum (\(AppConfig.version))."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // MARK: - NSApplicationDelegate
    // Не завершать приложение при закрытии последнего окна (приложение живёт в menubar)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }

        // Игнорируем закрытие screenshot notification window - это временное окно
        if closedWindow == screenshotNotificationWindow {
            screenshotNotificationWindow = nil
            return
        }

        if closedWindow == settingsWindow {
            // Сначала убираем delegate чтобы избежать повторных вызовов
            settingsWindow?.delegate = nil
            settingsWindow = nil
            SettingsManager.shared.settingsWindowWasOpen = false

            // Показываем модальное окно после закрытия настроек
            // showWindow() сам создаст окно если его нет
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showWindow()
            }
            return
        }

        // H3: Для главного окна - пересоздаём через setupWindow
        if closedWindow == window {
            window?.delegate = nil
            window = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupWindow()
            }
        }
    }

    @objc func quitApp() {
        // Fix 1: Очищаем Carbon hotkeys ДО terminate
        unregisterHotKeys()

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

        // Закрываем screenshot notification window если открыто
        if let notificationWindow = screenshotNotificationWindow {
            notificationWindow.orderOut(nil)
            notificationWindow.close()
            screenshotNotificationWindow = nil
        }

        NSApplication.shared.terminate(nil)
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
struct DictumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - SwiftUI Previews

// ==========================================
// ГЛАВНЫЕ VIEWS
// ==========================================

#Preview("InputModalView") {
    InputModalView()
        .frame(width: 600, height: 300)
        .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
}

#Preview("SettingsView") {
    SettingsView()
        .frame(width: 650, height: 700)
}

// ==========================================
// VOICE & AUDIO
// ==========================================

#Preview("VoiceOverlayView - Medium") {
    VoiceOverlayView(audioLevel: 0.5)
        .frame(width: 500, height: 60)
        .background(Color.black.opacity(0.8))
}

#Preview("VoiceOverlayView - Low") {
    VoiceOverlayView(audioLevel: 0.15)
        .frame(width: 500, height: 60)
        .background(Color.black.opacity(0.8))
}

#Preview("VoiceOverlayView - High") {
    VoiceOverlayView(audioLevel: 0.95)
        .frame(width: 500, height: 60)
        .background(Color.black.opacity(0.8))
}

// ==========================================
// HISTORY
// ==========================================

#Preview("HistoryListView") {
    HistoryListView(
        items: [
            HistoryItem(text: "Привет, это тестовая заметка"),
            HistoryItem(text: "Вторая заметка с более длинным текстом для проверки переноса строк"),
            HistoryItem(text: "Третья заметка")
        ],
        searchQuery: .constant(""),
        onSelect: { _ in },
        onSearch: { _ in }
    )
    .frame(width: 500, height: 300)
    .background(VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow))
}

#Preview("HistoryRowView") {
    HistoryRowView(
        item: HistoryItem(text: "Пример записи в истории"),
        onTap: {}
    )
    .frame(width: 400)
    .background(Color.black.opacity(0.8))
}

// ==========================================
// NOTIFICATIONS
// ==========================================

#Preview("ScreenshotNotificationView") {
    ScreenshotNotificationView()
        .padding()
        .background(Color.black.opacity(0.5))
}

// ==========================================
// BUTTONS
// ==========================================

#Preview("LoadingLanguageButton - Normal") {
    LoadingLanguageButton(
        label: "WB",
        tooltip: "Вежливый бот",
        isLoading: false,
        action: {}
    )
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("LoadingLanguageButton - Loading") {
    LoadingLanguageButton(
        label: "RU",
        tooltip: "Русификация",
        isLoading: true,
        action: {}
    )
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("SnippetButton") {
    SnippetButton(
        shortcut: "addr",
        tooltip: "Домашний адрес",
        action: {}
    )
    .padding()
    .background(Color.black.opacity(0.8))
}

// ==========================================
// QUICK ACCESS ROW
// ==========================================

#Preview("UnifiedQuickAccessRow") {
    UnifiedQuickAccessRow(
        promptsManager: PromptsManager.shared,
        snippetsManager: SnippetsManager.shared,
        inputText: .constant("Пример текста"),
        showLeftPanel: .constant(false),
        showRightPanel: .constant(false),
        onProcessWithGemini: { _ in },
        currentProcessingPrompt: nil,
        editingPrompt: .constant(nil),
        editingSnippet: .constant(nil)
    )
    .frame(width: 550, height: 50)
    .background(Color.black.opacity(0.3))
}

// ==========================================
// PROMPTS
// ==========================================

#Preview("PromptRowView") {
    let prompt = CustomPrompt(
        id: UUID(),
        label: "WB",
        description: "Вежливый бот",
        prompt: "Обработай текст вежливо",
        isVisible: true,
        isFavorite: true,
        isSystem: true,
        order: 0
    )
    return PromptRowView(
        prompt: prompt,
        isProcessing: false,
        onToggleFavorite: {},
        onEdit: {},
        onDelete: {},
        onTap: {}
    )
    .frame(width: 400)
    .background(Color.black.opacity(0.8))
}

#Preview("PromptRowView - Processing") {
    let prompt = CustomPrompt(
        id: UUID(),
        label: "EN",
        description: "Английский",
        prompt: "Translate to English",
        isVisible: true,
        isFavorite: true,
        isSystem: true,
        order: 1
    )
    return PromptRowView(
        prompt: prompt,
        isProcessing: true,
        onToggleFavorite: {},
        onEdit: {},
        onDelete: {},
        onTap: {}
    )
    .frame(width: 400)
    .background(Color.black.opacity(0.8))
}

#Preview("PromptEditView") {
    let prompt = CustomPrompt(
        id: UUID(),
        label: "WB",
        description: "Вежливый бот",
        prompt: "Обработай текст вежливо и грамотно",
        isVisible: true,
        isFavorite: true,
        isSystem: false,
        order: 0
    )
    return PromptEditView(
        prompt: prompt,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("PromptAddView") {
    PromptAddView(
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("SettingsPromptRowView") {
    let prompt = CustomPrompt(
        id: UUID(),
        label: "CH",
        description: "Китайский перевод",
        prompt: "Translate to Chinese",
        isVisible: true,
        isFavorite: false,
        isSystem: false,
        order: 3
    )
    return SettingsPromptRowView(
        prompt: prompt,
        onToggleFavorite: {},
        onEdit: {}
    )
    .frame(width: 400)
    .background(Color.black.opacity(0.8))
}

#Preview("AddPromptSheet") {
    AddPromptSheet { _ in }
}

#Preview("EditPromptSheet") {
    let prompt = CustomPrompt(
        id: UUID(),
        label: "TEST",
        description: "Тестовый промпт",
        prompt: "Это текст промпта для тестирования",
        isVisible: true,
        isFavorite: true,
        isSystem: false,
        order: 5
    )
    return EditPromptSheet(
        prompt: prompt,
        onSave: { _ in },
        onDelete: {}
    )
}

// ==========================================
// SNIPPETS
// ==========================================

#Preview("SnippetRowView") {
    let snippet = Snippet(
        id: UUID(),
        shortcut: "addr",
        title: "Домашний адрес",
        content: "ул. Пушкина, д. 10, кв. 5",
        isFavorite: true,
        order: 0
    )
    return SnippetRowView(
        snippet: snippet,
        onToggleFavorite: {},
        onEdit: {},
        onDelete: {},
        onInsert: {}
    )
    .frame(width: 400)
    .background(Color.black.opacity(0.8))
}

#Preview("SnippetEditView") {
    let snippet = Snippet(
        id: UUID(),
        shortcut: "sig",
        title: "Подпись",
        content: "С уважением,\nИван Петров",
        isFavorite: true,
        order: 1
    )
    return SnippetEditView(
        snippet: snippet,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("SnippetAddView") {
    SnippetAddView(
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("SettingsSnippetRowView") {
    let snippet = Snippet(
        id: UUID(),
        shortcut: "phone",
        title: "Номер телефона",
        content: "+7 999 123-45-67",
        isFavorite: false,
        order: 2
    )
    return SettingsSnippetRowView(
        snippet: snippet,
        onToggleFavorite: {},
        onEdit: {},
        onDelete: {}
    )
    .frame(width: 450)
    .background(Color.black.opacity(0.8))
}

#Preview("AddSnippetSheet") {
    AddSnippetSheet { _ in }
}

#Preview("EditSnippetSheet") {
    let snippet = Snippet(
        id: UUID(),
        shortcut: "email",
        title: "Email",
        content: "example@mail.ru",
        isFavorite: true,
        order: 0
    )
    return EditSnippetSheet(
        snippet: snippet,
        onSave: { _ in }
    )
}

// ==========================================
// SETTINGS TABS & SECTIONS
// ==========================================

#Preview("SettingsTabButton - Selected") {
    SettingsTabButton(
        tab: .general,
        isSelected: true,
        action: {}
    )
    .frame(width: 180)
    .background(Color.black.opacity(0.9))
}

#Preview("SettingsTabButton - Not Selected") {
    SettingsTabButton(
        tab: .ai,
        isSelected: false,
        action: {}
    )
    .frame(width: 180)
    .background(Color.black.opacity(0.9))
}

#Preview("UpdatesSettingsSection") {
    UpdatesSettingsSection()
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

#Preview("ASRProviderSection") {
    ASRProviderSection()
        .frame(width: 550)
        .background(Color.black.opacity(0.9))
}

#Preview("AIPromptsSection") {
    AIPromptsSection()
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

#Preview("SnippetsSettingsSection") {
    SnippetsSettingsSection()
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

#Preview("LanguageSettingsSection") {
    LanguageSettingsSection()
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

// ==========================================
// ASR PROVIDER CARDS
// ==========================================

#Preview("ASRProviderCard - Parakeet Selected") {
    ASRProviderCard(
        icon: "cpu",
        title: "Parakeet v3",
        subtitle: "25 языков • ~190× RT",
        badge: "Офлайн",
        isSelected: true,
        accentColor: DesignSystem.Colors.accent,
        action: {}
    )
    .frame(width: 260)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("ASRProviderCard - Deepgram") {
    ASRProviderCard(
        icon: "cloud.fill",
        title: "Deepgram",
        subtitle: "Streaming • ~200мс",
        badge: nil,
        isSelected: false,
        accentColor: DesignSystem.Colors.deepgramOrange,
        action: {}
    )
    .frame(width: 260)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("ParakeetModelStatusView") {
    ParakeetModelStatusView()
        .frame(width: 350)
        .padding()
        .background(Color.black.opacity(0.8))
}

// ==========================================
// DEEPGRAM PANELS
// ==========================================

#Preview("DeepgramSettingsPanel") {
    DeepgramSettingsPanel()
        .frame(width: 400)
        .padding()
        .background(Color.black.opacity(0.8))
}

#Preview("DeepgramBillingPanel") {
    DeepgramBillingPanel()
        .frame(width: 350)
        .padding()
        .background(Color.black.opacity(0.8))
}

#Preview("DeepgramAPISection") {
    DeepgramAPISection()
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

#Preview("DeepgramModelSection") {
    DeepgramModelSection()
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

// ==========================================
// LLM / GEMINI
// ==========================================

#Preview("LLMSettingsInlineView") {
    LLMSettingsInlineView()
        .frame(width: 450)
        .padding()
        .background(Color.black.opacity(0.8))
}

#Preview("GeminiAPIKeyStatus") {
    GeminiAPIKeyStatus()
        .frame(width: 400)
        .padding()
        .background(Color.black.opacity(0.8))
}

#Preview("GeminiModelPicker") {
    GeminiModelPicker(
        selection: .constant(.gemini25Flash),
        label: "Модель Gemini"
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("LLMProcessingSection") {
    LLMProcessingSection()
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

#Preview("AISettingsSection") {
    AISettingsSection(aiEnabled: .constant(true))
        .frame(width: 500)
        .background(Color.black.opacity(0.9))
}

// ==========================================
// HELPER ROWS
// ==========================================

#Preview("HotkeyDisplayRow") {
    HotkeyDisplayRow(
        action: "Открыть модалку",
        keys: "⌘ + `"
    )
    .frame(width: 350)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("HotkeyRow") {
    HotkeyRow(
        action: "Вставить текст",
        keys: ["⌘", "+", "Enter"],
        note: nil
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("HotkeyRow - With Note") {
    HotkeyRow(
        action: "Скриншот области",
        keys: ["⌘", "+", "⇧", "+", "4"],
        note: "⚠️ Требуется разрешение"
    )
    .frame(width: 450)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("ModelOptionRow - Selected") {
    ModelOptionRow(
        model: "nova-2",
        title: "Nova 2",
        description: "Самая точная модель, рекомендуется",
        badge: "Рекомендуется",
        isSelected: true,
        onSelect: {}
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("ModelOptionRow - Not Selected") {
    ModelOptionRow(
        model: "base",
        title: "Base",
        description: "Быстрая базовая модель",
        badge: nil,
        isSelected: false,
        onSelect: {}
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("LanguageOptionRow - Selected") {
    LanguageOptionRow(
        title: "Русский (рекомендуется)",
        subtitle: "Оптимизировано для русского языка",
        value: "ru",
        isSelected: true,
        action: {}
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("LanguageOptionRow - Not Selected") {
    LanguageOptionRow(
        title: "Английский",
        subtitle: "Оптимизировано для английского языка",
        value: "en",
        isSelected: false,
        action: {}
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("PermissionRow - Granted") {
    PermissionRow(
        icon: "keyboard",
        title: "Accessibility",
        subtitle: "Для вставки текста",
        isGranted: true,
        action: {}
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

#Preview("PermissionRow - Not Granted") {
    PermissionRow(
        icon: "mic.fill",
        title: "Микрофон",
        subtitle: "Для записи голоса",
        isGranted: false,
        action: {}
    )
    .frame(width: 400)
    .padding()
    .background(Color.black.opacity(0.8))
}

// ==========================================
// BILLING
// ==========================================

#Preview("BillingErrorView") {
    BillingErrorView(
        message: "Не удалось загрузить данные биллинга. Проверьте подключение к интернету.",
        retry: {}
    )
    .frame(width: 350, height: 200)
    .background(Color.black.opacity(0.9))
}
