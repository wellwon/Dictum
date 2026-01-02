//
//  HybridValidator.swift
//  Dictum
//
//  4-слойная валидация для определения нужно ли исправлять раскладку.
//  Слои (каскадная проверка с ранним выходом):
//  1. UserExceptions — пользовательские исключения
//  2. NSSpellChecker — системный словарь
//  3. NLLanguageRecognizer — распознавание языка Apple
//  4. N-grams — статистический анализ
//

import Foundation
import NaturalLanguage
import AppKit
import os

private let logger = Logger(subsystem: "com.dictum.app", category: "HybridValidator")

// MARK: - Validation Result

/// Результат валидации слова
enum ValidationResult: Equatable, CustomStringConvertible {
    /// Оставить как есть (не исправлять)
    case keep

    /// Переключить на другую раскладку
    case switchLayout(to: KeyboardLayout, reason: String)

    var description: String {
        switch self {
        case .keep:
            return "keep"
        case .switchLayout(let layout, let reason):
            return "switch(\(layout.rawValue), \(reason))"
        }
    }
}

// MARK: - Hybrid Validator

/// 4-слойный валидатор для определения правильности раскладки
class HybridValidator: @unchecked Sendable {

    /// Singleton
    static let shared = HybridValidator()

    // MARK: - Public API for CLI Mode

    /// Проверяет является ли слово CLI командой
    /// Используется для установки CLI режима в ContextTracker
    /// - Parameter word: Слово для проверки
    /// - Returns: true если слово — CLI команда (tar, git, npm, etc.)
    static func isCliCommand(_ word: String) -> Bool {
        return cliCommands.contains(word.lowercased())
    }

    // MARK: - Configuration

    /// Минимальная длина слова для проверки
    /// Снижено до 2 для обработки коротких слов (in, to, на, от)
    let minWordLength: Int = 2

    // MARK: - Single-Letter Whitelist

    /// Single-letter слова которые 100% нужно конвертировать
    /// Кириллица → латиница: Ш→I (местоимение), ф→a (артикль)
    /// Латиница → кириллица: d→в, b→и, c→с, f→а (предлоги/союзы)
    private let singleLetterConversions: [Character: (target: Character, layout: KeyboardLayout)] = [
        // Кириллица набранная в русской раскладке, но должна быть английской
        "Ш": ("I", .qwerty),    // I (местоимение)
        "ш": ("i", .qwerty),
        "Ф": ("A", .qwerty),    // A (артикль, редко с большой)
        "ф": ("a", .qwerty),    // a (артикль)
        // Латиница набранная в английской раскладке, но должна быть русской
        "d": ("в", .russian),   // в (предлог "в доме")
        "D": ("В", .russian),
        "b": ("и", .russian),   // и (союз "ты и я")
        "B": ("И", .russian),
        "c": ("с", .russian),   // с (предлог "с тобой")
        "C": ("С", .russian),
        "f": ("а", .russian),   // а (союз "а мы")
        "F": ("А", .russian),
        // Дополнительные предлоги/местоимения (добавлено для контекстного биаса)
        "r": ("к", .russian),   // к (предлог "к дому")
        "R": ("К", .russian),
        "e": ("у", .russian),   // у (предлог "у меня")
        "E": ("У", .russian),
        "j": ("о", .russian),   // о (предлог "о тебе")
        "J": ("О", .russian),
        "z": ("я", .russian),   // я (местоимение)
        "Z": ("Я", .russian),
    ]

    /// Адаптивный порог для NLLanguageRecognizer (зависит от длины слова)
    /// Короткие слова требуют меньшего порога, т.к. NL даёт меньше уверенности
    private func getLanguageConfidenceThreshold(wordLength: Int) -> Double {
        switch wordLength {
        case 0...4:   return 0.15   // Очень короткие (3-4 буквы)
        case 5...7:   return 0.25   // Средние (5-7 букв)
        default:      return 0.40   // Длинные (8+ букв)
        }
    }

    /// Порог для N-gram скоринга (во сколько раз должен быть лучше)
    /// Понижен с 5.0 до 2.5 для более агрессивной конвертации
    private let ngramScoreRatio: Double = 2.5

    // MARK: - Protective Layers (Phase 1 improvements)

