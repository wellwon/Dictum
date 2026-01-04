#!/usr/bin/env python3
"""
Конвертация rubert-tiny2 в CoreML для Dictum TextSwitcher

Модель: cointegrated/rubert-tiny2 (DeepPavlov)
- Размер: ~30MB
- Скорость: <2ms на Apple Neural Engine
- Задача: Masked Language Modeling для контекстного анализа

Использование:
    pip install torch transformers coremltools numpy
    python convert_rubert_to_coreml.py

Результат:
    - RuBertTiny2.mlpackage (~30MB)
    - vocab.txt (словарь токенов)
"""

import os
import sys
import shutil
from pathlib import Path

import numpy as np
import torch
import coremltools as ct
from transformers import AutoModelForMaskedLM, AutoTokenizer

# === Конфигурация ===
MODEL_NAME = "cointegrated/rubert-tiny2"
OUTPUT_DIR = Path(__file__).parent.parent / "Dictum" / "Resources"
MLPACKAGE_NAME = "RuBertTiny2.mlpackage"
VOCAB_NAME = "vocab.txt"
MAX_SEQ_LENGTH = 64  # Короткие предложения для контекста (достаточно 64)


def download_model():
    """Скачивает модель и токенизатор с HuggingFace."""
    print(f"📥 Скачивание модели {MODEL_NAME}...")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModelForMaskedLM.from_pretrained(MODEL_NAME, torchscript=False)
    model.eval()

    print(f"✅ Модель загружена: {model.config.hidden_size} hidden, {model.config.num_hidden_layers} layers")
    return model, tokenizer


def trace_model(model, tokenizer):
    """Трейсит модель для конвертации в CoreML."""
    print("🔧 Трейсинг модели...")

    # Пример входных данных
    sample_text = "Привет как [MASK] дела"
    inputs = tokenizer(
        sample_text,
        return_tensors="pt",
        padding="max_length",
        truncation=True,
        max_length=MAX_SEQ_LENGTH
    )

    input_ids = inputs["input_ids"]
    attention_mask = inputs["attention_mask"]

    # Оборачиваем модель для получения только logits
    class BertWrapper(torch.nn.Module):
        def __init__(self, bert_model):
            super().__init__()
            self.bert = bert_model

        def forward(self, input_ids, attention_mask):
            outputs = self.bert(input_ids=input_ids, attention_mask=attention_mask)
            return outputs.logits  # [batch, seq_len, vocab_size]

    wrapped_model = BertWrapper(model)
    wrapped_model.eval()

    # Трейсинг
    with torch.no_grad():
        traced_model = torch.jit.trace(wrapped_model, (input_ids, attention_mask))

    print("✅ Модель успешно трейснута")
    return traced_model, tokenizer


def convert_to_coreml(traced_model, tokenizer):
    """Конвертирует трейснутую модель в CoreML."""
    print("🔄 Конвертация в CoreML...")

    # Определяем входы
    input_ids_shape = ct.Shape(shape=(1, MAX_SEQ_LENGTH))
    attention_mask_shape = ct.Shape(shape=(1, MAX_SEQ_LENGTH))

    # Конвертация
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=input_ids_shape, dtype=np.int32),
            ct.TensorType(name="attention_mask", shape=attention_mask_shape, dtype=np.int32),
        ],
        outputs=[
            ct.TensorType(name="logits", dtype=np.float32),
        ],
        convert_to="mlprogram",  # Современный формат (.mlpackage)
        compute_units=ct.ComputeUnit.ALL,  # CPU + GPU + Neural Engine
        minimum_deployment_target=ct.target.macOS14,  # macOS Sonoma
    )

    # Добавляем метаданные
    mlmodel.author = "Dictum"
    mlmodel.short_description = "rubert-tiny2 для контекстного анализа раскладки"
    mlmodel.version = "1.0"

    # Входы/выходы
    mlmodel.input_description["input_ids"] = "Токенизированный текст (WordPiece)"
    mlmodel.input_description["attention_mask"] = "Маска внимания (1=токен, 0=паддинг)"
    mlmodel.output_description["logits"] = "Логиты для каждого токена [1, seq_len, vocab_size]"

    print(f"✅ Модель конвертирована в CoreML (compute_units=ALL)")
    return mlmodel


