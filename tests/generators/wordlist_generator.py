#!/usr/bin/env python3
"""
Wordlist-based test generator - generates tests from frequency wordlists.
Creates variants: uppercase, with punctuation, in sentences, etc.
"""

import json
import os
import random
from dataclasses import dataclass, asdict
from typing import List, Set, Tuple

# QWERTY to ЙЦУКЕН mapping
QWERTY_TO_RUSSIAN = {
    'q': 'й', 'w': 'ц', 'e': 'у', 'r': 'к', 't': 'е', 'y': 'н', 'u': 'г', 'i': 'ш', 'o': 'щ', 'p': 'з',
    '[': 'х', ']': 'ъ', 'a': 'ф', 's': 'ы', 'd': 'в', 'f': 'а', 'g': 'п', 'h': 'р', 'j': 'о', 'k': 'л',
    'l': 'д', ';': 'ж', "'": 'э', 'z': 'я', 'x': 'ч', 'c': 'с', 'v': 'м', 'b': 'и', 'n': 'т', 'm': 'ь',
    ',': 'б', '.': 'ю', '/': '.', '`': 'ё', '{': 'Х', '}': 'Ъ', ':': 'Ж', '"': 'Э', '<': 'Б', '>': 'Ю',
    '?': ',', '~': 'Ё',
    'Q': 'Й', 'W': 'Ц', 'E': 'У', 'R': 'К', 'T': 'Е', 'Y': 'Н', 'U': 'Г', 'I': 'Ш', 'O': 'Щ', 'P': 'З',
    'A': 'Ф', 'S': 'Ы', 'D': 'В', 'F': 'А', 'G': 'П', 'H': 'Р', 'J': 'О', 'K': 'Л', 'L': 'Д',
    'Z': 'Я', 'X': 'Ч', 'C': 'С', 'V': 'М', 'B': 'И', 'N': 'Т', 'M': 'Ь'
}

RUSSIAN_TO_QWERTY = {v: k for k, v in QWERTY_TO_RUSSIAN.items()}

@dataclass
class TestCase:
    id: str
    category: str
    input: str
    expected: str
    should_convert: bool
    notes: str = ""

def convert_ru_to_en(text: str) -> str:
    return ''.join(RUSSIAN_TO_QWERTY.get(c, c) for c in text)

def load_wordlist(filename: str) -> List[str]:
    """Load words from a wordlist file."""
    path = f"../data/wordlists/{filename}"
    if not os.path.exists(path):
        print(f"Warning: {path} not found")
        return []

    words = []
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # Format: "    1→word" or just "word"
            if '→' in line:
                parts = line.split('→')
                if len(parts) >= 2:
                    word = parts[1].strip()
                    if word:
                        words.append(word)
            else:
                words.append(line)
    return words

def generate_ru_word_variants(words: List[str], existing_pairs: Set[Tuple[str, str]]) -> List[TestCase]:
    """Generate variants of Russian words."""
    tests = []
    counter = 1

    for word in words[:1000]:  # Top 1000 words
        # Skip if too short or contains non-Cyrillic
        if len(word) < 2 or not all(c in RUSSIAN_TO_QWERTY or c in ' -' for c in word):
            continue

        # Basic corrupted form
        corrupted = convert_ru_to_en(word)
        if corrupted == word:
            continue

        pair = (corrupted, word)
        if pair not in existing_pairs:
            existing_pairs.add(pair)
            tests.append(TestCase(
                id=f"wl_ru_{counter:05d}",
                category="ru_common_words",
                input=corrupted,
                expected=word,
                should_convert=True,
                notes=f"Russian word #{counter}"
            ))
            counter += 1

        # Uppercase variant
        word_upper = word.upper()
        corrupted_upper = convert_ru_to_en(word_upper)
        pair = (corrupted_upper, word_upper)
        if pair not in existing_pairs and corrupted_upper != word_upper:
            existing_pairs.add(pair)
            tests.append(TestCase(
                id=f"wl_ru_{counter:05d}",
                category="uppercase",
                input=corrupted_upper,
                expected=word_upper,
                should_convert=True,
                notes=f"Russian word uppercase"
            ))
            counter += 1

        # With punctuation variants
        for punct in ['.', ',', '!', '?', ':', ';']:
            word_punct = word + punct
            corrupted_punct = convert_ru_to_en(word) + punct
            pair = (corrupted_punct, word_punct)
            if pair not in existing_pairs:
                existing_pairs.add(pair)
                tests.append(TestCase(
                    id=f"wl_ru_{counter:05d}",
                    category="punctuation",
                    input=corrupted_punct,
                    expected=word_punct,
                    should_convert=True,
                    notes=f"Russian word with {punct}"
                ))
                counter += 1

    return tests

