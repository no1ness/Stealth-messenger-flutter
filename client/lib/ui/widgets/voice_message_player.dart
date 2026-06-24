import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:stealth/logging/logger.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:stealth/themes/tg/tg_theme_exports.dart';

class VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final bool isSent;
  final int? duration; // длительность в секундах, если известна

  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    required this.isSent,
    this.duration,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;
  StreamSubscription? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    // Подписываемся на изменения позиции
    _positionSubscription = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    // Подписываемся на изменения длительности
    _durationSubscription = _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });

    // Подписываемся на изменения состояния
    _stateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        if (state == PlayerState.completed) {
          _audioPlayer.seek(Duration.zero);
          setState(() {
            _isPlaying = false;
            _currentPosition = Duration.zero;
          });
        }
      }
    });

    final url = widget.audioUrl.trim();
    final hasValidUrl = url.isNotEmpty &&
        (url.startsWith('http://') || url.startsWith('https://'));

    if (!hasValidUrl) {
      Logger.warn('[voice-player] skipped: invalid audio url',
          extras: {'url': url});
      return;
    }

    try {
      await _audioPlayer.setSource(UrlSource(url));
    } catch (e) {
      Logger.warn('[voice-player] error initializing audio player',
          extras: {'error': e});
      // Don't show snackbar for every error, as this might flood the UI
      // Just log the error and continue
    }
  }

  Future<void> _togglePlayback() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        await _audioPlayer.resume();
      }
    } catch (e) {
      Logger.warn('[voice-player] error toggling playback',
          extras: {'error': e});
    }
  }

  Future<void> _changeSpeed() async {
    double newSpeed;
    if (_playbackSpeed == 1.0) {
      newSpeed = 1.5;
    } else if (_playbackSpeed == 1.5) {
      newSpeed = 2.0;
    } else {
      newSpeed = 1.0;
    }

    setState(() {
      _playbackSpeed = newSpeed;
    });

    await _audioPlayer.setPlaybackRate(_playbackSpeed);
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _stateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TgThemeColors.of(context);

    final progress = _totalDuration.inMilliseconds > 0
        ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;

    final accent =
        widget.isSent ? c.primary : c.primary;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280, minWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: widget.isSent
            ? c.primary.withValues(alpha: 0.1)
            : c.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
                  child: CustomPaint(
                    painter: WaveformPainter(
                      progress: progress,
                      color: accent,
                      backgroundColor: c.dividers,
                    ),
                    size: const Size(double.infinity, 24),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isPlaying || _currentPosition.inSeconds > 0
                          ? _formatDuration(_currentPosition)
                          : _formatDuration(_totalDuration),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                      ),
                    ),
                    Text(
                      _formatDuration(_totalDuration),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          GestureDetector(
            onTap: _changeSpeed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: c.dividers.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_playbackSpeed.toStringAsFixed(1)}x',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: c.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Рисует волну аудио (упрощенная версия)
class WaveformPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  WaveformPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = 40;
    final barWidth = size.width / barCount;
    final paint = Paint()..strokeWidth = 2;

    for (int i = 0; i < barCount; i++) {
      final barProgress = i / barCount;
      final isPlayed = barProgress <= progress;

      // Генерируем случайную высоту для волны (детерминированно)
      final heightFactor = ((i * 7) % 10) / 10.0;
      final barHeight = 4 + (heightFactor * (size.height - 8));

      paint.color = isPlayed ? color : backgroundColor;

      final x = i * barWidth + barWidth / 2;
      final y1 = (size.height - barHeight) / 2;
      final y2 = y1 + barHeight;

      canvas.drawLine(
        ui.Offset(x, y1),
        ui.Offset(x, y2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
