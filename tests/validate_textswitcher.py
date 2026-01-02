#!/usr/bin/env python3
"""
TextSwitcher Validation Script
Запускает CLI тесты и генерирует отчёт
"""

import json
import subprocess
import os
import sys
from datetime import datetime
from pathlib import Path
from collections import defaultdict

# Пути
PROJECT_DIR = Path(__file__).parent.parent
CLI_PATH = PROJECT_DIR / "build" / "Build" / "Products" / "Debug" / "TextSwitcherCLI"
CORPUS_PATH = PROJECT_DIR / "tests" / "test_corpus.json"
RESULTS_DIR = PROJECT_DIR / "tests" / "results"


def run_cli(text: str) -> str:
    """Запускает CLI и возвращает результат конвертации"""
    try:
        result = subprocess.run(
            [str(CLI_PATH), text],
            capture_output=True,
            text=True,
            timeout=10
        )
        # Парсим вывод CLI — ищем строку "Выход:"
        for line in result.stdout.split('\n'):
            if 'Выход:' in line:
                # Выход: "текст"
                start = line.find('"') + 1
                end = line.rfind('"')
                if start > 0 and end > start:
                    return line[start:end]
        return text  # Если не нашли — возвращаем оригинал
    except subprocess.TimeoutExpired:
        return text
    except Exception as e:
        print(f"Error running CLI: {e}")
        return text


def load_corpus() -> dict:
    """Загружает тестовый корпус"""
    with open(CORPUS_PATH, 'r', encoding='utf-8') as f:
        return json.load(f)


def run_tests() -> dict:
    """Запускает все тесты и возвращает результаты"""
    corpus = load_corpus()
    results = {
        'timestamp': datetime.now().isoformat(),
        'total': 0,
        'passed': 0,
        'failed': 0,
        'errors': [],
        'by_category': defaultdict(lambda: {'total': 0, 'passed': 0, 'failed': 0, 'fp': 0, 'fn': 0}),
        'error_types': defaultdict(int)
    }

    for category_name, category_data in corpus.get('categories', {}).items():
        tests = category_data.get('tests', [])

        for test in tests:
            results['total'] += 1
            results['by_category'][category_name]['total'] += 1

            input_text = test.get('corrupted', test.get('input', ''))
            expected = test.get('expected', '')
            should_convert = test.get('should_convert', True)
            test_id = test.get('id', f'unknown_{results["total"]}')

            # Запускаем CLI
            actual = run_cli(input_text)

            # Сравниваем
            if actual == expected:
                results['passed'] += 1
                results['by_category'][category_name]['passed'] += 1
            else:
                results['failed'] += 1
                results['by_category'][category_name]['failed'] += 1

                # Определяем тип ошибки
                if should_convert:
                    if actual == input_text:
                        error_type = 'false_negative'
                        results['by_category'][category_name]['fn'] += 1
                    else:
                        error_type = 'wrong_conversion'
                else:
                    error_type = 'false_positive'
                    results['by_category'][category_name]['fp'] += 1

                results['error_types'][error_type] += 1
                results['errors'].append({
                    'id': test_id,
                    'category': category_name,
                    'input': input_text,
                    'expected': expected,
                    'actual': actual,
                    'error_type': error_type
                })

    return results


def calculate_metrics(results: dict) -> dict:
    """Вычисляет precision, recall, F1"""
    total = results['total']
    passed = results['passed']

    # TP = корректные конвертации
    # FP = ложные конвертации (не должны были конвертировать)
    # FN = пропущенные конвертации (должны были конвертировать)

    fp = results['error_types'].get('false_positive', 0)
    fn = results['error_types'].get('false_negative', 0)
    tp = passed

    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    return {
        'accuracy': passed / total if total > 0 else 0,
        'precision': precision,
        'recall': recall,
        'f1': f1
    }