def generate_en_stress_tests(words: List[str], existing_pairs: Set[Tuple[str, str]]) -> List[TestCase]:
    """Generate English word stress tests (should NOT convert)."""
    tests = []
    counter = 1

    for word in words[:1500]:  # Top 1500 words
        if len(word) < 2:
            continue

        pair = (word, word)
        if pair not in existing_pairs:
            existing_pairs.add(pair)
            tests.append(TestCase(
                id=f"wl_en_{counter:05d}",
                category="stress_tests_en",
                input=word,
                expected=word,
                should_convert=False,
                notes=f"Valid English word #{counter}"
            ))
            counter += 1

        # Uppercase variant
        word_upper = word.upper()
        pair = (word_upper, word_upper)
        if pair not in existing_pairs and len(word_upper) >= 2:
            existing_pairs.add(pair)
            tests.append(TestCase(
                id=f"wl_en_{counter:05d}",
                category="stress_tests_en",
                input=word_upper,
                expected=word_upper,
                should_convert=False,
                notes=f"Valid English word uppercase"
            ))
            counter += 1

    return tests

def generate_sentence_tests(ru_words: List[str], existing_pairs: Set[Tuple[str, str]]) -> List[TestCase]:
    """Generate sentence-like combinations."""
    tests = []
    counter = 1

    # Filter to get useful words
    nouns = [w for w in ru_words if len(w) >= 4 and w not in ['что', 'это', 'как', 'так']][:100]
    verbs = ['делать', 'работать', 'думать', 'знать', 'видеть', 'понимать', 'говорить',
             'писать', 'читать', 'слушать', 'смотреть', 'искать', 'найти', 'взять']
    adjectives = ['новый', 'старый', 'большой', 'маленький', 'хороший', 'плохой',
                  'красивый', 'быстрый', 'медленный', 'важный', 'простой', 'сложный']

    # Two-word combinations
    for word1 in nouns[:50]:
        for word2 in nouns[:30]:
            if word1 != word2:
                sentence = f"{word1} {word2}"
                corrupted = convert_ru_to_en(sentence)
                pair = (corrupted, sentence)
                if pair not in existing_pairs:
                    existing_pairs.add(pair)
                    tests.append(TestCase(
                        id=f"wl_sent_{counter:05d}",
                        category="sentences",
                        input=corrupted,
                        expected=sentence,
                        should_convert=True,
                        notes="Two Russian words"
                    ))
                    counter += 1
                    if counter > 1000:
                        break
        if counter > 1000:
            break

    # Adjective + Noun combinations
    for adj in adjectives[:10]:
        for noun in nouns[:50]:
            sentence = f"{adj} {noun}"
            corrupted = convert_ru_to_en(sentence)
            pair = (corrupted, sentence)
            if pair not in existing_pairs:
                existing_pairs.add(pair)
                tests.append(TestCase(
                    id=f"wl_sent_{counter:05d}",
                    category="sentences",
                    input=corrupted,
                    expected=sentence,
                    should_convert=True,
                    notes="Adjective + Noun"
                ))
                counter += 1

    return tests

def generate_number_mixed_tests(ru_words: List[str], existing_pairs: Set[Tuple[str, str]]) -> List[TestCase]:
    """Generate number + word combinations."""
    tests = []
    counter = 1

    numbers = ['1', '2', '3', '5', '10', '100', '2024', '2025']
    short_words = [w for w in ru_words if 3 <= len(w) <= 6][:50]

    for num in numbers:
        for word in short_words:
            # Number + word (Russian)
            combo = f"{num}{word}"
            corrupted = num + convert_ru_to_en(word)
            pair = (corrupted, combo)
            if pair not in existing_pairs:
                existing_pairs.add(pair)
                tests.append(TestCase(
                    id=f"wl_num_{counter:05d}",
                    category="numbers_mixed",
                    input=corrupted,
                    expected=combo,
                    should_convert=True,
                    notes="Number + Russian word"
                ))
                counter += 1

            # Word + number (Russian)
            combo = f"{word}{num}"
            corrupted = convert_ru_to_en(word) + num
            pair = (corrupted, combo)
            if pair not in existing_pairs:
                existing_pairs.add(pair)
                tests.append(TestCase(
                    id=f"wl_num_{counter:05d}",
                    category="numbers_mixed",
                    input=corrupted,
                    expected=combo,
                    should_convert=True,
                    notes="Russian word + number"
                ))
                counter += 1

    return tests

