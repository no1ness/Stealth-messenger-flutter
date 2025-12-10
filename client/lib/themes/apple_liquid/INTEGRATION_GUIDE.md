# Руководство по интеграции Apple Liquid Theme

## Быстрый старт (3 минуты)

### Шаг 1: Активация темы

Откройте файл `lib/main.dart` и найдите функцию `main()`:

**Было:**
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: "https://kazyqhdshaptuqcujjag.supabase.co",
    anonKey: "...",
  );

  runApp(const MyApp());
}
```

**Стало:**
```dart
import 'themes/apple_liquid/apple_liquid_app.dart'; // Добавьте этот импорт

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: "https://kazyqhdshaptuqcujjag.supabase.co",
    anonKey: "...",
  );

  runApp(const AppleLiquidApp()); // Замените MyApp на AppleLiquidApp
}
```

### Шаг 2: Горячая перезагрузка

Нажмите `r` в консоли Flutter или используйте кнопку Hot Reload в вашей IDE.

### Шаг 3: Наслаждайтесь!

Приложение теперь использует тему Apple Liquid Glass UI! 🎉

## Возврат к оригинальной теме

Просто верните обратно `runApp(const MyApp());` в `main.dart`.

## Альтернативные способы активации

### Способ 2: Условное переключение

Добавьте возможность выбора темы через флаг:

```dart
const bool useAppleTheme = true; // Переключатель

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: "https://kazyqhdshaptuqcujjag.supabase.co",
    anonKey: "...",
  );

  runApp(useAppleTheme ? const AppleLiquidApp() : const MyApp());
}
```

### Способ 3: Отдельная точка входа

Создайте файл `lib/main_apple.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'themes/apple_liquid/apple_liquid_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: "https://kazyqhdshaptuqcujjag.supabase.co",
    anonKey: "YOUR_KEY",
  );

  runApp(const AppleLiquidApp());
}
```

Запустите с этой точкой входа:

```bash
flutter run -t lib/main_apple.dart
```

Или в VS Code, добавьте в `.vscode/launch.json`:

```json
{
  "configurations": [
    {
      "name": "Apple Liquid Theme",
      "type": "dart",
      "request": "launch",
      "program": "lib/main_apple.dart"
    },
    {
      "name": "Original Theme",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart"
    }
  ]
}
```

## Кастомизация темы

### Изменение цветов

Откройте `lib/themes/apple_liquid/constants/app_colors.dart` и измените нужные цвета:

```dart
// Например, изменить основной синий цвет
static const Color systemBlue = Color(0xFF0066FF); // Ваш цвет
```

### Изменение градиентов

```dart
// Создайте свой градиент
static const List<Color> myCustomGradient = [
  Color(0xFFFF6B6B),
  Color(0xFF4ECDC4),
];
```

Используйте в компонентах:

```dart
GlassButton(
  isPrimary: true,
  gradient: AppColors.myCustomGradient,
  child: Text('Кнопка'),
)
```

### Настройка glass эффектов

В `lib/themes/apple_liquid/constants/app_spacing.dart`:

```dart
// Сделать размытие сильнее
static const double glassBlur = 30.0; // было 20.0
static const double glassBlurStrong = 60.0; // было 40.0
```

### Изменение шрифтов

В `lib/themes/apple_liquid/constants/app_typography.dart`:

```dart
// Изменить размер основного текста
static const TextStyle body = TextStyle(
  fontSize: 18, // было 17
  // ...
);
```

## Расширение темы

### Добавление нового экрана

1. Создайте файл в `lib/themes/apple_liquid/screens/my_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../widgets/glass_app_bar.dart';
import '../components/glass_container.dart';

class MyLiquidScreen extends StatelessWidget {
  const MyLiquidScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.backgroundPrimary,
              AppColors.backgroundSecondary,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              GlassAppBar(
                title: 'My Screen',
              ),
              // Ваш контент
            ],
          ),
        ),
      ),
    );
  }
}
```

2. Добавьте экспорт в `theme_exports.dart`:

```dart
export 'screens/my_screen.dart';
```

### Создание нового виджета

1. Создайте файл `lib/themes/apple_liquid/widgets/my_widget.dart`:

```dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../components/glass_container.dart';

class MyGlassWidget extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;

  const MyGlassWidget({
    super.key,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      child: Text(title),
    );
  }
}
```

2. Используйте в своих экранах:

```dart
MyGlassWidget(
  title: 'Hello',
  onTap: () => print('Tapped'),
)
```

## Миграция существующих экранов

### Пример: Конвертация обычного экрана в Liquid Glass стиль

**Было:**
```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Title')),
      body: ListView(
        children: [
          Card(
            child: Text('Item'),
          ),
        ],
      ),
    );
  }
}
```

**Стало:**
```dart
import 'package:turbo/themes/apple_liquid/theme_exports.dart';

class MyLiquidScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.backgroundPrimary,
              AppColors.backgroundSecondary,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              GlassAppBar(title: 'Title'),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.all(AppSpacing.md),
                  children: [
                    GlassCard(
                      child: Text(
                        'Item',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## Часто задаваемые вопросы

### Q: Будет ли тема работать на iOS и Android?
**A:** Да, тема полностью кросс-платформенная.

### Q: Влияет ли glass эффект на производительность?
**A:** BackdropFilter может быть ресурсоемким. Оптимизируйте:
- Используйте `GlassIntensity.dark` для неважных элементов
- Не вкладывайте много glass контейнеров друг в друга
- Тестируйте на реальных устройствах

### Q: Можно ли использовать тему частично?
**A:** Да! Импортируйте только нужные компоненты:

```dart
import 'package:turbo/themes/apple_liquid/components/glass_container.dart';
import 'package:turbo/themes/apple_liquid/constants/app_colors.dart';

// Используйте в существующем приложении
GlassContainer(
  child: YourWidget(),
)
```

### Q: Как добавить светлую тему?
**A:** Это планируется в будущих версиях. Вы можете начать с копирования `app_colors.dart` и создания светлой версии.

### Q: Почему не портирован экран регистрации?
**A:** Экран регистрации пока использует оригинальный дизайн. Вы можете портировать его самостоятельно, следуя примерам других экранов.

## Поддержка

Если возникли проблемы:

1. Проверьте, что все импорты корректны
2. Убедитесь, что вы используете Flutter 3.0+
3. Выполните `flutter clean` и `flutter pub get`
4. Проверьте консоль на ошибки

## Полезные ссылки

- [README темы](README.md) - Полная документация
- [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/) - Гайдлайны дизайна
- [Flutter BackdropFilter](https://api.flutter.dev/flutter/widgets/BackdropFilter-class.html) - Документация по glass эффекту
