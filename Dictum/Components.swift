//
//  Components.swift
//  Dictum
//
//  Общие UI компоненты: редактор текста, панели, стили, хелперы
//

import SwiftUI
import AppKit
import Carbon
import AVFoundation

// MARK: - Text Language Detection
enum TextLanguage {
    case cyrillic  // Русский
    case latin     // Английский
    case mixed     // Смешанный, не подсвечиваем
}

struct ForeignWord {
    let range: NSRange
}

// MARK: - Custom Text Editor
struct CustomTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onHeightChange: ((CGFloat) -> Void)?
    var highlightForeignWords: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            // Сохраняем видимую область
            let visibleRect = textView.visibleRect
            let shouldPreserveScroll = textView.string.count > 0 && text.count > textView.string.count

            // Флаг что текст заменен извне (для подсветки)
            context.coordinator.textWasReplacedExternally = true

            // Заменяем текст
            textView.string = text

            // Курсор в конец
            let endPosition = (text as NSString).length
            textView.setSelectedRange(NSRange(location: endPosition, length: 0))

            // Блокируем автопрокрутку к курсору - восстанавливаем видимую область
            if shouldPreserveScroll {
                textView.scroll(visibleRect.origin)
            }

            // Пересчитываем высоту и применяем подсветку
            DispatchQueue.main.async {
                context.coordinator.updateHeight(textView)
                context.coordinator.applyForeignWordHighlighting(textView)
            }
        }
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onHeightChange = onHeightChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CustomTextEditor
        var onSubmit: () -> Void
        var onHeightChange: ((CGFloat) -> Void)?
        private var isApplyingHighlight = false
        var textWasReplacedExternally = false  // Флаг для различения внешней замены текста (Gemini) и обычного ввода

        // Кешированный regex (компилируется один раз)
        private static let wordRegex = try! NSRegularExpression(pattern: "[\\p{L}]+")

        init(_ parent: CustomTextEditor) {
            self.parent = parent
            self.onSubmit = parent.onSubmit
            self.onHeightChange = parent.onHeightChange
        }

        // MARK: - Language Detection
        private func detectPrimaryLanguage(_ text: String) -> TextLanguage {
            var cyrillicCount = 0
            var latinCount = 0

            for char in text where char.isLetter {
                if ("а"..."я").contains(char.lowercased()) || ("А"..."Я").contains(char) {
                    cyrillicCount += 1
                } else if ("a"..."z").contains(char.lowercased()) {
                    latinCount += 1
                }
            }

            let total = cyrillicCount + latinCount
            guard total > 0 else { return .mixed }

            let cyrillicRatio = Double(cyrillicCount) / Double(total)

            if cyrillicRatio > 0.55 { return .cyrillic }
            else if cyrillicRatio < 0.45 { return .latin }
            else { return .mixed }
        }

        private func findForeignWords(in text: String, primaryLanguage: TextLanguage) -> [ForeignWord] {
            guard primaryLanguage != .mixed else { return [] }

            let nsText = text as NSString
            let matches = Self.wordRegex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

            return matches.compactMap { match in
                let word = nsText.substring(with: match.range)
                return isWordForeign(word, primaryLanguage) ? ForeignWord(range: match.range) : nil
            }
        }

        private func isWordForeign(_ word: String, _ primaryLanguage: TextLanguage) -> Bool {
            let hasCyrillic = word.unicodeScalars.contains { ("а"..."я").contains($0) || ("А"..."Я").contains($0) }
            let hasLatin = word.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }

            if primaryLanguage == .cyrillic {
                return hasLatin && !hasCyrillic
            } else {
                return hasCyrillic && !hasLatin
            }
        }

        // MARK: - Foreign Word Highlighting
        func applyForeignWordHighlighting(_ textView: NSTextView) {
            guard parent.highlightForeignWords else { return }
            guard let textStorage = textView.textStorage else { return }

            isApplyingHighlight = true
            defer { isApplyingHighlight = false }

            let text = textView.string
            let fullRange = NSRange(location: 0, length: (text as NSString).length)

            // Сохраняем курсор
            let selectedRanges = textView.selectedRanges

            // Сброс атрибутов
            textStorage.setAttributes([
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.white
            ], range: fullRange)

            // Определяем язык и подсвечиваем
            let language = detectPrimaryLanguage(text)
            let foreignWords = findForeignWords(in: text, primaryLanguage: language)

            let highlightColor = NSColor(red: 1.0, green: 0.26, blue: 0.27, alpha: 1.0) // #ff4246

            for foreignWord in foreignWords {
                textStorage.addAttribute(.foregroundColor, value: highlightColor, range: foreignWord.range)
            }

            // Восстанавливаем курсор
            if textWasReplacedExternally {
                // Текст был заменен извне (Gemini) - НЕ восстанавливаем старую позицию
                // Курсор уже установлен в конец в updateNSView
                textWasReplacedExternally = false
            } else {
                // Обычная подсветка при вводе - восстанавливаем позицию
                textView.selectedRanges = selectedRanges
            }
        }

        func updateHeight(_ textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = max(40, usedRect.height + 10) // +10 для padding

            onHeightChange?(newHeight)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingHighlight else { return }
            guard let textView = notification.object as? NSTextView else { return }
            DispatchQueue.main.async {
                self.parent.text = textView.string
                self.updateHeight(textView)
                self.applyForeignWordHighlighting(textView)
            }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // ESC - закрыть окно без сохранения
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                textView.string = ""
                NSApp.keyWindow?.close()
                return true
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                guard let event = NSApp.currentEvent else {
                    return false
                }

                // Любой модификатор + Enter = новая строка
                let hasModifier = !event.modifierFlags.intersection([.shift, .option, .control, .command]).isEmpty

                if hasModifier {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }

                // Просто Enter - отправить
                onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Visual Effect Background
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Toggle Styles

/// iOS-style тумблер для macOS Tahoe — pill shape, тёмный фон, белый круг
/// Размер 44×26 (стандарт iOS), spring анимация
struct TahoeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                // Фон — Capsule (pill shape)
                Capsule()
                    .fill(configuration.isOn ? DesignSystem.Colors.accent : DesignSystem.Colors.toggleBackground)
                    .frame(width: 44, height: 26)

                // Кружок — Circle
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .padding(2)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

/// Старый стиль тумблера (deprecated, используйте TahoeToggleStyle)
@available(*, deprecated, message: "Use TahoeToggleStyle instead")
struct GreenToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isOn ? DesignSystem.Colors.accent : Color.gray.opacity(0.3))
                    .frame(width: 36, height: 20)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 14, height: 14)
                    .offset(x: configuration.isOn ? 8 : -8)
                    .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

