#!/usr/bin/env python3
"""
generate_test_corpus.py

Генерирует реалистичные тестовые данные для TextSwitcher.
Создаёт ~11,000 тест-кейсов с различными категориями.
"""

import json
import os
from pathlib import Path
from datetime import datetime

# Таблицы конвертации (из LayoutMaps.swift)
QWERTY_TO_RUSSIAN_LOWER = {
    '`': 'ё', 'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е',
    'y': 'н', 'u': 'г', 'i': 'ш', 'o': 'щ', 'p': 'з', '[': 'х', ']': 'ъ',
    'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р',
    'j': 'о', 'k': 'л', 'l': 'д', ';': 'ж', "'": 'э',
    'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
    ',': 'б', '.': 'ю', '/': '.'
}

QWERTY_TO_RUSSIAN_UPPER = {
    '~': 'Ё', 'Q': 'Й', 'W': 'Ц', 'E': 'У', 'R': 'К', 'T': 'Е',
    'Y': 'Н', 'U': 'Г', 'I': 'Ш', 'O': 'Щ', 'P': 'З', '{': 'Х', '}': 'Ъ',
    'A': 'Ф', 'S': 'Ы', 'D': 'В', 'F': 'А', 'G': 'П', 'H': 'Р',
    'J': 'О', 'K': 'Л', 'L': 'Д', ':': 'Ж', '"': 'Э',
    'Z': 'Я', 'X': 'Ч', 'C': 'С', 'V': 'М', 'B': 'И', 'N': 'Т', 'M': 'Ь',
    '<': 'Б', '>': 'Ю'
}

RUSSIAN_TO_QWERTY_LOWER = {v: k for k, v in QWERTY_TO_RUSSIAN_LOWER.items()}
RUSSIAN_TO_QWERTY_UPPER = {v: k for k, v in QWERTY_TO_RUSSIAN_UPPER.items()}


def ru_to_en(text: str) -> str:
    """Конвертирует русский текст как будто набран на английской раскладке."""
    result = []
    for char in text:
        if char in RUSSIAN_TO_QWERTY_LOWER:
            result.append(RUSSIAN_TO_QWERTY_LOWER[char])
        elif char in RUSSIAN_TO_QWERTY_UPPER:
            result.append(RUSSIAN_TO_QWERTY_UPPER[char])
        else:
            result.append(char)
    return ''.join(result)


def en_to_ru(text: str) -> str:
    """Конвертирует английский текст как будто набран на русской раскладке."""
    result = []
    for char in text:
        if char in QWERTY_TO_RUSSIAN_LOWER:
            result.append(QWERTY_TO_RUSSIAN_LOWER[char])
        elif char in QWERTY_TO_RUSSIAN_UPPER:
            result.append(QWERTY_TO_RUSSIAN_UPPER[char])
        else:
            result.append(char)
    return ''.join(result)


# ============================================================
# ТЕСТОВЫЕ ДАННЫЕ
# ============================================================

# Частые русские слова (топ-2000)
RU_COMMON_WORDS = [
    # Приветствия и базовые
    "привет", "здравствуй", "пока", "спасибо", "пожалуйста", "да", "нет",
    "хорошо", "плохо", "ладно", "давай", "потом", "сейчас", "завтра", "вчера",

    # Глаголы (частые)
    "делать", "сделать", "работать", "идти", "ехать", "смотреть", "видеть",
    "слышать", "говорить", "сказать", "знать", "думать", "хотеть", "мочь",
    "любить", "нравиться", "писать", "читать", "понимать", "помнить",
    "звонить", "отправить", "получить", "найти", "искать", "ждать",
    "начать", "закончить", "открыть", "закрыть", "взять", "дать",
    "купить", "продать", "платить", "стоить", "жить", "работать",

    # Существительные (частые)
    "дом", "работа", "день", "время", "год", "человек", "место", "жизнь",
    "мир", "страна", "город", "улица", "дорога", "машина", "деньги",
    "вопрос", "ответ", "проблема", "решение", "результат", "причина",
    "слово", "текст", "письмо", "сообщение", "звонок", "встреча",
    "компьютер", "телефон", "интернет", "сайт", "программа", "файл",
    "документ", "проект", "задача", "план", "цель", "идея",

    # Прилагательные
    "хороший", "плохой", "большой", "маленький", "новый", "старый",
    "первый", "последний", "важный", "нужный", "готовый", "свободный",
    "быстрый", "медленный", "простой", "сложный", "легкий", "тяжелый",

    # Местоимения и частицы
    "что", "кто", "где", "когда", "как", "почему", "зачем", "какой",
    "который", "этот", "тот", "такой", "весь", "каждый", "другой",

    # Числительные
    "один", "два", "три", "четыре", "пять", "шесть", "семь", "восемь",
    "девять", "десять", "сто", "тысяча", "миллион",

    # Дополнительные частые слова
    "может", "должен", "нужно", "можно", "надо", "будет", "было", "есть",
    "очень", "только", "уже", "ещё", "тоже", "также", "вообще", "просто",
    "конечно", "наверное", "кажется", "точно", "обязательно", "возможно",
]

