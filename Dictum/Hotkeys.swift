//
//  Hotkeys.swift
//  Dictum
//
//  Конфигурация и запись глобальных хоткеев
//

import SwiftUI
import AppKit
import Carbon

// MARK: - Hotkey Configuration
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt32  // Carbon modifiers

    // Отображаемое имя клавиши
    var keyName: String {
        switch keyCode {
        case 10: return "§"
        case 50: return "`"
        case 49: return "Space"
        case 36: return "Return"
        case 53: return "Esc"
        default:
            if let char = keyCodeToChar(keyCode) {
                return String(char).uppercased()
            }
            return "Key \(keyCode)"
        }
    }

    var modifierNames: String {
        var names: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { names.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { names.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { names.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { names.append("⌃") }
        return names.joined(separator: " ")
    }

    var displayString: String {
        if modifiers == 0 {
            return keyName
        }
        return modifierNames + " " + keyName
    }

    private func keyCodeToChar(_ code: UInt16) -> Character? {
        let keyMap: [UInt16: Character] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: "."
        ]
        return keyMap[code]
    }

    static let defaultToggle = HotkeyConfig(keyCode: 10, modifiers: UInt32(cmdKey)) // ⌘ + §
}

