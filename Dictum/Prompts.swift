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

// MARK: - Prompt Edit View
struct PromptEditView: View {
    let prompt: CustomPrompt
    let onSave: (CustomPrompt) -> Void
    let onCancel: () -> Void

    @State private var editedLabel: String
    @State private var editedDescription: String
    @State private var editedPrompt: String
    @FocusState private var isLabelFocused: Bool

    init(prompt: CustomPrompt, onSave: @escaping (CustomPrompt) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        _editedLabel = State(initialValue: prompt.label)
        _editedDescription = State(initialValue: prompt.description)
        _editedPrompt = State(initialValue: prompt.prompt)
    }

    private var canSave: Bool {
        !editedLabel.isEmpty && !editedPrompt.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Редактировать промпт")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Fields
            VStack(spacing: 16) {
                // Label + Описание в одной строке
                HStack(alignment: .top, spacing: 12) {
                    // Label (30%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Label")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("WB", text: $editedLabel)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            )
                            .disabled(prompt.isSystem)
                            .opacity(prompt.isSystem ? 0.5 : 1)
                            .focused($isLabelFocused)
                    }
                    .frame(width: 100)

                    // Описание (70%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Описание")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("Описание промпта", text: $editedDescription)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            )
                    }
                }

                // Prompt text field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст промпта")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextEditor(text: $editedPrompt)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .tint(.white)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .frame(height: 150)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // Footer
            HStack {
                Button(action: onCancel) {
                    Text("Отмена")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: {
                    var updated = prompt
                    updated.label = editedLabel
                    updated.description = editedDescription
                    updated.prompt = editedPrompt
                    onSave(updated)
                }) {
                    HStack(spacing: 6) {
                        Text("Сохранить")
                            .font(.system(size: 13, weight: .semibold))
                        Text("↵")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(canSave ? DesignSystem.Colors.accent : Color.gray.opacity(0.3)))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 720, height: 450)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 24/255, green: 24/255, blue: 26/255))
        )
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 26))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isLabelFocused = true }
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.return) {
            if canSave {
                var updated = prompt
                updated.label = editedLabel
                updated.description = editedDescription
                updated.prompt = editedPrompt
                onSave(updated)
            }
            return .handled
        }
    }
}

// MARK: - Prompt Add View
struct PromptAddView: View {
    let onSave: (CustomPrompt) -> Void
    let onCancel: () -> Void

    @State private var label: String = ""
    @State private var description: String = ""
    @State private var promptText: String = ""
    @FocusState private var isLabelFocused: Bool

    private var canSave: Bool {
        !label.isEmpty && !promptText.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Новый AI промпт")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Fields
            VStack(spacing: 16) {
                // Label + Описание в одной строке
                HStack(alignment: .top, spacing: 12) {
                    // Label (30%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Label")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("FIX", text: $label)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            )
                            .focused($isLabelFocused)
                    }
                    .frame(width: 100)

                    // Описание (70%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Описание")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("Исправить ошибки", text: $description)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .tint(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                            )
                    }
                }

                // Prompt text field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст промпта")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextEditor(text: $promptText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .tint(.white)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .frame(minHeight: 150, maxHeight: .infinity)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // Footer
            HStack {
                Button(action: onCancel) {
                    Text("Отмена")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: {
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
                }) {
                    Text("Добавить")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(canSave ? DesignSystem.Colors.accent : Color.gray.opacity(0.3)))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 720, height: 450)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 24/255, green: 24/255, blue: 26/255))
                // БЕЗ shadow! Тень обрезается границами окна
        )
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 26))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isLabelFocused = true }
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.return) {
            if canSave {
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
            return .handled
        }
    }
}

