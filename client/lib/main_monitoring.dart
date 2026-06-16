import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:stealth/bootstrap_env.dart';
import 'package:stealth/logging/logger.dart';
import 'package:stealth/themes/apple_liquid/liquid_theme.dart';
import 'package:stealth/themes/theme_controller.dart';
import 'package:stealth/ui/screens/dashboard/dashboard_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env.defaults');
  applyDartDefineOverrides();

  final pocketbaseUrl = dotenv.env['POCKETBASE_URL']?.trim() ?? '';
  if (pocketbaseUrl.isEmpty) {
    Logger.error('[dashboard] POCKETBASE_URL not configured');
  }

  await ThemeController.loadInitial();

  runApp(const DashboardApp());
}

class DashboardApp extends StatefulWidget {
  const DashboardApp({super.key});

  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, controllerMode, _) {
        return MaterialApp(
          title: 'Stealth Dashboard',
          debugShowCheckedModeBanner: false,
          themeMode: controllerMode,
          theme: LiquidTheme.theme,
          darkTheme: LiquidTheme.darkTheme,
          home: const DashboardHomeScreen(),
        );
      },
    );
  }
}
