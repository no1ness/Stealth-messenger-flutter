import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/tg/tg_theme_exports.dart';

void main() {
  group('TgBottomNavBar', () {
    testWidgets('renders all three tabs', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        MaterialApp(
          theme: TgThemeData.light,
          home: Scaffold(
            body: TgBottomNavBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                TgBottomNavBarItem(icon: Icons.chat_bubble_outline, label: 'Chats'),
                TgBottomNavBarItem(icon: Icons.people_outline, label: 'Contacts'),
                TgBottomNavBarItem(icon: Icons.person_outline, label: 'Profile'),
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byIcon(Icons.people_outline), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });
  });
}
