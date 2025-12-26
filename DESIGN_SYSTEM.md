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
| **Hover Background** | `rgba(255, 255, 255, 0.1)` | Ховер-состояние (общий) |
| **Selected Background** | `rgba(255, 255, 255, 0.15)` | Выбранные элементы (общий) |
| **Row Highlight** | `#242425` / `(36, 36, 37)` | Выделение строки в модалке истории (hover + selection) |

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
| **Toggle Background** | `#3D3D3D` | Фон выключенного тумблера |
| **Destructive** | `#FF3B30` | Удаление, ошибки |
| **Warning** | `Color.orange` | Предупреждения |

### Cards (Tahoe style)
| Название | Значение | Использование |
|----------|----------|---------------|
| **Card Background** | `Color.white.opacity(0.03)` | Фон карточек в стиле Tahoe |
| **Card Border** | `Color.white.opacity(0.15)` | Рамка карточек в стиле Tahoe |

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
| **Card Tahoe** | 8px | Карточки в стиле macOS Tahoe |
| **Window** | 26px | Окна macOS Tahoe Toolbar Window |

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

## Тумблеры (Toggle Style)

### TahoeToggleStyle (основной)

iOS-style тумблер для macOS Tahoe — pill shape (Capsule), тёмный фон, белый круг.

| Свойство | Значение | Описание |
|----------|----------|----------|
| **Размер** | 44×26 | Стандарт iOS |
| **Кружок** | 22×22 | Белый круг с padding 2 |
| **Фон выключен** | `#3D3D3D` | Тёмно-серый |
| **Фон включён** | `#1AAF87` | Зелёный accent |
| **Анимация** | spring | response: 0.25, dampingFraction: 0.7 |
| **Тень кружка** | opacity 0.15, radius 2, y: 1 | Лёгкая тень |

### Использование

```swift
Toggle("", isOn: $value)
    .toggleStyle(TahoeToggleStyle())
    .labelsHidden()
```

### Примеры

```swift
// В SettingsRow
SettingsRow(title: "Автозапуск") {
    Toggle("", isOn: $settings.launchAtLogin)
        .toggleStyle(TahoeToggleStyle())
        .labelsHidden()
}

// Standalone
Toggle("Включить функцию", isOn: $isEnabled)
    .toggleStyle(TahoeToggleStyle())
```

### ⚠️ GreenToggleStyle — deprecated

Старый прямоугольный стиль. Используйте `TahoeToggleStyle` вместо него.

---

## Использование в коде

```swift
// Цвета
DesignSystem.Colors.accent              // Зеленый #1AAF87
DesignSystem.Colors.toggleActive        // Цвет активного тумблера
DesignSystem.Colors.toggleBackground    // Фон выключенного тумблера #3D3D3D
DesignSystem.Colors.textSecondary       // Серый текст
DesignSystem.Colors.buttonAreaBackground // Фон области кнопок #272729
DesignSystem.Colors.borderColor         // Бордер модалки #4c4d4d
DesignSystem.Colors.cardBackgroundTahoe // Фон карточек Tahoe (0.03 opacity)
DesignSystem.Colors.cardBorderTahoe     // Рамка карточек Tahoe (0.15 opacity)

// Отступы
DesignSystem.Spacing.sm                 // 8px
DesignSystem.Spacing.lg                 // 16px

// Радиусы
DesignSystem.CornerRadius.button        // 4px
DesignSystem.CornerRadius.cardTahoe     // 8px
DesignSystem.CornerRadius.window        // 26px (macOS Tahoe)

// Шрифты
DesignSystem.Typography.sectionHeader   // Font.system(size: 11, weight: .semibold)

// Тумблеры
Toggle("", isOn: $value)
    .toggleStyle(TahoeToggleStyle())    // iOS-style pill toggle
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
- **Модалка истории** — `.shadow(color: .black.opacity(0.5), radius: 30, y: 15)` — отдельное окно поверх основного
- **Нотификации** (screenshot notification) — `.shadow(radius: 10, y: 5)`
- **Glow-эффекты кнопок** — `.shadow(color: accent, radius: 4)` при загрузке

---

## Бордеры модалки

**macOS Tahoe Toolbar Window standard: 26pt**

```swift
// ✅ ПРАВИЛЬНО — strokeBorder рисует внутри контура (равномерная толщина)
.overlay(
    RoundedRectangle(cornerRadius: 26)  // macOS Tahoe: 26pt
        .strokeBorder(DesignSystem.Colors.borderColor, lineWidth: 1)
)

