//
//  DoubleCmdFlowTests.swift
//  Dictum
//
//  ЭМУЛЯЦИЯ РЕАЛЬНОГО ПОВЕДЕНИЯ Double Cmd.
//
//  Эти тесты симулируют ПОЛНЫЙ FLOW пользователя:
//  1. Набор текста (обновление wordBuffer)
//  2. Нажатие пробела (wordBuffer → lastProcessedWord)
//  3. Double Cmd (getTextToConvert → convert → replace)
//
//  Цель: найти ВСЕ баги до того как пользователь их найдёт.
//
//  Запуск: ./build/Build/Products/Debug/DoubleCmdFlowTests
//

import Foundation

// MARK: - Test Infrastructure

struct FlowTestResult {
    let name: String
    let scenario: String
    let passed: Bool
    let expected: String
    let actual: String
    let debug: String

    var description: String {
        if passed {
            return "✅ \(name)"
        } else {
            return """
            ❌ \(name)
               Сценарий: \(scenario)
               Expected: '\(expected)'
               Actual:   '\(actual)'
               Debug:    \(debug)
            """
        }
    }
}

nonisolated(unsafe) var flowResults: [FlowTestResult] = []

// MARK: - Full Flow Simulator

/// Эмулятор ПОЛНОГО flow Double Cmd
/// Копирует РЕАЛЬНУЮ логику из:
/// - KeyboardMonitor.swift (wordBuffer, lastProcessedWord, pendingPunctuation)
/// - DoubleCmdHandler.getTextToConvert()
/// - LayoutMaps.convert()
class FullFlowSimulator {

    // MARK: - State (как в KeyboardMonitor)

    var wordBuffer: String = ""
    var lastProcessedWord: String = ""
    var pendingPunctuation: String = ""
    var isReplacing: Bool = false

    // MARK: - Actions Log

    var actionLog: [String] = []

    // MARK: - User Actions

    /// Симуляция нажатия клавиши
    func pressKey(_ char: Character) {
        // Логика из KeyboardMonitor.handleKeyDownCGEvent()

        // Блокируем во время замены
        if isReplacing {
            actionLog.append("BLOCKED: '\(char)' (isReplacing=true)")
            return
        }

        let lowercasedChar = Character(char.lowercased())
        let isMappableQWERTY = LayoutMaps.qwertyCharacters.contains(lowercasedChar) ||
                               LayoutMaps.allQwertyMappableCharacters.contains(char)
        let isMappableRussian = LayoutMaps.russianCharacters.contains(lowercasedChar) ||
                                LayoutMaps.allRussianMappableCharacters.contains(char)
        let isMappable = isMappableQWERTY || isMappableRussian

        if char.isLetter || char.isNumber || (isMappable && !char.isPunctuation && !char.isWhitespace) {
            // Буква/цифра → добавляем в wordBuffer
            pendingPunctuation = ""
            wordBuffer.append(char)
            actionLog.append("LETTER: '\(char)' → wordBuffer='\(wordBuffer)'")
        } else if char.isPunctuation {
            // Пунктуация → триггер processWord, добавляем в pendingPunctuation
            if !wordBuffer.isEmpty {
                lastProcessedWord = wordBuffer
                actionLog.append("PUNCT TRIGGER: wordBuffer→lastProcessedWord, lastProcessedWord='\(lastProcessedWord)'")
                wordBuffer = ""
            }
            pendingPunctuation.append(char)
            actionLog.append("PUNCT: '\(char)' → pendingPunctuation='\(pendingPunctuation)'")
        } else if char.isWhitespace {
            // Пробел → триггер processWord, очистка pendingPunctuation
            if !wordBuffer.isEmpty {
                lastProcessedWord = wordBuffer
                actionLog.append("SPACE TRIGGER: wordBuffer→lastProcessedWord, lastProcessedWord='\(lastProcessedWord)'")
                wordBuffer = ""
            }
            pendingPunctuation = ""
            actionLog.append("SPACE: pendingPunctuation cleared")
        }
    }

    /// Симуляция набора текста
    func typeText(_ text: String) {
        actionLog.append("--- TYPE: '\(text)' ---")
        for char in text {
            pressKey(char)
        }
    }

    // MARK: - Double Cmd Action

