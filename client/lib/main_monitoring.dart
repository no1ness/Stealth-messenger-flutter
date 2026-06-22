import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stealth/bootstrap_env.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';
import 'package:stealth/ui/screens/dashboard/dashboard_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env.defaults');
  applyDartDefineOverrides();

  final pocketbaseUrl = dotenv.env['POCKETBASE_URL']?.trim() ?? '';
  if (pocketbaseUrl.isEmpty) {
    Logger.error('[dashboard] POCKETBASE_URL not configured');
  }

  runApp(const DashboardApp());
}

class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return MaterialApp(
      title: 'STEALTH Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF17212B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2AABEE),
          secondary: Color(0xFF00C853),
          surface: Color(0xFF242F3D),
          onSurface: Color(0xFFF5F5F5),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF17212B),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF242F3D),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: Color(0xFF3C4A57),
              width: 0.5,
            ),
          ),
        ),
        fontFamily: 'Geist',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Color(0xFFF5F5F5)),
          bodyMedium: TextStyle(color: Color(0xFFF5F5F5)),
          bodySmall: TextStyle(color: Color(0xFF8B9CA9)),
        ),
      ),
      home: const DashboardHomeScreen(),
    );
  }
}
