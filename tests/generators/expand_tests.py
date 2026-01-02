#!/usr/bin/env python3
"""
Expands the test corpus with additional variations and categories.
Adds sentence variations, multi-word tests, and edge cases.
"""

import json
import random
from pathlib import Path
from typing import List, Dict
from dataclasses import dataclass, asdict

# MARK: - Keyboard Mapping

EN_TO_RU = {
    'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н', 'u': 'г', 'i': 'ш', 'o': 'щ', 'p': 'з',
    '[': 'х', ']': 'ъ', 'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р', 'j': 'о', 'k': 'л',
    'l': 'д', ';': 'ж', "'": 'э', 'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
    ',': 'б', '.': 'ю', '/': '.', '`': 'ё',
    'Q': 'Й', 'W': 'Ц', 'E': 'У', 'R': 'К', 'T': 'Е', 'Y': 'Н', 'U': 'Г', 'I': 'Ш', 'O': 'Щ', 'P': 'З',
    '{': 'Х', '}': 'Ъ', 'A': 'Ф', 'S': 'Ы', 'D': 'В', 'F': 'А', 'G': 'П', 'H': 'Р', 'J': 'О', 'K': 'Л',
    'L': 'Д', ':': 'Ж', '"': 'Э', 'Z': 'Я', 'X': 'Ч', 'C': 'С', 'V': 'М', 'B': 'И', 'N': 'Т', 'M': 'Ь',
    '<': 'Б', '>': 'Ю', '?': ',', '~': 'Ё',
}

RU_TO_EN = {
    'й': 'q', 'ц': 'w', 'у': 'e', 'к': 'r', 'е': 't', 'н': 'y', 'г': 'u', 'ш': 'i', 'щ': 'o', 'з': 'p',
    'х': '[', 'ъ': ']', 'ф': 'a', 'ы': 's', 'в': 'd', 'а': 'f', 'п': 'g', 'р': 'h', 'о': 'j', 'л': 'k',
    'д': 'l', 'ж': ';', 'э': "'", 'я': 'z', 'ч': 'x', 'с': 'c', 'м': 'v', 'и': 'b', 'т': 'n', 'ь': 'm',
    'б': ',', 'ю': '.', 'ё': '`',
    'Й': 'Q', 'Ц': 'W', 'У': 'E', 'К': 'R', 'Е': 'T', 'Н': 'Y', 'Г': 'U', 'Ш': 'I', 'Щ': 'O', 'З': 'P',
    'Х': '{', 'Ъ': '}', 'Ф': 'A', 'Ы': 'S', 'В': 'D', 'А': 'F', 'П': 'G', 'Р': 'H', 'О': 'J', 'Л': 'K',
    'Д': 'L', 'Ж': ':', 'Э': '"', 'Я': 'Z', 'Ч': 'X', 'С': 'C', 'М': 'V', 'И': 'B', 'Т': 'N', 'Ь': 'M',
    'Б': '<', 'Ю': '>', 'Ё': '~',
}

def corrupt_ru(text: str) -> str:
    return ''.join(RU_TO_EN.get(c, c) for c in text)

def corrupt_en(text: str) -> str:
    return ''.join(EN_TO_RU.get(c, c) for c in text)


# MARK: - Russian Sentences (diverse)

