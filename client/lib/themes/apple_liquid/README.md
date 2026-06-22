# Apple Liquid Glass UI Theme

Премиум тема для мобильного приложения Turbo, выполненная в стиле Apple с использованием эффектов Liquid Glass UI.

## Особенности

### Дизайн
- 🍎 **Apple Design Language** - следует гайдлайнам Apple Human Interface Guidelines
- 🌊 **Liquid Glass Effects** - потрясающие эффекты glassmorphism с размытием
- 🎨 **Градиенты** - плавные цветовые переходы в стиле iOS
- ✨ **Анимации** - плавные микроанимации при взаимодействии
- 🌙 **Dark Mode** - красивый темный режим

### Компоненты

#### Константы
- `app_colors.dart` - цветовая палитра Apple (системные цвета, градиенты)
- `app_typography.dart` - типографика SF Pro (Title, Body, Caption и т.д.)
- `app_spacing.dart` - отступы и размеры в стиле Apple
- `glass_styles.dart` - готовые стили glassmorphism

#### UI Компоненты
- `GlassContainer` - контейнер с эффектом стекла
- `GlassCard` - карточка с glassmorphism
- `GlassButton` - кнопка с анимацией нажатия
- `GlassTextField` - поле ввода с фокусом
- `GlassSearchField` - поисковое поле
- `GlassAppBar` - навигационная панель
- `GlassBottomNavBar` - нижняя навигация
- `GlassChatBubble` - облачка сообщений
- `GlassChatInput` - ввод сообщений

#### Экраны
- `LiquidChatsScreen` - список чатов и просмотр чата
- `LiquidContactsScreen` - список контактов
- `LiquidProfileScreen` - профиль пользователя
- `LiquidMainScreen` - главный экран с навигацией

## Установка

### Способ 1: Временное переключение (рекомендуется для тестирования)

Откройте файл `lib/main.dart` и измените:

```dart
// Старый код:
runApp(const MyApp());

// Новый код:
import 'themes/apple_liquid/apple_liquid_app.dart';

runApp(const AppleLiquidApp());
```

### Способ 2: Создание отдельной точки входа

Создайте новый файл `lib/main_liquid.dart`:

```dart
import 'package:flutter/material.dart';
import 'themes/apple_liquid/apple_liquid_app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const AppleLiquidApp());
}
```

Затем запустите:
```bash
flutter run -t lib/main_liquid.dart
```

### Способ 3: Переключатель тем (требует доработки)

Создайте провайдер для управления темами и добавьте переключатель в настройках.

## Использование компонентов

### GlassContainer

```dart
GlassContainer(
  intensity: GlassIntensity.medium,
  padding: EdgeInsets.all(16),
  borderRadius: 20,
  child: Text('Hello Glass!'),
)
```

### GlassButton

```dart
// Обычная кнопка
GlassButton(
  onPressed: () {},
  child: Text('Tap me'),
)

// Primary кнопка с градиентом
GlassButton(
  isPrimary: true,
  gradient: AppColors.liquidGradient1,
  onPressed: () {},
  child: Text('Primary'),
)
```

### GlassTextField

```dart
GlassTextField(
  controller: controller,
  hintText: 'Enter text',
  labelText: 'Label',
  prefixIcon: Icon(Icons.search),
)
```

### GlassChatBubble

```dart
GlassChatBubble(
  message: 'Hello!',
  type: MessageType.sent,
  timestamp: '12:30',
  isRead: true,
)
```

## Цветовая палитра

### Системные цвета
- `systemBlue` - #007AFF
- `systemGreen` - #34C759
- `systemRed` - #FF3B30
- `systemPurple` - #AF52DE
- `systemPink` - #FF2D55

### Градиенты
- `liquidGradient1` - Синий → Фиолетовый
- `liquidGradient2` - Розовый → Оранжевый
- `liquidGradient3` - Зеленый → Голубой
- `liquidGradient4` - Фиолетовый → Розовый

