//
//  History.swift
//  Dictum
//
//  История заметок: модель, менеджер и UI
//

import SwiftUI

// MARK: - History Item Model
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

    init(id: String, text: String, timestamp: Date) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
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
            NSLog("📋 History: returning all \(history.count) items")
            return Array(history.prefix(limit))
        } else {
            let lowercasedQuery = searchQuery.lowercased()
            let filtered = history.filter { $0.text.lowercased().contains(lowercasedQuery) }
            NSLog("📋 History search '\(searchQuery)': found \(filtered.count) of \(history.count)")
            return Array(filtered.prefix(limit))
        }
    }

    func getHistoryCount() -> Int {
        return history.count
    }

    func delete(_ item: HistoryItem) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.history.removeAll { $0.id == item.id }
            self.saveHistory()
            NSLog("🗑️ History item deleted")
        }
    }

    func update(_ item: HistoryItem, text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.history.firstIndex(where: { $0.id == item.id }) {
                self.history[index] = HistoryItem(id: item.id, text: text, timestamp: item.timestamp)
                self.saveHistory()
                NSLog("✏️ History item updated")
            }
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            history = try decoder.decode([HistoryItem].self, from: data)
        } catch {
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
            NSLog("❌ Error saving history: \(error.localizedDescription)")
        }
    }
}

// MARK: - History List View
struct HistoryListView: View {
    let items: [HistoryItem]
    @Binding var searchQuery: String
    let onSelect: (HistoryItem) -> Void
    let onSearch: (String) -> Void

    @State private var selectedIndex: Int = 0
    @FocusState private var isListFocused: Bool

    // MARK: - Subviews (разбиты для ускорения компиляции)

    private var searchFieldView: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.2))

            TextField("Поиск...", text: $searchQuery)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.9))
                .onChange(of: searchQuery) { _, newValue in
                    onSearch(newValue)
                }

            if !searchQuery.isEmpty {
                Button(action: {
                    searchQuery = ""
                    onSearch("")
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(PlainButtonStyle())
            }

            hotkeyBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.05))
                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var hotkeyBadge: some View {
        HStack(spacing: 2) {
            Text("⌘")
                .font(.system(size: 11))
            Text("4")
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

    private var headerView: some View {
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
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: searchQuery.isEmpty ? "clock" : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(searchQuery.isEmpty ? "История пуста" : "Ничего не найдено")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(height: 120)
    }

    @ViewBuilder
    private func resultsView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HistoryRowView(
                        item: item,
                        isSelected: index == selectedIndex,
                        onTap: { onSelect(item) }
                    )
                    .id(index)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isListFocused)
        .onKeyPress(.downArrow) {
            if selectedIndex < items.count - 1 {
                selectedIndex += 1
                proxy.scrollTo(selectedIndex, anchor: .center)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedIndex > 0 {
                selectedIndex -= 1
                proxy.scrollTo(selectedIndex, anchor: .center)
            }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedIndex < items.count {
                onSelect(items[selectedIndex])
            }
            return .handled
        }
        .frame(height: min(CGFloat(items.count) * 44, 5 * 44))
        .padding(.bottom, 8)
    }

    // MARK: - Body

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                searchFieldView

                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(height: 1)
                    .padding(.horizontal, 24)

                if items.isEmpty {
                    emptyStateView
                } else {
                    resultsView(proxy: proxy)
                }
            }
            .background(Color.black.opacity(0.2))
            .onChange(of: items) { _, _ in
                selectedIndex = 0
            }
            .onAppear {
                isListFocused = true
            }
        }
    }
}

// MARK: - History Row View
struct HistoryRowView: View {
    let item: HistoryItem
    var isSelected: Bool = false
    var isExpanded: Bool = false
    var isKeyboardNavigating: Bool = false
    let onTap: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var isHovered = false

    private var isHighlighted: Bool {
        isSelected || isHovered
    }

