#!/usr/bin/env python3
"""
batch_test_switcher.py

Batch-тестировщик для TextSwitcher.
Запускает тесты из JSON корпуса через TextSwitcherCLI и собирает метрики.
"""

import json
import subprocess
import re
import sys
import csv
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass, field
from typing import Optional
from collections import defaultdict


# ============================================================
# КОНФИГУРАЦИЯ
# ============================================================

PROJECT_ROOT = Path(__file__).parent.parent
CLI_PATH = PROJECT_ROOT / "build" / "Build" / "Products" / "Debug" / "TextSwitcherCLI"
TEST_CORPUS_PATH = PROJECT_ROOT / "tests" / "test_corpus.json"
RESULTS_DIR = PROJECT_ROOT / "tests" / "results"


# ============================================================
# DATA CLASSES
# ============================================================

@dataclass
class TestResult:
    """Результат одного теста."""
    test_id: str
    category: str
    input_text: str
    expected: str
    actual: str
    passed: bool
    should_convert: bool
    was_converted: bool
    # Детали от CLI
    detected_layout: str = ""
    ngram_ratio: float = 0.0
    spellcheck_original: bool = False
    spellcheck_converted: bool = False
    is_buzzword: bool = False
    validation_result: str = ""  # KEEP или SWITCH
    reason: str = ""
    # Классификация ошибки
    error_type: str = ""


@dataclass
class CategoryStats:
    """Статистика по категории."""
    total: int = 0
    passed: int = 0
    failed: int = 0
    true_positives: int = 0   # Правильно конвертировали
    true_negatives: int = 0   # Правильно НЕ конвертировали
    false_positives: int = 0  # Конвертировали, но не надо было
    false_negatives: int = 0  # Не конвертировали, но надо было


@dataclass
class OverallStats:
    """Общая статистика."""
    total: int = 0
    passed: int = 0
    failed: int = 0
    accuracy: float = 0.0
    precision: float = 0.0
    recall: float = 0.0
    f1: float = 0.0
    categories: dict = field(default_factory=dict)


# ============================================================
# CLI RUNNER
# ============================================================

def run_cli(text: str) -> Optional[str]:
    """Запускает TextSwitcherCLI с текстом и возвращает вывод."""
    try:
        result = subprocess.run(
            [str(CLI_PATH), text],
            capture_output=True,
            text=True,
            timeout=30
        )
        return result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        print(f"  ⚠️ Timeout для: {text[:50]}...")
        return None
    except FileNotFoundError:
        print(f"❌ CLI не найден: {CLI_PATH}")
        print("   Запустите: xcodebuild -project Dictum.xcodeproj -scheme TextSwitcherCLI -configuration Debug -derivedDataPath ./build build")
        sys.exit(1)


def parse_cli_output(output: str, input_word: str) -> dict:
    """
    Парсит вывод CLI и извлекает детали валидации.

    Пример вывода для слова:
      ┌─ Слово: "ghbdtn"
      │  Раскладка: QWERTY
      │  Конвертация: "ghbdtn" → "привет"
      │  N-gram:
      │    Original (qwerty): -12.34
      │    Converted (russian): -5.67
      │    Ratio: 15.23
      │  SpellChecker:
      │    "ghbdtn" (qwerty): ✗ невалидно
      │    "привет" (russian): ✓ валидно
      │  TechBuzzword: ✓ найдено — НЕ конвертировать
      └─ РЕЗУЛЬТАТ: 🔵 KEEP (оставить как есть)
    """
    info = {
        "detected_layout": "",
        "converted_word": "",
        "ngram_original": 0.0,
        "ngram_converted": 0.0,
        "ngram_ratio": 0.0,
        "spellcheck_original": False,
        "spellcheck_converted": False,
        "is_buzzword": False,
        "result": "",  # KEEP или SWITCH
        "final_word": "",
        "reason": ""
    }

    # Детектим раскладку
    layout_match = re.search(r'Раскладка:\s*(\w+)', output)
    if layout_match:
        info["detected_layout"] = layout_match.group(1).lower()

    # Конвертация
    conv_match = re.search(r'Конвертация:\s*"([^"]+)"\s*→\s*"([^"]+)"', output)
    if conv_match:
        info["converted_word"] = conv_match.group(2)

    # N-gram scores (handle -inf, inf, nan)
    def safe_float(s: str) -> float:
        """Safely parse float including -inf, inf, nan."""
        s = s.strip().lower()
        if s in ("-inf", "-infinity"):
            return float("-inf")
        if s in ("inf", "infinity"):
            return float("inf")
        if s == "nan":
            return float("nan")
        return float(s)

    # Pattern: -inf first, then inf, then nan, then numbers
    num_pattern = r'(-inf|inf|nan|[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?)'

    ratio_match = re.search(r'Ratio:\s*' + num_pattern, output, re.IGNORECASE)
    if ratio_match:
        info["ngram_ratio"] = safe_float(ratio_match.group(1))

    orig_match = re.search(r'Original\s*\([^)]+\):\s*' + num_pattern, output, re.IGNORECASE)
    if orig_match:
        info["ngram_original"] = safe_float(orig_match.group(1))

    conv_score_match = re.search(r'Converted\s*\([^)]+\):\s*' + num_pattern, output, re.IGNORECASE)
    if conv_score_match:
        info["ngram_converted"] = safe_float(conv_score_match.group(1))

    # SpellChecker
    if '✓ валидно' in output:
        # Проверяем какой именно валидный
        lines = output.split('\n')
        for line in lines:
            if '✓ валидно' in line:
                if 'qwerty' in line.lower() or 'english' in line.lower():
                    info["spellcheck_original"] = True
                elif 'russian' in line.lower():
                    info["spellcheck_converted"] = True

    # TechBuzzword
    if 'TechBuzzword: ✓' in output or 'TechBuzzword:.*найдено' in output:
        info["is_buzzword"] = True

    # Результат
    if 'KEEP' in output:
        info["result"] = "KEEP"
        info["final_word"] = input_word
    elif 'SWITCH' in output:
        info["result"] = "SWITCH"
        info["final_word"] = info["converted_word"]
        # Извлекаем reason
        reason_match = re.search(r'SWITCH.*\(([^)]+)\)', output)
        if reason_match:
            info["reason"] = reason_match.group(1)

    # Финальный результат из секции ИТОГОВЫЙ РЕЗУЛЬТАТ
    final_match = re.search(r'Выход:\s*"([^"]+)"', output)
    if final_match:
        info["final_word"] = final_match.group(1)

    return info


