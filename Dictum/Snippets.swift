//
//  Snippets.swift
//  Dictum
//
//  Текстовые сниппеты: модель, менеджер и UI
//

import SwiftUI
import AppKit

// MARK: - Snippet Model
struct Snippet: Codable, Identifiable, Equatable {
    let id: UUID
    var shortcut: String        // "addr", "sig" (2-6 символов для быстрого доступа)
    var title: String           // "Домашний адрес" (описание)
    var content: String         // Текст сниппета (может быть многострочным)
    var isFavorite: Bool        // Показывать в строке быстрого доступа
    var order: Int              // Порядок сортировки

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

    static let defaultSnippets: [Snippet] = []
}

// MARK: - Snippets Manager
class SnippetsManager: ObservableObject, @unchecked Sendable {
    static let shared = SnippetsManager()

    private let userDefaultsKey = "com.dictum.snippets"

    @Published var snippets: [Snippet] = [] {
        didSet { saveSnippets() }
    }

    // Избранные сниппеты для строки быстрого доступа
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

    private var openSound: NSSound?
    private var closeSound: NSSound?

    init() {
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
        playCloseSound()
    }

    func playStopSound() {
        guard SettingsManager.shared.soundEnabled else { return }
        openSound?.stop()
        openSound?.play()
    }
}

// MARK: - Snippets Panel
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

