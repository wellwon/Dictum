#!/usr/bin/env python3
"""
Генерация биграмм и триграмм из Taiga корпусов (оптимизированная версия).
Выход: 5 Swift файлов в папке NgramData/ для параллельной компиляции.

Источники:
- Russian: Taiga Corpus (local) - Social 50%, Subtitles 50%
- English: Сохраняется из текущего NgramData.swift

Использование:
    python3 generate_ngrams.py
"""

import os
import re
import random
from pathlib import Path
from collections import Counter
from typing import Generator

try:
    from tqdm import tqdm
except ImportError:
    print("Installing tqdm...")
    os.system("pip install tqdm")
    from tqdm import tqdm

# Алфавиты
ALPHABET_RU = set("абвгдеёжзийклмнопрстуфхцчшщъыьэюя")
ALPHABET_EN = set("abcdefghijklmnopqrstuvwxyz")

# Лимиты
LIMIT_RU = 500_000  # 500K примеров (250K social + 250K subtitles)

# Пути к локальным корпусам
SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
CORPORA_DIR = PROJECT_DIR / "corpora"
TAIGA_SOCIAL_DIR = CORPORA_DIR / "taiga_social_ru" / "texts"
TAIGA_SUBTITLES_DIR = CORPORA_DIR / "taiga_subtitles_ru" / "texts"
OUTPUT_DIR = PROJECT_DIR / "Dictum" / "NgramData"
OLD_OUTPUT_PATH = PROJECT_DIR / "Dictum" / "NgramData.swift"  # Для извлечения EN данных

# Файлы social corpus
SOCIAL_FILES = [
    "twtexts.txt",           # Twitter ~67 MB
    "vktexts.txt",           # VK ~205 MB
    "fbtexts.txt",           # Facebook ~73 MB
    "LiveJournalPostsandcommentsGICR.txt"  # LJ ~338 MB
]


def stream_taiga_social(limit: int) -> Generator[str, None, None]:
    """Русский из Taiga Social (Twitter, VK, Facebook, LJ)."""
    if not TAIGA_SOCIAL_DIR.exists():
        print(f"  ! Social dir not found: {TAIGA_SOCIAL_DIR}")
        return

    per_file_limit = limit // len(SOCIAL_FILES)
    total_count = 0

    for filename in SOCIAL_FILES:
        filepath = TAIGA_SOCIAL_DIR / filename
        if not filepath.exists():
            print(f"  ! Missing: {filename}")
            continue

        file_count = 0
        current_text = []

        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                line = line.strip()

                # Пропускаем маркеры DataBaseItem
                if line.startswith("DataBaseItem:"):
                    continue

                # Пустая строка = конец записи
                if not line:
                    if current_text:
                        text = " ".join(current_text)
                        yield text
                        file_count += 1
                        total_count += 1
                        current_text = []

                        if total_count >= limit:
                            return
                        if file_count >= per_file_limit:
                            break
                else:
                    current_text.append(line)

        print(f"    {filename}: {file_count:,} texts")