RU_SENTENCES = [
    # Greetings & Basic
    "Привет как дела",
    "Здравствуйте",
    "Добрый день",
    "Добрый вечер",
    "Доброе утро",
    "До свидания",
    "Пока",
    "Спасибо большое",
    "Спасибо за помощь",
    "Пожалуйста",
    "Извините",
    "Простите пожалуйста",

    # Questions
    "Как тебя зовут",
    "Сколько это стоит",
    "Где находится офис",
    "Когда будет готово",
    "Почему так долго",
    "Кто это сделал",
    "Что случилось",
    "Куда идти",
    "Откуда вы",
    "Зачем это нужно",

    # Work & IT
    "Проверь код пожалуйста",
    "Отправь мне файл",
    "Посмотри логи",
    "Запусти тесты",
    "Исправь ошибку",
    "Добавь комментарий",
    "Удали этот файл",
    "Создай новый проект",
    "Обнови зависимости",
    "Перезапусти сервер",
    "Проверь базу данных",
    "Сделай бэкап",
    "Залей на сервер",
    "Склонируй репозиторий",
    "Сделай пулл реквест",
    "Смержи ветку",
    "Откати изменения",
    "Протестируй функцию",
    "Оптимизируй запрос",
    "Добавь валидацию",

    # Common phrases
    "Хорошо понял",
    "Не понимаю",
    "Повтори пожалуйста",
    "Минутку",
    "Сейчас сделаю",
    "Готово",
    "Не работает",
    "Все в порядке",
    "Есть проблема",
    "Нужна помощь",
    "Срочно",
    "Не срочно",
    "На связи",
    "Буду через час",
    "Скоро вернусь",
    "Уже еду",
    "Опаздываю",
    "Жду ответа",
    "Перезвоню позже",
    "Напишу завтра",

    # Instructions
    "Открой файл",
    "Закрой программу",
    "Перезагрузи компьютер",
    "Подключи к сети",
    "Выключи звук",
    "Включи камеру",
    "Сохрани документ",
    "Отправь письмо",
    "Прочитай сообщение",
    "Напиши ответ",

    # Common words
    "Работа",
    "Дом",
    "Компьютер",
    "Телефон",
    "Интернет",
    "Программа",
    "Файл",
    "Папка",
    "Сообщение",
    "Письмо",
    "Задача",
    "Проект",
    "Встреча",
    "Звонок",
    "Документ",
]

# MARK: - English Sentences (diverse)

EN_SENTENCES = [
    # Greetings
    "Hello how are you",
    "Good morning",
    "Good afternoon",
    "Good evening",
    "Good night",
    "See you later",
    "Take care",
    "Thank you very much",
    "Thanks for your help",
    "You are welcome",
    "Sorry about that",
    "Excuse me please",

    # Questions
    "What is your name",
    "How much does it cost",
    "Where is the office",
    "When will it be ready",
    "Why does it take so long",
    "Who did this",
    "What happened",
    "Where to go",
    "Where are you from",
    "Why do we need this",

    # Work & IT
    "Check the code please",
    "Send me the file",
    "Look at the logs",
    "Run the tests",
    "Fix the bug",
    "Add a comment",
    "Delete this file",
    "Create new project",
    "Update dependencies",
    "Restart the server",
    "Check the database",
    "Make a backup",
    "Deploy to server",
    "Clone the repository",
    "Create pull request",
    "Merge the branch",
    "Revert changes",
    "Test the function",
    "Optimize the query",
    "Add validation",

    # Common phrases
    "Okay got it",
    "I do not understand",
    "Can you repeat please",
    "Just a moment",
    "I will do it now",
    "Done",
    "Not working",
    "Everything is fine",
    "There is a problem",
    "Need help",
    "Urgent",
    "Not urgent",
    "Available",
    "Will be there in an hour",
    "Will be back soon",
    "On my way",
    "Running late",
    "Waiting for response",
    "Will call you later",
    "Will write tomorrow",

    # Instructions
    "Open the file",
    "Close the program",
    "Restart the computer",
    "Connect to network",
    "Mute the sound",
    "Turn on the camera",
    "Save the document",
    "Send the email",
    "Read the message",
    "Write a response",

    # Common words
    "Work",
    "Home",
    "Computer",
    "Phone",
    "Internet",
    "Program",
    "File",
    "Folder",
    "Message",
    "Email",
    "Task",
    "Project",
    "Meeting",
    "Call",
    "Document",
]

# MARK: - Code Switching Examples (IT Communication)

