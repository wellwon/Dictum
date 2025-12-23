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
            return Array(history.prefix(limit))
        } else {
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
                    .onChange(of: searchQuery) { _, newValue in
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

            // Результаты
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
                .frame(height: min(CGFloat(items.count) * 44, 5 * 44))
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

// MARK: - SwiftUI Previews
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
        onTap: {}
    )
    .frame(width: 400)
    .background(Color.black.opacity(0.8))
}