def stream_taiga_subtitles(limit: int) -> Generator[str, None, None]:
    """Русский из Taiga Subtitles (фильмы/сериалы)."""
    if not TAIGA_SUBTITLES_DIR.exists():
        print(f"  ! Subtitles dir not found: {TAIGA_SUBTITLES_DIR}")
        return

    # Кэшируем список файлов ОДИН РАЗ
    print("    Scanning subtitle files...")
    subtitle_files = list(TAIGA_SUBTITLES_DIR.rglob("*.ru.txt"))
    print(f"    Found {len(subtitle_files):,} subtitle files")

    # Перемешиваем для разнообразия сериалов
    random.shuffle(subtitle_files)

    count = 0
    for txt_file in subtitle_files:
        try:
            with open(txt_file, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    # Формат SubRip: номер TAB начало TAB конец TAB текст
                    parts = line.split('\t')
                    if len(parts) >= 4:
                        text = parts[3].strip()
                        if text:
                            yield text
                            count += 1
                            if count >= limit:
                                print(f"    Subtitles: {count:,} lines")
                                return
        except Exception:
            continue  # Пропускаем битые файлы

    print(f"    Subtitles: {count:,} lines")


def count_ngrams(texts: Generator[str, None, None], limit: int, desc: str) -> tuple[Counter, Counter]:
    """Подсчёт биграмм и триграмм из потока текстов."""
    bigrams: Counter = Counter()
    trigrams: Counter = Counter()

    for i, text in enumerate(tqdm(texts, total=limit, desc=desc, unit="text")):
        if i >= limit:
            break

        text = text.lower()
        # Фильтруем только русские буквы
        chars = [c for c in text if c in ALPHABET_RU]

        if len(chars) >= 2:
            # Биграммы
            bigrams.update(chars[j] + chars[j + 1] for j in range(len(chars) - 1))

        if len(chars) >= 3:
            # Триграммы
            trigrams.update(chars[j] + chars[j + 1] + chars[j + 2] for j in range(len(chars) - 2))

    return bigrams, trigrams


def normalize_to_probability(ngrams: Counter) -> dict[str, float]:
    """Нормализация counts в вероятности."""
    total = sum(ngrams.values())
    if total == 0:
        return {}
    return {k: v / total for k, v in ngrams.items()}


def fill_bigram_matrix(bigrams: dict[str, float], alphabet: str) -> dict[str, float]:
    """Заполнить полную матрицу биграмм (включая нулевые)."""
    result = {}
    for c1 in alphabet:
        for c2 in alphabet:
            key = c1 + c2
            result[key] = bigrams.get(key, 0.0)
    return result


def extract_english_from_current() -> tuple[dict, dict]:
    """Извлечь английские данные из текущего NgramData.swift."""
    # Проверяем оба возможных пути
    source_path = None
    if OLD_OUTPUT_PATH.exists():
        source_path = OLD_OUTPUT_PATH
    elif (OUTPUT_DIR / "NgramDataEnBigrams.swift").exists():
        # Уже разбито на файлы, извлекаем из них
        en_bigrams = {}
        en_trigrams = {}

        bigrams_path = OUTPUT_DIR / "NgramDataEnBigrams.swift"
        if bigrams_path.exists():
            content = bigrams_path.read_text(encoding='utf-8')
            for m in re.finditer(r'"([a-z]{2})":\s*([\d.e\-]+)', content):
                en_bigrams[m.group(1)] = float(m.group(2))

        trigrams_path = OUTPUT_DIR / "NgramDataEnTrigrams.swift"
        if trigrams_path.exists():
            content = trigrams_path.read_text(encoding='utf-8')
            for m in re.finditer(r'"([a-z]{3})":\s*([\d.e\-]+)', content):
                en_trigrams[m.group(1)] = float(m.group(2))

        print(f"  Extracted {len(en_bigrams)} EN bigrams, {len(en_trigrams):,} EN trigrams from split files")
        return en_bigrams, en_trigrams

    if source_path is None:
        print("  ! No NgramData source found")
        return {}, {}

    content = source_path.read_text(encoding='utf-8')

    # Регулярки для извлечения словарей
    en_bigrams = {}
    en_trigrams = {}

    # Извлекаем enBigrams
    match = re.search(r'static let enBigrams.*?=\s*\[(.*?)\]', content, re.DOTALL)
    if match:
        dict_content = match.group(1)
        for m in re.finditer(r'"([a-z]{2})":\s*([\d.e\-]+)', dict_content):
            en_bigrams[m.group(1)] = float(m.group(2))

    # Извлекаем enTrigrams
    match = re.search(r'static let enTrigrams.*?=\s*\[(.*?)\]', content, re.DOTALL)
    if match:
        dict_content = match.group(1)
        for m in re.finditer(r'"([a-z]{3})":\s*([\d.e\-]+)', dict_content):
            en_trigrams[m.group(1)] = float(m.group(2))

    print(f"  Extracted {len(en_bigrams)} EN bigrams, {len(en_trigrams):,} EN trigrams")
    return en_bigrams, en_trigrams


def format_swift_dict(data: dict[str, float], indent: int = 8) -> str:
    """Форматирование словаря в Swift синтаксис."""
    lines = []
    items = sorted(data.items(), key=lambda x: -x[1])  # По убыванию частоты

    for key, value in items:
        if value < 1e-10:
            val_str = "0"
        elif value < 0.0001:
            val_str = f"{value:.10f}".rstrip('0').rstrip('.')
        else:
            val_str = f"{value:.8f}".rstrip('0').rstrip('.')
        lines.append(f'{" " * indent}"{key}": {val_str}')

    return ",\n".join(lines)


def main():
    print("=" * 60)
    print("N-gram Generator v4.0 (Optimized Taiga)")
    print("=" * 60)

    social_limit = LIMIT_RU // 2
    subtitles_limit = LIMIT_RU // 2

    # === РУССКИЙ: Social ===
    print(f"\n[1/4] Processing Taiga Social (limit={social_limit:,})...")
    social_bi, social_tri = count_ngrams(
        stream_taiga_social(social_limit),
        social_limit,
        "Social"
    )
    print(f"  Social: {sum(social_bi.values()):,} bigrams, {sum(social_tri.values()):,} trigrams")

    # === РУССКИЙ: Subtitles ===
    print(f"\n[2/4] Processing Taiga Subtitles (limit={subtitles_limit:,})...")
    subs_bi, subs_tri = count_ngrams(
        stream_taiga_subtitles(subtitles_limit),
        subtitles_limit,
        "Subtitles"
    )
    print(f"  Subtitles: {sum(subs_bi.values()):,} bigrams, {sum(subs_tri.values()):,} trigrams")

    # Объединяем
    ru_bi_counts = social_bi + subs_bi
    ru_tri_counts = social_tri + subs_tri

    ru_bigrams = normalize_to_probability(ru_bi_counts)
    ru_trigrams = normalize_to_probability(ru_tri_counts)
    ru_bigrams_full = fill_bigram_matrix(ru_bigrams, "абвгдеёжзийклмнопрстуфхцчшщъыьэюя")

    print(f"\n  Russian total: {len(ru_bigrams_full)} bigrams, {len(ru_trigrams):,} trigrams")

    # === АНГЛИЙСКИЙ: Извлекаем из текущего файла ===
    print("\n[3/4] Extracting English from current NgramData.swift...")
    en_bigrams, en_trigrams = extract_english_from_current()

    if not en_bigrams:
        # Fallback: заполняем пустым
        en_bigrams = fill_bigram_matrix({}, "abcdefghijklmnopqrstuvwxyz")
        en_trigrams = {}

    # === ГЕНЕРАЦИЯ SWIFT ФАЙЛОВ ===
    print("\n[4/4] Generating Swift files...")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Главный файл NgramData.swift
    main_content = '''// NgramData.swift
// Auto-generated from Taiga corpora
//
// Sources:
// - Russian: Taiga Corpus (taiga_social_ru 50% + taiga_subtitles_ru 50%)
// - English: Preserved from previous version
//
// Разбито на 5 файлов для параллельной компиляции
//
// DO NOT EDIT - regenerate with scripts/generate_ngrams.py

import Foundation

/// N-грамм статистика для детекции языка
enum NgramData {
    // Данные в extension файлах:
    // - NgramDataRuBigrams.swift
    // - NgramDataRuTrigrams.swift
    // - NgramDataEnBigrams.swift
    // - NgramDataEnTrigrams.swift
}
'''
    (OUTPUT_DIR / "NgramData.swift").write_text(main_content, encoding='utf-8')

    # 2. Russian Bigrams
    ru_bi_content = f'''// NgramDataRuBigrams.swift
// Auto-generated - DO NOT EDIT

import Foundation

extension NgramData {{
    /// Вероятности биграмм русского языка (полная матрица 33x33)
    static let ruBigrams: [String: Double] = [
{format_swift_dict(ru_bigrams_full)}
    ]
}}
'''
    (OUTPUT_DIR / "NgramDataRuBigrams.swift").write_text(ru_bi_content, encoding='utf-8')

    # 3. Russian Trigrams
    ru_tri_content = f'''// NgramDataRuTrigrams.swift
// Auto-generated - DO NOT EDIT

import Foundation

extension NgramData {{
    /// Вероятности триграмм русского языка
    static let ruTrigrams: [String: Double] = [
{format_swift_dict(ru_trigrams)}
    ]
}}
'''
    (OUTPUT_DIR / "NgramDataRuTrigrams.swift").write_text(ru_tri_content, encoding='utf-8')

    # 4. English Bigrams
    en_bi_content = f'''// NgramDataEnBigrams.swift
// Auto-generated - DO NOT EDIT

import Foundation

extension NgramData {{
    /// Вероятности биграмм английского языка (полная матрица 26x26)
    static let enBigrams: [String: Double] = [
{format_swift_dict(en_bigrams)}
    ]
}}
'''
    (OUTPUT_DIR / "NgramDataEnBigrams.swift").write_text(en_bi_content, encoding='utf-8')

    # 5. English Trigrams
    en_tri_content = f'''// NgramDataEnTrigrams.swift
// Auto-generated - DO NOT EDIT

import Foundation

extension NgramData {{
    /// Вероятности триграмм английского языка
    static let enTrigrams: [String: Double] = [
{format_swift_dict(en_trigrams)}
    ]
}}
'''
    (OUTPUT_DIR / "NgramDataEnTrigrams.swift").write_text(en_tri_content, encoding='utf-8')

    # Статистика
    total_size = sum(f.stat().st_size for f in OUTPUT_DIR.glob("*.swift")) / 1024

    print(f"\nDone!")
    print(f"  Output: {OUTPUT_DIR}/ (5 files)")
    print(f"  Total size: {total_size:.1f} KB")
    print(f"  Russian: {len(ru_bigrams_full)} bigrams + {len(ru_trigrams):,} trigrams")
    print(f"  English: {len(en_bigrams)} bigrams + {len(en_trigrams):,} trigrams")

    # Топ-10 для проверки
    print("\n Top-10 Russian bigrams:")
    for i, (k, v) in enumerate(sorted(ru_bigrams.items(), key=lambda x: -x[1])[:10]):
        print(f"   {i + 1}. '{k}': {v:.6f} ({v * 100:.2f}%)")

    print("\n Top-10 Russian trigrams:")
    for i, (k, v) in enumerate(sorted(ru_trigrams.items(), key=lambda x: -x[1])[:10]):
        print(f"   {i + 1}. '{k}': {v:.6f}")


if __name__ == "__main__":
    main()