    /// Layer -3: Sensitive Patterns — UUIDs, tokens, semver, ARNs
    /// Эти паттерны НИКОГДА не конвертировать — они технические идентификаторы
    private static let sensitivePatterns: [NSRegularExpression] = {
        let patterns = [
            // UUID: 550e8400-e29b-41d4-a716-446655440000
            "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$",
            // Tokens: sk_live_abc123, pk_test_xyz, api_key_abc
            "^(sk|pk|api|key|token|secret)_[a-z]+_[a-z0-9]+$",
            // Semver: 1.0.0, 2.0.0-beta.1, v3.2.1
            "^v?\\d+\\.\\d+\\.\\d+(-[a-z0-9.]+)?$",
            // AWS ARN: arn:aws:s3:::bucket
            "^arn:aws:[a-z0-9-]+:",
            // SHA hashes (short): abc123def456
            "^[a-f0-9]{7,40}$",
            // Base64-like tokens (32+ chars with mixed case and numbers)
            "^[A-Za-z0-9+/=]{32,}$",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    /// Layer -2.5: File Extensions — программные расширения файлов
    /// Не конвертировать .py, .js, .swift и т.д.
    private static let fileExtensions: Set<String> = [
        // Python/Ruby/Go
        ".py", ".rb", ".go", ".rs", ".pl", ".lua",
        // JavaScript/TypeScript
        ".js", ".ts", ".jsx", ".tsx", ".mjs", ".cjs", ".vue", ".svelte",
        // C/C++/Objective-C
        ".c", ".h", ".cpp", ".hpp", ".cc", ".hh", ".m", ".mm",
        // Java/Kotlin/Scala
        ".java", ".kt", ".kts", ".scala", ".groovy",
        // Swift/Dart
        ".swift", ".dart",
        // Web
        ".html", ".htm", ".css", ".scss", ".sass", ".less",
        // Data/Config
        ".json", ".yaml", ".yml", ".xml", ".toml", ".ini", ".env",
        // Documents
        ".md", ".txt", ".rst", ".csv", ".tsv",
        // Database
        ".sql", ".db", ".sqlite",
        // Shell/Scripts
        ".sh", ".bash", ".zsh", ".fish", ".bat", ".cmd", ".ps1",
        // Other
        ".log", ".lock", ".gitignore", ".dockerignore",
    ]

    /// Layer -2.4: CLI Commands — команды терминала
    /// docker, git, npm и т.д. НЕ конвертировать
    private static let cliCommands: Set<String> = [
        // Unix core
        "ls", "cd", "pwd", "mkdir", "rmdir", "rm", "cp", "mv", "cat", "grep", "find", "head", "tail",
        "ps", "kill", "killall", "top", "htop", "df", "du", "free", "uname", "whoami", "which", "where",
        "chmod", "chown", "chgrp", "ln", "touch", "stat", "file", "wc", "sort", "uniq", "diff", "patch",
        "tar", "gzip", "gunzip", "zip", "unzip", "bzip2", "xz",
        "curl", "wget", "ssh", "scp", "rsync", "ftp", "sftp",
        "ping", "traceroute", "netstat", "ifconfig", "ip", "dig", "nslookup", "host",
        "awk", "sed", "tr", "cut", "paste", "tee", "xargs", "env", "export", "source",
        "echo", "printf", "read", "test", "true", "false", "yes", "no",

        // Git
        "git", "clone", "commit", "push", "pull", "fetch", "merge", "rebase", "checkout", "branch",
        "status", "log", "diff", "add", "reset", "stash", "cherry-pick", "bisect", "blame", "reflog",

        // Package managers
        "npm", "npx", "yarn", "pnpm", "bun", "deno",
        "pip", "pip3", "pipenv", "poetry", "conda",
        "gem", "bundle", "bundler",
        "cargo", "rustup", "rustc",
        "go", "gofmt", "golint",
        "brew", "apt", "apt-get", "yum", "dnf", "pacman", "snap", "flatpak", "apk",
        "composer", "pecl", "pear",
        "nuget", "dotnet",
        "maven", "mvn", "gradle",
        "cocoapods", "pod", "carthage", "swift", "swiftc", "xcodebuild",

        // Containers & Cloud
        "docker", "docker-compose", "podman", "kubectl", "helm", "minikube", "kind",
        "terraform", "ansible", "vagrant", "packer",
        "aws", "gcloud", "az", "heroku", "vercel", "netlify", "fly", "railway",

        // Build tools
        "make", "cmake", "ninja", "meson", "bazel",
        "gcc", "g++", "clang", "clang++", "ld", "ar", "nm", "objdump", "strip",

        // Languages/Runtimes
        "python", "python3", "node", "ruby", "perl", "php", "java", "javac", "scala", "kotlin",
        "lua", "elixir", "erlang", "haskell", "ghc", "ocaml", "racket", "scheme", "lisp",

        // Editors/Tools
        "vim", "nvim", "nano", "emacs", "code", "subl", "atom",
        "tmux", "screen", "less", "more", "man", "info", "help",

        // Testing
        "jest", "mocha", "pytest", "rspec", "phpunit", "junit",

        // Other dev tools
        "jq", "yq", "ag", "rg", "fd", "fzf", "bat", "exa", "lsd",
    ]

    /// Layer -2.3: Short Brand Names — короткие бренды/аббревиатуры
    /// HP, LG, IBM в UPPERCASE — НЕ конвертировать
    private static let shortBrands: Set<String> = [
        // Tech companies
        "HP", "LG", "IBM", "AMD", "ARM", "SAP", "NCR", "EMC", "VMX",
        "HTC", "ZTE", "JBL", "AKG", "AOC",
        // Russian/Chinese companies
        "VK", "VTB", "JD",
        // Other brands
        "BMW", "VW", "GM", "GE", "DHL", "UPS", "FDX",
        "CNN", "BBC", "MTV", "HBO", "NBC", "CBS", "ABC", "FOX", "PBS",
        "NBA", "NFL", "MLB", "NHL", "UFC", "WWE", "FIFA", "UEFA",
        "ATM", "GPS", "USB", "VPN", "SSD", "HDD", "RAM", "CPU", "GPU", "TPU", "NPU",
        // Tech acronyms (часто встречаются в коде)
        "AI", "ML", "DL", "NLP", "CV", "AR", "VR", "XR", "MR",
        "API", "SDK", "CLI", "GUI", "TUI", "IDE", "CMS", "CRM", "ERP",
        "CI", "CD", "QA", "UAT", "MVP", "POC", "SLA", "SLO", "KPI",
        "DNS", "CDN", "SSL", "TLS", "SSH", "FTP", "TCP", "UDP", "IP",
        "URL", "URI", "JWT", "OAuth", "SSO", "MFA", "RBAC",
        "SQL", "NoSQL", "ORM", "ETL", "CSV", "XML", "JSON", "YAML", "TOML",
        "REST", "SOAP", "RPC", "gRPC", "GraphQL",
        "AWS", "GCP", "OCI", "IBM",
        "S3", "EC2", "ECS", "EKS", "RDS", "DynamoDB", "Lambda",
        "IoT", "5G", "4G", "LTE", "WiFi", "NFC", "RFID",
        "3D", "2D", "HD", "4K", "8K", "HDR",
        "PDF", "PNG", "JPG", "GIF", "SVG", "MP3", "MP4", "AVI", "MOV",
        // Unix/Programming
        "EOF", "STDIN", "STDOUT", "STDERR", "PID", "UID", "GID",
    ]

    // MARK: - Common Short Words (Layer 0.1)

    /// Частые короткие английские слова (1-3 буквы)
    /// Используется для точного определения раскладки коротких слов
    private let commonShortWordsEN: Set<String> = [
        // 1 буква
        "a", "i",
        // 2 буквы
        "in", "on", "at", "to", "is", "if", "it", "be", "we", "he",
        "me", "my", "no", "so", "up", "or", "by", "an", "as", "of",
        "do", "go", "ok", "id", "am", "us", "hi", "oh", "ah",
        // 3 буквы (самые частые)
        "the", "and", "for", "are", "but", "not", "you", "all", "can",
        "her", "was", "one", "our", "out", "day", "get", "has", "him",
        "his", "how", "its", "let", "may", "new", "now", "old", "see",
        "two", "way", "who", "boy", "did", "own", "say", "she", "too",
        "use", "dad", "mom", "car", "run", "try", "ask", "big", "end"
        // tot и vs УДАЛЕНЫ — еще/мы важнее редких EN слов
    ]

    /// Частые короткие русские слова (1-3 буквы)
    private let commonShortWordsRU: Set<String> = [
        // 1 буква
        "в", "и", "я", "к", "о", "с", "у", "а",
        // 2 буквы
        "на", "не", "от", "за", "из", "ко", "до", "по", "со", "то",
        "он", "мы", "ты", "вы", "их", "её", "ей", "да", "ну", "но",
        "бы", "же", "ли", "уж", "во", "об", "ах", "ох", "эх", "ух",
        // 3 буквы (самые частые)
        "что", "как", "все", "она", "так", "его", "это", "еще", "ещё",
        "для", "вот", "кто", "был", "мне", "под", "при", "раз", "где",
        "чем", "там", "над", "без", "три", "два", "сам", "вас", "нас",
        "тут", "вам", "нам", "они", "или", "уже", "чуть", "тоже"
    ]

    /// Адаптивный порог N-gram для коротких слов
    /// Короткие слова требуют мягче порогов (меньше данных для анализа)
    private func getNgramThreshold(wordLength: Int) -> Double {
        switch wordLength {
        case 2:      return 1.5   // Мягче для 2-буквенных
        case 3:      return 1.8   // Немного строже
        case 4:      return 2.0   // Стандарт
        case 5...7:  return 2.5   // Строже
        default:     return 3.0   // Очень строго для длинных
        }
    }

    // MARK: - Dependencies

    private let spellChecker = NSSpellChecker.shared

    // MARK: - Initialization

    private init() {
        logger.info("🔍 HybridValidator инициализирован")

        // ДИАГНОСТИКА: Проверяем конвертацию и SpellChecker при старте
        runDiagnostics()
    }

    /// Диагностика при старте — проверяем почему RU→EN не работает
    private func runDiagnostics() {
        NSLog("🧪 === ДИАГНОСТИКА HybridValidator ===")

        // Тест 1: Конвертация руддщ → hello
        let ruWord = "руддщ"
        let converted = LayoutMaps.convert(ruWord, from: .russian, to: .qwerty)
        NSLog("🧪 Конвертация: '%@' → '%@'", ruWord, converted)

        // Тест 2: SpellChecker для руддщ (должен быть false)
        let ruValid = isValidInDictionary(ruWord, language: "ru")
        NSLog("🧪 SpellChecker: '%@' в ru_RU = %@", ruWord, ruValid ? "✓ ВАЛИДНО" : "✗ невалидно")

        // Тест 3: SpellChecker для hello (должен быть true!)
        let enValid = isValidInDictionary(converted, language: "en")
        NSLog("🧪 SpellChecker: '%@' в en_US = %@", converted, enValid ? "✓ ВАЛИДНО" : "✗ невалидно")

        // Тест 4: Обратное направление - ghbdtn → привет
        let enWord = "ghbdtn"
        let convertedRu = LayoutMaps.convert(enWord, from: .qwerty, to: .russian)
        NSLog("🧪 Конвертация: '%@' → '%@'", enWord, convertedRu)

        let enWordValid = isValidInDictionary(enWord, language: "en")
        NSLog("🧪 SpellChecker: '%@' в en_US = %@", enWord, enWordValid ? "✓ ВАЛИДНО" : "✗ невалидно")

        let convertedRuValid = isValidInDictionary(convertedRu, language: "ru")
        NSLog("🧪 SpellChecker: '%@' в ru_RU = %@", convertedRu, convertedRuValid ? "✓ ВАЛИДНО" : "✗ невалидно")

        NSLog("🧪 === КОНЕЦ ДИАГНОСТИКИ ===")
    }

    // MARK: - Public API

    /// Валидирует слово и определяет нужно ли переключать раскладку
    /// - Parameters:
    ///   - word: Слово для проверки
    ///   - currentLayout: Текущая раскладка клавиатуры
    ///   - biasTowardLayout: Раскладка для биаса (если недавно переключили), или nil
    /// - Returns: Результат валидации
    func validate(_ word: String, currentLayout: KeyboardLayout, biasTowardLayout: KeyboardLayout? = nil) -> ValidationResult {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)

        // ═══════════════════════════════════════════════════════════════════
        // ЗАЩИТНЫЕ СЛОИ (Phase 1) — early-exit для технических паттернов
        // ═══════════════════════════════════════════════════════════════════

        // СЛОЙ -3: Sensitive Patterns — UUIDs, tokens, semver, hashes
        // Эти паттерны НИКОГДА не конвертировать — они технические идентификаторы
        let wordRange = NSRange(normalizedWord.startIndex..., in: normalizedWord)
        for pattern in Self.sensitivePatterns {
            if pattern.firstMatch(in: normalizedWord, options: [], range: wordRange) != nil {
                NSLog("🛡️ Layer -3 (Sensitive): '%@' — keep (sensitive pattern)", normalizedWord)
                logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer -3: sensitive_pattern)")
                return .keep
            }
        }

        // СЛОЙ -2.5: File Extensions — программные расширения
        // .py, .js, .swift и т.д. НЕ конвертировать
        if Self.fileExtensions.contains(normalizedWord.lowercased()) {
            NSLog("🛡️ Layer -2.5 (FileExt): '%@' — keep (file extension)", normalizedWord)
            logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer -2.5: file_extension)")
            return .keep
        }

