#!/usr/bin/env python3
"""
Конвертация NgramData из Swift литералов в JSON файлы.

Парсит Swift файлы вида:
    static let ruBigrams: [String: Double] = [
        "то": 0.01538327,
        ...
    ]

И создаёт JSON файлы в Dictum/Resources/
"""

import re
import json
import os
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
NGRAM_DIR = PROJECT_DIR / "Dictum" / "NgramData"
RESOURCES_DIR = PROJECT_DIR / "Dictum" / "Resources"

# Маппинг Swift файлов -> JSON файлов
FILES_MAP = {
    "NgramDataRuBigrams.swift": "ngrams_ru_bigrams.json",
    "NgramDataRuTrigrams.swift": "ngrams_ru_trigrams.json",
    "NgramDataEnBigrams.swift": "ngrams_en_bigrams.json",
    "NgramDataEnTrigrams.swift": "ngrams_en_trigrams.json",
}


def parse_swift_dict(content: str) -> dict[str, float]:
    """
    Парсит Swift Dictionary литерал из содержимого файла.

    Ищет паттерн: "ключ": значение,
    """
    result = {}

    # Паттерн для строк вида: "то": 0.01538327,
    pattern = r'"([^"]+)":\s*([\d.]+)'

    matches = re.findall(pattern, content)
    for key, value in matches:
        result[key] = float(value)

    return result


def convert_file(swift_filename: str, json_filename: str) -> int:
    """
    Конвертирует один Swift файл в JSON.
    Возвращает количество записей.
    """
    swift_path = NGRAM_DIR / swift_filename
    json_path = RESOURCES_DIR / json_filename

    if not swift_path.exists():
        print(f"⚠️  Файл не найден: {swift_path}")
        return 0

    print(f"📖 Читаю: {swift_filename}")
    content = swift_path.read_text(encoding="utf-8")

    data = parse_swift_dict(content)
    count = len(data)

    print(f"📝 Записываю: {json_filename} ({count} записей)")

    # Создаём директорию если не существует
    RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

    # Записываем JSON (компактный формат для экономии места)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))

    return count


def main():
    print("🔄 Конвертация NgramData Swift → JSON\n")

    total = 0
    for swift_file, json_file in FILES_MAP.items():
        count = convert_file(swift_file, json_file)
        total += count
        print()

    print(f"✅ Готово! Всего: {total} записей в {len(FILES_MAP)} файлах")
    print(f"📁 Файлы сохранены в: {RESOURCES_DIR}")


if __name__ == "__main__":
    main()
