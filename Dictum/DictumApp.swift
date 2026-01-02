//
//  DictumApp.swift
//  Dictum
//
//  Entry point: @main, AppDelegate, FloatingPanel, menu bar
//

import SwiftUI
import AppKit
import Carbon

// MARK: - Custom Floating Panel
@MainActor
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Menu Bar Icon Creator
@MainActor
func createMenuBarIcon() -> NSImage {
    let size: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    let scale = size / 100.0

    // Хелпер для конвертации SVG координат в Core Graphics
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x * scale, y: size - y * scale)
    }

    // Создаём путь буквы D
    func createDPath() -> NSBezierPath {
        let path = NSBezierPath()

        // Внешний контур
        path.move(to: point(20, 20))
        path.line(to: point(50, 20))
        path.curve(to: point(80, 50),
                   controlPoint1: point(67, 20),
                   controlPoint2: point(80, 33))
        path.curve(to: point(50, 80),
                   controlPoint1: point(80, 67),
                   controlPoint2: point(67, 80))
        path.line(to: point(20, 80))
        path.close()

        // Внутреннее отверстие
        path.move(to: point(37, 35))
        path.line(to: point(37, 65))
        path.line(to: point(47, 65))
        path.curve(to: point(62, 50),
                   controlPoint1: point(55, 65),
                   controlPoint2: point(62, 58))
        path.curve(to: point(47, 35),
                   controlPoint1: point(62, 42),
                   controlPoint2: point(55, 35))
        path.close()

        path.windingRule = .evenOdd
        return path
    }

    // Clipping path для верхней части
    func createTopClip() -> NSBezierPath {
        let clip = NSBezierPath()
        clip.move(to: point(-10, -10))
        clip.line(to: point(110, -10))
        clip.line(to: point(110, 34))
        clip.line(to: point(-10, 60))
        clip.close()
        return clip
    }

    // Clipping path для нижней части
    func createBottomClip() -> NSBezierPath {
        let clip = NSBezierPath()
        clip.move(to: point(-10, 68))
        clip.line(to: point(110, 42))
        clip.line(to: point(110, 110))
        clip.line(to: point(-10, 110))
        clip.close()
        return clip
    }

    // Рисуем верхнюю часть (белая, сдвинутая)
    NSGraphicsContext.saveGraphicsState()
    createTopClip().addClip()

    let transform1 = AffineTransform(translationByX: -1.5 * scale, byY: 1.5 * scale)
    let upperPath = createDPath()
    upperPath.transform(using: transform1)

    NSColor.white.setFill()
    upperPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Рисуем нижнюю часть (серая, сдвинутая)
    NSGraphicsContext.saveGraphicsState()
    createBottomClip().addClip()

    let transform2 = AffineTransform(translationByX: 1.5 * scale, byY: -1.5 * scale)
    let lowerPath = createDPath()
    lowerPath.transform(using: transform2)

    NSColor(red: 0x9a / 255.0, green: 0x9a / 255.0, blue: 0x9c / 255.0, alpha: 1.0).setFill()
    lowerPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Красная точка (такие же пропорции как в основной иконке)
    let dotRadius = 8 * scale
    let dotCenter = point(82, 17)
    let dotRect = NSRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    let dotPath = NSBezierPath(ovalIn: dotRect)
    NSColor(red: 0xd9 / 255.0, green: 0x3f / 255.0, blue: 0x41 / 255.0, alpha: 1.0).setFill()
    dotPath.fill()

    image.unlockFocus()
    image.isTemplate = false
    return image
}


// MARK: - Screenshot Notification View
struct ScreenshotNotificationView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(DesignSystem.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Путь скопирован")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Готово к вставке")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .overlay(Color(red: 30/255, green: 30/255, blue: 32/255).opacity(0.95))
        )
        .cornerRadius(26)  // macOS Tahoe Toolbar Window standard
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }
}

