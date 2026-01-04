//
//  Notes.swift
//  Dictum
//
//  Заметки: модель, менеджер и UI модалки
//

import SwiftUI

// MARK: - Note Model
struct Note: Codable, Identifiable, Equatable {
    let id: String
    var title: String           // Заголовок (первая строка или "Без названия")
    var content: String         // Полный текст
    let createdAt: Date
    var updatedAt: Date

    init(content: String) {
        self.id = UUID().uuidString
        self.content = content
        self.title = Note.extractTitle(from: content)
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    init(id: String, title: String, content: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func extractTitle(from content: String) -> String {
        let firstLine = content.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? content
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Без названия"
        }
        return String(trimmed.prefix(50))
    }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 60 { return "Только что" }
        if interval < 3600 { return "\(Int(interval / 60)) мин" }
        if interval < 86400 { return "\(Int(interval / 3600)) ч" }
        return "\(Int(interval / 86400)) д"
    }

    static func == (lhs: Note, rhs: Note) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Notes Manager
class NotesManager: ObservableObject, @unchecked Sendable {
    static let shared = NotesManager()

    @Published var notes: [Note] = []
    private let maxNotes = 100
    private let notesKey = "dictum-notes"

    init() {
        loadNotes()
    }

    func addNote(_ content: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let newNote = Note(content: content)
            self.notes.insert(newNote, at: 0)

            if self.notes.count > self.maxNotes {
                self.notes = Array(self.notes.prefix(self.maxNotes))
            }

            self.saveNotes()
        }
    }