# IT-сленг на русском
RU_IT_SLANG = [
    "коммит", "коммитить", "закоммитить", "пуш", "пушить", "запушить",
    "мердж", "мерджить", "замерджить", "ребейз", "ребейзить",
    "деплой", "деплоить", "задеплоить", "билд", "билдить", "забилдить",
    "баг", "багфикс", "фикс", "фиксить", "пофиксить", "хотфикс",
    "релиз", "релизить", "зарелизить", "откатить", "роллбэк",
    "тест", "тестить", "протестить", "дебаг", "дебажить", "отдебажить",
    "рефактор", "рефакторить", "отрефакторить", "оптимизация", "оптимизировать",
    "апдейт", "апдейтить", "обновить", "даунгрейд", "апгрейд",
    "логин", "логинить", "залогиниться", "логаут", "разлогиниться",
    "бэкенд", "фронтенд", "фуллстек", "девопс", "сисадмин",
    "продакшен", "продакшн", "стейджинг", "девелопмент", "локалка",
    "репозиторий", "репа", "бранч", "ветка", "мастер", "мейн",
    "пулреквест", "ревью", "код ревью", "апрув", "аппрувить",
    "спринт", "скрам", "митинг", "стендап", "дейли", "ретро",
    "тикет", "таска", "эпик", "сторя", "бэклог", "приоритет",
    "сервер", "клиент", "база", "кэш", "кэшировать", "очередь",
    "эндпоинт", "роут", "роутинг", "миддлвара", "хендлер",
    "юнит", "интеграционный", "функциональный", "регрессия",
]

# Русские предложения (разговорные)
RU_SENTENCES = [
    "Привет, как дела?",
    "Всё хорошо, спасибо!",
    "Что делаешь сегодня?",
    "Давай встретимся завтра",
    "Скинь ссылку пожалуйста",
    "Посмотри когда будет время",
    "Нужно срочно сделать",
    "Это важная задача",
    "Подожди минутку",
    "Сейчас отправлю",
    "Проверь почту",
    "Перезвоню позже",
    "Не понял вопрос",
    "Можешь повторить?",
    "Согласен полностью",
    "Отличная идея!",
    "Надо подумать",
    "Не уверен пока",
    "Спасибо за помощь",
    "До связи!",

    # IT-контекст
    "Сейчас закоммичу и запушу",
    "Надо пофиксить баг в продакшене",
    "Деплоим через пайплайн",
    "Ребейзни на мейн пожалуйста",
    "Прогони тесты перед мерджем",
    "Создай новый бранч для фичи",
    "Откати последний релиз",
    "Проверь логи на сервере",
    "База не отвечает",
    "Кэш надо почистить",
    "Эндпоинт возвращает ошибку",
    "Митинг через полчаса",
    "Посмотри мой пулреквест",
    "Нужен код ревью срочно",
    "Таска в спринте висит",
    "Дедлайн завтра утром",
    "Продакшен упал",
    "Тесты не проходят",
    "Билд сломался",
    "Память течёт",
]