CODE_SWITCH_EXAMPLES = [
    # Format: (ru_context, en_term, full_expected)
    ("Запусти", "build", "Запусти build"),
    ("Сделай", "pull", "Сделай pull"),
    ("Проверь", "log", "Проверь log"),
    ("Открой", "file", "Открой file"),
    ("Закрой", "browser", "Закрой browser"),
    ("Запушь", "commit", "Запушь commit"),
    ("Смержи", "branch", "Смержи branch"),
    ("Сделай", "review", "Сделай review"),
    ("Открой", "tests", "Открой tests"),
    ("Запусти", "server", "Запусти server"),
    ("Проверь", "logs", "Проверь logs"),
    ("Включи", "debug", "Включи debug"),
    ("Выключи", "cache", "Выключи cache"),
    ("Обнови", "packages", "Обнови packages"),
    ("Удали", "cache", "Удали cache"),
    ("Залей", "changes", "Залей changes"),
    ("Откати", "merge", "Откати merge"),
    ("Исправь", "bug", "Исправь bug"),
    ("Добавь", "feature", "Добавь feature"),
    ("Создай", "issue", "Создай issue"),
    ("Закрой", "ticket", "Закрой ticket"),
    ("Посмотри", "diff", "Посмотри diff"),
    ("Проверь", "status", "Проверь status"),
    ("Запусти", "deploy", "Запусти deploy"),
    ("Сделай", "backup", "Сделай backup"),
    ("Почисти", "build", "Почисти build"),
    ("Перезапусти", "service", "Перезапусти service"),
    ("Обнови", "config", "Обнови config"),
    ("Проверь", "version", "Проверь version"),
    ("Добавь", "endpoint", "Добавь endpoint"),
]

# MARK: - Additional CLI Commands

CLI_COMMANDS = [
    # Git commands
    "git init",
    "git add .",
    "git add -A",
    "git commit -m",
    "git push origin main",
    "git push origin master",
    "git pull origin main",
    "git pull --rebase",
    "git fetch --all",
    "git checkout -b feature",
    "git merge develop",
    "git rebase main",
    "git stash",
    "git stash pop",
    "git log --oneline",
    "git diff HEAD",
    "git reset --hard",
    "git cherry-pick",
    "git tag v1.0.0",
    "git remote -v",

    # NPM/Yarn commands
    "npm init -y",
    "npm install --save",
    "npm install --save-dev",
    "npm run start",
    "npm run test",
    "npm run lint",
    "npm run format",
    "npm ci",
    "npm outdated",
    "npm update",
    "yarn init",
    "yarn add",
    "yarn remove",
    "pnpm install",
    "pnpm add -D",

    # Docker commands
    "docker build -t app .",
    "docker run -d -p 8080:80",
    "docker compose up -d",
    "docker compose down",
    "docker ps -a",
    "docker logs -f",
    "docker exec -it",
    "docker images",
    "docker pull nginx",
    "docker push",

    # Python commands
    "python3 -m venv venv",
    "pip install -r requirements.txt",
    "pip freeze > requirements.txt",
    "pytest -v",
    "python manage.py runserver",
    "python -m pip install",
    "flask run",
    "uvicorn main:app --reload",

    # System commands
    "ls -la",
    "ls -lah",
    "cd ..",
    "mkdir -p",
    "rm -rf",
    "cp -r",
    "mv",
    "chmod +x",
    "chown -R",
    "cat",
    "grep -r",
    "find . -name",
    "head -n 10",
    "tail -f",
    "wc -l",
    "du -sh",
    "df -h",
    "top",
    "htop",
    "kill -9",
    "ps aux",
    "netstat -tlnp",
    "curl -X GET",
    "wget",
    "ssh user@host",
    "scp file user@host:",
    "tar -xvzf",
    "unzip",

    # macOS specific
    "brew install",
    "brew update",
    "brew upgrade",
    "brew cask install",
    "open .",
    "pbcopy",
    "pbpaste",
    "defaults write",
    "xcode-select --install",
    "xcrun",
    "codesign",
    "notarize",

    # Kubernetes
    "kubectl get pods",
    "kubectl get svc",
    "kubectl apply -f",
    "kubectl delete",
    "kubectl logs",
    "kubectl exec -it",
    "kubectl describe",
    "kubectl rollout",
    "helm install",
    "helm upgrade",
]

# MARK: - Programming Terms (should NOT convert)

