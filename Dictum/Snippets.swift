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
        .overlay {
            if let snippet = editingSnippet {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        editingSnippet = nil
                    }

                SnippetEditView(
                    snippet: snippet,
                    onSave: { updated in
                        snippetsManager.updateSnippet(updated)
                        editingSnippet = nil
                    },
                    onCancel: {
                        editingSnippet = nil
                    },
                    onDelete: {
                        snippetsManager.deleteSnippet(snippet)
                        editingSnippet = nil
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: editingSnippet)
        .overlay {
            if showAddSheet {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showAddSheet = false
                    }

                SnippetAddView(
                    onSave: { newSnippet in
                        snippetsManager.addSnippet(newSnippet)
                        showAddSheet = false
                    },
                    onCancel: {
                        showAddSheet = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showAddSheet)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

                // Actions (показываются при наведении)
                if isHovered {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .foregroundColor(.gray)
                }
            }

            // Content preview (всегда видно)
            Text(snippet.content)
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .lineLimit(2)
                .padding(.leading, 46) // Выравнивание с title (star + badge)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onInsert)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Snippet Edit View
struct SnippetEditView: View {
    let snippet: Snippet
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var editedShortcut: String
    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var showDeleteConfirm = false
    @FocusState private var isShortcutFocused: Bool

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.snippet = snippet
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        _editedShortcut = State(initialValue: snippet.shortcut)
        _editedTitle = State(initialValue: snippet.title)
        _editedContent = State(initialValue: snippet.content)
    }

    private var canSave: Bool {
        !editedShortcut.isEmpty && !editedContent.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Редактировать сниппет")
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
                // Shortcut + Название в одной строке
                HStack(alignment: .top, spacing: 12) {
                    // Shortcut (30%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcut")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("addr", text: $editedShortcut)
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
                            .focused($isShortcutFocused)
                    }
                    .frame(width: 100)

                    // Название (70%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Название")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("Домашний адрес", text: $editedTitle)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст сниппета")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextEditor(text: $editedContent)
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
                if let deleteAction = onDelete {
                    Button(action: { showDeleteConfirm = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Удалить")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.1)))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .alert("Удалить сниппет?", isPresented: $showDeleteConfirm) {
                        Button("Отмена", role: .cancel) { }
                        Button("Удалить", role: .destructive) { deleteAction() }
                    } message: {
                        Text("Это действие нельзя отменить")
                    }
                }

                Button(action: onCancel) {
                    Text("Отмена")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: {
                    var updated = snippet
                    updated.shortcut = editedShortcut
                    updated.title = editedTitle
                    updated.content = editedContent
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
                // БЕЗ shadow! Тень обрезается границами окна
        )
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 26))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isShortcutFocused = true }
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.return) {
            if canSave {
                var updated = snippet
                updated.shortcut = editedShortcut
                updated.title = editedTitle
                updated.content = editedContent
                onSave(updated)
            }
            return .handled
        }
    }
}

// MARK: - Snippet Add View
struct SnippetAddView: View {
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @State private var shortcut: String = ""
    @State private var title: String = ""
    @State private var content: String = ""
    @FocusState private var isShortcutFocused: Bool

    private var canSave: Bool {
        !shortcut.isEmpty && !content.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Новый сниппет")
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
                // Shortcut + Название в одной строке
                HStack(alignment: .top, spacing: 12) {
                    // Shortcut (30%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Shortcut")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("addr", text: $shortcut)
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
                            .focused($isShortcutFocused)
                    }
                    .frame(width: 100)

                    // Название (70%)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Название")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        TextField("Домашний адрес", text: $title)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст сниппета")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextEditor(text: $content)
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
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: {
                    let newSnippet = Snippet.create(shortcut: shortcut, title: title, content: content)
                    onSave(newSnippet)
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
                .clipShape(RoundedRectangle(cornerRadius: 26))
        )
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isShortcutFocused = true }
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.return) {
            if canSave {
                let newSnippet = Snippet.create(shortcut: shortcut, title: title, content: content)
                onSave(newSnippet)
            }
            return .handled
        }
    }
}

// MARK: - Snippets Modal Row View
struct SnippetsModalRowView: View {
    let snippet: Snippet
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
                        .fill(isHighlighted ? DesignSystem.Colors.accent.opacity(0.3) : DesignSystem.Colors.accent.opacity(0.2))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.title)
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                    .lineLimit(isExpanded ? nil : 1)

                if isExpanded {
                    Text(snippet.content)
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                        .lineLimit(3)
                }
            }

            Spacer()
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
    }
}