# Частые английские слова
EN_COMMON_WORDS = [
    # Basic
    "hello", "hi", "bye", "thanks", "please", "yes", "no", "okay",
    "good", "bad", "fine", "well", "now", "later", "today", "tomorrow",

    # Verbs
    "make", "do", "work", "go", "come", "see", "look", "watch",
    "hear", "listen", "speak", "say", "tell", "know", "think", "want",
    "need", "like", "love", "write", "read", "understand", "remember",
    "call", "send", "get", "find", "search", "wait", "start", "finish",
    "open", "close", "take", "give", "buy", "sell", "pay", "cost",

    # Nouns
    "home", "work", "day", "time", "year", "person", "place", "life",
    "world", "country", "city", "street", "road", "car", "money",
    "question", "answer", "problem", "solution", "result", "reason",
    "word", "text", "letter", "message", "call", "meeting",
    "computer", "phone", "internet", "website", "program", "file",
    "document", "project", "task", "plan", "goal", "idea",

    # Adjectives
    "good", "bad", "big", "small", "new", "old", "first", "last",
    "important", "ready", "free", "fast", "slow", "simple", "complex",

    # Common phrases
    "email", "password", "login", "logout", "username", "account",
    "server", "client", "database", "cache", "queue", "request",
    "response", "error", "success", "status", "update", "delete",
]

# Английские предложения
EN_SENTENCES = [
    "Hello, how are you?",
    "I'm fine, thanks!",
    "What are you doing?",
    "Let's meet tomorrow",
    "Please send me the link",
    "Check when you have time",
    "This is urgent",
    "Important task",
    "Wait a moment",
    "Sending now",
    "Check your email",
    "Call you later",
    "I don't understand",
    "Can you repeat?",
    "I agree",
    "Great idea!",
    "Let me think",
    "Not sure yet",
    "Thanks for help",
    "See you!",

    # IT context
    "Please review my pull request",
    "The build failed",
    "Tests are not passing",
    "Deploy to production",
    "Check the server logs",
    "Database connection error",
    "Cache needs to be cleared",
    "API returns error",
    "Meeting in 30 minutes",
    "Deadline is tomorrow",
]

# Смешанный RU+EN текст (не конвертировать EN часть)
MIXED_LANG_SENTENCES = [
    ("Отправь мне API key", "API", "tech"),
    ("Настрой Docker на сервере", "Docker", "tech"),
    ("Почему webpack не билдит?", "webpack", "tech"),
    ("Проверь GitHub репозиторий", "GitHub", "tech"),
    ("Запусти npm install", "npm install", "tech"),
    ("Обнови README файл", "README", "tech"),
    ("Посмотри Jira тикет", "Jira", "tech"),
    ("Slack сообщение пришло", "Slack", "tech"),
    ("Zoom митинг через час", "Zoom", "tech"),
    ("VS Code глючит", "VS Code", "tech"),
    ("Используй TypeScript", "TypeScript", "tech"),
    ("Напиши unit test", "unit test", "tech"),
    ("Добавь в .gitignore", ".gitignore", "tech"),
    ("Проверь package.json", "package.json", "tech"),
    ("Обнови node modules", "node modules", "tech"),
]

# Короткие слова (2-4 буквы) - сложные для распознавания
SHORT_WORDS_RU = [
    "на", "не", "за", "от", "из", "до", "по", "со", "об", "ко",
    "да", "но", "ну", "же", "ли", "бы", "уж", "он", "мы", "ты",
    "кот", "дом", "сад", "год", "раз", "мир", "час", "ряд", "вид",
    "тут", "там", "так", "как", "где", "кто", "что", "ещё", "уже",
]

SHORT_WORDS_EN = [
    "in", "on", "at", "to", "is", "if", "it", "be", "we", "he",
    "me", "my", "no", "so", "up", "or", "by", "an", "as", "of",
    "cat", "dog", "car", "day", "way", "man", "new", "old", "big",
    "the", "and", "for", "are", "but", "not", "you", "all", "can",
]

# Предложения для тестирования context_bias
CONTEXT_TEST_SENTENCES = [
    # Несколько слов на неправильной раскладке + одно "спорное"
    ("ghbdtn vbh tot", "привет мир еще"),  # tot→еще с context_bias
    ("rfr ltkf tot", "как дела еще"),
    ("ghbdtn lheu tot", "привет друг еще"),
    ("cghfcb,j tot", "спасибо еще"),

    # Без достаточного контекста - не должно конвертировать tot
    ("tot", "tot"),  # одно слово - keep
    ("ghbdtn tot", "привет tot"),  # только 1 конвертация - недостаточно
]