// MARK: - Prompts Modal Row View
struct PromptsModalRowView: View {
    let prompt: CustomPrompt
    var isSelected: Bool = false
    var isExpanded: Bool = false
    var isKeyboardNavigating: Bool = false
    let onTap: () -> Void
    var onToggleFavorite: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        HStack(spacing: 12) {
            // Звезда избранного (кликабельная)
            Button(action: { onToggleFavorite?() }) {
                Image(systemName: prompt.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundColor(prompt.isFavorite ? .yellow : .gray)
            }
            .buttonStyle(PlainButtonStyle())

            // Label badge (адаптивная ширина до ~10 символов)
            Text(prompt.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .frame(minWidth: 32)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHighlighted ? Color.white.opacity(0.15) : Color.white.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(prompt.description)
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                    .lineLimit(isExpanded ? nil : 1)

                if isExpanded {
                    Text(prompt.prompt)
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                        .lineLimit(3)
                }
            }

            Spacer()

            // Системный индикатор
            if prompt.isSystem {
                Text("system")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isHighlighted ? Color(red: 36/255, green: 36/255, blue: 37/255) : Color.clear)  // #242425
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onHover { hovering in
            if !isKeyboardNavigating {
                isHovered = hovering
            }
        }
        .contextMenu {
            if let onEdit = onEdit, !prompt.isSystem {
                Button {
                    onEdit()
                } label: {
                    Label("Редактировать", systemImage: "pencil")
                }
            }

            if let onDelete = onDelete, !prompt.isSystem {
                Divider()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Prompts Modal View
struct PromptsModalView: View {
    @Binding var isPresented: Bool
    let onSelect: (CustomPrompt) -> Void
    var onCancel: (() -> Void)? = nil

    @ObservedObject private var promptsManager = PromptsManager.shared
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var expandedIndex: Int? = nil
    @State private var isKeyboardNavigating = false
    @State private var mouseMonitor: Any?
    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var promptToEdit: CustomPrompt? = nil
    @State private var showDeleteConfirm = false
    @State private var promptToDelete: CustomPrompt? = nil
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [CustomPrompt] {
        let visible = promptsManager.visiblePrompts
        if searchQuery.isEmpty {
            return visible
        }
        let query = searchQuery.lowercased()
        return visible.filter {
            $0.label.lowercased().contains(query) ||
            $0.description.lowercased().contains(query) ||
            $0.prompt.lowercased().contains(query)
        }
    }

    // MARK: - Search Field

    private var searchFieldView: some View {
        HStack(spacing: 12) {
            // Поле поиска (capsule)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.3))

                TextField("Поиск промптов...", text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.9))
                    .focused($isSearchFocused)
                    .onSubmit {
                        if selectedIndex < filteredItems.count {
                            onSelect(filteredItems[selectedIndex])
                            isPresented = false
                        }
                    }

                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .padding(4)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // Hotkey badge ⌘1
                HStack(spacing: 2) {
                    Text("⌘")
                        .font(.system(size: 11))
                    Text("1")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.3))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .cornerRadius(4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            )

            // Кнопка создания — круглая зелёная 32×32
            Button(action: { showAddSheet = true }) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(DesignSystem.Colors.accent))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Results List

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, prompt in
                        PromptsModalRowView(
                            prompt: prompt,
                            isSelected: index == selectedIndex,
                            isExpanded: index == expandedIndex,
                            isKeyboardNavigating: isKeyboardNavigating,
                            onTap: {
                                onSelect(prompt)
                                isPresented = false
                            },
                            onToggleFavorite: {
                                promptsManager.toggleFavorite(prompt)
                            },
                            onEdit: prompt.isSystem ? nil : {
                                promptToEdit = prompt
                                showEditSheet = true
                            },
                            onDelete: prompt.isSystem ? nil : {
                                promptToDelete = prompt
                                showDeleteConfirm = true
                            }
                        )
                        .id(index)
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newIndex, anchor: nil)
                }
            }
        }
        .frame(maxHeight: 320)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: searchQuery.isEmpty ? "sparkles" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))
            Text(searchQuery.isEmpty ? "Нет промптов" : "Ничего не найдено")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))

            if searchQuery.isEmpty {
                Button(action: { showAddSheet = true }) {
                    Text("Создать промпт")
                        .font(.system(size: 13))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            // Кнопка назад слева
            Button(action: { onCancel?() }) {
                Text("Назад")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()

            // Все хоткеи справа
            HStack(spacing: 20) {
                hotkeyHint("ENTER", "выбрать")
                hotkeyHint("↑↓", "навигация")
                hotkeyHint("←→", "свернуть")
                hotkeyHint("ESC", "закрыть")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(red: 39/255, green: 39/255, blue: 41/255))  // #272729
    }

    private func hotkeyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15), lineWidth: 1))
                .cornerRadius(4)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // MARK: - Main Content
            VStack(spacing: 0) {
                searchFieldView

                if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    resultsListView
                }

                Spacer(minLength: 0)

                footerView
            }
            .frame(width: 720, height: 450)
            .background(
                RoundedRectangle(cornerRadius: 26)
                    .fill(Color(red: 24/255, green: 24/255, blue: 26/255))
                    // БЕЗ shadow! Тень обрезается границами окна
            )
            .background(
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 26))
            )
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .opacity(showAddSheet ? 0 : 1)  // Скрываем при показе Add View

            // MARK: - Add Prompt Overlay
            if showAddSheet {
                PromptAddView(
                    onSave: { prompt in
                        PromptsManager.shared.addPrompt(prompt)
                        showAddSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = true
                        }
                    },
                    onCancel: {
                        showAddSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = true
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showAddSheet)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) {
            isKeyboardNavigating = true
            if selectedIndex < filteredItems.count - 1 {
                selectedIndex += 1
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            isKeyboardNavigating = true
            if selectedIndex > 0 {
                selectedIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            expandedIndex = selectedIndex
            return .handled
        }
        .onKeyPress(.leftArrow) {
            if expandedIndex != nil {
                expandedIndex = nil
            } else {
                onCancel?()  // Закрыть панель (как Escape)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < filteredItems.count {
                onSelect(filteredItems[selectedIndex])
                onCancel?()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            onCancel?()
            return .handled
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
                isKeyboardNavigating = false
                return event
            }
        }
        .onDisappear {
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                mouseMonitor = nil
            }
        }
        .onChange(of: searchQuery) { _, _ in
            selectedIndex = 0
        }
        .alert("Удалить промпт?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {
                promptToDelete = nil
            }
            Button("Удалить", role: .destructive) {
                if let prompt = promptToDelete {
                    PromptsManager.shared.deletePrompt(prompt)
                    promptToDelete = nil
                    // Сбросить индекс после удаления
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        let count = filteredItems.count
                        if count == 0 {
                            selectedIndex = 0
                        } else if selectedIndex >= count {
                            selectedIndex = count - 1
                        }
                    }
                }
            }
        } message: {
            Text("Это действие нельзя отменить")
        }
        .sheet(isPresented: $showEditSheet) {
            if let prompt = promptToEdit {
                PromptEditSheet(
                    prompt: prompt,
                    onSave: { updated in
                        PromptsManager.shared.updatePrompt(updated)
                        showEditSheet = false
                        promptToEdit = nil
                    },
                    onCancel: {
                        showEditSheet = false
                        promptToEdit = nil
                    }
                )
            }
        }
    }
}

