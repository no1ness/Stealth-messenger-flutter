import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:stealth/logging/logger.dart';

/// Lazy singleton-обёртка над [PocketBase] клиентом.
///
/// URL читается из `dotenv.env['POCKETBASE_URL']`. Без этого URL
/// сигналинг звонков не работает — запуск приложения должен показать
/// `StartupErrorScreen` (см. task 20 плана). Сам класс [PocketBaseClient]
/// не делает retry: первый `instance` либо успешно создаётся, либо
/// бросает [StateError]. Транспорт (`WebRtcSignalingService`) уже сам
/// обрабатывает разрывы SSE-подписки.
class PocketBaseClient {
  PocketBaseClient._(this.pb);

  /// Низкоуровневый PocketBase SDK-клиент. Доступ к коллекциям —
  /// `instance.pb.collection('rtc_signaling')`.
  final PocketBase pb;

  static PocketBaseClient? _instance;

  /// Возвращает singleton-инстанс. Первое обращение валидирует URL и
  /// создаёт SDK-клиент. Если `POCKETBASE_URL` не задан или пуст —
  /// бросает [StateError] (это критическая ошибка конфигурации).
  static PocketBaseClient get instance {
    final cached = _instance;
    if (cached != null) return cached;
    final url = dotenv.env['POCKETBASE_URL']?.trim();
    if (url == null || url.isEmpty) {
      throw StateError(
        'POCKETBASE_URL is not configured in .env. Calls cannot be initiated. '
        'See docs/POCKETBASE_SETUP.md.',
      );
    }
    Logger.info('[signaling] PocketBase client init', extras: {'url': url});
    final fresh = PocketBaseClient._(PocketBase(url));
    _instance = fresh;
    return fresh;
  }

  /// Сбрасывает singleton. Используется только в тестах.
  static void resetForTests() {
    _instance = null;
  }
}