// MARK: - App Delegate
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var window: NSWindow?
    var settingsWindow: NSWindow?
    var historyWindow: NSWindow?  // Отдельное окно для истории (CMD+4)
    var promptsWindow: NSWindow?  // Окно AI промптов (CMD+1)
    var snippetsWindow: NSWindow?  // Окно сниппетов (CMD+2)
    var notesWindow: NSWindow?  // Окно заметок (CMD+3)
    var onboardingWindow: NSWindow?  // Окно первоначальной настройки
    var hotKeyRefs: [EventHotKeyRef] = []
    var localEventMonitor: Any?
    var globalEventMonitor: Any?
    var localFlagsChangedMonitor: Any?

    // MARK: - CGEventTap для Right Option (Input Monitoring, работает без рестарта)
    private var rightOptionEventTap: CFMachPort?
    private var rightOptionRunLoopSource: CFRunLoopSource?
    private var _previousApp: NSRunningApplication?  // Предыдущее активное приложение для авто-вставки
    // Fix 10: NSLock для thread-safe доступа к previousApp
    private let previousAppLock = NSLock()
    var previousApp: NSRunningApplication? {
        get { previousAppLock.withLock { _previousApp } }
        set { previousAppLock.withLock { _previousApp = newValue } }
    }
    var screenshotNotificationWindow: NSWindow?  // Окно уведомления о скриншоте
    private var settingsKeyMonitor: Any?  // ESC monitor для закрытия настроек
    private var lastToggleTime: Date = .distantPast  // Debouncing для toggle записи (§/`)
    var lastAccessibilityState: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Убить предыдущие экземпляры приложения (при пересборке)
        // КРИТИЧНО: Защита от self-kill при system restart
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for app in runningApps where app != NSRunningApplication.current && app.processIdentifier != currentPID {
            // Убивать ТОЛЬКО старые процессы (запущенные >5 секунд назад)
            // Это защищает от убийства себя при system restart
            if let launchDate = app.launchDate,
               launchDate < Date().addingTimeInterval(-5) {
                NSLog("🔪 Killing old instance PID=\(app.processIdentifier) launched at \(launchDate)")
                app.forceTerminate()
            }
        }
        // Небольшая задержка чтобы старый процесс завершился
        Thread.sleep(forTimeInterval: 0.2)

        NSLog("🚀 Dictum запущен (PID=\(currentPID))")

        // Проверяем Accessibility БЕЗ показа диалога (диалог покажется в onboarding)
        let hasAccess = AccessibilityHelper.checkAccessibility()
        NSLog("🔐 Accessibility: \(hasAccess)")

        // Инициализация менеджеров
        _ = HistoryManager.shared
        _ = SettingsManager.shared
        _ = TextSwitcherManager.shared  // TextSwitcher

        // Предзагрузка локальной модели в фоне (если onboarding пройден)
        // Модель загружается всегда — будет готова при переключении на локальный провайдер
        if SettingsManager.shared.hasCompletedOnboarding {
            Task {
                // Сначала проверяем статус файлов модели
                await ParakeetASRProvider.shared.checkModelStatus()
                // Затем загружаем модель в память (если файлы есть)
                await ParakeetASRProvider.shared.initializeModelsIfNeeded()
                NSLog("✅ Локальная модель загружена при старте приложения")
            }
        }

        // Menu bar
        setupMenuBar()

        // Хоткеи
        setupHotKeys()
        startAccessibilityMonitoring()

        // Окно
        setupWindow()

        // Notifications
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: .openSettings, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hotkeyDidChange), name: .hotkeyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenshotHotkeyDidChange), name: .screenshotHotkeyChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubmitAndPaste), name: .submitAndPaste, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(disableGlobalHotkeys), name: .disableGlobalHotkeys, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enableGlobalHotkeys), name: .enableGlobalHotkeys, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleHistoryWindow), name: .toggleHistoryModal, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(togglePromptsWindow), name: .togglePromptsModal, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleSnippetsWindow), name: .toggleSnippetsModal, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleNotesWindow), name: .toggleNotesModal, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOnboardingCompleted), name: .onboardingCompleted, object: nil)

        // Авто-проверка Accessibility при возврате в приложение
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        // Резервный механизм: NSApplication.didBecomeActiveNotification (более надёжный)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        // Показываем окно при запуске (уменьшена задержка для быстрого старта)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if !SettingsManager.shared.hasCompletedOnboarding {
                // Первый запуск — показываем onboarding wizard
                self?.showOnboarding()
            } else if SettingsManager.shared.settingsWindowWasOpen {
                self?.openSettings()
            } else {
                self?.showWindow()
            }
        }

        // Автоматическая проверка обновлений при запуске (если включена)
        if SettingsManager.shared.autoCheckUpdates {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                UpdateManager.shared.checkForUpdates()
            }
        }

        NSLog("✅ Инициализация завершена")
    }

    @objc func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Bundle.main.bundleIdentifier else { return }

        // Приложение стало активным — проверить Accessibility
        NSLog("📱 appDidActivate (Workspace): отправляю accessibilityStatusChanged")
        NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
    }

    @objc func appDidBecomeActive(_ notification: Notification) {
        // NSApplication.didBecomeActiveNotification — более надёжный для нашего приложения
        NSLog("📱 appDidBecomeActive (NSApp): отправляю accessibilityStatusChanged")
        NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
    }

    // MARK: - Onboarding

    @objc func showOnboarding() {
        // Закрыть другие окна если открыты
        window?.orderOut(nil)
        settingsWindow?.orderOut(nil)

        let ow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 576),
            styleMask: [.titled, .fullSizeContentView],  // Без .closable — используем свою X кнопку
            backing: .buffered,
            defer: false
        )

        ow.title = "Настройка Dictum"
        ow.titlebarAppearsTransparent = true
        ow.titleVisibility = .hidden
        ow.backgroundColor = .clear
        ow.isOpaque = false
        ow.isMovableByWindowBackground = true

        let hostingView = NSHostingView(rootView: OnboardingView())
        ow.contentView = hostingView

        // Скругление углов (macOS Tahoe standard: 26pt)
        if let contentView = ow.contentView {
            contentView.superview?.wantsLayer = true
            contentView.superview?.layer?.cornerRadius = 26
            contentView.superview?.layer?.masksToBounds = true
        }

        ow.center()
        ow.isReleasedWhenClosed = false
        ow.delegate = self

        onboardingWindow = ow
        ow.makeKeyAndOrderFront(nil)
        NSApp.activate()

        NSLog("🎉 Onboarding wizard показан")
    }

    @objc func handleOnboardingCompleted() {
        NSLog("✅ Onboarding завершён")
        onboardingWindow?.close()
        showWindow()
    }

    @objc func hotkeyDidChange() {
        // Перерегистрируем хоткеи с новыми настройками
        unregisterHotKeys()
        setupHotKeys()
        NSLog("🔄 Хоткеи перерегистрированы")
    }

    @objc func screenshotHotkeyDidChange() {
        NSLog("📸 Screenshot hotkey changed, re-registering...")
        unregisterHotKeys()
        setupHotKeys()
    }

    @objc func handleScreenshotHotkey() {
        guard SettingsManager.shared.screenshotFeatureEnabled else {
            NSLog("⚠️ Screenshot feature is disabled")
            return
        }

        // Проверяем Screen Recording permission
        if !AccessibilityHelper.hasScreenRecordingPermission() {
            NSLog("❌ Screen Recording permission not granted")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Нужно разрешение"
                alert.informativeText = "Для создания скриншотов нужно разрешение Screen Recording.\n\nОткройте Системные настройки → Конфиденциальность → Запись экрана и включите Dictum."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Открыть настройки")
                alert.addButton(withTitle: "Отмена")

                if alert.runModal() == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return
        }

        NSLog("📸 Screenshot hotkey pressed")

        // Используем путь из настроек (по умолчанию ~/Documents/Screenshots)
        let savePath = SettingsManager.shared.screenshotSavePath
        let expandedPath = NSString(string: savePath).expandingTildeInPath

        // Создаём папку если не существует
        try? FileManager.default.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "dictum-screenshot-\(timestamp).png"
        let filepath = "\(expandedPath)/\(filename)"

        // Запускаем screencapture с интерактивным выбором
        // Fix R4-H1: Выполняем в background thread чтобы не блокировать UI
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", filepath]  // -i = interactive mode

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    // Диагностика
                    NSLog("📸 screencapture exit status: \(process.terminationStatus)")
                    NSLog("📸 Expected file: \(filepath)")
                    NSLog("📸 File exists: \(FileManager.default.fileExists(atPath: filepath))")

                    if process.terminationStatus == 0 {
                        if FileManager.default.fileExists(atPath: filepath) {
                            NSLog("✅ Screenshot saved: \(filepath)")

                            // Копируем путь в буфер обмена
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(filepath, forType: .string)

                            // Показываем уведомление
                            Task { @MainActor [weak self] in
                                self?.showScreenshotNotification()
                            }
                        } else {
                            NSLog("⚠️ Screenshot cancelled by user (file not created)")
                        }
                    } else {
                        NSLog("❌ screencapture failed with status: \(process.terminationStatus)")
                    }
                }
            } catch {
                NSLog("❌ Failed to execute screencapture: \(error)")
            }
        }
    }

    @MainActor
    func showScreenshotNotification() {
        // @MainActor гарантирует выполнение на main thread

        // Закрываем предыдущее уведомление если оно еще видимо
        if let existingWindow = screenshotNotificationWindow {
            existingWindow.orderOut(nil)
            existingWindow.close()
            screenshotNotificationWindow = nil
        }

        // Создаём временное floating уведомление
        let notification = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        notification.isOpaque = false
        notification.backgroundColor = .clear
        notification.level = .floating
        notification.collectionBehavior = [.canJoinAllSpaces, .stationary]
        notification.isReleasedWhenClosed = false  // Предотвращает краш при закрытии

        // SwiftUI контент
        let hostingView = NSHostingView(rootView: ScreenshotNotificationView())
        notification.contentView = hostingView

        // Позиционируем в правом верхнем углу активного экрана
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 240
            let y = screenFrame.maxY - 70
            notification.setFrameOrigin(NSPoint(x: x, y: y))
        }

        notification.orderFrontRegardless()

        // Сохраняем ссылку на окно
        screenshotNotificationWindow = notification

        // Автоматически скрываем через 2 секунды с weak self для предотвращения retain cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            // Проверяем что это все еще то же окно (может быть заменено новым)
            if let currentWindow = self?.screenshotNotificationWindow, currentWindow === notification {
                currentWindow.orderOut(nil)
                currentWindow.close()
                self?.screenshotNotificationWindow = nil
            }
        }
    }

    @objc func handleSubmitAndPaste() {
        submitAndPaste()
    }

    @objc func disableGlobalHotkeys() {
        // Временно отключить локальный монитор (для записи хоткеев в настройках)
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        NSLog("⌨️ Глобальные хоткеи отключены")
    }

    @objc func enableGlobalHotkeys() {
        // Восстановить хоткеи
        if localEventMonitor == nil {
            setupHotKeys()
        }
        NSLog("⌨️ Глобальные хоткеи включены")
    }

    func submitAndPaste() {
        guard let prevApp = previousApp else {
            // Нет предыдущего приложения - просто закрыть
            NSLog("⚠️ previousApp is nil, just closing")
            SoundManager.shared.playCopySound()
            window?.close()
            return
        }

        // FIX: Проверить что это не сам Dictum
        if prevApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            NSLog("⚠️ previousApp is Dictum itself, just closing")
            previousApp = nil
            SoundManager.shared.playCopySound()
            window?.close()
            return
        }

        NSLog("📱 Вставка в приложение: \(prevApp.localizedName ?? "unknown")")

        // Закрыть окно
        SoundManager.shared.playCopySound()
        window?.close()

        // Сохраняем ссылку перед обнулением
        let targetApp = prevApp
        previousApp = nil

        // Активировать предыдущее приложение с force
        targetApp.activate()

        // Вставить через Cmd+V с достаточной задержкой
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            // Проверить что приложение активировалось
            let currentApp = NSWorkspace.shared.frontmostApplication
            if currentApp?.processIdentifier == targetApp.processIdentifier {
                NSLog("✅ Приложение активно, вставляем")
                self?.simulatePaste()
            } else {
                NSLog("⚠️ Приложение не активировалось (\(currentApp?.localizedName ?? "nil")), повторная попытка")
                targetApp.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.simulatePaste()
                }
            }
        }
    }

    func simulatePaste() {
        // CGEvent — как в Maccy/Clipy, не требует диалога "управление System Events"
        // Требует только Accessibility permission (галочка в System Settings)
        let source = CGEventSource(stateID: .combinedSessionState)
        // Отключаем локальные события клавиатуры во время paste
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 0x09  // 'v' key

        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        keyVDown?.flags = .maskCommand
        keyVUp?.flags = .maskCommand

        keyVDown?.post(tap: .cgSessionEventTap)
        keyVUp?.post(tap: .cgSessionEventTap)

        NSLog("✅ Paste выполнен через CGEvent")
    }

    func unregisterHotKeys() {
        // Убираем старые Carbon хоткеи
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        // Убираем мониторы
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localFlagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            localFlagsChangedMonitor = nil
        }

        // CGEventTap для Right Option
        removeRightOptionEventTap()
    }

    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = createMenuBarIcon()
            button.action = #selector(statusBarClicked)
            button.sendAction(on: [.leftMouseUp])  // Только левый клик через action
        }

        // Создаём меню для правого клика (назначаем напрямую на statusItem)
        let menu = NSMenu()
        menu.autoenablesItems = false

        let openItem = NSMenuItem(title: "Открыть Dictum", action: #selector(showWindow), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        menu.addItem(openItem)

        let updateItem = NSMenuItem(title: "Проверить обновления...", action: #selector(checkForUpdatesMenu), keyEquivalent: "")
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(title: "Настройки...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Выход", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        statusItem?.menu = menu  // Правый клик автоматически показывает это меню
    }

    @objc func statusBarClicked(_ sender: NSStatusBarButton) {
        // FIX: Сохраняем previousApp СРАЗУ при клике, до активации Dictum
        let frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontApp
            NSLog("📱 [statusBarClicked] Сохранено: \(previousApp?.localizedName ?? "nil")")
        }

        // Левый клик - toggle окно (правый клик обрабатывается через statusItem?.menu)
        toggleWindow()
    }

    func setupHotKeys() {
        // Проверяем Accessibility
        let hasAccess = AccessibilityHelper.checkAccessibility()
        NSLog("🔐 Accessibility: \(hasAccess)")

        let hotkey = SettingsManager.shared.toggleHotkey
        NSLog("⌨️ Настроенный хоткей: keyCode=\(hotkey.keyCode), mods=\(hotkey.modifiers)")

        // Carbon API для глобальных хоткеев
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, inEvent, userData -> OSStatus in
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()

                // Получаем ID хоткея
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    inEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                // Обрабатываем в зависимости от ID
                switch hotKeyID.id {
                case 6:
                    // Screenshot hotkey
                    appDelegate.handleScreenshotHotkey()
                case 10:
                    // CMD+1 = Промпты
                    appDelegate.togglePromptsWindow()
                case 11:
                    // CMD+2 = Сниппеты
                    appDelegate.toggleSnippetsWindow()
                case 12:
                    // CMD+3 = Заметки
                    appDelegate.toggleNotesWindow()
                case 13:
                    // CMD+4 = История
                    appDelegate.toggleHistoryWindow()
                default:
                    // Toggle window hotkeys (1-5)
                    appDelegate.toggleWindow()
                }

                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        // Главный хоткей: правый Option (обрабатывается через flagsChanged мониторы)
        // Carbon API не поддерживает модификаторы как отдельные клавиши
        NSLog("⌨️ Главный хоткей: правый Option (обрабатывается через NSEvent monitors)")

        // Register screenshot hotkey (ID=6) if feature is enabled
        if SettingsManager.shared.screenshotFeatureEnabled {
            let screenshotHotkey = SettingsManager.shared.screenshotHotkey
            registerCarbonHotKey(
                keyCode: UInt32(screenshotHotkey.keyCode),
                modifiers: screenshotHotkey.modifiers,
                id: 6
            )
            NSLog("📸 Screenshot hotkey registered: \(screenshotHotkey.displayString)")
        }

        // Register modal hotkeys (CMD+1/2/3/4)
        // CMD+1 = Промпты (keyCode 18)
        registerCarbonHotKey(keyCode: 18, modifiers: UInt32(cmdKey), id: 10)
        // CMD+2 = Сниппеты (keyCode 19)
        registerCarbonHotKey(keyCode: 19, modifiers: UInt32(cmdKey), id: 11)
        // CMD+3 = Заметки (keyCode 20)
        registerCarbonHotKey(keyCode: 20, modifiers: UInt32(cmdKey), id: 12)
        // CMD+4 = История (keyCode 21)
        registerCarbonHotKey(keyCode: 21, modifiers: UInt32(cmdKey), id: 13)
        NSLog("⌨️ Modal hotkeys registered: CMD+1/2/3/4")

        // Локальный монитор для правого Option (когда модалка активна)
        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            // Правый Option: keyCode 61
            if event.keyCode == 61 && event.modifierFlags.contains(.option) {
                // Debouncing (150ms для быстрого отклика)
                let now = Date()
                if now.timeIntervalSince(self?.lastToggleTime ?? .distantPast) < 0.15 {
                    return event
                }
                self?.lastToggleTime = now
                self?.hideWindow()
                return nil  // Поглощаем
            }
            return event
        }

        // Локальный монитор (когда окно активно)
        // Перехватываем настроенный хоткей ДО того как символ попадёт в текстовое поле
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let eventKeyCode = event.keyCode

            // § (keyCode 10) или ` (keyCode 50) БЕЗ модификаторов — toggle записи
            // Только когда модалка видима
            if (eventKeyCode == 10 || eventKeyCode == 50) &&
               !event.modifierFlags.contains(.command) &&
               !event.modifierFlags.contains(.shift) &&
               !event.modifierFlags.contains(.option) &&
               !event.modifierFlags.contains(.control) &&
               self?.window?.isVisible == true {
                // Debouncing (150ms для быстрого отклика)
                let now = Date()
                if now.timeIntervalSince(self?.lastToggleTime ?? .distantPast) < 0.15 {
                    return nil  // Поглощаем, но не отправляем notification
                }
                self?.lastToggleTime = now

                // Отправляем notification для toggle записи
                NotificationCenter.default.post(name: .toggleRecording, object: nil)
                return nil  // Поглощаем — символ не попадёт в текстовое поле
            }

            let hotkeyKeyCode = SettingsManager.shared.toggleHotkey.keyCode
            let hotkeyMods = SettingsManager.shared.toggleHotkey.modifiers

            // Проверяем модификаторы
            var eventCarbonMods: UInt32 = 0
            if event.modifierFlags.contains(.command) { eventCarbonMods |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.shift) { eventCarbonMods |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.option) { eventCarbonMods |= UInt32(optionKey) }
            if event.modifierFlags.contains(.control) { eventCarbonMods |= UInt32(controlKey) }

            // Проверяем совпадение с настроенным хоткеем
            if eventKeyCode == hotkeyKeyCode && eventCarbonMods == hotkeyMods {
                self?.hideWindow()
                return nil
            }

            return event
        }

        // CGEventTap для правого Option (Input Monitoring — работает сразу без рестарта!)
        // Заменяет NSEvent.addGlobalMonitorForEvents который требует Accessibility и рестарт
        setupRightOptionEventTap()

        // Глобальный монитор (требует Accessibility)
        if hasAccess {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let eventKeyCode = event.keyCode
                let hotkeyKeyCode = SettingsManager.shared.toggleHotkey.keyCode
                let hotkeyMods = SettingsManager.shared.toggleHotkey.modifiers

                // Проверяем модификаторы
                var eventCarbonMods: UInt32 = 0
                if event.modifierFlags.contains(.command) { eventCarbonMods |= UInt32(cmdKey) }
                if event.modifierFlags.contains(.shift) { eventCarbonMods |= UInt32(shiftKey) }
                if event.modifierFlags.contains(.option) { eventCarbonMods |= UInt32(optionKey) }
                if event.modifierFlags.contains(.control) { eventCarbonMods |= UInt32(controlKey) }

                // Проверяем совпадение с настроенным хоткеем
                if eventKeyCode == hotkeyKeyCode && eventCarbonMods == hotkeyMods {
                    Task { @MainActor [weak self] in
                        self?.toggleWindow()
                    }
                    return
                }

                // ESC закрывает окно если оно видно (работает без фокуса)
                if eventKeyCode == 53 && self?.window?.isVisible == true {
                    Task { @MainActor [weak self] in
                        self?.hideWindow()
                    }
                }
            }
            NSLog("✅ Глобальный монитор событий установлен")
        } else {
            NSLog("⚠️ Глобальный монитор недоступен без Accessibility")
        }
    }

    // MARK: - Accessibility Monitoring
    func startAccessibilityMonitoring() {
        lastAccessibilityState = AccessibilityHelper.checkAccessibility()

        // Подписываемся на notification об изменении статуса Accessibility
        // (отправляется когда приложение становится активным после System Settings)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccessibilityStatusChanged),
            name: .accessibilityStatusChanged,
            object: nil
        )
        NSLog("👀 Подписался на accessibilityStatusChanged")
    }

    @objc func handleAccessibilityStatusChanged() {
        let currentState = AccessibilityHelper.checkAccessibility()
        let hasInputMonitoring = CGPreflightListenEventAccess()
        NSLog("🔔 handleAccessibilityStatusChanged: accessibility=%@, inputMonitoring=%@, lastState=%@",
              currentState ? "true" : "false",
              hasInputMonitoring ? "true" : "false",
              lastAccessibilityState ? "true" : "false")

        // CGEventTap для Right Option — перезапускаем если есть Input Monitoring
        // Input Monitoring работает СРАЗУ без рестарта!
        if hasInputMonitoring {
            setupRightOptionEventTap()
        }

        // Если статус изменился с false на true — перерегистрируем хоткеи и TextSwitcher
        if currentState && !lastAccessibilityState {
            NSLog("✅ Accessibility получен! Перерегистрирую хоткеи и TextSwitcher...")

            // Первая попытка — немедленно
            unregisterHotKeys()
            setupHotKeys()

            // Повторные попытки с задержкой (для NSEvent глобальных мониторов которые всё ещё используются)
            // CGEventTap с Input Monitoring работает сразу, но NSEvent глобальные мониторы требуют задержку
            for delay in [0.5, 1.0, 2.0, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    // Проверяем что Accessibility всё ещё есть
                    guard AccessibilityHelper.checkAccessibility() else { return }

                    NSLog("🔄 Повторная перерегистрация хоткеев (%.1f сек)", delay)
                    self.unregisterHotKeys()
                    self.setupHotKeys()
                }
            }

            // Запускаем TextSwitcher если он включён (без перезагрузки!)
            if TextSwitcherManager.shared.isEnabled {
                let started = KeyboardMonitor.shared.startMonitoring()
                NSLog("✅ KeyboardMonitor: %@", started ? "запущен" : "ОШИБКА")
            }
        }

        lastAccessibilityState = currentState
    }

    func registerCarbonHotKey(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x4F4C4142) // "OLAB"
        hotKeyID.id = id

        var eventHotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )

        if status == noErr, let ref = eventHotKeyRef {
            hotKeyRefs.append(ref)
            NSLog("✅ Carbon хоткей: id=\(id), code=\(keyCode), mod=\(modifiers)")
        } else {
            NSLog("❌ Ошибка Carbon хоткея: \(status)")
        }
    }

    // MARK: - CGEventTap для Right Option (Input Monitoring)

    /// Настраивает CGEventTap для отслеживания Right Option
    /// Использует Input Monitoring permission (работает сразу без рестарта!)
    func setupRightOptionEventTap() {
        // Убираем старый tap если есть
        removeRightOptionEventTap()

        // Проверяем Input Monitoring permission
        guard CGPreflightListenEventAccess() else {
            NSLog("⚠️ Нет Input Monitoring для Right Option")

            // Если onboarding не пройден — НЕ показывать диалог сейчас
            // Onboarding сам покажет диалог в permissions step
            if !SettingsManager.shared.hasCompletedOnboarding {
                NSLog("   Onboarding не пройден — откладываю запрос Input Monitoring для Right Option")
                NSLog("   Event tap будет создан после прохождения onboarding")
                return
            }

            // Запрашиваем только если onboarding уже пройден
            NSLog("   Запрашиваю Input Monitoring для Right Option (onboarding пройден)")
            CGRequestListenEventAccess()
            return
        }

        // Только flagsChanged для отслеживания модификаторов
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)

        // Создаём event tap
        // .listenOnly = Input Monitoring permission (работает сразу!)
        // .defaultTap = Accessibility permission (требует рестарт)
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { (proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

                // tapDisabledByTimeout — macOS отключает tap если callback слишком долгий
                if type == .tapDisabledByTimeout {
                    if let tap = appDelegate.rightOptionEventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        NSLog("🔄 CGEventTap перезапущен после timeout")
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Правый Option: keyCode 61
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if keyCode == 61 && event.flags.contains(.maskAlternate) {
                    // Debouncing (150ms)
                    let now = Date()
                    if now.timeIntervalSince(appDelegate.lastToggleTime) >= 0.15 {
                        appDelegate.lastToggleTime = now
                        // UI операции на main thread!
                        DispatchQueue.main.async {
                            NSLog("✅ [CGEventTap] Right Option → toggleWindow()")
                            appDelegate.toggleWindow()
                        }
                    }
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("❌ Не удалось создать CGEventTap для Right Option")
            return
        }

        rightOptionEventTap = eventTap

        // Добавляем в RunLoop
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        rightOptionRunLoopSource = source

        // Активируем tap
        CGEvent.tapEnable(tap: eventTap, enable: true)

        NSLog("✅ CGEventTap для Right Option установлен (Input Monitoring)")
    }

    /// Удаляет CGEventTap для Right Option
    func removeRightOptionEventTap() {
        if let source = rightOptionRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            rightOptionRunLoopSource = nil
        }
        if let tap = rightOptionEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            rightOptionEventTap = nil
        }
    }

    func setupWindow() {
        let contentView = InputModalView()

        let windowWidth: CGFloat = 680

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 150),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true  // Обрезать по границам окна
        hostingView.layer?.cornerRadius = 26  // Синхронизировать с SwiftUI clipShape
        hostingView.layer?.shadowOpacity = 0  // Явно отключить тень на слое
        panel.contentView = hostingView

        self.window = panel
        panel.orderOut(nil)  // Скрыть, но НЕ закрывать (close() вызывает applicationShouldTerminateAfterLastWindowClosed)
    }

    func centerWindowOnActiveScreen() {
        guard let window = window else { return }

        let width: CGFloat = 680
        let height: CGFloat = 150

        // Находим экран с курсором мыши
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen: NSScreen? = nil

        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                targetScreen = screen
                break
            }
        }

        // Fallback на главный экран
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first

        if let screen = screen {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.origin.x + (screenFrame.width - width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - height) / 2
            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    @objc func toggleWindow() {
        guard let window = window else { return }

        if window.isVisible {
            // Закрытие по хоткею - проверить есть ли текст для вставки
            NotificationCenter.default.post(name: .checkAndSubmit, object: nil)
        } else {
            showWindow()
        }
    }

    func hideWindow() {
        guard let window = window else { return }
        SoundManager.shared.playCloseSound()

        // Сначала активируем предыдущее приложение (курсор вернётся в исходное поле)
        if let prevApp = previousApp {
            prevApp.activate()
            previousApp = nil
        }

        // Потом закрываем окно (небольшая задержка для активации)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak window] in
            window?.close()
        }
    }

    @objc func showWindow() {
        // Создаём окно если его нет (защита от краша)
        if window == nil {
            setupWindow()
        }
        guard let window = window else { return }

        // Сохраняем предыдущее активное приложение (до активации нашего)
        // Только если окно ещё не видно И previousApp ещё не установлен
        // (previousApp может быть уже установлен в statusBarClicked)
        if !window.isVisible && previousApp == nil {
            let frontApp = NSWorkspace.shared.frontmostApplication
            // Не сохраняем если это сам Dictum
            if frontApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = frontApp
            }
            NSLog("📱 [showWindow] Сохранено: \(previousApp?.localizedName ?? "nil")")
        }

        // Сбрасываем состояние View (история закрыта, текст пустой)
        NotificationCenter.default.post(name: .resetInputView, object: nil)

        // Центрируем на активном экране
        centerWindowOnActiveScreen()

        // Звук
        SoundManager.shared.playOpenSound()

        // Показываем
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        // Фокус на текстовое поле
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
            guard let self = self, let window = window, window.isVisible else { return }
            if let textView = self.findTextView(in: window.contentView) {
                window.makeFirstResponder(textView)
            }
        }
    }

    func findTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }

        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let found = findTextView(in: subview) {
                return found
            }
        }

        return nil
    }

    @objc func openSettings() {
        // Скрываем главное модальное окно если оно открыто
        if let mainWindow = window, mainWindow.isVisible {
            mainWindow.close()
        }

        // Проверяем, не открыто ли уже окно настроек
        if let sw = settingsWindow, sw.isVisible {
            sw.orderFront(nil)
            NSApp.activate()
            return
        }

        // Фиксированный размер окна
        let windowWidth: CGFloat = 900
        let windowHeight: CGFloat = 700

        let sw = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        sw.title = "Настройки Dictum"
        sw.titlebarAppearsTransparent = true
        sw.titleVisibility = .hidden
        sw.backgroundColor = .clear
        sw.isOpaque = false

        let hostingView = NSHostingView(rootView: SettingsView())
        hostingView.wantsLayer = true
        hostingView.layer?.masksToBounds = true
        sw.contentView = hostingView

        // Скругление ВНЕШНЕЙ рамки окна через _NSThemeFrame (superview contentView)
        // macOS Tahoe Toolbar Window standard: 26pt
        if let contentView = sw.contentView {
            contentView.superview?.wantsLayer = true
            contentView.superview?.layer?.cornerRadius = 26
            contentView.superview?.layer?.masksToBounds = true
        }

        sw.minSize = NSSize(width: 800, height: 600)

        // Центрируем на экране с курсором (как модалка)
        let mouseLocation = NSEvent.mouseLocation
        var targetScreen: NSScreen? = nil
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                targetScreen = screen
                break
            }
        }
        if let screen = targetScreen ?? NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = sw.frame.size
            let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
            sw.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            sw.center()
        }

        // H6: isReleasedWhenClosed = false - мы сами управляем lifecycle через settingsWindow = nil
        sw.isReleasedWhenClosed = false
        sw.delegate = self
        settingsWindow = sw

        // Кастомизация кнопок окна: скрыть minimize, переместить zoom на его место
        sw.standardWindowButton(.miniaturizeButton)?.isHidden = true
        if let zoomButton = sw.standardWindowButton(.zoomButton),
           let minimizeButton = sw.standardWindowButton(.miniaturizeButton) {
            zoomButton.setFrameOrigin(minimizeButton.frame.origin)
        }
        // Сдвинуть close и zoom на 6pt вниз-вправо
        let buttonOffset: CGFloat = 6
        for buttonType: NSWindow.ButtonType in [.closeButton, .zoomButton] {
            if let button = sw.standardWindowButton(buttonType) {
                button.setFrameOrigin(NSPoint(
                    x: button.frame.origin.x + buttonOffset,
                    y: button.frame.origin.y - buttonOffset
                ))
            }
        }

        // ESC закрывает окно настроек
        settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.settingsWindow?.isKeyWindow == true {
                self?.settingsWindow?.close()
                return nil  // Поглощаем событие
            }
            return event
        }

        SettingsManager.shared.settingsWindowWasOpen = true

        sw.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - History Window
    @objc func toggleHistoryWindow() {
        if let hw = historyWindow, hw.isVisible {
            // Закрыть окно истории
            hw.close()
            historyWindow = nil
        } else {
            // Открыть окно истории
            showHistoryWindow()
        }
    }

    func showHistoryWindow() {
        // Закрыть предыдущее если есть
        if let hw = historyWindow {
            hw.close()
            historyWindow = nil
        }

        // Размер окна истории
        let historyWidth: CGFloat = 720
        let historyHeight: CGFloat = 450

        // Создаём floating panel для истории
        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: historyWidth, height: historyHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        // SwiftUI контент
        let historyView = HistoryModalView(
            isPresented: .constant(true),
            onSelect: { [weak self] item in
                // Отправить выбранный элемент в InputModal
                NotificationCenter.default.post(name: .historyItemSelected, object: item)
                // Закрыть окно истории
                self?.historyWindow?.close()
                self?.historyWindow = nil
            }
        )

        let hostingView = NSHostingView(rootView: historyView)
        panel.contentView = hostingView

        // Центрируем относительно основного окна или экрана
        if let mainWindow = window, mainWindow.isVisible {
            let mainFrame = mainWindow.frame
            let x = mainFrame.origin.x + (mainFrame.width - historyWidth) / 2
            let y = mainFrame.origin.y + (mainFrame.height - historyHeight) / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        historyWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Prompts Modal (CMD+1)

    @objc func togglePromptsWindow() {
        if promptsWindow?.isVisible == true {
            promptsWindow?.close()
            promptsWindow = nil
        } else {
            showPromptsWindow()
        }
    }

    func showPromptsWindow() {
        // Закрываем если уже открыто
        if promptsWindow != nil {
            promptsWindow?.close()
            promptsWindow = nil
        }

        let modalWidth: CGFloat = 720
        let modalHeight: CGFloat = 450

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: modalWidth, height: modalHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let promptsView = PromptsModalView(
            isPresented: .constant(true),
            onSelect: { [weak self] prompt in
                NotificationCenter.default.post(name: .promptSelected, object: prompt)
                self?.promptsWindow?.close()
                self?.promptsWindow = nil
            }
        )

        let hostingView = NSHostingView(rootView: promptsView)
        panel.contentView = hostingView

        if let mainWindow = window, mainWindow.isVisible {
            let mainFrame = mainWindow.frame
            let x = mainFrame.origin.x + (mainFrame.width - modalWidth) / 2
            let y = mainFrame.origin.y + (mainFrame.height - modalHeight) / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        promptsWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Snippets Modal (CMD+2)

    @objc func toggleSnippetsWindow() {
        if snippetsWindow?.isVisible == true {
            snippetsWindow?.close()
            snippetsWindow = nil
        } else {
            showSnippetsWindow()
        }
    }

    func showSnippetsWindow() {
        if snippetsWindow != nil {
            snippetsWindow?.close()
            snippetsWindow = nil
        }

        let modalWidth: CGFloat = 720
        let modalHeight: CGFloat = 450

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: modalWidth, height: modalHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let snippetsView = SnippetsModalView(
            isPresented: .constant(true),
            onSelect: { [weak self] snippet in
                NotificationCenter.default.post(name: .snippetSelected, object: snippet)
                self?.snippetsWindow?.close()
                self?.snippetsWindow = nil
            }
        )

        let hostingView = NSHostingView(rootView: snippetsView)
        panel.contentView = hostingView

        if let mainWindow = window, mainWindow.isVisible {
            let mainFrame = mainWindow.frame
            let x = mainFrame.origin.x + (mainFrame.width - modalWidth) / 2
            let y = mainFrame.origin.y + (mainFrame.height - modalHeight) / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        snippetsWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Notes Modal (CMD+3)

    @objc func toggleNotesWindow() {
        if notesWindow?.isVisible == true {
            notesWindow?.close()
            notesWindow = nil
        } else {
            showNotesWindow()
        }
    }

    func showNotesWindow() {
        if notesWindow != nil {
            notesWindow?.close()
            notesWindow = nil
        }

        let modalWidth: CGFloat = 720
        let modalHeight: CGFloat = 450

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: modalWidth, height: modalHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let notesView = NotesModalView(
            isPresented: .constant(true),
            onSelect: { [weak self] note in
                NotificationCenter.default.post(name: .noteSelected, object: note)
                self?.notesWindow?.close()
                self?.notesWindow = nil
            }
        )

        let hostingView = NSHostingView(rootView: notesView)
        panel.contentView = hostingView

        if let mainWindow = window, mainWindow.isVisible {
            let mainFrame = mainWindow.frame
            let x = mainFrame.origin.x + (mainFrame.width - modalWidth) / 2
            let y = mainFrame.origin.y + (mainFrame.height - modalHeight) / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        notesWindow = panel
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func checkForUpdatesMenu() {
        UpdateManager.shared.checkForUpdates(force: true)

        // Показать уведомление через 2 секунды
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let updateManager = UpdateManager.shared

            if updateManager.updateAvailable, let version = updateManager.latestVersion {
                let alert = NSAlert()
                alert.messageText = "Доступна новая версия"
                alert.informativeText = "Dictum \(version) доступна для скачивания.\nТекущая версия: \(AppConfig.version)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Скачать")
                alert.addButton(withTitle: "Позже")

                if alert.runModal() == .alertFirstButtonReturn {
                    updateManager.openDownloadPage()
                }
            } else if !updateManager.isChecking && updateManager.checkError == nil {
                let alert = NSAlert()
                alert.messageText = "Обновлений нет"
                alert.informativeText = "Вы используете последнюю версию Dictum (\(AppConfig.version))."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // MARK: - NSApplicationDelegate
    // Не завершать приложение при закрытии последнего окна (приложение живёт в menubar)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotKeys()
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }

        // Игнорируем закрытие screenshot notification window - это временное окно
        if closedWindow == screenshotNotificationWindow {
            screenshotNotificationWindow = nil
            return
        }

        // Окно истории
        if closedWindow == historyWindow {
            historyWindow?.delegate = nil
            historyWindow = nil
            return
        }

        // Окно промптов
        if closedWindow == promptsWindow {
            promptsWindow?.delegate = nil
            promptsWindow = nil
            return
        }

        // Окно сниппетов
        if closedWindow == snippetsWindow {
            snippetsWindow?.delegate = nil
            snippetsWindow = nil
            return
        }

        // Окно заметок
        if closedWindow == notesWindow {
            notesWindow?.delegate = nil
            notesWindow = nil
            return
        }

        // Окно onboarding
        if closedWindow == onboardingWindow {
            onboardingWindow?.delegate = nil
            onboardingWindow = nil
            // НЕ помечаем как завершённый и НЕ показываем модалку
            // При следующем запуске onboarding откроется снова
            if !SettingsManager.shared.hasCompletedOnboarding {
                NSLog("⚠️ Onboarding закрыт без завершения")
            }
            return
        }

        if closedWindow == settingsWindow {
            // Удаляем ESC monitor
            if let monitor = settingsKeyMonitor {
                NSEvent.removeMonitor(monitor)
                settingsKeyMonitor = nil
            }
            // Сначала убираем delegate чтобы избежать повторных вызовов
            settingsWindow?.delegate = nil
            settingsWindow = nil
            SettingsManager.shared.settingsWindowWasOpen = false

            // Показываем модальное окно после закрытия настроек (без сброса текста)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
            return
        }

        // H3: Для главного окна - пересоздаём через setupWindow
        if closedWindow == window {
            window?.delegate = nil
            window = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.setupWindow()
            }
        }
    }

    @objc func quitApp() {
        // Fix 1: Очищаем Carbon hotkeys ДО terminate
        unregisterHotKeys()

        // Убираем NotificationCenter observers
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)

        // Убираем мониторы событий
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
        }

        // Закрываем screenshot notification window если открыто
        if let notificationWindow = screenshotNotificationWindow {
            notificationWindow.orderOut(nil)
            notificationWindow.close()
            screenshotNotificationWindow = nil
        }

        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main App
@main
struct DictumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
