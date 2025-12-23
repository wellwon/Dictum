//
//  Prompts.swift
//  Dictum
//
//  AI промпты: модель, менеджер и UI
//

import SwiftUI

// MARK: - Custom Prompt Model
struct CustomPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var label: String           // "WB", "FR" (2-4 символа)
    var description: String     // "Вежливый Бот" (описание на русском)
    var prompt: String          // Текст промпта
    var isVisible: Bool         // Показывать в UI
    var isFavorite: Bool        // Показывать в строке быстрого доступа
    var isSystem: Bool          // true для 4 стандартных
    var order: Int              // Порядок отображения

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
        let uuidString = "00000000-0000-0000-0000-\(String(format: "%012d", label.hashValue & 0xFFFFFFFF))"
        let stableId = UUID(uuidString: uuidString) ?? UUID()
        return CustomPrompt(
            id: stableId,
            label: label,
            description: description,
            prompt: prompt,
            isVisible: true,
            isFavorite: true,
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

        if let data = try? JSONEncoder().encode(migratedPrompts) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }

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