        // СЛОЙ -2.4: CLI Commands — команды терминала
        // docker, git, npm и т.д. НЕ конвертировать
        // Проверяем первое "слово" (до пробела) для составных команд типа "docker ps"
        let firstToken = normalizedWord.split(separator: " ").first.map(String.init) ?? normalizedWord
        if Self.cliCommands.contains(firstToken.lowercased()) {
            NSLog("🛡️ Layer -2.4 (CLI): '%@' — keep (cli command)", normalizedWord)
            logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer -2.4: cli_command)")
            return .keep
        }

        // СЛОЙ -2.3: Short Brand Names — короткие аббревиатуры
        // HP, LG, IBM (2-4 буквы UPPERCASE) НЕ конвертировать
        // Проверяем только если слово целиком uppercase и короткое
        if normalizedWord.count <= 4 &&
           normalizedWord == normalizedWord.uppercased() &&
           normalizedWord.allSatisfy({ $0.isLetter || $0.isNumber }) &&
           Self.shortBrands.contains(normalizedWord) {
            NSLog("🛡️ Layer -2.3 (Brand): '%@' — keep (short brand)", normalizedWord)
            logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer -2.3: short_brand)")
            return .keep
        }

        // СЛОЙ -2.2: Mixed Buzzwords — буквы + символы (f#, c#, c++)
        // Для коротких слов с символами (#, +) проверяем:
        // 1. Если исходное слово — buzzword (f#, c++) → keep
        // 2. Если конвертированные ТОЛЬКО БУКВЫ + исходные символы = buzzword → switch
        // Пример: "а#" → извлекаем "а", конвертируем в "f", проверяем "f#" в buzzwords
        if normalizedWord.count <= 3 {
            let symbolChars: Set<Character> = ["#", "+"]
            let hasSymbol = normalizedWord.contains(where: { symbolChars.contains($0) })

            if hasSymbol {
                // Уже buzzword → keep
                if TechBuzzwordsManager.shared.contains(normalizedWord) {
                    NSLog("🛡️ Layer -2.2 (MixedBuzzword): '%@' — keep (already buzzword)", normalizedWord)
                    logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer -2.2: mixed_buzzword)")
                    return .keep
                }

                // Извлекаем буквы и символы отдельно
                var letters = ""
                var symbols = ""
                for char in normalizedWord {
                    if symbolChars.contains(char) {
                        symbols.append(char)
                    } else {
                        letters.append(char)
                    }
                }

                // Конвертируем ТОЛЬКО буквы
                if !letters.isEmpty {
                    let convertedLetters = LayoutMaps.convert(letters, from: currentLayout, to: currentLayout.opposite)
                    // Собираем обратно: конвертированные буквы + исходные символы
                    let potentialBuzzword = convertedLetters + symbols

                    if TechBuzzwordsManager.shared.contains(potentialBuzzword.lowercased()) {
                        NSLog("🛡️ Layer -2.2 (MixedBuzzword): '%@' → '%@' (buzzword with symbols)", normalizedWord, potentialBuzzword)
                        logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer -2.2: mixed_buzzword_convert)")
                        // Возвращаем специальный результат с причиной и целевым текстом
                        return .switchLayout(to: currentLayout.opposite, reason: "mixed_buzzword:\(potentialBuzzword)")
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════════
        // ОСНОВНЫЕ СЛОИ (существующая логика)
        // ═══════════════════════════════════════════════════════════════════

        // СЛОЙ -2: Single-letter whitelist — особые однобуквенные слова
        // Ш→I, ф→a, d→в, b→и, r→к, e→у, j→о, z→я
        // С учётом контекстного биаса И TechBuzzwords:
        // - С контекстом RU → конвертируем (даже если buzzword)
        // - С контекстом EN → keep
        // - Без контекста + buzzword → keep (R lang, V lang)
        // - Без контекста + не buzzword → конвертируем
        if normalizedWord.count == 1, let firstChar = normalizedWord.first {
            if let conversion = singleLetterConversions[firstChar] {
                // 1. Проверяем контекстный биас
                if let bias = biasTowardLayout {
                    // Контекст совпадает с целевой раскладкой → конвертируем
                    if bias == conversion.layout {
                        NSLog("🔍 Layer -2 (Single-Letter+Context): '%@' → '%@' (%@)", normalizedWord, String(conversion.target), conversion.layout.rawValue)
                        logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer -2: single_letter_with_context)")
                        return .switchLayout(to: conversion.layout, reason: "single_letter_with_context")
                    }
                    // Контекст ПРОТИВОПОЛОЖЕН целевой раскладке → НЕ конвертируем
                    if bias == currentLayout {
                        NSLog("🔍 Layer -2 (Single-Letter+Context): '%@' — keep (context bias = %@)", normalizedWord, bias.rawValue)
                        logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer -2: context says keep)")
                        return .keep
                    }
                }

                // 2. Без контекста: проверяем TechBuzzwords (R, V — языки программирования)
                if TechBuzzwordsManager.shared.contains(normalizedWord) {
                    NSLog("🔍 Layer -2 (Single-Letter+Buzzword): '%@' — keep (buzzword без контекста)", normalizedWord)
                    logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer -2: single_letter_buzzword)")
                    return .keep
                }

                // 3. Без контекста, не buzzword → конвертируем
                NSLog("🔍 Layer -2 (Single-Letter): '%@' → '%@' (%@)", normalizedWord, String(conversion.target), conversion.layout.rawValue)
                logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer -2: single_letter_whitelist)")
                return .switchLayout(to: conversion.layout, reason: "single_letter_whitelist")
            }
        }

        // Минимальная длина
        guard normalizedWord.count >= minWordLength else {
            logger.debug("🔍 validate: '\(word)' — слишком короткое (< \(self.minWordLength))")
            return .keep
        }

        logger.debug("🔍 validate: '\(normalizedWord)' layout=\(currentLayout.rawValue)")

        // СЛОЙ -1: Soft Sign в начале слова — 100% неправильная раскладка
        // Русские слова НИКОГДА не начинаются с ь или Ь
        // Если видим "ьуу|" на русской раскладке — это "meet" на английской
        if currentLayout == .russian {
            let firstChar = normalizedWord.first
            if firstChar == "ь" || firstChar == "Ь" {
                NSLog("🔍 Layer -1 (Soft Sign): '%@' начинается с ь — 100%% wrong layout", normalizedWord)
                logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer -1: starts with soft sign)")
                return .switchLayout(to: .qwerty, reason: "starts_with_soft_sign")
            }
        }

        // СЛОЙ 0: Tech Buzzwords (docker, npm, git, etc.) — НИКОГДА не конвертировать
        if TechBuzzwordsManager.shared.contains(normalizedWord) {
            logger.debug("   Layer 0 (TechBuzzwords): ✓ найдено — keep")
            return .keep
        }
        logger.debug("   Layer 0 (TechBuzzwords): ✗ не найдено")

        // СЛОЙ 0.1: Common Short Words — точная проверка коротких слов (2-3 буквы)
        // Если слово короткое, проверяем его и конвертированную версию в словарях частых слов
        if normalizedWord.count <= 3 {
            let swappedShort = LayoutMaps.convert(normalizedWord, from: currentLayout, to: currentLayout.opposite)

            // Проверяем: набранное в словаре текущего языка?
            let isCurrentCommon = currentLayout == .qwerty
                ? commonShortWordsEN.contains(normalizedWord.lowercased())
                : commonShortWordsRU.contains(normalizedWord.lowercased())

            // Проверяем: конвертированное в словаре целевого языка?
            let isTargetCommon = currentLayout == .qwerty
                ? commonShortWordsRU.contains(swappedShort.lowercased())
                : commonShortWordsEN.contains(swappedShort.lowercased())

            NSLog("🔍 Layer 0.1: '%@' current=%@, '%@' target=%@",
                  normalizedWord, isCurrentCommon ? "✓" : "✗",
                  swappedShort, isTargetCommon ? "✓" : "✗")

            // Если набранное НЕ частое, но конвертированное — частое → конвертируем
            // Пример: "tot" (не частое EN) → "еще" (частое RU) = конвертируем
            if !isCurrentCommon && isTargetCommon {
                logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer 0.1: common_short_word)")
                return .switchLayout(to: currentLayout.opposite, reason: "common_short_word")
            }

            // Если набранное частое — оставляем
            if isCurrentCommon {
                logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer 0.1: current is common)")
                return .keep
            }
        }

        // СЛОЙ 0.5: ForcedConversions (белый список) — ВСЕГДА конвертировать
        // Приоритет ВЫШЕ словаря! Если пользователь подтвердил руддщ→hello, всегда менять.
        if let forcedResult = ForcedConversionsManager.shared.getConversion(for: normalizedWord) {
            logger.info("   Layer 0.5 (ForcedConversions): ✓ найдено '\(normalizedWord)' → '\(forcedResult)'")
            return .switchLayout(to: currentLayout.opposite, reason: "forced_conversion")
        }
        logger.debug("   Layer 0.5 (ForcedConversions): ✗ не найдено")

        // СЛОЙ 1: UserExceptions (чёрный список) — НЕ конвертировать
        if UserExceptionsManager.shared.contains(normalizedWord) {
            logger.debug("   Layer 1 (UserExceptions): ✓ найдено — keep")
            return .keep
        }
        logger.debug("   Layer 1 (UserExceptions): ✗ не найдено")

        // Конвертируем в противоположную раскладку
        let swapped = LayoutMaps.convert(normalizedWord, from: currentLayout, to: currentLayout.opposite, includeAllSymbols: true)
        NSLog("🔍 HybridValidator: '%@' → '%@'", normalizedWord, swapped)
        logger.debug("   Swapped: '\(normalizedWord)' → '\(swapped)'")

        // СЛОЙ 1.5: TechBuzzwords в СКОНВЕРТИРОВАННОМ тексте (DHL, NASA, IBM, API)
        // Когда пользователь набирает "API" на русской раскладке, буфер получает "ФЗШ",
        // но после конвертации получается "API" — это buzzword, нужно КОНВЕРТИРОВАТЬ!
        if TechBuzzwordsManager.shared.contains(swapped) {
            NSLog("🔍 Layer 1.5 (TechBuzzwords swapped): ✓ '%@' найдено — SWITCH", swapped)
            logger.info("   Layer 1.5 (TechBuzzwords swapped): ✓ '\(swapped)' найдено — switch")
            return .switchLayout(to: currentLayout.opposite, reason: "swapped_is_buzzword")
        }
        logger.debug("   Layer 1.5 (TechBuzzwords swapped): ✗ не найдено")

        // СЛОЙ 2: N-gram как ПЕРВИЧНЫЙ метод (как в Punto/Caramba/LangChecker)
        // SpellChecker ненадёжен для русского — считает "руддщ" валидным
        let originalScore = NgramScorer.shared.score(normalizedWord, language: currentLayout.languageCode)
        let swappedScore = NgramScorer.shared.score(swapped, language: currentLayout.opposite.languageCode)
        let scoreRatio = exp(swappedScore - originalScore)

        NSLog("🔍 N-gram: '%@'(%@)=%.2f, '%@'(%@)=%.2f, ratio=%.2f",
              normalizedWord, currentLayout.languageCode, originalScore,
              swapped, currentLayout.opposite.languageCode, swappedScore,
              scoreRatio)
        logger.debug("   Layer 2 (N-gram PRIMARY): current=\(String(format: "%.2f", originalScore)), target=\(String(format: "%.2f", swappedScore)), ratio=\(String(format: "%.2f", scoreRatio))")

        // Адаптивный порог: короткие слова требуют мягче порогов
        let ngramThreshold = getNgramThreshold(wordLength: normalizedWord.count)
        NSLog("🔍 N-gram threshold for len=%d: %.1f", normalizedWord.count, ngramThreshold)

        // Если ratio > threshold — уверенно конвертируем (target НАМНОГО лучше)
        if scoreRatio > ngramThreshold {
            logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer 2: N-gram ratio > \(String(format: "%.1f", ngramThreshold)))")
            return .switchLayout(to: currentLayout.opposite, reason: "ngram_primary")
        }

        // СЛОЙ 2.1: Contextual Bias Override (для коротких слов в контексте)
        // Если есть контекстный биас И слово короткое (≤5 букв) И ratio не экстремальный (> 0.1)
        // → доверяем контексту. Пример: "tot" в контексте "Сейчас Влада tot" → "ещё"
        if let bias = biasTowardLayout, bias == currentLayout.opposite {
            // Для коротких слов с контекстом используем мягкий порог
            let isShortWord = normalizedWord.count <= 5
            let isNotExtremeRatio = scoreRatio > 0.1  // ratio 0.25 пройдёт, но 0.01 — нет

            if isShortWord && isNotExtremeRatio {
                NSLog("🔍 Context Override: '%@' (ratio=%.2f, len=%d) → switch to %@ (контекстный биас)",
                      normalizedWord, scoreRatio, normalizedWord.count, bias.rawValue)
                logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer 2.1: context_bias, ratio=\(String(format: "%.2f", scoreRatio)))")
                return .switchLayout(to: bias, reason: "context_bias")
            }
        }

        // Если ratio < 0.5 — уверенно НЕ конвертируем (current НАМНОГО лучше)
        // НО только если нет контекстного биаса (проверен выше)
        if scoreRatio < 0.5 {
            logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer 2: N-gram ratio < 0.5)")
            return .keep
        }

        // Если ratio между 0.5 и 2.0 — неуверены, используем SpellChecker как tiebreaker
        let validInCurrent = isValidInDictionary(normalizedWord, language: currentLayout.languageCode)
        let validInTarget = isValidInDictionary(swapped, language: currentLayout.opposite.languageCode)

        NSLog("🔍 SpellChecker tiebreaker: '%@'(%@)=%@, '%@'(%@)=%@",
              normalizedWord, currentLayout.languageCode, validInCurrent ? "✓" : "✗",
              swapped, currentLayout.opposite.languageCode, validInTarget ? "✓" : "✗")
        logger.debug("   Layer 2.5 (SpellChecker tiebreaker): current=\(validInCurrent), target=\(validInTarget)")

        if !validInCurrent && validInTarget {
            logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer 2.5: only target valid)")
            return .switchLayout(to: currentLayout.opposite, reason: "spellchecker_tiebreaker")
        }

        if validInCurrent && !validInTarget {
            logger.debug("🔍 validate: '\(normalizedWord)' → keep (Layer 2.5: only current valid)")
            return .keep
        }

        // Оба валидны или оба невалидны — продолжаем к Layer 3

        // СЛОЙ 3: NLLanguageRecognizer (~0.002 сек)
        let originalConfidence = languageConfidence(normalizedWord, expected: currentLayout)
        let swappedConfidence = languageConfidence(swapped, expected: currentLayout.opposite)
        let confidenceDiff = swappedConfidence - originalConfidence
        let adaptiveThreshold = getLanguageConfidenceThreshold(wordLength: normalizedWord.count)
        logger.debug("   Layer 3 (NLRecognizer): current=\(String(format: "%.3f", originalConfidence)), target=\(String(format: "%.3f", swappedConfidence)), diff=\(String(format: "%.3f", confidenceDiff)), threshold=\(String(format: "%.2f", adaptiveThreshold))")

        if confidenceDiff > adaptiveThreshold {
            logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer 3: confidence diff > \(adaptiveThreshold))")
            return .switchLayout(to: currentLayout.opposite, reason: "language_recognizer")
        }

        // N-gram уже проверен в СЛОЕ 2 как PRIMARY метод

        // СЛОЙ 4: Layout Switch Bias (для коротких слов типа "tot" → "еще")
        // Если недавно переключили раскладку и есть биас к целевому языку — конвертируем
        if let bias = biasTowardLayout, bias == currentLayout.opposite {
            NSLog("🔍 Layout Bias: '%@' → switch to %@ (недавнее переключение раскладки)", normalizedWord, bias.rawValue)
            logger.info("🔍 validate: '\(normalizedWord)' → switch (Layer 4: layout_bias → \(bias.rawValue))")
            return .switchLayout(to: bias, reason: "layout_bias")
        }

        // Не уверены — не меняем
        logger.debug("🔍 validate: '\(normalizedWord)' → keep (все слои: не уверены)")
        return .keep
    }

    /// Быстрая проверка — нужно ли вообще анализировать слово
    /// - Parameter word: Слово для проверки
    /// - Returns: true если слово стоит анализировать
    func shouldAnalyze(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)

        // Минимальная длина
        guard trimmed.count >= minWordLength else { return false }

        // Содержит хотя бы одну букву
        guard trimmed.contains(where: { $0.isLetter }) else { return false }

        // Не в исключениях
        guard !UserExceptionsManager.shared.contains(trimmed) else { return false }

        return true
    }

    // MARK: - Private Methods

    /// Проверяет слово через NSSpellChecker
    /// - Parameters:
    ///   - word: Слово для проверки
    ///   - language: Код языка ("ru" или "en")
    /// - Returns: true если слово найдено в словаре
    private func isValidInDictionary(_ word: String, language: String) -> Bool {
        // Маппинг на коды NSSpellChecker
        let spellCheckerLanguage: String
        switch language {
        case "ru":
            spellCheckerLanguage = "ru_RU"
        case "en":
            spellCheckerLanguage = "en_US"
        default:
            spellCheckerLanguage = language
        }

        // Временно устанавливаем язык
        let previousLanguage = spellChecker.language()
        spellChecker.setLanguage(spellCheckerLanguage)

        // Проверяем слово
        let range = spellChecker.checkSpelling(of: word, startingAt: 0)
        let isValid = range.location == NSNotFound

        // ДИАГНОСТИКА
        NSLog("🔤 SpellChecker: '%@' [%@] = %@", word, spellCheckerLanguage, isValid ? "✓" : "✗")

        // Восстанавливаем язык
        spellChecker.setLanguage(previousLanguage)

        return isValid
    }

    /// Определяет уверенность в языке через NLLanguageRecognizer
    /// - Parameters:
    ///   - text: Текст для анализа
    ///   - expected: Ожидаемая раскладка/язык
    /// - Returns: Уверенность от 0 до 1
    private func languageConfidence(_ text: String, expected: KeyboardLayout) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        // Получаем гипотезы с вероятностями
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)

        // Ищем ожидаемый язык
        let expectedNLLanguage: NLLanguage
        switch expected {
        case .russian:
            expectedNLLanguage = .russian
        case .qwerty:
            expectedNLLanguage = .english
        }

        return hypotheses[expectedNLLanguage] ?? 0.0
    }
}

