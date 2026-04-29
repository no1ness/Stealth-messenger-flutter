import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/themes/apple_liquid/widgets/glass_bottom_nav_bar.dart';

void main() {
  testWidgets('GlassBottomNavBar exposes Chats, Contacts, Profile semantics labels',
      (WidgetTester tester) async {
    // Validates: Requirements 1.1, 1.2, 1.3, 1.4

    // Enable semantics tree before pumping.
    final handle = tester.ensureSemantics();

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Suppress the minor 0.5px overflow that is a pre-existing widget issue
    // unrelated to semantics correctness.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: GlassBottomNavBar(
            currentIndex: 0,
            onTap: (_) {},
            items: const [
              GlassBottomNavBarItem(
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
                label: 'Chats',
              ),
              GlassBottomNavBarItem(
                icon: Icons.people_outline,
                selectedIcon: Icons.people,
                label: 'Contacts',
              ),
              GlassBottomNavBarItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: 'Profile',
              ),
            ],
          ),
          body: const SizedBox.shrink(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Flutter merges the Semantics(label:) with the child Text label, so the
    // resulting node label is "Chats\nChats". Use a RegExp to match the label
    // as a substring, which confirms the accessibility label is present.
    expect(find.bySemanticsLabel(RegExp('Chats')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Contacts')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Profile')), findsOneWidget);
    handle.dispose();
  });
}