PROGRAMMING_TERMS = [
    # Keywords
    "function", "class", "const", "let", "var", "return", "if", "else", "for", "while",
    "switch", "case", "break", "continue", "try", "catch", "finally", "throw", "async",
    "await", "import", "export", "default", "from", "as", "extends", "implements",
    "interface", "type", "enum", "namespace", "module", "package", "public", "private",
    "protected", "static", "final", "abstract", "virtual", "override", "readonly",
    "null", "undefined", "true", "false", "void", "any", "never", "unknown",

    # Common identifiers
    "main", "init", "setup", "config", "app", "server", "client", "handler", "controller",
    "service", "model", "view", "component", "module", "util", "helper", "factory",
    "builder", "manager", "provider", "repository", "gateway", "adapter", "wrapper",
    "listener", "observer", "subscriber", "publisher", "emitter", "dispatcher",
    "validator", "parser", "formatter", "converter", "transformer", "mapper",
    "reducer", "selector", "middleware", "interceptor", "guard", "filter", "pipe",

    # Data structures
    "array", "list", "map", "set", "dict", "hash", "tree", "graph", "stack", "queue",
    "heap", "vector", "tuple", "pair", "node", "edge", "vertex", "linked", "binary",

    # Common functions
    "get", "set", "put", "post", "delete", "patch", "head", "options",
    "find", "filter", "map", "reduce", "forEach", "some", "every", "sort", "reverse",
    "push", "pop", "shift", "unshift", "slice", "splice", "concat", "join", "split",
    "trim", "replace", "match", "test", "exec", "parse", "stringify", "format",
    "encode", "decode", "encrypt", "decrypt", "hash", "sign", "verify",
    "open", "close", "read", "write", "append", "seek", "flush", "sync",
    "connect", "disconnect", "send", "receive", "emit", "on", "off", "once",
    "start", "stop", "pause", "resume", "reset", "clear", "destroy", "dispose",
    "create", "update", "delete", "remove", "insert", "select", "query", "execute",
    "validate", "sanitize", "normalize", "transform", "convert", "serialize",
    "log", "debug", "info", "warn", "error", "trace", "assert", "throw",

    # File extensions
    ".js", ".ts", ".jsx", ".tsx", ".vue", ".svelte",
    ".py", ".rb", ".php", ".java", ".kt", ".scala", ".go", ".rs", ".swift",
    ".c", ".cpp", ".h", ".hpp", ".cs", ".fs",
    ".json", ".yaml", ".yml", ".xml", ".html", ".css", ".scss", ".sass", ".less",
    ".md", ".txt", ".csv", ".sql", ".graphql", ".proto",
    ".sh", ".bash", ".zsh", ".fish", ".ps1", ".bat", ".cmd",
    ".dockerfile", ".gitignore", ".env", ".editorconfig",
]

# MARK: - Generator