// MARK: - Debug Extension

extension HybridValidator {
    /// Детальный анализ слова для отладки
    func debugAnalyze(_ word: String, currentLayout: KeyboardLayout) -> String {
        let swapped = LayoutMaps.convert(word, from: currentLayout, to: currentLayout.opposite)

        var report = "=== Debug: '\(word)' (layout: \(currentLayout.rawValue)) ===\n"
        report += "Swapped: '\(swapped)'\n"

        // Layer 1
        let inExceptions = UserExceptionsManager.shared.contains(word)
        report += "Layer 1 (UserExceptions): \(inExceptions ? "✓ в исключениях" : "✗ не в исключениях")\n"

        // Layer 2
        let validCurrent = isValidInDictionary(word, language: currentLayout.languageCode)
        let validTarget = isValidInDictionary(swapped, language: currentLayout.opposite.languageCode)
        report += "Layer 2 (SpellChecker): current=\(validCurrent), target=\(validTarget)\n"

        // Layer 3
        let confCurrent = languageConfidence(word, expected: currentLayout)
        let confTarget = languageConfidence(swapped, expected: currentLayout.opposite)
        report += "Layer 3 (NLRecognizer): current=\(String(format: "%.3f", confCurrent)), target=\(String(format: "%.3f", confTarget))\n"

        // Layer 4
        let scoreCurrent = NgramScorer.shared.score(word, language: currentLayout.languageCode)
        let scoreTarget = NgramScorer.shared.score(swapped, language: currentLayout.opposite.languageCode)
        let ratio = exp(scoreTarget - scoreCurrent)
        report += "Layer 4 (N-grams): current=\(String(format: "%.2f", scoreCurrent)), target=\(String(format: "%.2f", scoreTarget)), ratio=\(String(format: "%.2f", ratio))\n"

        // Result
        let result = validate(word, currentLayout: currentLayout)
        report += "Result: \(result)\n"

        return report
    }
}
