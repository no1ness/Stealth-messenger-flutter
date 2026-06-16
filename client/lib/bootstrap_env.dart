import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stealth/logging/logger.dart';

const List<String> kDartDefineEnvKeys = <String>[
  'POCKETBASE_URL',
  'TURN_URL',
  'TURN_USERNAME',
  'TURN_PASSWORD',
  'TURNS_URL',
  'TURNS_USERNAME',
  'TURNS_PASSWORD',
];

void applyDartDefineOverrides() {
  for (final key in kDartDefineEnvKeys) {
    final fromDefine = fromEnvironmentByKey(key);
    if (fromDefine.isNotEmpty) {
      dotenv.env[key] = fromDefine;
      Logger.info('[bootstrap] env key overridden via --dart-define',
          extras: {'key': key});
    }
  }
}

String fromEnvironmentByKey(String key) {
  switch (key) {
    case 'POCKETBASE_URL':
      return const String.fromEnvironment('POCKETBASE_URL');
    case 'TURN_URL':
      return const String.fromEnvironment('TURN_URL');
    case 'TURN_USERNAME':
      return const String.fromEnvironment('TURN_USERNAME');
    case 'TURN_PASSWORD':
      return const String.fromEnvironment('TURN_PASSWORD');
    case 'TURNS_URL':
      return const String.fromEnvironment('TURNS_URL');
    case 'TURNS_USERNAME':
      return const String.fromEnvironment('TURNS_USERNAME');
    case 'TURNS_PASSWORD':
      return const String.fromEnvironment('TURNS_PASSWORD');
    default:
      return '';
  }
}