### Glass эффекты
- `glassLight` - светлое стекло (40% opacity)
- `glassMedium` - среднее стекло (20% opacity)
- `glassDark` - темное стекло (10% opacity)
- `glassUltraDark` - очень темное стекло (8% opacity)

## Типографика

Используется стиль SF Pro от Apple:

- `largeTitle` - 34px, Bold - Заголовки экранов
- `title1` - 28px, Bold - Крупные заголовки
- `title2` - 22px, Bold - Средние заголовки
- `title3` - 20px, Semibold - Малые заголовки
- `headline` - 17px, Semibold - Выделенный текст
- `body` - 17px, Regular - Основной текст
- `callout` - 16px, Regular - Вспомогательный текст
- `subheadline` - 15px, Regular - Подзаголовки
- `footnote` - 13px, Regular - Сноски
- `caption1` - 12px, Regular - Подписи
- `caption2` - 11px, Regular - Мелкие подписи

Пример использования:

```dart
Text(
  'Hello',
  style: AppTypography.title1.copyWith(
    color: AppColors.textPrimary,
  ),
)
```

## Настройка

### Изменение blur эффекта

В `constants/app_spacing.dart`:

```dart
static const double glassBlur = 20.0; // увеличьте для сильнего размытия
static const double glassBlurStrong = 40.0;
static const double glassBlurLight = 10.0;
```

### Создание собственных градиентов

В `constants/app_colors.dart`:

```dart
static const List<Color> myGradient = [
  Color(0xFFFF0000),
  Color(0xFF00FF00),
];
```

### Кастомные стили стекла

```dart
BoxDecoration customGlass = GlassStyles.customGlass(
  color: AppColors.glassMedium,
  borderRadius: 16,
  borderColor: AppColors.glassLight,
  borderWidth: 1.5,
  blurRadius: 20,
  shadowOpacity: 0.3,
);
```

## Возврат к старой теме

Чтобы вернуться к оригинальному дизайну:

1. Откройте `lib/main.dart`
2. Измените обратно на `runApp(const MyApp())`
3. Перезапустите приложение

Оригинальные файлы остаются нетронутыми в `lib/ui/`.

## Производительность

### Оптимизация BackdropFilter

BackdropFilter может быть ресурсоемким. Для оптимизации:

1. Используйте `GlassIntensity.dark` для менее важных элементов
2. Ограничьте количество вложенных glass эффектов
3. Кэшируйте виджеты с `const` где возможно

### Рекомендации

- ✅ Используйте glass эффекты для главных UI элементов
- ✅ Комбинируйте с градиентами для выделения
- ⚠️ Избегайте чрезмерного использования BackdropFilter
- ⚠️ Тестируйте на реальных устройствах

## Разработка

### Добавление нового экрана

1. Создайте файл в `themes/apple_liquid/screens/`
2. Используйте базовые компоненты из `widgets/`
3. Следуйте стилистике существующих экранов

### Создание нового компонента

1. Создайте файл в `themes/apple_liquid/widgets/` или `components/`
2. Используйте константы из `constants/`
3. Добавьте анимации для интерактивных элементов

## Известные ограничения

- Не все экраны оригинального приложения портированы
- BackdropFilter может работать медленно на слабых устройствах
- Некоторые анимации могут требовать доработки

## Roadmap

- [ ] Экран регистрации в новом стиле
- [ ] Экран видеозвонка с glass эффектами
- [ ] Настройки с переключателем тем
- [ ] Светлая тема
- [ ] Кастомизация градиентов из UI
- [ ] Анимированные переходы между экранами

## Контакты и поддержка

Если у вас возникли вопросы или предложения по улучшению темы, создайте issue в репозитории проекта.

---

**Дизайн вдохновлен:** Apple iOS, Liquid Glass UI
**Совместимость:** Flutter 3.0+, iOS 13+, Android 6+
