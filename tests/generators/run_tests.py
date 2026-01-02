#!/usr/bin/env python3
"""
Test runner for TextSwitcher CLI.
Runs all tests from corpus against TextSwitcherCLI and reports accuracy.
"""

import json
import os
import subprocess
import re
import sys
from typing import List, Dict, Tuple
from collections import Counter
from dataclasses import dataclass
from concurrent.futures import ThreadPoolExecutor, as_completed
import time

CLI_PATH = "/Users/macbookpro/PycharmProjects/Dictum/build/Build/Products/Debug/TextSwitcherCLI"
CORPUS_PATH = "../test_corpus_v2.json"

@dataclass
class TestResult:
    test_id: str
    category: str
    input_text: str
    expected: str
    actual: str
    should_convert: bool
    passed: bool
    error: str = ""

def run_cli(input_text: str, timeout: int = 5) -> Tuple[str, str]:
    """Run TextSwitcherCLI with input and return (output, error)."""
    try:
        result = subprocess.run(
            [CLI_PATH, input_text],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return "", "TIMEOUT"
    except Exception as e:
        return "", str(e)

def parse_cli_output(output: str) -> str:
    """Extract the converted result from CLI output."""
    # Look for line: "  Выход: "..."" or similar
    lines = output.strip().split('\n')
    for line in lines:
        # Match pattern: Выход: "result"
        match = re.search(r'Выход:\s*"(.+)"', line)
        if match:
            return match.group(1)

    # Fallback: look for last non-empty line that looks like result
    for line in reversed(lines):
        line = line.strip()
        if line and not line.startswith('═') and not line.startswith('─') and not line.startswith('│'):
            # Try to extract from quotes
            match = re.search(r'"([^"]+)"', line)
            if match:
                return match.group(1)

    return ""

def run_single_test(test: Dict) -> TestResult:
    """Run a single test and return result."""
    test_id = test['id']
    category = test['category']
    input_text = test['input']
    expected = test['expected']
    should_convert = test['should_convert']

    output, error = run_cli(input_text)

    # stderr is just logs, not real errors - only check if output is empty
    if not output and error == "TIMEOUT":
        return TestResult(
            test_id=test_id,
            category=category,
            input_text=input_text,
            expected=expected,
            actual="",
            should_convert=should_convert,
            passed=False,
            error="TIMEOUT"
        )

    actual = parse_cli_output(output)

    # Determine if test passed
    if should_convert:
        # Expected: input should be converted to expected
        passed = actual == expected
    else:
        # Expected: input should NOT be converted (remain the same)
        passed = actual == input_text

    return TestResult(
        test_id=test_id,
        category=category,
        input_text=input_text,
        expected=expected,
        actual=actual,
        should_convert=should_convert,
        passed=passed
    )

def run_batch_test(tests: List[Dict], batch_size: int = 100) -> List[TestResult]:
    """Run tests in batches for progress reporting."""
    results = []
    total = len(tests)

    for i in range(0, total, batch_size):
        batch = tests[i:i+batch_size]
        for test in batch:
            result = run_single_test(test)
            results.append(result)

        # Progress report
        done = min(i + batch_size, total)
        passed = sum(1 for r in results if r.passed)
        accuracy = 100 * passed / len(results) if results else 0
        print(f"\r  Progress: {done}/{total} ({100*done/total:.1f}%) | Accuracy: {accuracy:.2f}%", end='', flush=True)

    print()  # New line after progress
    return results

def main():
    print("═" * 70)
    print("  TextSwitcher Test Runner")
    print("═" * 70)

    # Check CLI exists
    if not os.path.exists(CLI_PATH):
        print(f"Error: CLI not found at {CLI_PATH}")
        print("Run: xcodebuild -scheme TextSwitcherCLI -configuration Debug")
        sys.exit(1)

    # Load corpus
    if not os.path.exists(CORPUS_PATH):
        print(f"Error: Corpus not found at {CORPUS_PATH}")
        sys.exit(1)

    with open(CORPUS_PATH, 'r', encoding='utf-8') as f:
        tests = json.load(f)

    print(f"\n  Total tests: {len(tests):,}")
    print(f"  CLI: {CLI_PATH}")
    print()

    # Ask for sample or full run
    if len(sys.argv) > 1 and sys.argv[1] == '--sample':
        # Sample 500 random tests
        import random
        random.seed(42)
        tests = random.sample(tests, min(500, len(tests)))
        print(f"  Running SAMPLE of {len(tests)} tests...")
    elif len(sys.argv) > 1 and sys.argv[1] == '--quick':
        # Quick test with first 100
        tests = tests[:100]
        print(f"  Running QUICK test with {len(tests)} tests...")
    else:
        print(f"  Running ALL {len(tests):,} tests (this may take a while)...")
        print(f"  Tip: Use --sample for 500 random tests, --quick for first 100")

    print()

    # Run tests
    start_time = time.time()
    results = run_batch_test(tests)
    elapsed = time.time() - start_time

    # Calculate statistics
    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    accuracy = 100 * passed / len(results) if results else 0

    print()
    print("═" * 70)
    print("  RESULTS")
    print("═" * 70)
    print(f"\n  Total:    {len(results):,}")
    print(f"  Passed:   {passed:,} ({accuracy:.2f}%)")
    print(f"  Failed:   {failed:,} ({100-accuracy:.2f}%)")
    print(f"  Time:     {elapsed:.1f}s ({len(results)/elapsed:.1f} tests/sec)")

    # Category breakdown for failures
    if failed > 0:
        print(f"\n  Failures by category:")
        failures_by_cat = Counter(r.category for r in results if not r.passed)
        for cat, count in failures_by_cat.most_common(10):
            cat_total = sum(1 for r in results if r.category == cat)
            cat_passed = sum(1 for r in results if r.category == cat and r.passed)
            cat_accuracy = 100 * cat_passed / cat_total if cat_total else 0
            print(f"    {cat}: {count} failed ({cat_accuracy:.1f}% accuracy)")

        # Show sample failures
        print(f"\n  Sample failures (first 10):")
        failures = [r for r in results if not r.passed][:10]
        for r in failures:
            convert_str = "CONVERT" if r.should_convert else "NO CONV"
            print(f"    [{r.category}] [{convert_str}]")
            print(f"      Input:    '{r.input_text}'")
            print(f"      Expected: '{r.expected}'")
            print(f"      Actual:   '{r.actual}'")
            if r.error:
                print(f"      Error:    {r.error}")
            print()

    # Save detailed results
    results_file = "../test_results.json"
    results_data = [
        {
            'test_id': r.test_id,
            'category': r.category,
            'input': r.input_text,
            'expected': r.expected,
            'actual': r.actual,
            'should_convert': r.should_convert,
            'passed': r.passed,
            'error': r.error
        }
        for r in results
    ]

    with open(results_file, 'w', encoding='utf-8') as f:
        json.dump(results_data, f, ensure_ascii=False, indent=2)

    print(f"\n  Detailed results saved to: {results_file}")
    print("═" * 70)

    # Exit code based on accuracy
    if accuracy >= 95:
        print("\n  ✅ PASS (accuracy >= 95%)")
        sys.exit(0)
    else:
        print("\n  ❌ FAIL (accuracy < 95%)")
        sys.exit(1)

if __name__ == "__main__":
    main()