// MARK: - Prompt Edit Sheet
struct PromptEditSheet: View {
    let prompt: CustomPrompt
    let onSave: (CustomPrompt) -> Void
    let onCancel: () -> Void

    @State private var label: String
    @State private var description: String
    @State private var promptText: String
    @FocusState private var isLabelFocused: Bool

    init(prompt: CustomPrompt, onSave: @escaping (CustomPrompt) -> Void, onCancel: @escaping () -> Void) {
        self.prompt = prompt
        self.onSave = onSave
        self.onCancel = onCancel
        self._label = State(initialValue: prompt.label)
        self._description = State(initialValue: prompt.description)
        self._promptText = State(initialValue: prompt.prompt)
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Редактировать промпт")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Form
            VStack(spacing: 16) {
                // Label
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ярлык (2-4 символа)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextField("WB", text: $label)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .tint(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .focused($isLabelFocused)
                }
                .padding(.horizontal, 24)

                // Description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Описание")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextField("Описание промпта", text: $description)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .tint(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                }
                .padding(.horizontal, 24)

                // Prompt text
                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст промпта")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextEditor(text: $promptText)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .tint(.white)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.05))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        )
                        .frame(minHeight: 150, maxHeight: .infinity)
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)

            // Footer
            HStack {
                Button(action: onCancel) {
                    Text("Отмена")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: {
                    var updated = prompt
                    updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.prompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(updated)
                }) {
                    Text("Сохранить")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(canSave ? DesignSystem.Colors.accent : Color.gray.opacity(0.3)))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSave)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 450)
        .background(Color(red: 24/255, green: 24/255, blue: 26/255))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isLabelFocused = true
            }
        }
    }
}

// MARK: - SwiftUI Previews
#Preview("PromptsModalView") {
    PromptsModalView(
        isPresented: .constant(true),
        onSelect: { _ in }
    )
    .frame(width: 800, height: 500)
    .background(Color.black.opacity(0.5))
}

