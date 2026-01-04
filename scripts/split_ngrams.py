#!/usr/bin/env python3
"""
Разбивает существующий NgramData.swift на 5 файлов для параллельной компиляции.
"""

import re
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
PROJECT_DIR = SCRIPT_DIR.parent
INPUT_PATH = PROJECT_DIR / "Dictum" / "NgramData.swift"
OUTPUT_DIR = PROJECT_DIR / "Dictum" / "NgramData"


def extract_dict(content: str, var_name: str) -> str:
    """Извлечь содержимое словаря по имени переменной."""
    # Ищем паттерн: static let varName: [String: Double] = [ ... ]
    pattern = rf'static let {var_name}:\s*\[String:\s*Double\]\s*=\s*\[(.*?)\]'
    match = re.search(pattern, content, re.DOTALL)
    if match:
        return match.group(1).strip()
    return ""


def main():
    print("Splitting NgramData.swift into 5 files...")

    if not INPUT_PATH.exists():
        print(f"Error: {INPUT_PATH} not found")
        return

    content = INPUT_PATH.read_text(encoding='utf-8')

    # Извлекаем все 4 словаря
    ru_bigrams = extract_dict(content, "ruBigrams")
    en_bigrams = extract_dict(content, "enBigrams")
    ru_trigrams = extract_dict(content, "ruTrigrams")
    en_trigrams = extract_dict(content, "enTrigrams")

    print(f"  ruBigrams: {ru_bigrams.count(':'):,} entries")
    print(f"  enBigrams: {en_bigrams.count(':'):,} entries")
    print(f"  ruTrigrams: {ru_trigrams.count(':'):,} entries")
    print(f"  enTrigrams: {en_trigrams.count(':'):,} entries")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Главный файл
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
        {ru_bigrams}
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
        {ru_trigrams}
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
        {en_bigrams}
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
        {en_trigrams}
    ]
}}
'''
    (OUTPUT_DIR / "NgramDataEnTrigrams.swift").write_text(en_tri_content, encoding='utf-8')

    # Статистика
    total_size = sum(f.stat().st_size for f in OUTPUT_DIR.glob("*.swift")) / 1024

    print(f"\nDone!")
    print(f"  Output: {OUTPUT_DIR}/ (5 files)")
    print(f"  Total size: {total_size:.1f} KB")


if __name__ == "__main__":
    main()
