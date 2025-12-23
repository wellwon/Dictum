//
//  AI.swift
//  Dictum
//
//  Gemini AI сервис и модели
//

import SwiftUI

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