// MARK: - Snippets Modal View
struct SnippetsModalView: View {
    @Binding var isPresented: Bool
    let onSelect: (Snippet) -> Void
    var onCancel: (() -> Void)? = nil

    @ObservedObject private var snippetsManager = SnippetsManager.shared
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var expandedIndex: Int? = nil
    @State private var isKeyboardNavigating = false
    @State private var mouseMonitor: Any?
    @State private var showAddSheet = false
    @State private var showEditSheet = false
    @State private var snippetToEdit: Snippet? = nil
    @State private var showDeleteConfirm = false
    @State private var snippetToDelete: Snippet? = nil
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [Snippet] {
        let all = snippetsManager.allSnippets
        if searchQuery.isEmpty {
            return all
        }
        let query = searchQuery.lowercased()
        return all.filter {
            $0.shortcut.lowercased().contains(query) ||
            $0.title.lowercased().contains(query) ||
            $0.content.lowercased().contains(query)
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

                TextField("Поиск сниппетов...", text: $searchQuery)
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

                // Hotkey badge ⌘2
                HStack(spacing: 2) {
                    Text("⌘")
                        .font(.system(size: 11))
                    Text("2")
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
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, snippet in
                        SnippetsModalRowView(
                            snippet: snippet,
                            isSelected: index == selectedIndex,
                            isExpanded: index == expandedIndex,
                            isKeyboardNavigating: isKeyboardNavigating,
                            onTap: {
                                onSelect(snippet)
                                isPresented = false
                            },
                            onToggleFavorite: {
                                SnippetsManager.shared.toggleFavorite(snippet)
                            },
                            onEdit: {
                                snippetToEdit = snippet
                                showEditSheet = true
                            },
                            onDelete: {
                                snippetToDelete = snippet
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
            Image(systemName: searchQuery.isEmpty ? "doc.text" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))
            Text(searchQuery.isEmpty ? "Нет сниппетов" : "Ничего не найдено")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))

            if searchQuery.isEmpty {
                Button(action: { showAddSheet = true }) {
                    Text("Создать сниппет")
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
                hotkeyHint("ENTER", "вставить")
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

            // MARK: - Add Snippet Overlay
            if showAddSheet {
                SnippetAddView(
                    onSave: { snippet in
                        SnippetsManager.shared.addSnippet(snippet)
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
        .alert("Удалить сниппет?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) {
                snippetToDelete = nil
            }
            Button("Удалить", role: .destructive) {
                if let snippet = snippetToDelete {
                    SnippetsManager.shared.deleteSnippet(snippet)
                    snippetToDelete = nil
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
            if let snippet = snippetToEdit {
                SnippetEditSheet(
                    snippet: snippet,
                    onSave: { updated in
                        SnippetsManager.shared.updateSnippet(updated)
                        showEditSheet = false
                        snippetToEdit = nil
                    },
                    onCancel: {
                        showEditSheet = false
                        snippetToEdit = nil
                    }
                )
            }
        }
    }
}

// MARK: - Snippet Edit Sheet
struct SnippetEditSheet: View {
    let snippet: Snippet
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @State private var shortcut: String
    @State private var title: String
    @State private var content: String
    @FocusState private var isShortcutFocused: Bool

    init(snippet: Snippet, onSave: @escaping (Snippet) -> Void, onCancel: @escaping () -> Void) {
        self.snippet = snippet
        self.onSave = onSave
        self.onCancel = onCancel
        self._shortcut = State(initialValue: snippet.shortcut)
        self._title = State(initialValue: snippet.title)
        self._content = State(initialValue: snippet.content)
    }

    private var canSave: Bool {
        !shortcut.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Редактировать сниппет")
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
                // Shortcut
                VStack(alignment: .leading, spacing: 6) {
                    Text("Сокращение")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextField("//email", text: $shortcut)
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
                        .focused($isShortcutFocused)
                }
                .padding(.horizontal, 24)

                // Title
                VStack(alignment: .leading, spacing: 6) {
                    Text("Название")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextField("Название сниппета", text: $title)
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

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text("Текст сниппета")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    TextEditor(text: $content)
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
                    var updated = snippet
                    updated.shortcut = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    updated.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
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
        .frame(width: 500, height: 500)
        .background(Color(red: 24/255, green: 24/255, blue: 26/255))
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isShortcutFocused = true
            }
        }
    }
}

// MARK: - SwiftUI Previews
#Preview("SnippetsModalView") {
    SnippetsModalView(
        isPresented: .constant(true),
        onSelect: { _ in }
    )
    .frame(width: 800, height: 500)
    .background(Color.black.opacity(0.5))
}