// ❌ НЕПРАВИЛЬНО — stroke рисует по центру контура (неравномерно на углах)
.overlay(
    RoundedRectangle(cornerRadius: 26)
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

---

## Модалки (Modal Windows)

### Структура модалки истории

| Элемент | Значение | Описание |
|---------|----------|----------|
| **Size** | 720×450 | Размер модалки |
| **Corner Radius** | 26pt | Скругление (macOS Tahoe standard) |
| **Max Height** | 320px | Максимальная высота списка |
| **Header Padding** | 20px top/bottom, 24px horizontal | Отступы поля поиска |
| **Footer Padding** | 14px vertical, 24px horizontal | Отступы футера |
| **Row Padding** | 12px vertical, 20px horizontal | Отступы строки списка |
| **Row Highlight** | `#242425` | Цвет выделения строки (hover/selection) |
| **Shadow** | `radius: 30, y: 15, opacity: 0.5` | Тень модалки (исключение) |

### Поле поиска (Search Field)

```swift
HStack(spacing: 12) {
    Image(systemName: "magnifyingglass")
    TextField("Поиск...", text: $query)
}
.padding(.horizontal, 20)
.padding(.vertical, 14)
.background(Capsule().fill(Color.white.opacity(0.05)))
.overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
.padding(.horizontal, 24)
.padding(.top, 20)
.padding(.bottom, 20)
```

### Футер с хоткеями

```swift
HStack {
    HStack(spacing: 20) {
        hotkeyHint("KEY", "описание")
        // ...
    }
    Spacer()
    hotkeyHint("ESC", "закрыть")
}
.padding(.horizontal, 24)
.padding(.vertical, 14)
.background(Color(red: 39/255, green: 39/255, blue: 41/255))  // #272729
```

### Хоткей-бейдж

```swift
HStack(spacing: 8) {
    Text("KEY")
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.5))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.15)))
        .cornerRadius(4)
    Text("описание")
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.4))
}
```

### Навигация клавиатурой

| Клавиша | Действие |
|---------|----------|
| ↑↓ | Навигация по списку |
| ←→ | Свернуть/развернуть запись |
| Enter | Выбрать |
| ESC | Закрыть |
| ⌘K | Открыть/закрыть модалку |

### Выделение строки (Row Highlight)

```swift
// Цвет #242425 для hover и selection
.background(isHighlighted ? Color(red: 36/255, green: 36/255, blue: 37/255) : Color.clear)
```

### Hover vs Keyboard Navigation

При навигации клавишами hover отключается через `isKeyboardNavigating` флаг.
Сбрасывается через `NSEvent.addLocalMonitorForEvents(matching: .mouseMoved)`.

```swift
// В HistoryModalView
@State private var isKeyboardNavigating = false
@State private var mouseMonitor: Any?

.onAppear {
    mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
        isKeyboardNavigating = false
        return event
    }
}

// В HistoryRowView
.onHover { hovering in
    if !isKeyboardNavigating {
        isHovered = hovering
    }
}
```

---

## ⚠️ Overlay-модалки (вложенные окна)

### Проблема острых углов

Когда модалка показывается внутри другой модалки через `.overlay { }` или `ZStack`, тень **ОБРЕЗАЕТСЯ** на границе родителя.

```
┌─────────────────────────────────────────┐
│  Parent Modal (720×450)                 │
│  ┌─────────────────────────────────┐    │
│  │  Child Modal                    │    │
│  │  .shadow(radius: 30) ← ОБРЕЗКА! │    │
│  │                          ┌──────┼────┤ ← Тень обрезается здесь
│  │                          │██████│    │   = ОСТРЫЕ УГЛЫ!
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

**Результат:** Тень пытается выйти за границы 720×450, но обрезается → острые углы там, где обрезка.

### Решение: НЕ использовать тени на вложенных модалках

Для overlay-модалок (NoteAddView, NoteDetailView и т.п.) — **БЕЗ ТЕНИ**:

```swift
// ✅ ПРАВИЛЬНО — overlay-модалка БЕЗ тени
.frame(width: 720, height: 450)
.background(
    RoundedRectangle(cornerRadius: 26)
        .fill(Color(red: 24/255, green: 24/255, blue: 26/255))
        // БЕЗ shadow! Тень обрезается границами окна
)
.background(
    VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        .clipShape(RoundedRectangle(cornerRadius: 26))
)
.clipShape(RoundedRectangle(cornerRadius: 26))
.overlay(
    RoundedRectangle(cornerRadius: 26)
        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
)
.focusable()
.focusEffectDisabled()
```

```swift
// ❌ ЗАПРЕЩЕНО — тень на overlay-модалке
.background(
    RoundedRectangle(cornerRadius: 26)
        .fill(...)
        .shadow(color: .black.opacity(0.5), radius: 30, y: 15)  // ← НЕЛЬЗЯ!
)
```

### Когда МОЖНО использовать тени

| Тип модалки | Тень | Причина |
|-------------|------|---------|
| **Главная модалка** (InputModalView) | ❌ Нет | Floating panel, не нужна |
| **Overlay-модалки** (NoteAddView, NoteDetailView) | ❌ Нет | Обрезается границами родителя |
| **Отдельное окно** (HistoryModalView, NotesModalView) | ✅ Да | Рендерится независимо, тень не обрезается |

### Чеклист для overlay-модалок

- [ ] `.frame(width: 720, height: 450)` — фиксированный размер
- [ ] `.background(RoundedRectangle.fill())` — **БЕЗ .shadow()!**
- [ ] `.background(VisualEffectBackground.clipShape())` — blur-эффект
- [ ] `.clipShape(RoundedRectangle(cornerRadius: 26))` — обрезка контента
- [ ] `.overlay(strokeBorder)` — тонкий бордер
- [ ] `.focusable()` + `.focusEffectDisabled()` — фокус без рамки
