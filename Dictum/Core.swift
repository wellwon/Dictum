//
//  Core.swift
//  Dictum
//
//  Базовые утилиты, DesignSystem, конфигурация приложения
//

import SwiftUI
import AppKit

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

// MARK: - Notification Names
extension Notification.Name {
    static let dictumToggleWindow = Notification.Name("dictumToggleWindow")
    static let dictumShowWindow = Notification.Name("dictumShowWindow")
    static let dictumHideWindow = Notification.Name("dictumHideWindow")
    static let dictumPasteAndClose = Notification.Name("dictumPasteAndClose")
}