def save_vocab(tokenizer, output_dir):
    """Сохраняет словарь токенизатора."""
    vocab_path = output_dir / VOCAB_NAME

    # Получаем vocab
    vocab = tokenizer.get_vocab()

    # Сортируем по индексу
    sorted_vocab = sorted(vocab.items(), key=lambda x: x[1])

    # Сохраняем
    with open(vocab_path, "w", encoding="utf-8") as f:
        for token, idx in sorted_vocab:
            f.write(f"{token}\n")

    print(f"✅ Словарь сохранён: {vocab_path} ({len(vocab)} токенов)")
    return vocab_path


def save_model(mlmodel, output_dir):
    """Сохраняет CoreML модель."""
    output_path = output_dir / MLPACKAGE_NAME

    # Удаляем старую версию если есть
    if output_path.exists():
        shutil.rmtree(output_path)

    mlmodel.save(str(output_path))

    # Размер
    size_mb = sum(f.stat().st_size for f in output_path.rglob("*") if f.is_file()) / (1024 * 1024)
    print(f"✅ Модель сохранена: {output_path} ({size_mb:.1f} MB)")

    return output_path


def verify_model(mlmodel, tokenizer):
    """Проверяет работу модели."""
    print("🧪 Проверка модели...")

    # Тестовый текст
    test_text = "Привет как [MASK] дела"
    inputs = tokenizer(
        test_text,
        return_tensors="np",
        padding="max_length",
        truncation=True,
        max_length=MAX_SEQ_LENGTH
    )

    # Инференс
    prediction = mlmodel.predict({
        "input_ids": inputs["input_ids"].astype(np.int32),
        "attention_mask": inputs["attention_mask"].astype(np.int32),
    })

    logits = prediction["logits"]

    # Находим позицию [MASK]
    mask_token_id = tokenizer.mask_token_id
    mask_pos = np.where(inputs["input_ids"][0] == mask_token_id)[0]

    if len(mask_pos) > 0:
        mask_logits = logits[0, mask_pos[0], :]
        top_5_ids = np.argsort(mask_logits)[-5:][::-1]
        top_5_tokens = [tokenizer.decode([idx]) for idx in top_5_ids]
        print(f"   Тест: '{test_text}'")
        print(f"   Top-5 предсказаний для [MASK]: {top_5_tokens}")

    print("✅ Модель работает корректно")


def main():
    """Основная функция конвертации."""
    print("=" * 60)
    print("🚀 Конвертация rubert-tiny2 → CoreML для Dictum")
    print("=" * 60)

    # Создаём директорию
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Шаг 1: Скачиваем модель
    model, tokenizer = download_model()

    # Шаг 2: Трейсим модель
    traced_model, tokenizer = trace_model(model, tokenizer)

    # Шаг 3: Конвертируем в CoreML
    mlmodel = convert_to_coreml(traced_model, tokenizer)

    # Шаг 4: Сохраняем vocab
    save_vocab(tokenizer, OUTPUT_DIR)

    # Шаг 5: Сохраняем модель
    save_model(mlmodel, OUTPUT_DIR)

    # Шаг 6: Проверяем
    verify_model(mlmodel, tokenizer)

    print("=" * 60)
    print("🎉 Готово! Файлы сохранены в:")
    print(f"   📦 {OUTPUT_DIR / MLPACKAGE_NAME}")
    print(f"   📄 {OUTPUT_DIR / VOCAB_NAME}")
    print("=" * 60)
    print("\nСледующие шаги:")
    print("1. Добавить RuBertTiny2.mlpackage в Xcode проект")
    print("2. Добавить vocab.txt в Resources")
    print("3. Написать BertTokenizer.swift")
    print("4. Написать NeuralContextBrain.swift")


if __name__ == "__main__":
    main()
