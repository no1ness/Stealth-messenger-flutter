# Themes Directory

Эта директория содержит альтернативные темы оформления для мобильного приложения Turbo.

## Доступные темы

### 1. Apple Liquid Glass UI (`apple_liquid/`)

Премиум тема с эффектами glassmorphism в стиле Apple.

**Особенности:**
- Дизайн в стиле iOS/Apple
- Liquid Glass эффекты (размытие, прозрачность)
- Плавные градиенты
- Микроанимации
- Темный режим

**Документация:** [apple_liquid/README.md](apple_liquid/README.md)

**Быстрый старт:**
```dart
// В lib/main.dart
import 'themes/apple_liquid/apple_liquid_app.dart';

runApp(const AppleLiquidApp());
```

## Структура тем

Каждая тема должна содержать:

```
theme_name/
├── README.md                 # Документация темы
├── theme_name_app.dart      # Точка входа приложения
├── constants/               # Константы (цвета, типографика, отступы)
├── components/              # Базовые компоненты
├── widgets/                 # UI виджеты
└── screens/                 # Экраны приложения
```

## Создание новой темы

1. Создайте директорию с именем вашей темы
2. Скопируйте структуру из `apple_liquid/`
3. Измените константы в `constants/`
4. Адаптируйте компоненты под ваш стиль
5. Создайте точку входа `your_theme_app.dart`
6. Напишите README с инструкциями

## Переключение между темами

### Вариант 1: Изменение main.dart

Откройте `lib/main.dart` и измените runApp:

```dart
// Оригинальная тема
runApp(const MyApp());

// Apple Liquid тема
import 'themes/apple_liquid/apple_liquid_app.dart';
runApp(const AppleLiquidApp());
```

### Вариант 2: Отдельная точка входа

Запустите приложение с конкретной темой:

```bash
# Apple Liquid тема
flutter run -t lib/themes/apple_liquid/apple_liquid_app.dart
```

### Вариант 3: Runtime переключение (TODO)

Будет добавлена возможность переключения тем в настройках приложения.

## Рекомендации

- Не изменяйте файлы в `lib/ui/` - это оригинальная тема
- Каждая тема должна быть самодостаточной
- Используйте общую бизнес-логику из `lib/supabase_service.dart`
- Документируйте все изменения в README темы

## Обратная совместимость

Оригинальное оформление приложения находится в `lib/ui/` и остается нетронутым. Вы всегда можете вернуться к нему, изменив точку входа в `main.dart`.