    /// КРИТИЧЕСКАЯ ФУНКЦИЯ: копия логики из DoubleCmdHandler.getTextToConvert()
    /// Это ИМЕННО та логика которая содержит баг!
    func getTextToConvert_CURRENT() -> (text: String, isSelection: Bool)? {
        let minWordLength = 2

        actionLog.append("--- getTextToConvert_CURRENT ---")
        actionLog.append("  wordBuffer='\(wordBuffer)', lastProcessedWord='\(lastProcessedWord)', pending='\(pendingPunctuation)'")

        // Приоритет 1: AX Selection — пропускаем (тестируем только wordBuffer flow)

        // Приоритет 2: wordBuffer + pendingPunctuation (ТЕКУЩИЙ КОД — БАГОВЫЙ!)
        let wordWithPunc = wordBuffer + pendingPunctuation
        if !wordBuffer.isEmpty && wordWithPunc.count >= minWordLength {
            actionLog.append("  → RETURN wordBuffer+punc: '\(wordWithPunc)'")
            return (wordWithPunc, false)
        }

        // Приоритет 3: lastProcessedWord + pendingPunctuation
        let combined = lastProcessedWord + pendingPunctuation
        if !combined.isEmpty && combined.count >= minWordLength {
            actionLog.append("  → RETURN lastProcessedWord+punc: '\(combined)'")
            return (combined, false)
        }

        actionLog.append("  → RETURN nil")
        return nil
    }

    /// ИСПРАВЛЕННАЯ ФУНКЦИЯ: объединяет wordBuffer + lastProcessedWord
    func getTextToConvert_FIXED() -> (text: String, isSelection: Bool)? {
        let minWordLength = 2

        actionLog.append("--- getTextToConvert_FIXED ---")
        actionLog.append("  wordBuffer='\(wordBuffer)', lastProcessedWord='\(lastProcessedWord)', pending='\(pendingPunctuation)'")

        // Приоритет 1: AX Selection — пропускаем

        // ИСПРАВЛЕНИЕ: Проверяем ОБЪЕДИНЕНИЕ wordBuffer + lastProcessedWord
        if !wordBuffer.isEmpty && !lastProcessedWord.isEmpty {
            let wordLayout = LayoutMaps.detectLayout(in: wordBuffer)
            let lastLayout = LayoutMaps.detectLayout(in: lastProcessedWord)

            // Если ОБА слова в одной раскладке → объединяем
            if wordLayout == lastLayout {
                let combined = lastProcessedWord + " " + wordBuffer + pendingPunctuation
                if combined.count >= minWordLength {
                    actionLog.append("  → RETURN COMBINED: '\(combined)' (both \(wordLayout?.rawValue ?? "nil"))")
                    return (combined, false)
                }
            }
        }

        // Приоритет 2: Только wordBuffer (если lastProcessedWord пустой или другая раскладка)
        let wordWithPunc = wordBuffer + pendingPunctuation
        if !wordBuffer.isEmpty && wordWithPunc.count >= minWordLength {
            actionLog.append("  → RETURN wordBuffer+punc: '\(wordWithPunc)'")
            return (wordWithPunc, false)
        }

        // Приоритет 3: lastProcessedWord + pendingPunctuation
        let combined = lastProcessedWord + pendingPunctuation
        if !combined.isEmpty && combined.count >= minWordLength {
            actionLog.append("  → RETURN lastProcessedWord+punc: '\(combined)'")
            return (combined, false)
        }

        actionLog.append("  → RETURN nil")
        return nil
    }

    /// Симуляция Double Cmd с ТЕКУЩИМ (баговым) кодом
    func doubleCmdCurrent() -> (textToConvert: String, converted: String, debugLog: String) {
        actionLog.append("=== DOUBLE CMD (CURRENT) ===")

        guard let textInfo = getTextToConvert_CURRENT() else {
            return ("", "", actionLog.joined(separator: "\n"))
        }

        isReplacing = true

        // Конвертация
        let layout = LayoutMaps.detectLayout(in: textInfo.text) ?? .qwerty
        let converted = LayoutMaps.convert(textInfo.text, from: layout, to: layout.opposite, includeAllSymbols: true)

        actionLog.append("  CONVERT: '\(textInfo.text)' (\(layout.rawValue)) → '\(converted)'")

        // Обновление состояния после замены
        wordBuffer = ""
        lastProcessedWord = String(converted.filter { $0.isLetter })
        pendingPunctuation = ""

        isReplacing = false

        return (textInfo.text, converted, actionLog.joined(separator: "\n"))
    }

