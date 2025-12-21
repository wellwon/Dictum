#!/usr/bin/env swift

import AppKit
import Foundation

// Генератор иконки Dictum
// Создаёт .icns файл программно
// Дизайн: разрезанная буква D с красной точкой

func createIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()

    let scale = size / 100.0

    // Хелпер для конвертации SVG координат в Core Graphics
    // SVG: Y вниз (0 сверху), CG: Y вверх (0 снизу)
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x * scale, y: size - y * scale)
    }

    // Фон - чёрный с скруглёнными углами
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.22
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.black.setFill()
    bgPath.fill()

    // Создаём путь буквы D
    func createDPath() -> NSBezierPath {
        let path = NSBezierPath()

        // Внешний контур (SVG: M20 20 H50 C67 20 80 33 80 50 C80 67 67 80 50 80 H20 V20 Z)
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

        // Внутреннее отверстие (SVG: M37 35 V65 H47 C55 65 62 58 62 50 C62 42 55 35 47 35 H37 Z)
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
    // SVG: M -10 -10 L 110 -10 L 110 34 L -10 60 Z
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
    // SVG: M -10 68 L 110 42 L 110 110 L -10 110 Z
    func createBottomClip() -> NSBezierPath {
        let clip = NSBezierPath()
        clip.move(to: point(-10, 68))
        clip.line(to: point(110, 42))
        clip.line(to: point(110, 110))
        clip.line(to: point(-10, 110))
        clip.close()
        return clip
    }

    // Рисуем верхнюю часть (белая, сдвинутая на -1.5, -1.5 в SVG координатах)
    NSGraphicsContext.saveGraphicsState()
    createTopClip().addClip()

    let transform1 = AffineTransform(translationByX: -1.5 * scale, byY: 1.5 * scale)
    let upperPath = createDPath()
    upperPath.transform(using: transform1)

    NSColor.white.setFill()
    upperPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Рисуем нижнюю часть (серая #9a9a9c, сдвинутая на +1.5, +1.5 в SVG координатах)
    NSGraphicsContext.saveGraphicsState()
    createBottomClip().addClip()

    let transform2 = AffineTransform(translationByX: 1.5 * scale, byY: -1.5 * scale)
    let lowerPath = createDPath()
    lowerPath.transform(using: transform2)

    NSColor(red: 0x9a / 255.0, green: 0x9a / 255.0, blue: 0x9c / 255.0, alpha: 1.0).setFill()
    lowerPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Красная точка в правом верхнем углу
    // Равноудалена от угла (~95,5) и от буквы D (~80,20)
    let dotRadius = 8 * scale
    let dotCenter = point(82, 17)
    let dotRect = NSRect(
        x: dotCenter.x - dotRadius,
        y: dotCenter.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    let dotPath = NSBezierPath(ovalIn: dotRect)

    // Красный цвет #d93f41
    NSColor(red: 0xd9 / 255.0, green: 0x3f / 255.0, blue: 0x41 / 255.0, alpha: 1.0).setFill()
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

    print("🎨 Генерация иконок Dictum (буква D)...")

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