def generate_expanded_tests() -> List[Dict]:
    tests = []
    test_id = 10000  # Start from 10000 to avoid conflicts

    # 1. Russian sentences (corrupted)
    for sentence in RU_SENTENCES:
        corrupted = corrupt_ru(sentence)
        if corrupted != sentence:
            tests.append({
                "id": f"ru_sent_{test_id}",
                "category": "ru_sentences",
                "input": corrupted,
                "expected": sentence,
                "should_convert": True
            })
            test_id += 1

    # 2. English sentences (corrupted with RU layout)
    for sentence in EN_SENTENCES:
        corrupted = corrupt_en(sentence)
        if corrupted != sentence:
            tests.append({
                "id": f"en_sent_{test_id}",
                "category": "en_sentences",
                "input": corrupted,
                "expected": sentence,
                "should_convert": True
            })
            test_id += 1

    # 3. Code switching - corrupt only the English part
    for ru_context, en_term, expected in CODE_SWITCH_EXAMPLES:
        corrupted_en = corrupt_en(en_term)
        if corrupted_en != en_term:
            tests.append({
                "id": f"codeswitch_{test_id}",
                "category": "code_switching",
                "input": f"{ru_context} {corrupted_en}",
                "expected": expected,
                "should_convert": True
            })
            test_id += 1

    # 4. CLI commands (should NOT convert)
    for cmd in CLI_COMMANDS:
        tests.append({
            "id": f"cli_{test_id}",
            "category": "cli_commands",
            "input": cmd,
            "expected": cmd,
            "should_convert": False
        })
        test_id += 1

    # 5. Programming terms (should NOT convert)
    for term in PROGRAMMING_TERMS:
        tests.append({
            "id": f"prog_{test_id}",
            "category": "programming_terms",
            "input": term,
            "expected": term,
            "should_convert": False
        })
        test_id += 1

    # 6. Programming terms corrupted (should convert back)
    for term in PROGRAMMING_TERMS:
        if len(term) > 2 and not term.startswith('.'):
            corrupted = corrupt_en(term)
            if corrupted != term:
                tests.append({
                    "id": f"prog_corrupt_{test_id}",
                    "category": "programming_terms_corrupted",
                    "input": corrupted,
                    "expected": term,
                    "should_convert": True
                })
                test_id += 1

    # 7. Russian words with punctuation variations
    punctuation_marks = ["!", "?", ".", ",", ";", ":", "-", "()", "[]", '""']
    ru_words = ["привет", "спасибо", "пожалуйста", "работа", "проект", "задача", "файл", "код"]

    for word in ru_words:
        for punct in punctuation_marks:
            if punct in ["()", "[]", '""']:
                test_word = f"{punct[0]}{word}{punct[1]}"
            else:
                test_word = f"{word}{punct}"

            corrupted = corrupt_ru(test_word)
            if corrupted != test_word:
                tests.append({
                    "id": f"punct_{test_id}",
                    "category": "punctuation_variants",
                    "input": corrupted,
                    "expected": test_word,
                    "should_convert": True
                })
                test_id += 1

    # 8. URLs and paths (should NOT convert)
    urls_paths = [
        "https://github.com/user/repo",
        "https://api.example.com/v1/users",
        "http://localhost:3000/api",
        "https://www.google.com/search?q=test",
        "ftp://files.server.com/download",
        "/home/user/documents",
        "/var/log/syslog",
        "/etc/nginx/nginx.conf",
        "~/Desktop/file.txt",
        "./src/components/Button.tsx",
        "../config/settings.json",
        "C:\\Users\\Admin\\Documents",
        "D:\\Projects\\MyApp",
        "node_modules/package/index.js",
        ".git/config",
        ".github/workflows/ci.yml",
    ]

    for item in urls_paths:
        tests.append({
            "id": f"path_{test_id}",
            "category": "urls_paths",
            "input": item,
            "expected": item,
            "should_convert": False
        })
        test_id += 1

    # 9. Email addresses (should NOT convert)
    emails = [
        "user@example.com",
        "admin@company.org",
        "support@service.io",
        "test.user@gmail.com",
        "info@subdomain.domain.com",
        "user+tag@email.com",
        "первыйюзер@mail.ru",
        "contact@startup.tech",
        "hello@world.dev",
        "noreply@notifications.app",
    ]

    for email in emails:
        tests.append({
            "id": f"email_{test_id}",
            "category": "emails",
            "input": email,
            "expected": email,
            "should_convert": False
        })
        test_id += 1

    # 10. Valid English text stress tests (should NOT convert)
    valid_en_texts = [
        "The quick brown fox jumps over the lazy dog",
        "Hello World!",
        "This is a test message",
        "Please check the documentation",
        "Click here to continue",
        "Welcome to our website",
        "Loading please wait",
        "Error something went wrong",
        "Success operation completed",
        "Warning this action cannot be undone",
        "Confirm your email address",
        "Enter your password",
        "Forgot your password",
        "Sign in to continue",
        "Create new account",
        "Log out",
        "Settings",
        "Profile",
        "Dashboard",
        "Home",
        "About us",
        "Contact",
        "Help",
        "FAQ",
        "Terms of Service",
        "Privacy Policy",
        "All rights reserved",
        "Made with love",
        "Version 1.0.0",
        "Last updated today",
    ]

    for text in valid_en_texts:
        tests.append({
            "id": f"valid_en_{test_id}",
            "category": "valid_english",
            "input": text,
            "expected": text,
            "should_convert": False
        })
        test_id += 1

    # 11. Valid Russian text stress tests (should NOT convert)
    valid_ru_texts = [
        "Привет мир",
        "Это тестовое сообщение",
        "Загрузка пожалуйста подождите",
        "Ошибка что-то пошло не так",
        "Успех операция завершена",
        "Внимание это действие нельзя отменить",
        "Подтвердите ваш адрес",
        "Введите пароль",
        "Забыли пароль",
        "Войдите чтобы продолжить",
        "Создать новый аккаунт",
        "Выйти",
        "Настройки",
        "Профиль",
        "Панель управления",
        "Главная",
        "О нас",
        "Контакты",
        "Помощь",
        "Часто задаваемые вопросы",
        "Условия использования",
        "Политика конфиденциальности",
        "Все права защищены",
        "Сделано с любовью",
        "Версия 1.0.0",
        "Последнее обновление сегодня",
    ]

    for text in valid_ru_texts:
        tests.append({
            "id": f"valid_ru_{test_id}",
            "category": "valid_russian",
            "input": text,
            "expected": text,
            "should_convert": False
        })
        test_id += 1

    # 12. Numbers with text (mixed)
    numbers_with_text = [
        ("ntcn123", "тест123"),
        ("ntcn456", "тест456"),
        ("ghbdtn2024", "привет2024"),
        ("2024ujl", "2024год"),
        ("1vfz", "1мая"),
        ("2bю.yz", "2июня"),
        ("3bю.kz", "3июля"),
        ("gfhjkm123", "пароль123"),
        ("gjkmpjdfntkm1", "пользователь1"),
        ("flvby2", "админ2"),
    ]

    for corrupted, expected in numbers_with_text:
        tests.append({
            "id": f"num_text_{test_id}",
            "category": "numbers_with_text",
            "input": corrupted,
            "expected": expected,
            "should_convert": True
        })
        test_id += 1

    # 13. English with numbers (should NOT convert)
    en_with_numbers = [
        "user123", "test456", "admin2024", "version2", "stage3",
        "config1", "server01", "db02", "api3", "node4",
        "level5", "phase6", "sprint7", "ticket8", "issue9",
        "feature10", "bug11", "task12", "project13", "team14",
    ]

    for text in en_with_numbers:
        tests.append({
            "id": f"en_num_{test_id}",
            "category": "english_with_numbers",
            "input": text,
            "expected": text,
            "should_convert": False
        })
        test_id += 1

    # 14. Special characters that map to Russian
    special_mappings = [
        ("{jhjij", "Хорошо"),
        ("{jnm", "Хоть"),
        ("<jkm", "Боль"),
        ("<scnhj", "Быстро"),
        (">kz", "Юля"),
        (":bnm", "Жить"),
        (":tkfybt", "Желание"),
        ("\"nj", "Это"),
        ("\"ythubz", "Энергия"),
    ]

    for corrupted, expected in special_mappings:
        tests.append({
            "id": f"special_{test_id}",
            "category": "special_chars_mapped",
            "input": corrupted,
            "expected": expected,
            "should_convert": True
        })
        test_id += 1

    return tests


