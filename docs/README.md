# Stealth Messenger 🔐

Кроссплатформенный зашифрованный мессенджер на Flutter + Supabase.

## 🚀 Платформы

- ✅ **Android** 6.0+ (собран и протестирован)
- ✅ **Web** (собран и работает)
- 🔜 **iOS** (готов к сборке)
- 🔜 **Windows** (готов к сборке)
- 🔜 **macOS** (готов к сборке)
- 🔜 **Linux** (готов к сборке)

## 📁 Структура проекта

```
STEALTH/
├── client/                    # Flutter приложение
│   ├── .env                   # Переменные окружения (заполнить!)
│   ├── .env.example           # Шаблон переменных окружения
│   ├── lib/                   # Исходный код Dart
│   │   ├── main.dart          # Точка входа с переменными окружения
│   │   ├── supabase_service.dart # Сервис Supabase
│   │   ├── themes/            # Темы (Liquid Glass)
│   │   └── ui/                # UI компоненты
│   ├── supabase_migrations/   # Скрипты базы данных
│   │   ├── 0001_init_schema_improved.sql # Основная схема БД
│   │   └── MIGRATION_GUIDE.md # Руководство по миграции
│   ├── android/               # Android конфигурация
│   ├── web/                   # Web конфигурация
│   └── pubspec.yaml           # Зависимости Flutter
├── docs/                      # Документация
│   ├── README.md              # Английская версия (этот файл)
│   ├── README_RU.md           # Русская версия
│   └── ТЕХНИЧЕСКОЕ ЗАДАНИЕ.txt # Оригинальное ТЗ
└── .gitignore                 # Git игнорирование
```

## 🛠️ Технологии

- **Frontend**: Flutter 3.35.6 (Dart 3.9.2)
- **Backend**: Supabase (PostgreSQL + Real-time + Auth + Storage)
- **Тема**: Apple Liquid Glass
- **Шифрование**: End-to-end encryption (планируется)
- **Видео/Аудио**: WebRTC (flutter_webrtc)

## ⚙️ Установка и запуск

### Требования:
- Flutter SDK 3.35.6+ (установлен в `C:\flutter\`)
- Android Studio / VS Code
- Supabase аккаунт

### 1. Установка зависимостей:
```bash
cd client
flutter pub get
```

### 2. Запуск на Android:
```bash
flutter run
```

### 3. Запуск в браузере:
```bash
flutter run -d chrome
```

### 4. Сборка APK:
```bash
flutter build apk --release
# Файл: client/build/app/outputs/flutter-apk/app-release.apk
```

### 5. Сборка Web:
```bash
flutter build web --release
# Файлы: client/build/web/
```

## 🗄️ Настройка Supabase

### Для новой базы данных:
1. Создайте проект на [supabase.com](https://supabase.com)
2. Выполните SQL из `client/supabase_migrations/reset_and_setup.sql` (полный сброс)
3. Заполните переменные окружения в `client/.env`:
   ```bash
   SUPABASE_URL=https://your-project-id.supabase.co
   SUPABASE_ANON_KEY=your-anon-key-here
   ```

### Для существующей базы данных:
1. Выполните SQL из `client/supabase_migrations/0001_init_schema_improved.sql`
2. Заполните переменные окружения в `client/.env`

## 📱 APK

Последняя версия: **client/build/app/outputs/flutter-apk/app-release.apk** (86.1 MB)

**Установка:**
1. Скопируйте APK на телефон
2. Откройте файл
3. Разрешите установку из неизвестных источников
4. Установите

**Минимальные требования:**
- Android 6.0 (API 23) или выше
- 100 MB свободного места
- Интернет соединение

## 🌐 Web версия

**Локальный запуск:**
```bash
cd client/build/web
python -m http.server 8080
# Откройте http://localhost:8080
```

**Деплой:**
Загрузите папку `client/build/web/` на любой статический хостинг:
- Vercel
- Netlify
- Firebase Hosting
- GitHub Pages

## 🎨 Особенности

- 🔮 **Liquid Glass** тема (Apple-стиль)
- ⚡ **Real-time** сообщения через Supabase
- 🔒 **End-to-end шифрование** (в разработке)
- 📹 **Видео/аудио звонки** через WebRTC
- 💾 **Кэширование** данных (60 сек)
- 🚀 **Welcome screen** при загрузке
- 📱 **Адаптивный дизайн** для всех платформ

## 📝 Разработка

### Горячая перезагрузка:
```bash
flutter run
# Нажмите 'r' для hot reload
# Нажмите 'R' для hot restart
```

### Проверка кода:
```bash
flutter analyze
```

### Тесты:
```bash
flutter test
```

## 📄 Лицензия

Proprietary - все права защищены

## 👨‍💻 Контакты

Проект: STEALTH Messenger
Backend: Supabase (https://kazyqhdshaptuqcujjag.supabase.co)
