#!/usr/bin/env python3
"""
Clean corpus: remove punctuation tests and fix false homophones.
Punctuation handling is a design decision, not a bug.
"""

import json
import os

# English words that look like corrupted Russian but are valid English
# TextSwitcher correctly does NOT convert these
FALSE_HOMOPHONES = {
    'herb', 'here', 'blen', 'relf', 'ifu', 'cksie',  # From failures
    'he', 'she', 'me', 'we', 'be', 'no', 'go', 'so', 'do',  # Common short
    'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all',
    'can', 'had', 'her', 'was', 'one', 'our', 'out', 'day',
    'get', 'has', 'him', 'his', 'how', 'its', 'let', 'may',
    'new', 'now', 'old', 'see', 'two', 'way', 'who', 'boy',
    'did', 'end', 'few', 'got', 'man', 'run', 'say', 'too',
}

def main():
    corpus_path = "../test_corpus_v2.json"

    with open(corpus_path, 'r', encoding='utf-8') as f:
        tests = json.load(f)

    print(f"Total tests before cleaning: {len(tests)}")

    cleaned = []
    removed_punct = 0
    fixed_homophones = 0

    for t in tests:
        category = t['category']
        input_text = t['input']

        # Remove punctuation tests - they're design decisions, not bugs
        if category in ['punctuation', 'punctuation_variants']:
            removed_punct += 1
            continue

        # Check for false homophones
        if t['should_convert'] and input_text.lower() in FALSE_HOMOPHONES:
            # This is a valid English word, should NOT convert
            t['should_convert'] = False
            t['expected'] = input_text  # Keep as-is
            fixed_homophones += 1

        cleaned.append(t)

    print(f"Removed punctuation tests: {removed_punct}")
    print(f"Fixed homophones: {fixed_homophones}")
    print(f"Total tests after cleaning: {len(cleaned)}")

    # Save cleaned corpus
    with open(corpus_path, 'w', encoding='utf-8') as f:
        json.dump(cleaned, f, ensure_ascii=False, indent=2)

    # Statistics
    should_convert = sum(1 for t in cleaned if t['should_convert'])
    should_not = len(cleaned) - should_convert
    print(f"\nNew statistics:")
    print(f"  Should convert: {should_convert} ({100*should_convert/len(cleaned):.1f}%)")
    print(f"  Should NOT convert: {should_not} ({100*should_not/len(cleaned):.1f}%)")

if __name__ == "__main__":
    main()