    /// Симуляция Double Cmd с ИСПРАВЛЕННЫМ кодом
    func doubleCmdFixed() -> (textToConvert: String, converted: String, debugLog: String) {
        actionLog.append("=== DOUBLE CMD (FIXED) ===")

        guard let textInfo = getTextToConvert_FIXED() else {
            return ("", "", actionLog.joined(separator: "\n"))
        }

        isReplacing = true

        // Конвертация
        let layout = LayoutMaps.detectLayout(in: textInfo.text) ?? .qwerty
        let converted = LayoutMaps.convert(textInfo.text, from: layout, to: layout.opposite, includeAllSymbols: true)

        actionLog.append("  CONVERT: '\(textInfo.text)' (\(layout.rawValue)) → '\(converted)'")

        // Обновление состояния
        wordBuffer = ""
        lastProcessedWord = String(converted.filter { $0.isLetter })
        pendingPunctuation = ""

        isReplacing = false

        return (textInfo.text, converted, actionLog.joined(separator: "\n"))
    }

    func reset() {
        wordBuffer = ""
        lastProcessedWord = ""
        pendingPunctuation = ""
        isReplacing = false
        actionLog = []
    }
}

// MARK: - Test Scenarios

func printSection(_ title: String) {
    print("\n" + String(repeating: "═", count: 70))
    print(title)
    print(String(repeating: "═", count: 70))
}

// MARK: - TEST 1: Single Word (должен работать)

func testSingleWord() {
    printSection("ТЕСТ 1: Одно слово (базовый сценарий)")

    let tests: [(input: String, expectedText: String, expectedConverted: String)] = [
        ("ghbdtn", "ghbdtn", "привет"),
        ("ntcn", "ntcn", "тест"),
        ("привет", "привет", "ghbdtn"),
        ("Hello", "Hello", "Руддщ"),
    ]

    for test in tests {
        let sim = FullFlowSimulator()
        sim.typeText(test.input)
        let result = sim.doubleCmdCurrent()

        let passed = result.textToConvert == test.expectedText && result.converted == test.expectedConverted
        flowResults.append(FlowTestResult(
            name: "SingleWord: '\(test.input)'",
            scenario: "Набор '\(test.input)' + Double Cmd",
            passed: passed,
            expected: "\(test.expectedText) → \(test.expectedConverted)",
            actual: "\(result.textToConvert) → \(result.converted)",
            debug: ""
        ))
        print(flowResults.last!.description)
    }
}

// MARK: - TEST 2: Single Word with Space (должен работать)

func testSingleWordWithSpace() {
    printSection("ТЕСТ 2: Одно слово + пробел")

    let tests: [(input: String, expectedText: String, expectedConverted: String)] = [
        ("ghbdtn ", "ghbdtn", "привет"),
        ("ntcn ", "ntcn", "тест"),
    ]

    for test in tests {
        let sim = FullFlowSimulator()
        sim.typeText(test.input)
        let result = sim.doubleCmdCurrent()

        let passed = result.textToConvert == test.expectedText && result.converted == test.expectedConverted
        flowResults.append(FlowTestResult(
            name: "SingleWord+Space: '\(test.input)'",
            scenario: "Набор '\(test.input)' + Double Cmd",
            passed: passed,
            expected: "\(test.expectedText) → \(test.expectedConverted)",
            actual: "\(result.textToConvert) → \(result.converted)",
            debug: passed ? "" : result.debugLog
        ))
        print(flowResults.last!.description)
    }
}

// MARK: - TEST 3: Two Words — CRITICAL BUG!

