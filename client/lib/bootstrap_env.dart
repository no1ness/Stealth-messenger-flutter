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
  'BYPASS_SERVER_IP',
  'BYPASS_UUID',
  'BYPASS_PUBLIC_KEY',
  'BYPASS_SHORT_ID',
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
    case 'BYPASS_SERVER_IP':
      return const String.fromEnvironment('BYPASS_SERVER_IP');
    case 'BYPASS_UUID':
      return const String.fromEnvironment('BYPASS_UUID');
    case 'BYPASS_PUBLIC_KEY':
      return const String.fromEnvironment('BYPASS_PUBLIC_KEY');
    case 'BYPASS_SHORT_ID':
      return const String.fromEnvironment('BYPASS_SHORT_ID');
    default:
      return '';
  }
}