/// Checkbox стиль для экспорта настроек
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundColor(configuration.isOn ? DesignSystem.Colors.accent : .gray.opacity(0.5))
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

// MARK: - Settings Section (Tahoe Card Style)
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.gray)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(DesignSystem.Colors.cardBackgroundTahoe)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.cardTahoe)
                    .stroke(DesignSystem.Colors.cardBorderTahoe, lineWidth: 1)
            )
            .cornerRadius(DesignSystem.CornerRadius.cardTahoe)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

// MARK: - Settings Row
struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let accessory: Accessory

    init(title: String, subtitle: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            accessory
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Permission Row
struct PermissionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(isGranted ? DesignSystem.Colors.accent : DesignSystem.Colors.deepgramOrange)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DesignSystem.Colors.accent)
                    .font(.system(size: 18))
            } else {
                Button(action: action) {
                    Text("Разрешить")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.deepgramOrange)
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Hotkey Row
struct HotkeyRow: View {
    let action: String
    let keys: [String]
    let note: String?
    var isWarning: Bool = false

    var body: some View {
        HStack {
            Text(action)
                .font(.system(size: 13))
                .foregroundColor(.white)

            Spacer()

            if let note = note {
                HStack(spacing: 4) {
                    if isWarning {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                    }
                    Text(note)
                        .font(.system(size: 11))
                }
                .foregroundColor(isWarning ? .orange : .green)
                .padding(.trailing, 8)
            }

            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                    if key == "+" || key == "или" {
                        Text(key)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    } else {
                        Text(key)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }
        }
    }
}

// MARK: - Typewriter Text Animation
struct TypewriterText: View {
    let text: String
    let color: Color
    var speed: Double = 0.03  // секунд на букву

    @State private var displayedText = ""
    @State private var animationId = UUID()

    var body: some View {
        Text(displayedText)
            .foregroundColor(color)
            .onAppear { startAnimation() }
            .onChange(of: text) { _, _ in startAnimation() }
    }

    private func startAnimation() {
        let currentId = UUID()
        animationId = currentId
        displayedText = ""

        for (index, char) in text.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + speed * Double(index)) {
                // Проверяем что анимация не была перезапущена
                guard animationId == currentId else { return }
                displayedText += String(char)
            }
        }
    }
}

// MARK: - Looping Typewriter Text Animation
struct LoopingTypewriterText: View {
    let text: String
    let color: Color
    var typeSpeed: Double = 0.03  // секунд на букву
    var pauseDuration: Double = 2.0  // пауза между циклами

    @State private var displayedText = ""
    @State private var animationId = UUID()

    var body: some View {
        Text(displayedText)
            .foregroundColor(color)
            .onAppear { startLoop() }
            .onChange(of: text) { _, _ in startLoop() }
    }

    private func startLoop() {
        let currentId = UUID()
        animationId = currentId
        runCycle(id: currentId)
    }

    private func runCycle(id: UUID) {
        displayedText = ""

        // Печатаем буква за буквой
        for (index, char) in text.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + typeSpeed * Double(index)) {
                guard animationId == id else { return }
                displayedText += String(char)
            }
        }

        // После окончания печати + пауза — запускаем снова
        let totalTypingTime = typeSpeed * Double(text.count)
        DispatchQueue.main.asyncAfter(deadline: .now() + totalTypingTime + pauseDuration) {
            guard animationId == id else { return }
            runCycle(id: id)
        }
    }
}