def get_final_output_for_sentence(output: str) -> str:
    """Извлекает финальный результат для предложения."""
    # Ищем строку "Выход: ..."
    match = re.search(r'Выход:\s*"([^"]+)"', output)
    if match:
        return match.group(1)
    return ""


# ============================================================
# TEST RUNNER
# ============================================================

def run_single_test(test: dict, category: str) -> TestResult:
    """Запускает один тест и возвращает результат."""
    test_id = test["id"]
    corrupted = test["corrupted"]
    expected = test["expected"]
    should_convert = test.get("should_convert", True)

    # Запускаем CLI
    output = run_cli(corrupted)
    if output is None:
        return TestResult(
            test_id=test_id,
            category=category,
            input_text=corrupted,
            expected=expected,
            actual="[TIMEOUT]",
            passed=False,
            should_convert=should_convert,
            was_converted=False,
            error_type="timeout"
        )

    # Парсим вывод
    # Для предложений используем финальный вывод
    if ' ' in corrupted:
        actual = get_final_output_for_sentence(output)
    else:
        info = parse_cli_output(output, corrupted)
        actual = info.get("final_word", corrupted)

    # Определяем была ли конвертация
    was_converted = actual != corrupted

    # Проверяем результат
    # Для buzzwords и keep-cases: actual должен == corrupted (не конвертировать)
    # Для остальных: actual должен == expected
    if should_convert:
        passed = actual == expected
    else:
        passed = actual == corrupted  # Не должно было меняться

    # Классифицируем ошибку
    error_type = ""
    if not passed:
        if should_convert and not was_converted:
            error_type = "false_negative"  # Надо было конвертировать, но не конвертировали
        elif not should_convert and was_converted:
            error_type = "false_positive"  # Не надо было, но конвертировали
        elif was_converted and actual != expected:
            error_type = "wrong_conversion"  # Конвертировали неправильно
        else:
            error_type = "unknown"

    # Собираем детали
    info = parse_cli_output(output, corrupted) if ' ' not in corrupted else {}

    return TestResult(
        test_id=test_id,
        category=category,
        input_text=corrupted,
        expected=expected,
        actual=actual,
        passed=passed,
        should_convert=should_convert,
        was_converted=was_converted,
        detected_layout=info.get("detected_layout", ""),
        ngram_ratio=info.get("ngram_ratio", 0.0),
        spellcheck_original=info.get("spellcheck_original", False),
        spellcheck_converted=info.get("spellcheck_converted", False),
        is_buzzword=info.get("is_buzzword", False),
        validation_result=info.get("result", ""),
        reason=info.get("reason", ""),
        error_type=error_type
    )


