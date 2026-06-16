import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/constants/accessibility_ids.dart';
import 'package:stealth/themes/apple_liquid/widgets/contacts/contact_tile.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('ContactTile basic rendering', () {
    testWidgets('renders contact name and user id', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Alice', 'user_id': 'u-alice'},
          onTap: () {},
        ),
      ));

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('u-alice'), findsOneWidget);
    });

    testWidgets('uses fallback for unknown name', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'user_id': 'u-bob'},
          onTap: () {},
        ),
      ));

      expect(find.text('Unknown'), findsOneWidget);
    });

    testWidgets('renders initials in avatar', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Charlie Brown', 'user_id': 'u-charlie'},
          onTap: () {},
        ),
      ));

      expect(find.text('CB'), findsOneWidget);
    });

    testWidgets('shows single initial for one-word name', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Dave', 'user_id': 'u-dave'},
          onTap: () {},
        ),
      ));

      expect(find.text('D'), findsOneWidget);
    });

    testWidgets('shows ? for empty name', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': '', 'user_id': 'u-empty'},
          onTap: () {},
        ),
      ));

      expect(find.text('?'), findsOneWidget);
    });
  });

  group('ContactTile online indicator', () {
    testWidgets('shows Online semantics when isOnline=true', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Alice', 'user_id': 'u-alice'},
          onTap: () {},
          isOnline: true,
        ),
      ));

      expect(
        find.bySemanticsLabel(RegExp('Online')),
        findsOneWidget,
      );
    });

    testWidgets('shows Offline semantics when isOnline=false', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Bob', 'user_id': 'u-bob'},
          onTap: () {},
          isOnline: false,
        ),
      ));

      expect(
        find.bySemanticsLabel(RegExp('Offline')),
        findsOneWidget,
      );
    });

    testWidgets('hides indicator when isOnline is null', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Carol', 'user_id': 'u-carol'},
          onTap: () {},
        ),
      ));

      expect(find.bySemanticsLabel(RegExp('Online')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Offline')), findsNothing);
    });
  });

  group('ContactTile trailing widget', () {
    testWidgets('shows trailing when provided', (tester) async {
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Alice', 'user_id': 'u-alice'},
          onTap: () {},
          trailing: const Icon(Icons.info),
        ),
      ));

      expect(find.byIcon(Icons.info), findsOneWidget);
    });
  });

  group('ContactTile onTap', () {
    testWidgets('fires onTap when tapped', (tester) async {
      int tapCount = 0;
      await tester.pumpWidget(wrap(
        ContactTile(
          contact: {'name': 'Alice', 'user_id': 'u-alice'},
          onTap: () => tapCount++,
        ),
      ));

      await tester.tap(find.text('Alice'));
      expect(tapCount, 1);
    });
  });
}