func testTwoWords() {
    printSection("ТЕСТ 3: Два слова — КРИТИЧЕСКИЙ БАГ!")

    // Это ГЛАВНЫЙ баг который нашёл пользователь!
    // "ghbdtn vjh" → ожидается "привет мир", получается "ghbdtn мир"

    let tests: [(input: String, expectedTextCurrent: String, expectedTextFixed: String, expectedConverted: String)] = [
        // input, что вернёт ТЕКУЩИЙ код, что вернёт ИСПРАВЛЕННЫЙ код, ожидаемый результат
        ("ghbdtn vjh", "vjh", "ghbdtn vjh", "привет мир"),
        ("ghbdtn vjh!", "vjh!", "ghbdtn vjh!", "привет мир!"),
        ("hello world", "world", "hello world", "руддщ цщкдв"),
        ("Rfr ltkf", "ltkf", "Rfr ltkf", "Как дела"),
    ]

    print("\n📍 ТЕКУЩИЙ КОД (с багом):")
    for test in tests {
        let sim = FullFlowSimulator()
        sim.typeText(test.input)
        let result = sim.doubleCmdCurrent()

        // ТЕКУЩИЙ код возвращает ТОЛЬКО последнее слово!
        let passedCurrent = result.textToConvert == test.expectedTextCurrent
        flowResults.append(FlowTestResult(
            name: "TwoWords CURRENT: '\(test.input)'",
            scenario: "ТЕКУЩИЙ код: набор '\(test.input)' + Double Cmd",
            passed: passedCurrent,
            expected: "textToConvert='\(test.expectedTextCurrent)'",
            actual: "textToConvert='\(result.textToConvert)'",
            debug: passedCurrent ? "БАГ ПОДТВЕРЖДЁН: конвертируется только последнее слово!" : result.debugLog
        ))
        print(flowResults.last!.description)
    }

    print("\n📍 ИСПРАВЛЕННЫЙ КОД:")
    for test in tests {
        let sim = FullFlowSimulator()
        sim.typeText(test.input)
        let result = sim.doubleCmdFixed()

        // ИСПРАВЛЕННЫЙ код должен объединить оба слова
        let passedFixed = result.textToConvert == test.expectedTextFixed
        flowResults.append(FlowTestResult(
            name: "TwoWords FIXED: '\(test.input)'",
            scenario: "ИСПРАВЛЕННЫЙ код: набор '\(test.input)' + Double Cmd",
            passed: passedFixed,
            expected: "textToConvert='\(test.expectedTextFixed)' → '\(test.expectedConverted)'",
            actual: "textToConvert='\(result.textToConvert)' → '\(result.converted)'",
            debug: passedFixed ? "" : result.debugLog
        ))
        print(flowResults.last!.description)
    }
}

// MARK: - TEST 4: User's Exact Bug Report

func testUserBugReport() {
    printSection("ТЕСТ 4: Точные баги пользователя")

    // Из сообщения пользователя:
    // "Привет Hello how are you?" → garbled output
    // "(jlyj слово без пробела меняет правильно)" — одно слово работает

    print("\n📍 БАГ 1: 'ghbdtn vjh' должно стать 'привет мир'")

    let sim1 = FullFlowSimulator()
    sim1.typeText("ghbdtn vjh")

    print("  Состояние ПЕРЕД Double Cmd:")
    print("    wordBuffer = '\(sim1.wordBuffer)'")
    print("    lastProcessedWord = '\(sim1.lastProcessedWord)'")
    print("    pendingPunctuation = '\(sim1.pendingPunctuation)'")

    let result1Current = sim1.doubleCmdCurrent()
    print("\n  ТЕКУЩИЙ результат:")
    print("    textToConvert = '\(result1Current.textToConvert)'")
    print("    converted = '\(result1Current.converted)'")
    print("    ❌ ОЖИДАЛОСЬ: 'привет мир', ПОЛУЧИЛИ: '\(result1Current.converted)'")

    // Тест с исправленным кодом
    let sim1Fixed = FullFlowSimulator()
    sim1Fixed.typeText("ghbdtn vjh")
    let result1Fixed = sim1Fixed.doubleCmdFixed()
    print("\n  ИСПРАВЛЕННЫЙ результат:")
    print("    textToConvert = '\(result1Fixed.textToConvert)'")
    print("    converted = '\(result1Fixed.converted)'")

    let bug1Fixed = result1Fixed.converted == "привет мир"
    flowResults.append(FlowTestResult(
        name: "USER BUG: 'ghbdtn vjh' → 'привет мир'",
        scenario: "Точный ввод пользователя",
        passed: bug1Fixed,
        expected: "привет мир",
        actual: result1Fixed.converted,
        debug: ""
    ))
    print(bug1Fixed ? "    ✅ ИСПРАВЛЕНО!" : "    ❌ Баг не исправлен")

    // БАГ 2: с пунктуацией
    print("\n📍 БАГ 2: 'Ghbdtn, rfr ltkf?' → 'Привет, как дела?'")

    let sim2 = FullFlowSimulator()
    sim2.typeText("Ghbdtn, rfr ltkf?")

    print("  Состояние ПЕРЕД Double Cmd:")
    print("    wordBuffer = '\(sim2.wordBuffer)'")
    print("    lastProcessedWord = '\(sim2.lastProcessedWord)'")
    print("    pendingPunctuation = '\(sim2.pendingPunctuation)'")

    // ВАЖНО: Этот сценарий сложнее — тут 3 слова!
    // После "Ghbdtn," → lastProcessedWord = "Ghbdtn"
    // После " rfr" → lastProcessedWord = "rfr" (Ghbdtn потерян!)
    // После " ltkf?" → lastProcessedWord = "ltkf", pending = "?"
    // wordBuffer = "" (пустой после ?)

    let result2Current = sim2.doubleCmdCurrent()
    print("\n  ТЕКУЩИЙ результат:")
    print("    textToConvert = '\(result2Current.textToConvert)'")
    print("    converted = '\(result2Current.converted)'")

    // С 3+ словами даже FIXED версия не справится без массива previousWords
    print("    ⚠️ ОГРАНИЧЕНИЕ: 3+ слова требуют массива previousWords!")
}