def generate_brackets_tests(ru_words: List[str], existing_pairs: Set[Tuple[str, str]]) -> List[TestCase]:
    """Generate words with brackets/parentheses."""
    tests = []
    counter = 1

    brackets = [('(', ')'), ('[', ']'), ('"', '"'), ("'", "'")]
    words = [w for w in ru_words if 3 <= len(w) <= 8][:100]

    for open_br, close_br in brackets:
        for word in words:
            # Word in brackets
            bracketed = f"{open_br}{word}{close_br}"
            corrupted = f"{open_br}{convert_ru_to_en(word)}{close_br}"
            pair = (corrupted, bracketed)
            if pair not in existing_pairs:
                existing_pairs.add(pair)
                tests.append(TestCase(
                    id=f"wl_br_{counter:05d}",
                    category="punctuation",
                    input=corrupted,
                    expected=bracketed,
                    should_convert=True,
                    notes=f"Russian word in {open_br}{close_br}"
                ))
                counter += 1

    return tests

def generate_repeated_char_tests(existing_pairs: Set[Tuple[str, str]]) -> List[TestCase]:
    """Generate tests with repeated characters (typos)."""
    tests = []
    counter = 1

    # Russian words with common typo patterns
    words_with_typos = [
        ("привееет", "привееет"),  # Extended greeting
        ("даааа", "даааа"),  # Emphatic yes
        ("неееет", "неееет"),  # Emphatic no
        ("оооо", "оооо"),  # Reaction
        ("аааа", "аааа"),  # Scream
    ]

    for word, expected in words_with_typos:
        corrupted = convert_ru_to_en(word)
        pair = (corrupted, expected)
        if pair not in existing_pairs:
            existing_pairs.add(pair)
            tests.append(TestCase(
                id=f"wl_typo_{counter:05d}",
                category="edge_cases",
                input=corrupted,
                expected=expected,
                should_convert=True,
                notes="Repeated characters"
            ))
            counter += 1

    return tests

def main():
    """Main function."""
    corpus_path = "../test_corpus_v2.json"

    # Load existing tests
    if os.path.exists(corpus_path):
        with open(corpus_path, 'r', encoding='utf-8') as f:
            existing_tests = json.load(f)
        print(f"Existing tests: {len(existing_tests)}")
    else:
        existing_tests = []
        print("No existing corpus found")

    existing_pairs = {(t['input'], t['expected']) for t in existing_tests}

    # Load wordlists
    ru_words = load_wordlist("ru_top_2000.txt")
    en_words = load_wordlist("en_top_2000.txt")
    print(f"Loaded {len(ru_words)} Russian words, {len(en_words)} English words")

    # Generate tests
    all_new_tests = []

    generators = [
        ("Russian word variants", lambda: generate_ru_word_variants(ru_words, existing_pairs)),
        ("English stress tests", lambda: generate_en_stress_tests(en_words, existing_pairs)),
        ("Sentence combinations", lambda: generate_sentence_tests(ru_words, existing_pairs)),
        ("Number + word", lambda: generate_number_mixed_tests(ru_words, existing_pairs)),
        ("Brackets/quotes", lambda: generate_brackets_tests(ru_words, existing_pairs)),
        ("Repeated chars", lambda: generate_repeated_char_tests(existing_pairs)),
    ]

    for name, gen_func in generators:
        tests = gen_func()
        print(f"  {name}: {len(tests)} tests")
        all_new_tests.extend(tests)

    print(f"\nTotal new tests: {len(all_new_tests)}")

    # Merge
    merged = existing_tests + [asdict(t) for t in all_new_tests]

    # Save
    with open(corpus_path, 'w', encoding='utf-8') as f:
        json.dump(merged, f, ensure_ascii=False, indent=2)

    print(f"\nTotal tests: {len(merged)}")
    print(f"Saved to: {os.path.abspath(corpus_path)}")

    # Statistics
    should_convert = sum(1 for t in merged if t['should_convert'])
    should_not = len(merged) - should_convert
    print(f"\nStatistics:")
    print(f"  Should convert: {should_convert} ({100*should_convert/len(merged):.1f}%)")
    print(f"  Should NOT convert: {should_not} ({100*should_not/len(merged):.1f}%)")

    # Category breakdown
    categories = {}
    for t in merged:
        cat = t['category']
        categories[cat] = categories.get(cat, 0) + 1
    print(f"\nCategory breakdown:")
    for cat, count in sorted(categories.items(), key=lambda x: -x[1]):
        print(f"  {cat}: {count}")

if __name__ == "__main__":
    main()