def run_tests(corpus: dict, limit: int = 0, category_filter: str = "") -> list[TestResult]:
    """Запускает все тесты из корпуса."""
    results = []
    total = corpus.get("total_tests", 0)

    if limit > 0:
        print(f"🧪 Запуск тестов (лимит: {limit} из {total})...")
    else:
        print(f"🧪 Запуск всех {total} тестов...")

    count = 0
    for cat_name, cat_data in corpus["categories"].items():
        if category_filter and cat_name != category_filter:
            continue

        tests = cat_data["tests"]
        print(f"\n📁 Категория: {cat_name} ({len(tests)} тестов)")

        for i, test in enumerate(tests):
            if limit > 0 and count >= limit:
                break

            result = run_single_test(test, cat_name)
            results.append(result)
            count += 1

            # Прогресс
            status = "✓" if result.passed else "✗"
            if (i + 1) % 50 == 0 or i == len(tests) - 1:
                passed = sum(1 for r in results if r.category == cat_name and r.passed)
                print(f"  [{i+1}/{len(tests)}] Passed: {passed}")

        if limit > 0 and count >= limit:
            break

    return results


# ============================================================
# METRICS CALCULATION
# ============================================================

def calculate_stats(results: list[TestResult]) -> OverallStats:
    """Вычисляет статистику по результатам."""
    stats = OverallStats()
    stats.total = len(results)
    stats.passed = sum(1 for r in results if r.passed)
    stats.failed = stats.total - stats.passed

    # Per-category stats
    cat_stats: dict[str, CategoryStats] = defaultdict(CategoryStats)

    # True/False Positives/Negatives
    tp = fp = tn = fn = 0

    for r in results:
        cat = cat_stats[r.category]
        cat.total += 1

        if r.passed:
            cat.passed += 1
        else:
            cat.failed += 1

        # TP/TN/FP/FN
        if r.should_convert:
            if r.was_converted and r.passed:
                tp += 1
                cat.true_positives += 1
            elif not r.was_converted:
                fn += 1
                cat.false_negatives += 1
            else:
                # Конвертировали, но неправильно
                fp += 1
                cat.false_positives += 1
        else:
            if not r.was_converted:
                tn += 1
                cat.true_negatives += 1
            else:
                fp += 1
                cat.false_positives += 1

    # Overall metrics
    stats.accuracy = stats.passed / stats.total if stats.total > 0 else 0
    stats.precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    stats.recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    stats.f1 = 2 * stats.precision * stats.recall / (stats.precision + stats.recall) if (stats.precision + stats.recall) > 0 else 0

    stats.categories = dict(cat_stats)

    return stats


# ============================================================
# REPORT GENERATION
# ============================================================

