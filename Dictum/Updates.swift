//
//  Updates.swift
//  Dictum
//
//  Проверка обновлений: менеджер, парсер appcast и UI
//

import SwiftUI

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