// MARK: - TEST 5: Mixed Layout (English + Russian)

func testMixedLayout() {
    printSection("ТЕСТ 5: Смешанные раскладки")

    // Пользователь набирает: "Hello ghbdtn"
    // "Hello" — английский, "ghbdtn" — английский (но должен быть русским)
    // Оба слова в QWERTY → объединяем и конвертируем

    let sim = FullFlowSimulator()
    sim.typeText("Hello ghbdtn")

    print("  wordBuffer = '\(sim.wordBuffer)'")  // ghbdtn
    print("  lastProcessedWord = '\(sim.lastProcessedWord)'")  // Hello

    // Оба в QWERTY layout → FIXED код должен объединить
    let resultFixed = sim.doubleCmdFixed()
    print("  FIXED: '\(resultFixed.textToConvert)' → '\(resultFixed.converted)'")

    // Ожидаем: "Hello ghbdtn" → "Руддщ привет"
    let passed = resultFixed.textToConvert == "Hello ghbdtn" && resultFixed.converted == "Руддщ привет"
    flowResults.append(FlowTestResult(
        name: "MixedLayout: 'Hello ghbdtn'",
        scenario: "Два английских слова",
        passed: passed,
        expected: "Руддщ привет",
        actual: resultFixed.converted,
        debug: ""
    ))
    print(flowResults.last!.description)

    // Тест: разные раскладки НЕ должны объединяться
    let sim2 = FullFlowSimulator()
    sim2.typeText("Hello привет")  // Hello=en, привет=ru

    print("\n  Разные раскладки:")
    print("  wordBuffer = '\(sim2.wordBuffer)'")  // привет (ru)
    print("  lastProcessedWord = '\(sim2.lastProcessedWord)'")  // Hello (en)

    let result2Fixed = sim2.doubleCmdFixed()
    print("  FIXED: '\(result2Fixed.textToConvert)' → '\(result2Fixed.converted)'")

    // Ожидаем: только "привет" конвертируется (разные раскладки не объединяются)
    let passed2 = result2Fixed.textToConvert == "привет" && result2Fixed.converted == "ghbdtn"
    flowResults.append(FlowTestResult(
        name: "MixedLayout: 'Hello привет' (разные раскладки)",
        scenario: "Английское + русское слово",
        passed: passed2,
        expected: "привет → ghbdtn (только последнее)",
        actual: "\(result2Fixed.textToConvert) → \(result2Fixed.converted)",
        debug: ""
    ))
    print(flowResults.last!.description)
}

// MARK: - TEST 6: Punctuation Handling

func testPunctuationHandling() {
    printSection("ТЕСТ 6: Обработка пунктуации")

    let tests: [(input: String, expectedText: String, note: String)] = [
        ("ghbdtn!", "ghbdtn!", "! в конце"),
        ("ghbdtn?", "ghbdtn?", "? в конце"),
        ("ghbdtn...", "ghbdtn...", "многоточие"),
        ("ghbdtn!?", "ghbdtn!?", "смешанная пунктуация"),
    ]

    for test in tests {
        let sim = FullFlowSimulator()
        sim.typeText(test.input)
        let result = sim.doubleCmdCurrent()

        let passed = result.textToConvert == test.expectedText
        flowResults.append(FlowTestResult(
            name: "Punctuation: '\(test.input)'",
            scenario: test.note,
            passed: passed,
            expected: test.expectedText,
            actual: result.textToConvert,
            debug: ""
        ))
        print(flowResults.last!.description)
    }
}

