# Plan: GlassTextField Web Perf Budget — transplant from perf/glass-text-field-web-budget

**Branch:** `feature/glass-text-field-web-budget-merge`
**Created:** 2026-06-14
**Mode:** full

## Цель

Трансплантировать 3 коммита из ветки `perf/glass-text-field-web-budget` в `main`,
добавляя ghostBuilder API в ChromaticAberration и web cheap-ghost оптимизацию GlassTextField.
Main сильно изменился с момента создания ветки, поэтому прямой merge невозможен —
только хирургический перенос функциональных изменений.

## Settings

- **Testing:** yes (2 новых теста ghostBuilder в chromatic_aberration_test.dart + новый glass_text_field_test.dart с widget-тестами и web perf regression gate)
- **Logging:** verbose (добавить debugPrint в initState GlassTextField для web perf-budget)
- **Docs:** no (изменения только в коде, docs checkpoint не требуется)

## Roadmap Linkage

- **Milestone:** M10.1 (GlassTextField focus-pulse perf budget for web) — уже `[~]` in flight в ROADMAP.md
- **Rationale:** Трансплантация PR #4 в main завершает M10.1

## Затрагиваемые файлы

- `client/lib/themes/apple_liquid/effects/chromatic_aberration.dart` — добавить `ghostBuilder` параметр
- `client/lib/themes/apple_liquid/widgets/glass_text_field.dart` — extract `_glassFieldDecoration` helper, добавить `_GlassFieldGhost`, wire web cheap-ghost path
- `client/test/themes/apple_liquid/effects/chromatic_aberration_test.dart` — 2 новых теста для ghostBuilder
- `client/test/themes/apple_liquid/widgets/glass_text_field_test.dart` — НОВЫЙ файл: widget-тесты + source-as-fixture web perf regression gate

## Tasks

### Task 1 — ghostBuilder API в ChromaticAberration

**Файл:** `client/lib/themes/apple_liquid/effects/chromatic_aberration.dart`

Добавить:
- Поле `final WidgetBuilder? ghostBuilder;` в класс
- Обновить doc-comment: описать perf-контракт (ghostBuilder как escape hatch для дорогих сабтри)
- В `build()`: если `ghostBuilder != null`, использовать `ghost.call(context)` для ghost-слоёв вместо `child`
- Обновить `debugPrint` на mount — логировать `ghostBuilder=${ghostBuilder != null}`

**Логирование:**
- `Logger.debug` не используется (эффекты используют debugPrint напрямую) — сохранить существующий паттерн

### Task 2 — _glassFieldDecoration helper + _GlassFieldGhost + web cheap-ghost path

**Файл:** `client/lib/themes/apple_liquid/widgets/glass_text_field.dart`

Изменения:
1. Добавить `import 'package:flutter/foundation.dart';` (для `kIsWeb`)
2. В `initState()`: добавить `if (kIsWeb) { debugPrint('[ds:glass-text-field] perf-budget cheap-ghost path active'); }`
3. Извлечь `_glassFieldDecoration({required bool focused, required Color fillColor})` — top-level функция, возвращает `BoxDecoration`. Дублирует логику из inline BoxDecoration в build()
4. Заменить inline `BoxDecoration(...)` в `build()` на вызов `_glassFieldDecoration(focused: _isFocused, fillColor: ...)`
5. Добавить класс `_GlassFieldGhost extends StatelessWidget` — border-only контейнер (fillColor: Colors.transparent), использует `_glassFieldDecoration` для синхронизации стилей
6. В `build()` при создании `ChromaticAberration` передать `ghostBuilder: kIsWeb ? (ctx) => _GlassFieldGhost(focused: _isFocused) : null`

**Логирование:**
- `debugPrint` в `initState` при `kIsWeb == true`

### Task 3 — Тесты ghostBuilder в chromatic_aberration_test.dart

**Файл:** `client/test/themes/apple_liquid/effects/chromatic_aberration_test.dart`

Добавить 2 теста:
1. `ghostBuilder is used for ghost layers when provided` — assert: реальный child 1×, ghost 2×
2. `ghostBuilder == null falls back to child for ghost layers` — assert: child найден 3× (backward compat)

### Task 4 — НОВЫЙ файл glass_text_field_test.dart

**Файл:** `client/test/themes/apple_liquid/widgets/glass_text_field_test.dart`

Тесты:
1. `focus pulse mounts ChromaticAberration on focus gain (dark)` — pump + focus → ChromaticAberration в дереве; settle → нет
2. `light brightness gates out the focus pulse` — focus → нет ColorFiltered внутри GlassTextField
3. `web perf-budget regression gate` — source-as-fixture: assert `kIsWeb` import, `kIsWeb` branch, `_GlassFieldGhost` wiring присутствуют в исходнике

## Commit Plan

3 задачи + тесты → 1 коммит:

```
perf(ui): add ghostBuilder API to ChromaticAberration + web cheap-ghost path for GlassTextField

Transplant 3 commits from perf/glass-text-field-web-budget into main:
ff1f575, 7cb37d0, 29134b3

- ChromaticAberration: optional ghostBuilder param for cheaper ghost layers
- GlassTextField: extract _glassFieldDecoration helper, add _GlassFieldGhost
  border-only widget, wire kIsWeb cheap-ghost path in ChromaticAberration
- Tests: ghostBuilder coverage + GlassTextField widget tests + web perf
  regression gate (source-as-fixture)

Closes: M10.1 (GlassTextField focus-pulse perf budget for web)
```
