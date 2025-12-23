# Dictum Design System

Централизованная дизайн-система приложения. Все цвета, отступы и стили определены в `DesignSystem` enum в `Dictum.swift`.

## Цветовая палитра

### Accent (единый зеленый)
| Название | HEX | RGB | Использование |
|----------|-----|-----|---------------|
| **Primary Accent** | `#1AAF87` | `(26, 175, 135)` | Тумблеры, индикаторы успеха, кнопки промптов при загрузке, иконки статуса |
| **Secondary Accent** | `#3498DB` | `(52, 152, 219)` | Ссылки, вторичные акценты |

### Backgrounds
| Название | Значение | Использование |
|----------|----------|---------------|
| **Panel Background** | `rgba(0, 0, 0, 0.3)` | Фон панелей, сайдбаров |
| **Card Background** | `rgba(255, 255, 255, 0.05)` | Фон карточек, секций |
| **Hover Background** | `rgba(255, 255, 255, 0.1)` | Ховер-состояние |
| **Selected Background** | `rgba(255, 255, 255, 0.15)` | Выбранные элементы |

### Modal/Panel Elements
| Название | HEX | RGB | Использование |
|----------|-----|-----|---------------|
| **Button Area Background** | `#272729` | `(39, 39, 41)` | Фон нижней части модалки (область кнопок) |
| **Border Color** | `#4c4d4d` | `(76, 77, 77)` | Бордер модалки (1px, strokeBorder) |

### Text
| Название | Значение | Использование |
|----------|----------|---------------|
| **Primary** | `#FFFFFF` | Основной текст |
| **Secondary** | `Color.gray` | Вторичный текст, подписи |
| **Muted** | `rgba(255, 255, 255, 0.6)` | Приглушенный текст |

### States
| Название | HEX | Использование |
|----------|-----|---------------|
| **Toggle Active** | `#1AAF87` | Включенные тумблеры |
| **Destructive** | `#FF3B30` | Удаление, ошибки |
| **Warning** | `Color.orange` | Предупреждения |

---

## Типографика

| Стиль | Размер | Вес | Использование |
|-------|--------|-----|---------------|
| **Section Header** | 11pt | Semibold | Заголовки секций настроек |
| **Body** | 12pt | Regular | Основной текст |
| **Label** | 11pt | Medium | Метки кнопок, лейблы |
| **Caption** | 10pt | Regular | Подписи, версия |

---

## Отступы

| Название | Значение | Использование |
|----------|----------|---------------|
| **XS** | 4px | Минимальные отступы |
| **SM** | 8px | Маленькие отступы |
| **MD** | 12px | Средние отступы |
| **LG** | 16px | Большие отступы |
| **XL** | 20px | Секции, панели |

---

## Радиусы скругления

| Название | Значение | Использование |
|----------|----------|---------------|
| **Button** | 4px | Кнопки, чипы |
| **Card** | 6px | Карточки, поля ввода |
| **Panel** | 8px | Панели, модалки |

---

## Карточки / Плашки (Feature Cards)

Используется для выделения отдельных функций в настройках (AI Settings, Скриншоты, Бекап и т.д.).

| Свойство | Значение | Описание |
|----------|----------|----------|
| **Padding vertical** | 8px | Вертикальные отступы |
| **Padding horizontal** | 16px | Горизонтальные отступы |
| **Background** | `Color.white.opacity(0.03)` | Полупрозрачный белый фон |
| **Border** | `Color.white.opacity(0.15)` | Полупрозрачная рамка |
| **Border Width** | 1px | Толщина рамки |
| **Corner Radius** | 8px | Радиус скругления |

### Использование

```swift
VStack {
    // Содержимое секции
}
.padding(.vertical, 8)
.padding(.horizontal, 16)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.white.opacity(0.03))
)
.overlay(
    RoundedRectangle(cornerRadius: 8)
        .stroke(Color.white.opacity(0.15), lineWidth: 1)
)
```

### Примеры применения
- **ScreenshotSettingsSection** — секция инструмента скриншотов
- **AISettingsSection** — секция AI настроек
- **Backup Configuration** — секция бекапа конфигурации

---

## Использование в коде

```swift
// Цвета
DesignSystem.Colors.accent              // Зеленый #1AAF87
DesignSystem.Colors.toggleActive        // Цвет активного тумблера
DesignSystem.Colors.textSecondary       // Серый текст
DesignSystem.Colors.buttonAreaBackground // Фон области кнопок #272729
DesignSystem.Colors.borderColor         // Бордер модалки #4c4d4d

// Отступы
DesignSystem.Spacing.sm                 // 8px
DesignSystem.Spacing.lg                 // 16px

// Радиусы
DesignSystem.CornerRadius.button        // 4px

// Шрифты
DesignSystem.Typography.sectionHeader   // Font.system(size: 11, weight: .semibold)
```

---

## Тени

### ⛔ НЕ использовать тени на модалках!

Модалка Dictum — это floating panel без теней. Большие тени (radius > 10) создают визуальный мусор и расползаются в стороны.

```swift
// ❌ ЗАПРЕЩЕНО — тень расползается влево/вправо
.shadow(color: .black.opacity(0.65), radius: 27, x: 0, y: 24)

// ❌ ЗАПРЕЩЕНО — любые тени на главной модалке
.shadow(...)

// ✅ ПРАВИЛЬНО — модалка без теней
// (просто не добавлять .shadow())
```

### Исключения

Тени разрешены только для:
- **Нотификации** (screenshot notification) — `.shadow(radius: 10, y: 5)`
- **Glow-эффекты кнопок** — `.shadow(color: accent, radius: 4)` при загрузке

---

## Бордеры модалки

```swift
// ✅ ПРАВИЛЬНО — strokeBorder рисует внутри контура (равномерная толщина)
.overlay(
    RoundedRectangle(cornerRadius: 24)
        .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
)

// ❌ НЕПРАВИЛЬНО — stroke рисует по центру контура (неравномерно на углах)
.overlay(
    RoundedRectangle(cornerRadius: 24)
        .stroke(DesignSystem.Colors.borderColor, lineWidth: 2)
)
```

---

## Правила

1. **Не использовать `.green`** — только `DesignSystem.Colors.accent`
2. **Не хардкодить цвета** — всегда через `DesignSystem.Colors`
3. **Единый зеленый** — `#1AAF87` для всех зеленых элементов
4. **Проверять перед изменениями** — сначала глянуть этот файл
5. **Не добавлять тени на модалки** — модалка без `.shadow()`
6. **strokeBorder вместо stroke** — для равномерных бордеров
