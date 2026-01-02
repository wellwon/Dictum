#!/usr/bin/env python3
"""
Fix corpus issues: en_common tests incorrectly marked as should_convert=True.
"""

import json
import os

def is_cyrillic(char: str) -> bool:
    """Check if character is Cyrillic."""
    return '\u0400' <= char <= '\u04FF' or char == 'ё' or char == 'Ё'

def has_cyrillic(text: str) -> bool:
    """Check if text contains any Cyrillic characters."""
    return any(is_cyrillic(c) for c in text)

def main():
    corpus_path = "../test_corpus_v2.json"

    with open(corpus_path, 'r', encoding='utf-8') as f:
        tests = json.load(f)

    print(f"Total tests before fix: {len(tests)}")

    fixed_count = 0
    removed_count = 0
    fixed_tests = []

    for t in tests:
        should_convert = t['should_convert']
        expected = t['expected']
        input_text = t['input']
        category = t['category']

        # Skip tests where expected has Cyrillic (these are correct)
        if has_cyrillic(expected):
            fixed_tests.append(t)
            continue

        # For tests with English expected text
        if should_convert:
            # If expected is English and should_convert=True, it's wrong
            # Check if input is corrupted English (typed on Russian layout)
            # These tests should be should_convert=False
            if category in ['en_common_words', 'en_common']:
                # These tests claim English words were typed on Russian layout
                # and should convert to English - but that's backwards
                # Remove these tests as they don't make sense
                removed_count += 1
                continue
            else:
                # Other categories with English expected - might be code-switching
                # Keep but mark as should_convert=False
                if input_text == expected:
                    t['should_convert'] = False
                    fixed_count += 1

        fixed_tests.append(t)

    print(f"Fixed tests: {fixed_count}")
    print(f"Removed tests: {removed_count}")
    print(f"Total tests after fix: {len(fixed_tests)}")

    # Save
    with open(corpus_path, 'w', encoding='utf-8') as f:
        json.dump(fixed_tests, f, ensure_ascii=False, indent=2)

    # Statistics
    should_convert = sum(1 for t in fixed_tests if t['should_convert'])
    should_not = len(fixed_tests) - should_convert
    print(f"\nNew statistics:")
    print(f"  Should convert: {should_convert} ({100*should_convert/len(fixed_tests):.1f}%)")
    print(f"  Should NOT convert: {should_not} ({100*should_not/len(fixed_tests):.1f}%)")

if __name__ == "__main__":
    main()