def generate_report(results: list[TestResult], stats: OverallStats, output_dir: Path):
    """Генерирует отчёты."""
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # 1. JSON с полными результатами
    results_json = output_dir / f"results_{timestamp}.json"
    with open(results_json, 'w', encoding='utf-8') as f:
        json.dump([{
            "test_id": r.test_id,
            "category": r.category,
            "input": r.input_text,
            "expected": r.expected,
            "actual": r.actual,
            "passed": r.passed,
            "should_convert": r.should_convert,
            "was_converted": r.was_converted,
            "error_type": r.error_type,
            "ngram_ratio": r.ngram_ratio,
            "detected_layout": r.detected_layout,
        } for r in results], f, ensure_ascii=False, indent=2)
    print(f"\n📄 Результаты: {results_json}")

    # 2. CSV с ошибками
    errors = [r for r in results if not r.passed]
    errors_csv = output_dir / f"errors_{timestamp}.csv"
    with open(errors_csv, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow([
            "id", "category", "input", "expected", "actual",
            "error_type", "ngram_ratio", "detected_layout", "reason"
        ])
        for r in errors:
            writer.writerow([
                r.test_id, r.category, r.input_text, r.expected, r.actual,
                r.error_type, r.ngram_ratio, r.detected_layout, r.reason
            ])
    print(f"📄 Ошибки: {errors_csv}")

    # 3. Markdown отчёт
    report_md = output_dir / f"report_{timestamp}.md"
    with open(report_md, 'w', encoding='utf-8') as f:
        f.write("# TextSwitcher Validation Report\n\n")
        f.write(f"**Дата:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        f.write("## Summary\n\n")
        f.write(f"- **Total tests:** {stats.total}\n")
        f.write(f"- **Passed:** {stats.passed} ({stats.accuracy*100:.1f}%)\n")
        f.write(f"- **Failed:** {stats.failed}\n\n")

        f.write("### Metrics\n\n")
        f.write(f"| Metric | Value |\n")
        f.write(f"|--------|-------|\n")
        f.write(f"| Accuracy | {stats.accuracy*100:.1f}% |\n")
        f.write(f"| Precision | {stats.precision*100:.1f}% |\n")
        f.write(f"| Recall | {stats.recall*100:.1f}% |\n")
        f.write(f"| F1 Score | {stats.f1*100:.1f}% |\n\n")

        f.write("## By Category\n\n")
        f.write("| Category | Tests | Passed | Failed | Accuracy | FP | FN |\n")
        f.write("|----------|-------|--------|--------|----------|----|----|")

        for cat_name, cat_stats in sorted(stats.categories.items()):
            acc = cat_stats.passed / cat_stats.total * 100 if cat_stats.total > 0 else 0
            f.write(f"\n| {cat_name} | {cat_stats.total} | {cat_stats.passed} | {cat_stats.failed} | {acc:.1f}% | {cat_stats.false_positives} | {cat_stats.false_negatives} |")

        f.write("\n\n## Error Analysis\n\n")

        # Группируем ошибки по типу
        error_by_type = defaultdict(list)
        for r in errors:
            error_by_type[r.error_type].append(r)

        for error_type, error_list in sorted(error_by_type.items(), key=lambda x: -len(x[1])):
            pct = len(error_list) / len(errors) * 100 if errors else 0
            f.write(f"### {error_type} ({len(error_list)} errors, {pct:.1f}%)\n\n")

            # Показываем топ-10 примеров
            f.write("| Input | Expected | Actual | Category |\n")
            f.write("|-------|----------|--------|----------|")
            for r in error_list[:10]:
                f.write(f"\n| `{r.input_text[:30]}` | `{r.expected[:30]}` | `{r.actual[:30]}` | {r.category} |")
            f.write("\n\n")

        # Топ проблемных категорий
        f.write("## Problem Categories\n\n")
        problem_cats = sorted(
            [(name, cs) for name, cs in stats.categories.items() if cs.failed > 0],
            key=lambda x: -x[1].failed
        )
        for name, cs in problem_cats[:5]:
            f.write(f"### {name}\n")
            f.write(f"- Failed: {cs.failed}/{cs.total} ({cs.failed/cs.total*100:.1f}%)\n")
            f.write(f"- False Positives: {cs.false_positives}\n")
            f.write(f"- False Negatives: {cs.false_negatives}\n\n")

    print(f"📄 Отчёт: {report_md}")

    # 4. Краткая сводка в консоль
    print("\n" + "="*60)
    print("  SUMMARY")
    print("="*60)
    print(f"  Total:     {stats.total}")
    print(f"  Passed:    {stats.passed} ({stats.accuracy*100:.1f}%)")
    print(f"  Failed:    {stats.failed}")
    print(f"  Accuracy:  {stats.accuracy*100:.1f}%")
    print(f"  Precision: {stats.precision*100:.1f}%")
    print(f"  Recall:    {stats.recall*100:.1f}%")
    print(f"  F1:        {stats.f1*100:.1f}%")
    print("="*60)

    # Топ ошибок по категориям
    if errors:
        print("\nTop error categories:")
        for name, cs in problem_cats[:5]:
            print(f"  - {name}: {cs.failed} errors ({cs.failed/cs.total*100:.1f}%)")


# ============================================================
# MAIN
# ============================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(description="Batch test TextSwitcher")
    parser.add_argument("--limit", "-l", type=int, default=0,
                        help="Limit number of tests (0 = all)")
    parser.add_argument("--category", "-c", type=str, default="",
                        help="Run only specific category")
    parser.add_argument("--corpus", type=str, default=str(TEST_CORPUS_PATH),
                        help="Path to test corpus JSON")
    args = parser.parse_args()

    # Проверяем CLI
    if not CLI_PATH.exists():
        print(f"❌ TextSwitcherCLI не найден: {CLI_PATH}")
        print("\n  Соберите CLI:")
        print("  xcodebuild -project Dictum.xcodeproj -scheme TextSwitcherCLI -configuration Debug -derivedDataPath ./build build")
        sys.exit(1)

    # Загружаем корпус
    corpus_path = Path(args.corpus)
    if not corpus_path.exists():
        print(f"❌ Тестовый корпус не найден: {corpus_path}")
        print("\n  Сгенерируйте корпус:")
        print("  python3 scripts/generate_test_corpus.py")
        sys.exit(1)

    with open(corpus_path, encoding='utf-8') as f:
        corpus = json.load(f)

    print(f"📦 Загружен корпус: {corpus.get('total_tests', 0)} тестов")

    # Запускаем тесты
    results = run_tests(corpus, limit=args.limit, category_filter=args.category)

    # Вычисляем статистику
    stats = calculate_stats(results)

    # Генерируем отчёты
    generate_report(results, stats, RESULTS_DIR)


if __name__ == "__main__":
    main()
