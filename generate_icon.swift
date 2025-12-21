#!/usr/bin/env swift

import AppKit
import Foundation

// Генератор иконки Dictum
// Создаёт .icns файл программно

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    // Фон - тёмный градиент
    let gradient = NSGradient(colors: [
        NSColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0),
        NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
    ])!

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    gradient.draw(in: path, angle: -45)

    // Обводка
    NSColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 0.5).setStroke()
    path.lineWidth = size * 0.02
    path.stroke()

    // Буква "O" с градиентом
    let fontSize = size * 0.55
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle
    ]

    let text = "O"
    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: (size - textSize.width) / 2,
        y: (size - textSize.height) / 2 - size * 0.02,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)

    // Акцент - маленький кружок (точка записи)
    let dotSize = size * 0.12
    let dotX = size * 0.68
    let dotY = size * 0.68
    let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
    let dotPath = NSBezierPath(ovalIn: dotRect)

    // Оранжевый акцент
    NSColor(red: 1.0, green: 0.4, blue: 0.2, alpha: 1.0).setFill()
    dotPath.fill()

    image.unlockFocus()

    return image
}

func saveImage(_ image: NSImage, to url: URL, size: Int) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        print("❌ Ошибка создания PNG для размера \(size)")
        return
    }

    do {
        try pngData.write(to: url)
        print("✅ Создан: \(url.lastPathComponent)")
    } catch {
        print("❌ Ошибка записи: \(error)")
    }
}

func createIconSet() {
    let iconsetPath = FileManager.default.currentDirectoryPath + "/AppIcon.iconset"

    // Создаём директорию iconset
    try? FileManager.default.removeItem(atPath: iconsetPath)
    try! FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

    // Размеры иконок для macOS
    let sizes: [(name: String, size: Int)] = [
        ("icon_16x16", 16),
        ("icon_16x16@2x", 32),
        ("icon_32x32", 32),
        ("icon_32x32@2x", 64),
        ("icon_128x128", 128),
        ("icon_128x128@2x", 256),
        ("icon_256x256", 256),
        ("icon_256x256@2x", 512),
        ("icon_512x512", 512),
        ("icon_512x512@2x", 1024)
    ]

    print("🎨 Генерация иконок Dictum...")

    for (name, size) in sizes {
        let image = createIcon(size: CGFloat(size))
        let url = URL(fileURLWithPath: "\(iconsetPath)/\(name).png")
        saveImage(image, to: url, size: size)
    }

    print("\n📦 Создание .icns файла...")

    // Конвертируем iconset в icns
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetPath]

    do {
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("✅ AppIcon.icns создан успешно!")

            // Удаляем временную директорию iconset
            try? FileManager.default.removeItem(atPath: iconsetPath)
        } else {
            print("❌ Ошибка iconutil: \(process.terminationStatus)")
        }
    } catch {
        print("❌ Ошибка запуска iconutil: \(error)")
    }
}

// Запуск
createIconSet()