    var body: some View {
        HStack {
            Text(item.text)
                .foregroundColor(.white)
                .font(.system(size: 14))
                .lineLimit(isExpanded ? nil : 1)

            Spacer()

            Text(item.timeAgo)
                .font(.system(size: 12))
                .foregroundColor(.gray)
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

// MARK: - History Modal View (отдельная модалка поверх основной)
struct HistoryModalView: View {
    @Binding var isPresented: Bool
    let onSelect: (HistoryItem) -> Void

    @State private var searchQuery = ""
    @State private var selectedIndex = 0
    @State private var expandedIndex: Int? = nil
    @State private var isKeyboardNavigating = false
    @State private var mouseMonitor: Any?
    @State private var itemToDelete: HistoryItem? = nil
    @State private var itemToEdit: HistoryItem? = nil
    @FocusState private var isSearchFocused: Bool

    // Computed property — пересчитывается при каждом изменении searchQuery
    private var filteredItems: [HistoryItem] {
        let allItems = HistoryManager.shared.history
        if searchQuery.isEmpty {
            return Array(allItems.prefix(50))
        }
        let query = searchQuery.lowercased()
        return allItems.filter { $0.text.lowercased().contains(query) }
    }

    // MARK: - Search Field

    private var searchFieldView: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.3))

            TextField("Поиск в истории...", text: $searchQuery)
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

            // Hotkey badge ⌘4
            HStack(spacing: 2) {
                Text("⌘")
                    .font(.system(size: 11))
                Text("4")
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
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Results List

    private var resultsListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        HistoryRowView(
                            item: item,
                            isSelected: index == selectedIndex,
                            isExpanded: index == expandedIndex,
                            isKeyboardNavigating: isKeyboardNavigating,
                            onTap: {
                                onSelect(item)
                                isPresented = false
                            },
                            onEdit: {
                                itemToEdit = item
                            },
                            onDelete: {
                                itemToDelete = item
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
            Image(systemName: searchQuery.isEmpty ? "clock" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))
            Text(searchQuery.isEmpty ? "История пуста" : "Ничего не найдено")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Footer with Hotkey Hints

    private var footerView: some View {
        HStack {
            // Кнопка отмены слева
            Button(action: { isPresented = false }) {
                Text("Отмена")
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
            RoundedRectangle(cornerRadius: 26)  // macOS Tahoe: 26pt
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
            if selectedIndex < filteredItems.count {
                onSelect(filteredItems[selectedIndex])
                isPresented = false
            }
            return .handled
        }
        .onKeyPress(.escape) {
            NotificationCenter.default.post(name: .toggleHistoryModal, object: nil)
            return .handled
        }
        .onAppear {
            // Автофокус на поле поиска
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
            // Monitor реального движения мыши
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
            // Сбросить выделение при изменении поиска
            selectedIndex = 0
        }
        .alert("Удалить запись?", isPresented: .init(
            get: { itemToDelete != nil },
            set: { if !$0 { itemToDelete = nil } }
        )) {
            Button("Отмена", role: .cancel) { itemToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let item = itemToDelete {
                    HistoryManager.shared.delete(item)
                }
                itemToDelete = nil
            }
        } message: {
            Text("Вы уверены? Это действие нельзя отменить")
        }
        .sheet(item: $itemToEdit) { item in
            HistoryEditSheet(item: item) { updatedText in
                HistoryManager.shared.update(item, text: updatedText)
                itemToEdit = nil
            }
        }
    }
}

// MARK: - History Edit Sheet
struct HistoryEditSheet: View {
    let item: HistoryItem
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Редактировать запись")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Text editor
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundColor(.white)
                .scrollContentBackground(.hidden)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal, 24)
                .frame(minHeight: 150)

            // Footer
            HStack {
                Button("Отмена") {
                    dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.white.opacity(0.6))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))

                Spacer()

                Button("Сохранить") {
                    onSave(text)
                    dismiss()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(DesignSystem.Colors.accent))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 300)
        .background(Color(red: 24/255, green: 24/255, blue: 26/255))
        .onAppear {
            text = item.text
        }
    }
}

// MARK: - SwiftUI Previews
#Preview("HistoryModalView") {
    HistoryModalView(
        isPresented: .constant(true),
        onSelect: { _ in }
    )
    .frame(width: 800, height: 500)
    .background(Color.black.opacity(0.5))
}

#Preview("HistoryListView") {
    HistoryListView(
        items: [
            HistoryItem(text: "Привет, это тестовая заметка"),
            HistoryItem(text: "Вторая заметка с более длинным текстом"),
            HistoryItem(text: "Третья заметка")
        ],
        searchQuery: .constant(""),
        onSelect: { _ in },
        onSearch: { _ in }
    )
    .frame(width: 500, height: 300)
    .background(Color.black)
}

#Preview("HistoryRowView") {
    HistoryRowView(
        item: HistoryItem(text: "Пример записи в истории"),
        isSelected: false,
        onTap: {}
    )
    .frame(width: 400)
    .background(Color.black.opacity(0.8))
}
