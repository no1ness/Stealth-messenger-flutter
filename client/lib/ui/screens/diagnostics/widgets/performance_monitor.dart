import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../themes/apple_liquid/constants/app_colors.dart';
import '../../../../themes/apple_liquid/constants/app_spacing.dart';
import '../../../../themes/apple_liquid/constants/app_typography.dart';

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
    _currentFps = _frameTimes.length > 0
        ? _frameTimes.where((t) => t <= 16.67).length / _frameTimes.length * 60
        : 0;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FPS', style: AppTypography.title1),
              const SizedBox(width: AppSpacing.sm),
              Text(
                _currentFps.toStringAsFixed(1),
                style: AppTypography.largeTitle.copyWith(
                  color: _currentFps >= 55
                      ? AppColors.systemGreen
                      : _currentFps >= 30
                          ? AppColors.systemOrange
                          : AppColors.systemRed,
                ),
              ),
              const Spacer(),
              Text(
                '$_totalFrames кадров | $_jankFrames jank',
                style: AppTypography.caption1.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _StatChip(label: 'мин', value: '${_minFrameTime.toStringAsFixed(1)}ms'),
              const SizedBox(width: AppSpacing.sm),
              _StatChip(label: 'макс', value: '${_maxFrameTime.toStringAsFixed(1)}ms'),
              const SizedBox(width: AppSpacing.sm),
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.xs,
          horizontal: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.glassLight.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: AppTypography.body
                    .copyWith(fontWeight: FontWeight.w600)),
            Text(label,
                style: AppTypography.caption1
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
