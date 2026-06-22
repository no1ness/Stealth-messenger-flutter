import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:stealth/themes/tg/tg_theme_exports.dart';

class PerformanceMonitor extends StatefulWidget {
  const PerformanceMonitor({super.key});

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor>
    with SingleTickerProviderStateMixin {
  static const _windowSize = 60;
  final _frameTimes = <double>[];
  Timer? _refreshTimer;
  double _currentFps = 0;
  double _minFrameTime = 0;
  double _maxFrameTime = 0;
  double _avgFrameTime = 0;
  int _totalFrames = 0;
  int _jankFrames = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_recompute);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      _frameTimes.add(ms);
      if (_frameTimes.length > _windowSize) {
        _frameTimes.removeAt(0);
      }
      _totalFrames++;
      if (ms > 16.67) _jankFrames++;
    }
  }

  void _recompute() {
    if (_frameTimes.isEmpty) return;
    double sum = 0;
    _minFrameTime = _frameTimes[0];
    _maxFrameTime = _frameTimes[0];
    for (final t in _frameTimes) {
      if (t < _minFrameTime) _minFrameTime = t;
      if (t > _maxFrameTime) _maxFrameTime = t;
      sum += t;
    }
    _avgFrameTime = sum / _frameTimes.length;
    _currentFps = _frameTimes.isNotEmpty
        ? _frameTimes.where((t) => t <= 16.67).length / _frameTimes.length * 60
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(TgSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FPS', style: TgTypography.title1),
              const SizedBox(width: TgSpacing.sm),
              Text(
                _currentFps.toStringAsFixed(1),
                style: TgTypography.largeTitle.copyWith(
                  color: _currentFps >= 55
                      ? c.green
                      : _currentFps >= 30
                          ? c.warning
                          : c.error,
                ),
              ),
              const Spacer(),
              Text(
                '$_totalFrames кадров | $_jankFrames jank',
                style: TgTypography.caption1.copyWith(
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: TgSpacing.sm),
          Row(
            children: [
              _StatChip(label: 'мин', value: '${_minFrameTime.toStringAsFixed(1)}ms'),
              const SizedBox(width: TgSpacing.sm),
              _StatChip(label: 'макс', value: '${_maxFrameTime.toStringAsFixed(1)}ms'),
              const SizedBox(width: TgSpacing.sm),
              _StatChip(label: 'средн', value: '${_avgFrameTime.toStringAsFixed(1)}ms'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: TgSpacing.xs,
          horizontal: TgSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: c.backgroundSecondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TgTypography.body
                    .copyWith(fontWeight: FontWeight.w600)),
            Text(label,
                style: TgTypography.caption1
                    .copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}