def generate_report(results: dict) -> str:
    """Генерирует Markdown отчёт"""
    metrics = calculate_metrics(results)

    report = f"""# TextSwitcher Validation Report

**Дата:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

## Summary

- **Total tests:** {results['total']}
- **Passed:** {results['passed']} ({metrics['accuracy']*100:.1f}%)
- **Failed:** {results['failed']}

### Metrics

| Metric | Value |
|--------|-------|
| Accuracy | {metrics['accuracy']*100:.1f}% |
| Precision | {metrics['precision']*100:.1f}% |
| Recall | {metrics['recall']*100:.1f}% |
| F1 Score | {metrics['f1']*100:.1f}% |

## By Category

| Category | Tests | Passed | Failed | Accuracy | FP | FN |
|----------|-------|--------|--------|----------|----|----|
"""

    for cat, data in sorted(results['by_category'].items()):
        acc = data['passed'] / data['total'] * 100 if data['total'] > 0 else 0
        report += f"| {cat} | {data['total']} | {data['passed']} | {data['failed']} | {acc:.1f}% | {data['fp']} | {data['fn']} |\n"

    report += "\n## Error Analysis\n\n"

    # Группируем ошибки по типам
    errors_by_type = defaultdict(list)
    for error in results['errors']:
        errors_by_type[error['error_type']].append(error)

    for error_type, errors in sorted(errors_by_type.items(), key=lambda x: -len(x[1])):
        pct = len(errors) / results['failed'] * 100 if results['failed'] > 0 else 0
        report += f"### {error_type} ({len(errors)} errors, {pct:.1f}%)\n\n"
        report += "| Input | Expected | Actual | Category |\n"
        report += "|-------|----------|--------|----------|\n"

        for error in errors[:10]:  # Показываем первые 10
            report += f"| `{error['input']}` | `{error['expected']}` | `{error['actual']}` | {error['category']} |\n"

        if len(errors) > 10:
            report += f"\n*...and {len(errors) - 10} more*\n"
        report += "\n"

    # Проблемные категории
    report += "## Problem Categories\n\n"
    for cat, data in sorted(results['by_category'].items(), key=lambda x: x[1]['failed'], reverse=True):
        if data['failed'] > 0:
            report += f"### {cat}\n"
            report += f"- Failed: {data['failed']}/{data['total']} ({data['failed']/data['total']*100:.1f}%)\n"
            report += f"- False Positives: {data['fp']}\n"
            report += f"- False Negatives: {data['fn']}\n\n"

    return report


def save_results(results: dict, report: str):
    """Сохраняет результаты"""
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')

    # Сохраняем JSON с ошибками
    errors_file = RESULTS_DIR / f'errors_{timestamp}.csv'
    with open(errors_file, 'w', encoding='utf-8') as f:
        f.write('id,category,input,expected,actual,error_type\n')
        for error in results['errors']:
            f.write(f"{error['id']},{error['category']},{error['input']},{error['expected']},{error['actual']},{error['error_type']}\n")

    # Сохраняем отчёт
    report_file = RESULTS_DIR / f'report_{timestamp}.md'
    with open(report_file, 'w', encoding='utf-8') as f:
        f.write(report)

    print(f"Results saved to:")
    print(f"  - {errors_file}")
    print(f"  - {report_file}")


def main():
    print("=" * 60)
    print("  TextSwitcher Validation")
    print("=" * 60)

    # Проверяем наличие CLI
    if not CLI_PATH.exists():
        print(f"ERROR: CLI not found at {CLI_PATH}")
        print("Run: xcodebuild -scheme TextSwitcherCLI -derivedDataPath ./build build")
        sys.exit(1)

    # Проверяем наличие корпуса
    if not CORPUS_PATH.exists():
        print(f"ERROR: Test corpus not found at {CORPUS_PATH}")
        sys.exit(1)

    print(f"CLI: {CLI_PATH}")
    print(f"Corpus: {CORPUS_PATH}")
    print()

    # Запускаем тесты
    print("Running tests...")
    results = run_tests()

    # Генерируем отчёт
    report = generate_report(results)

    # Сохраняем результаты
    save_results(results, report)

    # Выводим summary
    print()
    print("=" * 60)
    metrics = calculate_metrics(results)
    print(f"  RESULTS: {results['passed']}/{results['total']} passed ({metrics['accuracy']*100:.1f}%)")
    print(f"  Precision: {metrics['precision']*100:.1f}%")
    print(f"  Recall: {metrics['recall']*100:.1f}%")
    print(f"  F1: {metrics['f1']*100:.1f}%")
    print("=" * 60)

    # Exit code based on results
    if metrics['accuracy'] >= 0.99:
        print("\n SUCCESS: 99%+ accuracy achieved!")
        sys.exit(0)
    else:
        print(f"\n Target: 99%+ accuracy, Current: {metrics['accuracy']*100:.1f}%")
        sys.exit(1)


if __name__ == '__main__':
    main()