def main():
    # Load existing tests
    existing_path = Path(__file__).parent.parent / "test_corpus_v2.json"
    with open(existing_path, 'r', encoding='utf-8') as f:
        existing_tests = json.load(f)

    print(f"Existing tests: {len(existing_tests)}")

    # Generate expanded tests
    expanded = generate_expanded_tests()
    print(f"Expanded tests: {len(expanded)}")

    # Deduplicate
    seen = set()
    for t in existing_tests:
        seen.add((t['input'], t['expected']))

    new_tests = []
    for t in expanded:
        key = (t['input'], t['expected'])
        if key not in seen:
            seen.add(key)
            new_tests.append(t)

    print(f"New unique tests: {len(new_tests)}")

    # Combine
    all_tests = existing_tests + new_tests
    print(f"Total tests: {len(all_tests)}")

    # Save
    output_path = Path(__file__).parent.parent / "test_corpus_v2.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(all_tests, f, ensure_ascii=False, indent=2)

    print(f"Saved to: {output_path}")

    # Statistics
    should_convert = sum(1 for t in all_tests if t.get('should_convert', True))
    should_not = len(all_tests) - should_convert

    print(f"\nStatistics:")
    print(f"  Should convert: {should_convert} ({100*should_convert/len(all_tests):.1f}%)")
    print(f"  Should NOT convert: {should_not} ({100*should_not/len(all_tests):.1f}%)")


if __name__ == "__main__":
    main()
