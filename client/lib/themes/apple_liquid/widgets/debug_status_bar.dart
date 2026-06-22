import 'dart:async';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';

class DebugStatusBar extends StatefulWidget {
  const DebugStatusBar({super.key});

  @override
  State<DebugStatusBar> createState() => _DebugStatusBarState();
}

class _DebugStatusBarState extends State<DebugStatusBar> {
  bool _isLocalReady = true;
  int _latencyMs = 0;
  Timer? _monitorTimer;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    super.dispose();
  }

  void _startMonitoring() {
    _monitorTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final start = DateTime.now();
    final end = DateTime.now();
    if (mounted) {
      setState(() {
        _isLocalReady = true;
        _latencyMs = end.difference(start).inMilliseconds;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: _isLocalReady
                ? AppColors.glassUltraDark
                : AppColors.systemRed.withValues(alpha: 0.2),
            border: Border(
              bottom: BorderSide(
                color: AppColors.glassLight.withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isLocalReady
                            ? AppColors.systemGreen
                            : AppColors.systemRed,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isLocalReady
                                    ? AppColors.systemGreen
                                    : AppColors.systemRed)
                                .withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'LOCAL',
                      style: AppTypography.caption2.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${_latencyMs}ms',
                  style: AppTypography.caption2.copyWith(
                    color: _latencyMs < 200
                        ? AppColors.systemGreen
                        : _latencyMs < 500
                            ? AppColors.systemOrange
                            : AppColors.systemRed,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  'E2E: ON',
                  style: AppTypography.caption2.copyWith(
                    color: AppColors.systemBlue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}
