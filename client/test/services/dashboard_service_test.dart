import 'package:flutter_test/flutter_test.dart';
import 'package:stealth/services/dashboard/dashboard_service.dart';

/// Focused unit tests for the extracted [DashboardService]. Methods
/// that touch [LocalDatabaseService] / [StorageService]
/// (`getDashboardSummary`, `getWeeklyActivityBars`) are covered through
/// existing widget/integration flows; here we lock down the pure
/// [computeWeeklyBars] aggregator that was carved out specifically for
/// unit coverage.
void main() {
  group('computeWeeklyBars (pure aggregator)', () {
    test('empty list yields 7 buckets of the minimum visible floor (0.12)', () {
      final now = DateTime.utc(2026, 5, 22, 12);
      final bars = computeWeeklyBars(const <DateTime>[], now: now);
      expect(bars.length, 7);
      expect(bars.every((value) => value == 0.12), isTrue);
    });

    test('single message today fills the rightmost bucket fully', () {
      final now = DateTime.utc(2026, 5, 22, 12);
      final bars = computeWeeklyBars([now], now: now);
      expect(bars.length, 7);
      // Bucket index 6 == "today"; with a single message, max == 1 so
      // the normalised value == 1.0. All other buckets stay at the
      // 0.12 floor.
      expect(bars[6], 1.0);
      for (var i = 0; i < 6; i++) {
        expect(bars[i], 0.12, reason: 'bucket $i should be at the floor');
      }
    });

    test('distribution across the week normalises to the busiest day', () {
      final now = DateTime.utc(2026, 5, 22, 12);
      final timestamps = <DateTime>[
        // Today (diff 0) — 4 messages, busiest
        now,
        now.subtract(const Duration(hours: 1)),
        now.subtract(const Duration(hours: 2)),
        now.subtract(const Duration(hours: 3)),
        // 2 days ago — 2 messages
        now.subtract(const Duration(days: 2, hours: 1)),
        now.subtract(const Duration(days: 2, hours: 5)),
        // 6 days ago — 1 message
        now.subtract(const Duration(days: 6, hours: 2)),
      ];
      final bars = computeWeeklyBars(timestamps, now: now);
      expect(bars.length, 7);
      // Today (bucket 6): 4/4 = 1.0
      expect(bars[6], 1.0);
      // Two days ago (bucket 4): 2/4 = 0.5
      expect(bars[4], 0.5);
      // Six days ago (bucket 0): 1/4 = 0.25
      expect(bars[0], 0.25);
      // Untouched days stay at the floor.
      expect(bars[1], 0.12);
      expect(bars[2], 0.12);
      expect(bars[3], 0.12);
      expect(bars[5], 0.12);
    });

    test('messages older than 7 days are ignored', () {
      final now = DateTime.utc(2026, 5, 22, 12);
      final bars = computeWeeklyBars(
        [now.subtract(const Duration(days: 8))],
        now: now,
      );
      expect(bars.every((value) => value == 0.12), isTrue);
    });

    test('future-dated messages are ignored (negative diff)', () {
      final now = DateTime.utc(2026, 5, 22, 12);
      final bars = computeWeeklyBars(
        [now.add(const Duration(days: 1))],
        now: now,
      );
      expect(bars.every((value) => value == 0.12), isTrue);
    });
  });

  test('DashboardService() instantiates without throw (factory singleton)', () {
    final a = DashboardService();
    final b = DashboardService();
    expect(identical(a, b), isTrue,
        reason: 'factory ctor must return the same singleton');
  });
}
