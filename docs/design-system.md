[← Architecture](ARCHITECTURE.md) · [Back to README](../README.md) · [Performance →](PERFORMANCE.md)

# Дизайн-система Stealth — Telegram-tt Flat

> Плоский Telegram-дизайн, портированный с telegram-tt (https://github.com/Ajaxy/telegram-tt).
> Исходные цветовые токены: `themes.json` (73+ токена), `_variables.scss` (120+ CSS-переменных).
>
> Владельцы: все, кто работает с `client/lib/themes/tg/` или `client/lib/ui/screens/`.
> Изменения здесь должны отражаться в коде виджетов; код виджетов должен ссылаться на токены,
> а не на магические числа.

---

## Эстетическое направление

**Плоский Telegram-дизайн.**

Минималистичный, функциональный интерфейс в стиле Telegram Web Z. Никаких стеклянных
эффектов, градиентов или декоративных наложений. Чистые поверхности, четкая типографика,
иерархия через цвет и отступы.

| Измерение      | Обязательство                                                |
|---------------|--------------------------------------------------------------|
| Палитра       | Telegram Web Z: `#3390EC` (синий), `#00C73E` (зелёный), `#8774E1` (фиолетовый dark) |
| Типографика   | **Roboto** для UI / текста; **Roboto Mono** для цифр, ID, кода (iOS: system-ui fallback) |
| Движение      | Стандартные Material-анимации (opacity, scale, position) |
| Подпись       | Нет signature-эффектов (Scanline, Grain, ChromaticAberration удалены) |
| Темная/Светлая| Полноценная светлая и тёмная темы на основе telegram-tt |

### Референсы

- Telegram Web Z (web.telegram.org) — плоские карточки, iMessage-баблы, боковая панель
- telegram-tt (github.com/Ajaxy/telegram-tt) — имплементация

### Анти-паттерны

- Использование `Theme.of(context).colorScheme.*` — используйте `TgThemeColors.of(context).*`
- Голый `AlertDialog` / `SnackBar` — используйте `TgDialog.show()` / `TgSnackBar.show()`
- Inline `EdgeInsets` с магическими числами — используйте `TgSpacing.*`
- Любые glass-эффекты, scanline, grain, chromatic aberration — **удалены**

---

## Архитектура темы

- `TgThemeColors` — ~76 цветовых токенов, переключаемых по `Brightness` через `TgThemeColors.of(context)`
- `TgThemeData` — полноценный `ThemeData` (light/dark) с Telegram-цветами
- `TgSpacing` — 6-tier scale отступов (xxs–xxl) + радиусы + UI-константы
- `TgTypography` — 22 именованных стиля + `textTheme`
- `FlatContainer` — замена `GlassContainer`: плоская, фон `surface`, `borderRadius: 12`
- `TgAppBar` — плоский `AppBar`, `elevation: 0`
- `TgBottomNavBar` — кастомная панель навигации (иконка + лейбл)
- `TgChatBubble` — iMessage-стиль: sent = `backgroundOwn`, received = `background`
- `TgSnackBar` / `TgDialog` / `TgHaptics` — Feedback-слой

---

## Шрифты

### Семейства

| Семейство     | Роль                                                  | Источник |
|---------------|-------------------------------------------------------|----------|
| `Roboto`      | Тело, UI-метки, заголовки — вся нечисловая строка    | системный (Android), загрузка (web) |
| `Roboto Mono` | Цифры, ID, хеши, метки времени, таймер звонка        | системный / загрузка |

На iOS/macOS используется `system-ui` через `defaultTargetPlatform`.

Geist/GeistMono заменены на Roboto/RobotoMono (см. commit `feat(theme): add Roboto typography`).

### Бюджет активов

Шрифты Geist (~1.18 MB) удалены. Roboto — системный, не добавляет к размеру сборки.

---

## Токены

Все токены живут в `client/lib/themes/tg/`. Используйте экспортный баррель:

```dart
import 'package:stealth/themes/tg/tg_theme_exports.dart';
```

### Цвета — `TgThemeColors`

Instance-класс через `TgThemeColors.of(context)`.
~76 цветовых токенов в light/dark вариантах:

| Группа       | Примеры токенов |
|-------------|-----------------|
| Primary     | `primary` (`#3390EC` light, `#8774E1` dark) |
| Background  | `background`, `backgroundSecondary`, `backgroundOwn` |
| Text        | `text`, `textSecondary`, `textMeta`, `messageMetaOwn` |
| Borders     | `borders`, `bordersInput`, `dividers` |
| Status      | `success` (`#00C73E`), `warning` (`#FB8C00`), `error` (`#E53935`) |
| Chat        | `chatHover`, `chatActive`, `chatUsername` |
| Feedback    | `toastBackground`, `skeletonBackground`, `scrollbar` |

**Контекст получения цвета в StatefulWidget:**
```dart
TgThemeColors get c => TgThemeColors.of(context);
// используйте c.primary, c.textSecondary и т.д. в любом методе State
```

### Отступы — `TgSpacing`

| Токен  | Значение | Использование |
|--------|----------|---------------|
| `xxs`  | 4        | Микро-отступы, gap между иконкой и текстом |
| `xs`   | 8        | Базовые отступы внутри строк |
| `sm`   | 12       | Отступы внутри карточек |
| `md`   | 16       | Стандартный отступ экрана (`screenEdge`) |
| `lg`   | 20       | Крупные отступы между секциями |
| `xl`   | 24       | Padding больших блоков |
| `xxl`  | 32       | Макро-отступы |

Радиусы: `radiusXs` (4), `radiusSm` (8), `radiusMd` (12), `radiusLg` (16), `radiusXl` (20), `radiusRound` (999).

### Типографика — `TgTypography`

22 именованных стиля через статические геттеры:

| Стиль                 | fontSize | weight | Material textTheme |
|-----------------------|----------|--------|-------------------|
| `largeTitle`          | 28       | w700   | `headlineMedium`  |
| `title1`              | 22       | w600   | `titleLarge`      |
| `title2`              | 20       | w600   | `titleMedium`     |
| `title3`              | 18       | w500   | `titleSmall`      |
| `headline`            | 17       | w600   | `titleLarge`      |
| `body`                | 16       | w400   | `bodyMedium`      |
| `caption1`            | 13       | w400   | `bodySmall`       |
| `captionMono`         | 13       | w400   | `bodySmall` + mono |
| `titleMono`           | 22       | w600   | `titleSmall` + mono |

---

## Ключевые компоненты

### `FlatContainer`
Замена `GlassContainer`. Плоская карточка с фоном `surface`, `borderRadius: 12`, опциональным `intensity` для разных вариантов фона.

### `TgAppBar`
Плоский `AppBar` + `TgSliverAppBar`. `elevation: 0`, `backgroundColor: backgroundSecondary`.

### `TgBottomNavBar`
Кастомная нижняя панель с иконкой + лейблом, активный — `primary` цвет, плоский фон `backgroundSecondary`.

### `TgChatBubble`
iMessage-стиль:
- **Sent:** `backgroundOwn` (зелёный light, фиолетовый dark)
- **Received:** `background` (белый light, тёмно-серый dark)
- `borderRadius: 15` (как telegram-tt `--border-radius-messages`)
- Время/статус внутри бабла
- Никаких эффектов (scanline, grain)

### `TgSearchField`
Плоское поле поиска: фон `backgroundSecondary`, иконка поиска, кнопка очистки.

### Feedback
- `TgSnackBar.show(context, message, {isError})` — плоский toast
- `TgDialog.show(context, {title, message})` — плоский диалог
- `TgLoading.spinner({size, color})` — Material CircularProgressIndicator
- `TgHaptics.light()` / `TgHaptics.medium()` / `TgHaptics.heavy()` — тактильная отдача

---

## Дисциплина производительности

- Все виджеты — плоские, без оверлеев; `RepaintBoundary` не требуется
- Нет `AnimationController` в базовых виджетах (кроме `CallHudOverlay` и `OutgoingDeliveryStatusIcon`)
- Тема кэшируется per-brightness через `TgThemeColors._instances`

---

## Двойная идентичность (тёмная против светлой)

Обе темы — равноправные, на основе telegram-tt. Светлая тема использует те же токены, что и тёмная, но с инвертированными значениями (белый фон, чёрный текст).

По умолчанию при новой установке: `ThemeMode.system`.

---

## Инвентарь компонентов

Весь UI собран из виджетов в `client/lib/themes/tg/widgets/`:

| Компонент | Файл |
|-----------|------|
| FlatContainer | `flat_container.dart` |
| TgAppBar | `tg_app_bar.dart` |
| TgBottomNavBar | `tg_bottom_nav_bar.dart` |
| TgChatBubble | `tg_chat_bubble.dart` |
| TgChatTile | `tg_chat_tile.dart` |
| TgContactTile | `tg_contact_tile.dart` |
| TgSectionHeader | `tg_section_header.dart` |
| TgTextField | `tg_text_field.dart` |
| TgSearchField | `tg_text_field.dart` |
| TgMessageInput | `tg_message_input.dart` |
| CallHudOverlay | `ui/widgets/call_hud_overlay.dart` |
| StatusChip | `ui/widgets/status_chip.dart` |
| OutgoingDeliveryStatusIcon | `ui/widgets/outgoing_delivery_status_icon.dart` |
| StealthEmptyState | `ui/widgets/empty_state.dart` |

---

## See Also

- [Architecture](ARCHITECTURE.md) — обзор системы и runtime-модель
- [Performance](PERFORMANCE.md) — оптимизация производительности
- [Android Release](ANDROID_RELEASE.md) — подпись release-сборки
