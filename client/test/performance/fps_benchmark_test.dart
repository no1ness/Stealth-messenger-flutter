import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders a representative widget tree and measures frame-pump latency.
/// Reports min / max / avg frame time for CI monitoring.
void main() {
  testWidgets('frame rendering latency',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 1920));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          child: ListView.builder(
            itemCount: 50,
            itemBuilder: (context, index) => Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(Icons.person)),
                title: Text('Contact $index'),
                subtitle: const Text('Online'),
                trailing: Icon(Icons.chat_bubble_outline),
              ),
            ),
          ),
        ),
      ),
    ));

    final stopwatch = Stopwatch()..start();
    final frameTimes = <double>[];
    for (var i = 0; i < 60; i++) {
      final start = stopwatch.elapsedMicroseconds;
      await tester.pump(const Duration(milliseconds: 16));
      final elapsed = stopwatch.elapsedMicroseconds - start;
      frameTimes.add(elapsed / 1000.0);
    }

    final min = frameTimes.reduce((a, b) => a < b ? a : b);
    final max = frameTimes.reduce((a, b) => a > b ? a : b);
    final avg =
        frameTimes.reduce((a, b) => a + b) / frameTimes.length;
    final fps = frameTimes.where((t) => t < 16.67).length;

    debugPrint('--- FPS Benchmark ---');
    debugPrint('Frames within 16.67ms budget: $fps / 60');
    debugPrint('Frame time: min=${min.toStringAsFixed(2)}ms '
        'max=${max.toStringAsFixed(2)}ms '
        'avg=${avg.toStringAsFixed(2)}ms');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