# Edge cases
EDGE_CASES = [
    # UPPERCASE
    ("ПРИВЕТ", "GHBDTN", "ru", "uppercase"),
    ("HELLO", "РУДДЩ", "en", "uppercase"),
    ("РАБОТА", "HF,JNF", "ru", "uppercase"),
    ("WORLD", "ЦЩКДВ", "en", "uppercase"),

    # Capitalize
    ("Привет", "Ghbdtn", "ru", "capitalize"),
    ("Hello", "Руддщ", "en", "capitalize"),

    # С цифрами (не конвертировать цифры)
    ("test123", "еу|е123", "en", "with_numbers"),
    ("тест456", "ntcn456", "ru", "with_numbers"),

    # Email-like (не конвертировать)
    ("test@mail.com", "test@mail.com", "keep", "email"),
    ("user@domain.ru", "user@domain.ru", "keep", "email"),
]


def generate_corpus():
    """Генерирует полный тестовый корпус."""

    corpus = {
        "version": 1,
        "generated": datetime.now().isoformat(),
        "description": "TextSwitcher validation test corpus",
        "categories": {}
    }

    test_id = 0

    # 1. Русские слова набранные на EN (должны конвертироваться)
    ru_common_tests = []
    for word in RU_COMMON_WORDS:
        corrupted = ru_to_en(word)
        ru_common_tests.append({
            "id": f"ru_common_{test_id:04d}",
            "original": word,
            "corrupted": corrupted,
            "expected": word,
            "should_convert": True,
            "source_lang": "ru"
        })
        test_id += 1
    corpus["categories"]["ru_common_words"] = {
        "description": "Частые русские слова набранные на EN раскладке",
        "tests": ru_common_tests
    }

    # 2. IT-сленг на русском
    ru_it_tests = []
    for word in RU_IT_SLANG:
        corrupted = ru_to_en(word)
        ru_it_tests.append({
            "id": f"ru_it_{test_id:04d}",
            "original": word,
            "corrupted": corrupted,
            "expected": word,
            "should_convert": True,
            "source_lang": "ru"
        })
        test_id += 1
    corpus["categories"]["ru_it_slang"] = {
        "description": "IT-жаргон набранный на EN раскладке",
        "tests": ru_it_tests
    }

    # 3. Русские предложения
    ru_sent_tests = []
    for sentence in RU_SENTENCES:
        corrupted = ru_to_en(sentence)
        ru_sent_tests.append({
            "id": f"ru_sent_{test_id:04d}",
            "original": sentence,
            "corrupted": corrupted,
            "expected": sentence,
            "should_convert": True,
            "source_lang": "ru"
        })
        test_id += 1
    corpus["categories"]["ru_sentences"] = {
        "description": "Русские предложения набранные на EN раскладке",
        "tests": ru_sent_tests
    }

    # 4. Английские слова набранные на RU (должны конвертироваться)
    en_common_tests = []
    for word in EN_COMMON_WORDS:
        corrupted = en_to_ru(word)
        en_common_tests.append({
            "id": f"en_common_{test_id:04d}",
            "original": word,
            "corrupted": corrupted,
            "expected": word,
            "should_convert": True,
            "source_lang": "en"
        })
        test_id += 1
    corpus["categories"]["en_common_words"] = {
        "description": "Частые английские слова набранные на RU раскладке",
        "tests": en_common_tests
    }

    # 5. Английские предложения
    en_sent_tests = []
    for sentence in EN_SENTENCES:
        corrupted = en_to_ru(sentence)
        en_sent_tests.append({
            "id": f"en_sent_{test_id:04d}",
            "original": sentence,
            "corrupted": corrupted,
            "expected": sentence,
            "should_convert": True,
            "source_lang": "en"
        })
        test_id += 1
    corpus["categories"]["en_sentences"] = {
        "description": "Английские предложения набранные на RU раскладке",
        "tests": en_sent_tests
    }

    # 6. Tech buzzwords (НЕ должны конвертироваться)
    buzzwords_path = Path(__file__).parent.parent / "Dictum" / "Resources" / "tech_buzzwords_2025.json"
    buzzwords_tests = []
    if buzzwords_path.exists():
        with open(buzzwords_path) as f:
            buzzwords_data = json.load(f)
            for category, words in buzzwords_data.items():
                for word in words:
                    buzzwords_tests.append({
                        "id": f"buzz_{test_id:04d}",
                        "original": word,
                        "corrupted": word,  # Подаём как есть
                        "expected": word,   # Ожидаем без изменений
                        "should_convert": False,
                        "source_lang": "en",
                        "buzzword_category": category
                    })
                    test_id += 1
    corpus["categories"]["tech_buzzwords"] = {
        "description": "Tech buzzwords которые НЕ должны конвертироваться",
        "tests": buzzwords_tests
    }

    # 7. Смешанный RU+EN текст
    mixed_tests = []
    for sentence, en_part, tag in MIXED_LANG_SENTENCES:
        # Конвертируем всё предложение как русский текст на EN раскладке
        # но EN часть должна остаться как есть
        corrupted = ru_to_en(sentence)
        mixed_tests.append({
            "id": f"mixed_{test_id:04d}",
            "original": sentence,
            "corrupted": corrupted,
            "expected": sentence,  # Ожидаем восстановление с сохранением EN части
            "should_convert": True,
            "source_lang": "mixed",
            "en_part": en_part,
            "tag": tag
        })
        test_id += 1
    corpus["categories"]["mixed_lang"] = {
        "description": "Смешанный RU+EN текст",
        "tests": mixed_tests
    }

    # 8. Короткие слова
    short_tests = []
    for word in SHORT_WORDS_RU:
        corrupted = ru_to_en(word)
        short_tests.append({
            "id": f"short_{test_id:04d}",
            "original": word,
            "corrupted": corrupted,
            "expected": word,
            "should_convert": True,
            "source_lang": "ru",
            "length": len(word)
        })
        test_id += 1
    for word in SHORT_WORDS_EN:
        corrupted = en_to_ru(word)
        short_tests.append({
            "id": f"short_{test_id:04d}",
            "original": word,
            "corrupted": corrupted,
            "expected": word,
            "should_convert": True,
            "source_lang": "en",
            "length": len(word)
        })
        test_id += 1
    corpus["categories"]["short_words"] = {
        "description": "Короткие слова (2-4 буквы) - сложные для распознавания",
        "tests": short_tests
    }

    # 9. Предложения для context_bias
    context_tests = []
    for corrupted, expected in CONTEXT_TEST_SENTENCES:
        context_tests.append({
            "id": f"context_{test_id:04d}",
            "original": expected,
            "corrupted": corrupted,
            "expected": expected,
            "should_convert": corrupted != expected,
            "source_lang": "ru",
            "test_type": "context_bias"
        })
        test_id += 1
    corpus["categories"]["context_test"] = {
        "description": "Предложения для тестирования context_bias",
        "tests": context_tests
    }

    # 10. Edge cases
    edge_tests = []
    for original, corrupted, lang, case_type in EDGE_CASES:
        edge_tests.append({
            "id": f"edge_{test_id:04d}",
            "original": original,
            "corrupted": corrupted,
            "expected": original if lang != "keep" else corrupted,
            "should_convert": lang != "keep",
            "source_lang": lang,
            "case_type": case_type
        })
        test_id += 1
    corpus["categories"]["edge_cases"] = {
        "description": "Edge cases: UPPERCASE, capitalize, numbers, emails",
        "tests": edge_tests
    }

    # Статистика
    total_tests = sum(len(cat["tests"]) for cat in corpus["categories"].values())
    corpus["total_tests"] = total_tests

    print(f"Сгенерировано {total_tests} тест-кейсов:")
    for cat_name, cat_data in corpus["categories"].items():
        print(f"  - {cat_name}: {len(cat_data['tests'])} тестов")

    return corpus


def main():
    # Создаём директорию tests если нет
    tests_dir = Path(__file__).parent.parent / "tests"
    tests_dir.mkdir(exist_ok=True)

    # Генерируем корпус
    corpus = generate_corpus()

    # Сохраняем
    output_path = tests_dir / "test_corpus.json"
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(corpus, f, ensure_ascii=False, indent=2)

    print(f"\nСохранено в: {output_path}")
    print(f"Всего тестов: {corpus['total_tests']}")


if __name__ == "__main__":
    main()