// MARK: - TEST 7: Edge Cases

func testEdgeCases() {
    printSection("ТЕСТ 7: Edge Cases")

    // Пустой буфер
    let sim1 = FullFlowSimulator()
    let result1 = sim1.doubleCmdCurrent()
    flowResults.append(FlowTestResult(
        name: "EdgeCase: пустой буфер",
        scenario: "Double Cmd без текста",
        passed: result1.textToConvert == "",
        expected: "'' (пустая строка)",
        actual: "'\(result1.textToConvert)'",
        debug: ""
    ))
    print(flowResults.last!.description)

    // Один символ (меньше minWordLength)
    let sim2 = FullFlowSimulator()
    sim2.typeText("a")
    let result2 = sim2.doubleCmdCurrent()
    // minWordLength = 2, поэтому "a" не конвертируется
    flowResults.append(FlowTestResult(
        name: "EdgeCase: один символ 'a'",
        scenario: "Меньше minWordLength",
        passed: result2.textToConvert == "",
        expected: "'' (слишком короткое)",
        actual: "'\(result2.textToConvert)'",
        debug: ""
    ))
    print(flowResults.last!.description)

    // Только пробелы
    let sim3 = FullFlowSimulator()
    sim3.typeText("   ")
    let result3 = sim3.doubleCmdCurrent()
    flowResults.append(FlowTestResult(
        name: "EdgeCase: только пробелы",
        scenario: "Три пробела",
        passed: result3.textToConvert == "",
        expected: "''",
        actual: "'\(result3.textToConvert)'",
        debug: ""
    ))
    print(flowResults.last!.description)
}

// MARK: - TEST 8: Rapid Typing After Double Cmd

func testRapidTypingAfterDoubleCmd() {
    printSection("ТЕСТ 8: Быстрый набор после Double Cmd")

    // Сценарий: пользователь набрал "ghbdtn", Double Cmd, потом сразу "друг"
    // Если буфер не очищается → буквы "друг" добавятся к старому буферу

    let sim = FullFlowSimulator()
    sim.typeText("ghbdtn")

    // Double Cmd
    _ = sim.doubleCmdCurrent()

    // После Double Cmd буфер должен быть пустой
    let bufferAfterCmd = sim.wordBuffer

    // Теперь набираем "друг"
    sim.typeText("друг")

    let passed = bufferAfterCmd == "" && sim.wordBuffer == "друг"
    flowResults.append(FlowTestResult(
        name: "RapidTyping: буфер после Double Cmd",
        scenario: "'ghbdtn' + Cmd + 'друг'",
        passed: passed,
        expected: "bufferAfter='' → newBuffer='друг'",
        actual: "bufferAfter='\(bufferAfterCmd)' → newBuffer='\(sim.wordBuffer)'",
        debug: ""
    ))
    print(flowResults.last!.description)
}

// MARK: - TEST 9: State Consistency

func testStateConsistency() {
    printSection("ТЕСТ 9: Консистентность состояния")

    let sim = FullFlowSimulator()

    // Сценарий 1: набор → Double Cmd → набор → Double Cmd (toggle)
    sim.typeText("ghbdtn ")
    let result1 = sim.doubleCmdCurrent()

    print("  После первого Double Cmd:")
    print("    converted: '\(result1.converted)'")
    print("    lastProcessedWord: '\(sim.lastProcessedWord)'")

    // Второй Double Cmd должен откатить (toggle)
    let result2 = sim.doubleCmdCurrent()

    print("  После второго Double Cmd (toggle):")
    print("    converted: '\(result2.converted)'")

    let passed = result1.converted == "привет" && result2.converted == "ghbdtn"
    flowResults.append(FlowTestResult(
        name: "StateConsistency: toggle",
        scenario: "Double Cmd туда-обратно",
        passed: passed,
        expected: "ghbdtn → привет → ghbdtn",
        actual: "\(result1.textToConvert) → \(result1.converted) → \(result2.converted)",
        debug: ""
    ))
    print(flowResults.last!.description)
}

// MARK: - TEST 10: Full Scenario From User