    func addNote(title: String, content: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let newNote = Note(
                id: UUID().uuidString,
                title: title.isEmpty ? Note.extractTitle(from: content) : title,
                content: content,
                createdAt: Date(),
                updatedAt: Date()
            )
            self.notes.insert(newNote, at: 0)

            if self.notes.count > self.maxNotes {
                self.notes = Array(self.notes.prefix(self.maxNotes))
            }

            self.saveNotes()
        }
    }

    func updateNote(_ note: Note) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let idx = self.notes.firstIndex(where: { $0.id == note.id }) {
                var updated = note
                updated.updatedAt = Date()
                // НЕ перезаписываем title - он уже установлен правильно в note
                self.notes[idx] = updated
                self.saveNotes()
            }
        }
    }

    func deleteNote(_ note: Note) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.notes.removeAll { $0.id == note.id }
            self.saveNotes()
        }
    }

    func getNotesItems(limit: Int = 50, searchQuery: String = "") -> [Note] {
        if searchQuery.isEmpty {
            return Array(notes.prefix(limit))
        }
        let query = searchQuery.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(query) ||
            $0.content.lowercased().contains(query)
        }.prefix(limit).map { $0 }
    }

    private func loadNotes() {
        guard let data = UserDefaults.standard.data(forKey: notesKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            notes = try decoder.decode([Note].self, from: data)
        } catch {
            NSLog("❌ Error loading notes: \(error.localizedDescription)")
            notes = []
        }
    }

    private func saveNotes() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            UserDefaults.standard.set(data, forKey: notesKey)
        } catch {
            NSLog("❌ Error saving notes: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notes Row View
struct NotesRowView: View {
    let note: Note
    var isSelected: Bool = false
    var isExpanded: Bool = false
    var isKeyboardNavigating: Bool = false
    let onOpen: () -> Void     // Открыть для просмотра/редактирования
    let onDelete: () -> Void   // Удалить (с подтверждением в parent)
    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .foregroundColor(.white)
                    .font(.system(size: 14))
                    .lineLimit(isExpanded ? nil : 1)

                if isExpanded && note.content != note.title {
                    Text(note.content)
                        .foregroundColor(.gray)
                        .font(.system(size: 12))
                        .lineLimit(3)
                }
            }

            Spacer()

            if isHovered {
                // Кнопка редактирования
                Button(action: onOpen) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(PlainButtonStyle())

                // Кнопка удаления
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }

            Text(note.timeAgo)
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(isHighlighted ? Color(red: 36/255, green: 36/255, blue: 37/255) : Color.clear)  // #242425
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .onHover { hovering in
            if !isKeyboardNavigating {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                onOpen()
            } label: {
                Label("Редактировать", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}

// MARK: - Notes Modal View
struct NotesModalView: View {
    @Binding var isPresented: Bool
    let onSelect: (Note) -> Void   // Отправить в чат (из NoteDetailView)
    var onCancel: (() -> Void)? = nil

    @StateObject private var notesManager = NotesManager.shared
    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var expandedIndex: Int? = nil
    @State private var isKeyboardNavigating = false
    @State private var mouseMonitor: Any?
    @State private var showAddSheet = false
    @State private var showNoteDetail = false
    @State private var selectedNote: Note? = nil
    @State private var showDeleteConfirm = false
    @State private var noteToDelete: Note? = nil
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [Note] {
        notesManager.getNotesItems(searchQuery: searchQuery)
    }

    // MARK: - Search Field

    private var searchFieldView: some View {
        HStack(spacing: 12) {
            // Поле поиска (capsule)
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.3))

                TextField("Поиск в заметках...", text: $searchQuery)
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
                    .onKeyPress(.downArrow) {
                        if !filteredItems.isEmpty {
                            isSearchFocused = false
                            selectedIndex = 0
                            isKeyboardNavigating = true
                        }
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        // Стрелка вверх из поиска - ничего не делаем
                        return .handled
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

                // Hotkey badge ⌘3
                HStack(spacing: 2) {
                    Text("⌘")
                        .font(.system(size: 11))
                    Text("3")
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
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, note in
                        NotesRowView(
                            note: note,
                            isSelected: index == selectedIndex,
                            isExpanded: index == expandedIndex,
                            isKeyboardNavigating: isKeyboardNavigating,
                            onOpen: {
                                selectedNote = note
                                showNoteDetail = true
                            },
                            onDelete: {
                                noteToDelete = note
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
            Image(systemName: searchQuery.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))
            Text(searchQuery.isEmpty ? "Нет заметок" : "Ничего не найдено")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))

            if searchQuery.isEmpty {
                Button(action: { showAddSheet = true }) {
                    Text("Создать заметку")
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
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 15)
            )
            .background(
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                    .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 26))
            )
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(
                RoundedRectangle(cornerRadius: 26)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
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
                expandedIndex = nil
                return .handled
            }
            .onKeyPress(.return) {
                // Enter открывает заметку для просмотра/редактирования
                if selectedIndex < filteredItems.count {
                    selectedNote = filteredItems[selectedIndex]
                    showNoteDetail = true
                }
                return .handled
            }
            .onKeyPress(.escape) {
                onCancel?()
                return .handled
            }
            .alert("Удалить заметку?", isPresented: $showDeleteConfirm) {
                Button("Отмена", role: .cancel) {
                    noteToDelete = nil
                }
                Button("Удалить", role: .destructive) {
                    if let note = noteToDelete {
                        notesManager.deleteNote(note)
                        noteToDelete = nil
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
            .opacity(showAddSheet || showNoteDetail ? 0 : 1)

            // MARK: - Add Note Overlay (на том же уровне ZStack)
            if showAddSheet {
                NoteAddView(
                    onSave: { title, content in
                        notesManager.addNote(title: title, content: content)
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

            // MARK: - Note Detail Overlay (на том же уровне ZStack)
            if showNoteDetail, let note = selectedNote {
                NoteDetailView(
                    note: note,
                    onSave: { updated in
                        notesManager.updateNote(updated)
                        showNoteDetail = false
                        selectedNote = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = true
                        }
                    },
                    onSend: { content in
                        // Создаём фейковую заметку для отправки в чат
                        var noteToSend = note
                        noteToSend.content = content
                        onSelect(noteToSend)
                        isPresented = false
                    },
                    onDelete: {
                        notesManager.deleteNote(note)
                        showNoteDetail = false
                        selectedNote = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = true
                        }
                    },
                    onCancel: {
                        showNoteDetail = false
                        selectedNote = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = true
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showAddSheet)
        .animation(.easeOut(duration: 0.15), value: showNoteDetail)
    }
}

// MARK: - Note Add View
struct NoteAddView: View {
    let onSave: (String, String) -> Void  // (title, content)
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var content: String = ""
    @FocusState private var isTitleFocused: Bool

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Text("Новая заметка")
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
    }

    // MARK: - Title Field
    private var titleFieldView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Заголовок")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            TextField("Введите заголовок...", text: $title)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 15))
                .foregroundColor(.white)
                .tint(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .focused($isTitleFocused)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Content Field
    private var contentFieldView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Содержимое")
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
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .frame(height: 200)
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack {
            Button(action: onCancel) {
                Text("Назад")
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
                onSave(title, content)
            }) {
                Text("Сохранить")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(canSave ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!canSave)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            headerView

            VStack(spacing: 16) {
                titleFieldView
                contentFieldView
            }

            Spacer(minLength: 0)

            footerView
        }
        .frame(width: 720, height: 450)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 24/255, green: 24/255, blue: 26/255))
                // БЕЗ shadow! Тень обрезается границами окна → острые углы
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
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
        .onKeyPress(.escape) {
            onCancel()
            return .handled
        }
        // Убрали .onKeyPress(.return) - он вызывал дубликаты при нажатии Enter в TextEditor
        // Сохранение только через кнопку "Сохранить"
    }
}

// MARK: - Note Detail View (просмотр/редактирование)
struct NoteDetailView: View {
    let note: Note
    let onSave: (Note) -> Void
    let onSend: (String) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var editedTitle: String
    @State private var editedContent: String
    @State private var showDeleteConfirm = false
    @FocusState private var isContentFocused: Bool

    init(note: Note, onSave: @escaping (Note) -> Void, onSend: @escaping (String) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.note = note
        self.onSave = onSave
        self.onSend = onSend
        self.onDelete = onDelete
        self.onCancel = onCancel
        self._editedTitle = State(initialValue: note.title)
        self._editedContent = State(initialValue: note.content)
    }

    private var hasChanges: Bool {
        editedTitle != note.title || editedContent != note.content
    }

    private var canSave: Bool {
        !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !editedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 12) {
            Button(action: {
                if hasChanges && canSave {
                    saveAndClose()
                } else {
                    onCancel()
                }
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())

            TextField("Заголовок", text: $editedTitle)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .tint(.white)

            Spacer()

            // Кнопка удалить
            Button(action: { showDeleteConfirm = true }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
                    .padding(8)
                    .background(Circle().fill(Color.red.opacity(0.1)))
            }
            .buttonStyle(PlainButtonStyle())

            // Кнопка закрыть
            Button(action: {
                if hasChanges && canSave {
                    saveAndClose()
                } else {
                    onCancel()
                }
            }) {
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
    }

    // MARK: - Content
    private var contentView: some View {
        TextEditor(text: $editedContent)
            .font(.system(size: 14))
            .foregroundColor(.white)
            .tint(.white)
            .scrollContentBackground(.hidden)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .focused($isContentFocused)
            .padding(.horizontal, 24)
    }

    // MARK: - Footer
    private var footerView: some View {
        HStack(spacing: 12) {
            // Время создания
            Text(note.timeAgo)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))

            Spacer()

            // Кнопка Сохранить (если есть изменения)
            if hasChanges {
                Button(action: saveAndClose) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11))
                        Text("Сохранить")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(DesignSystem.Colors.accent)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Кнопка Отправить в чат
            Button(action: {
                onSend(editedContent)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11))
                    Text("Отправить")
                        .font(.system(size: 13, weight: .medium))
                    Text("↵")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(3)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.1))
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func saveAndClose() {
        var updated = note
        updated.title = editedTitle.isEmpty ? Note.extractTitle(from: editedContent) : editedTitle
        updated.content = editedContent
        onSave(updated)
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            headerView

            contentView
                .frame(maxHeight: .infinity)

            footerView
        }
        .frame(width: 720, height: 450)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(Color(red: 24/255, green: 24/255, blue: 26/255))
                // БЕЗ shadow! Тень обрезается границами окна → острые углы
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
        .focusable()
        .focusEffectDisabled()
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isContentFocused = true
            }
        }
        .onKeyPress(.escape) {
            if hasChanges && canSave {
                saveAndClose()
            } else {
                onCancel()
            }
            return .handled
        }
        .onKeyPress(.return) {
            onSend(editedContent)
            return .handled
        }
        .alert("Удалить заметку?", isPresented: $showDeleteConfirm) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) { onDelete() }
        } message: {
            Text("Это действие нельзя отменить")
        }
    }
}

// MARK: - SwiftUI Previews
#Preview("NotesModalView") {
    NotesModalView(
        isPresented: .constant(true),
        onSelect: { _ in }
    )
    .frame(width: 800, height: 500)
    .background(Color.black.opacity(0.5))
}
