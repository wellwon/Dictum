#!/usr/bin/env python3
"""
Validate test corpus quality and check for issues.
"""

import json
import os
from collections import Counter
from typing import List, Dict, Set, Tuple

# QWERTY to ЙЦУКЕН mapping for validation
QWERTY_TO_RUSSIAN = {
    'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н', 'u': 'г', 'i': 'ш', 'o': 'щ', 'p': 'з',
    '[': 'х', ']': 'ъ', 'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р', 'j': 'о', 'k': 'л',
    'l': 'д', ';': 'ж', "'": 'э', 'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
    ',': 'б', '.': 'ю',
}

RUSSIAN_TO_QWERTY = {v: k for k, v in QWERTY_TO_RUSSIAN.items()}

def is_cyrillic(char: str) -> bool:
    """Check if character is Cyrillic."""
    return '\u0400' <= char <= '\u04FF' or char == 'ё' or char == 'Ё'

def is_latin(char: str) -> bool:
    """Check if character is Latin."""
    return char.isalpha() and char.isascii()

def analyze_text(text: str) -> Dict[str, int]:
    """Analyze character types in text."""
    result = {'cyrillic': 0, 'latin': 0, 'digit': 0, 'punct': 0, 'space': 0, 'other': 0}
    for char in text:
        if is_cyrillic(char):
            result['cyrillic'] += 1
        elif is_latin(char):
            result['latin'] += 1
        elif char.isdigit():
            result['digit'] += 1
        elif char in ' \t\n':
            result['space'] += 1
        elif char in '.,!?;:\'"-()[]{}/<>@#$%^&*+=~`|\\':
            result['punct'] += 1
        else:
            result['other'] += 1
    return result

def validate_conversion(test: Dict) -> Tuple[bool, str]:
    """Validate that conversion logic makes sense."""
    input_text = test['input']
    expected = test['expected']
    should_convert = test['should_convert']

    input_analysis = analyze_text(input_text)
    expected_analysis = analyze_text(expected)

    if should_convert:
        # For should_convert=True:
        # - Input should have mostly Latin (corrupted Russian)
        # - Expected should have mostly Cyrillic (correct Russian)
        if expected_analysis['cyrillic'] == 0 and expected_analysis['latin'] > 0:
            # Expected is English but should_convert=True - might be wrong
            # Unless it's code-switching (mixed)
            if 'code_switch' not in test['category']:
                return False, f"should_convert=True but expected is English: {expected}"

    else:
        # For should_convert=False:
        # - Input and expected should be the same
        if input_text != expected:
            return False, f"should_convert=False but input != expected"

    return True, "OK"

def check_duplicates(tests: List[Dict]) -> List[Tuple[str, str]]:
    """Find duplicate (input, expected) pairs."""
    seen = {}
    duplicates = []
    for t in tests:
        pair = (t['input'], t['expected'])
        if pair in seen:
            duplicates.append(pair)
        else:
            seen[pair] = t['id']
    return duplicates

def sample_tests(tests: List[Dict], category: str, n: int = 5) -> List[Dict]:
    """Sample n tests from a category."""
    cat_tests = [t for t in tests if t['category'] == category]
    import random
    random.seed(42)
    return random.sample(cat_tests, min(n, len(cat_tests)))

def main():
    corpus_path = "../test_corpus_v2.json"

    if not os.path.exists(corpus_path):
        print(f"Error: {corpus_path} not found")
        return

    with open(corpus_path, 'r', encoding='utf-8') as f:
        tests = json.load(f)

    print(f"=" * 60)
    print(f"TEST CORPUS VALIDATION REPORT")
    print(f"=" * 60)
    print(f"\nTotal tests: {len(tests):,}")

    # Statistics
    should_convert = sum(1 for t in tests if t['should_convert'])
    should_not = len(tests) - should_convert
    print(f"\nConversion balance:")
    print(f"  Should convert: {should_convert:,} ({100*should_convert/len(tests):.1f}%)")
    print(f"  Should NOT convert: {should_not:,} ({100*should_not/len(tests):.1f}%)")

    # Category breakdown
    categories = Counter(t['category'] for t in tests)
    print(f"\nCategories ({len(categories)} total):")
    for cat, count in categories.most_common():
        pct = 100 * count / len(tests)
        print(f"  {cat}: {count:,} ({pct:.1f}%)")

    # Check for duplicates
    duplicates = check_duplicates(tests)
    print(f"\nDuplicates: {len(duplicates)}")
    if duplicates:
        print("  First 5 duplicates:")
        for inp, exp in duplicates[:5]:
            print(f"    '{inp}' -> '{exp}'")

    # Validation checks
    print(f"\nValidation checks:")
    issues = []
    for t in tests:
        valid, msg = validate_conversion(t)
        if not valid:
            issues.append((t['id'], msg))

    print(f"  Issues found: {len(issues)}")
    if issues:
        print("  First 10 issues:")
        for test_id, msg in issues[:10]:
            print(f"    {test_id}: {msg}")

    # Sample tests from key categories
    print(f"\n" + "=" * 60)
    print("SAMPLE TESTS BY CATEGORY")
    print("=" * 60)

    key_categories = [
        'ru_common_words',
        'stress_tests_en',
        'companies_services',
        'cli_commands',
        'punctuation',
        'sentences',
        'code_switching',
        'sensitive_data',
    ]

    for cat in key_categories:
        samples = sample_tests(tests, cat, 3)
        if samples:
            print(f"\n{cat} ({categories.get(cat, 0)} tests):")
            for s in samples:
                convert_str = "CONVERT" if s['should_convert'] else "NO CONV"
                print(f"  [{convert_str}] '{s['input']}' -> '{s['expected']}'")

    # File size
    file_size = os.path.getsize(corpus_path) / 1024 / 1024
    print(f"\n" + "=" * 60)
    print(f"Corpus file size: {file_size:.2f} MB")
    print(f"=" * 60)

if __name__ == "__main__":
    main()