func testFullUserScenario() {
    printSection("ТЕСТ 10: Полный сценарий из репорта пользователя")

    // Точный репорт:
    // "Привет Hello how are you?" → various garbled results

    // Симулируем: пользователь набрал "Hello how are you" в РУССКОЙ раскладке
    // т.е. набрал: "Руддщ рща фку нщг"
    // и хочет конвертировать в "Hello how are you"

    // НО: это 4 слова! Текущая система может обработать только последние 2.

    print("  ⚠️ СЦЕНАРИЙ: 4 слова — текущая система поддерживает только 2!")

    // Упрощённый сценарий: 2 слова
    let sim = FullFlowSimulator()
    sim.typeText("Руддщ рща")  // "Hello how" в русской раскладке

    print("\n  Состояние:")
    print("    wordBuffer = '\(sim.wordBuffer)'")  // рща
    print("    lastProcessedWord = '\(sim.lastProcessedWord)'")  // Руддщ

    let resultCurrent = sim.doubleCmdCurrent()
    print("\n  ТЕКУЩИЙ код: '\(resultCurrent.textToConvert)' → '\(resultCurrent.converted)'")

    let simFixed = FullFlowSimulator()
    simFixed.typeText("Руддщ рща")
    let resultFixed = simFixed.doubleCmdFixed()
    print("  ИСПРАВЛЕННЫЙ код: '\(resultFixed.textToConvert)' → '\(resultFixed.converted)'")

    let passed = resultFixed.textToConvert == "Руддщ рща" && resultFixed.converted == "Hello how"
    flowResults.append(FlowTestResult(
        name: "FullScenario: 'Руддщ рща' → 'Hello how'",
        scenario: "2 слова в неправильной раскладке",
        passed: passed,
        expected: "Hello how",
        actual: resultFixed.converted,
        debug: ""
    ))
    print(flowResults.last!.description)
}

// MARK: - SUMMARY: What Needs Fixing

func printSummaryAndRecommendations() {
    printSection("ИТОГИ И РЕКОМЕНДАЦИИ")

    let passed = flowResults.filter { $0.passed }.count
    let failed = flowResults.count - passed

    print("""

    📊 РЕЗУЛЬТАТЫ:
       Всего тестов: \(flowResults.count)
       ✅ Успешно:   \(passed)
       ❌ Провалено: \(failed)
    """)

    print("""

    🔍 ВЫЯВЛЕННЫЕ ПРОБЛЕМЫ:

    1. getTextToConvert() возвращает ТОЛЬКО wordBuffer
       - При наборе "ghbdtn vjh" возвращается "vjh", а не "ghbdtn vjh"
       - lastProcessedWord игнорируется если wordBuffer не пустой

    2. Поддерживаются только 2 последовательных слова
       - "ghbdtn rfr ltkf" → только "rfr ltkf" будет обработано
       - Первое слово теряется при втором пробеле

    🛠️ РЕКОМЕНДУЕМЫЕ ИСПРАВЛЕНИЯ:

    1. МИНИМАЛЬНОЕ (2 слова):
       Изменить getTextToConvert() — объединять wordBuffer + lastProcessedWord
       если они в одной раскладке

    2. ПОЛНОЕ (N слов):
       Заменить lastProcessedWord на массив previousWords: [String]
       и объединять все слова в одной раскладке

    3. ИДЕАЛЬНОЕ:
       Использовать AX API для чтения текста ДО курсора
       и находить все слова в неправильной раскладке
    """)

    if failed > 0 {
        print("\n" + String(repeating: "─", count: 70))
        print("❌ ПРОВАЛИВШИЕСЯ ТЕСТЫ:")
        for result in flowResults where !result.passed {
            print(result.description)
        }
    }
}

// MARK: - Main

@main
struct DoubleCmdFlowTestsApp {
    static func main() {
        print("""
        ╔══════════════════════════════════════════════════════════════════════╗
        ║              Double Cmd FLOW Tests                                   ║
        ║              Эмуляция реального поведения                            ║
        ╚══════════════════════════════════════════════════════════════════════╝
        """)

        // Запуск тестов
        testSingleWord()
        testSingleWordWithSpace()
        testTwoWords()
        testUserBugReport()
        testMixedLayout()
        testPunctuationHandling()
        testEdgeCases()
        testRapidTypingAfterDoubleCmd()
        testStateConsistency()
        testFullUserScenario()

        // Итоги
        printSummaryAndRecommendations()

        let failed = flowResults.filter { !$0.passed }.count
        exit(Int32(failed > 0 ? 1 : 0))
    }
}
