import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

class WhatsAppVoiceRecorder extends StatefulWidget {
  final Future<void> Function(String filePath)? onVoiceRecorded;

  const WhatsAppVoiceRecorder({
    super.key,
    this.onVoiceRecorded,
  });

  @override
  State<WhatsAppVoiceRecorder> createState() => _WhatsAppVoiceRecorderState();
}

class _WhatsAppVoiceRecorderState extends State<WhatsAppVoiceRecorder>
    with SingleTickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  bool _isLocked = false;
  String? _recordFilePath;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  double _slideOffset = 0.0;
  double _lockOffset = 0.0;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recorder.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    // Проверка веб платформы
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запись голосовых сообщений на веб версии не поддерживается. Используйте мобильное приложение.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет доступа к микрофону. Разрешите в настройках.'),
            duration: Duration(seconds: 2),
          ),
        );
        await openAppSettings();
        return;
      }

      if (!await _recorder.hasPermission()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет разрешения на запись')),
        );
        return;
      }

      final path;
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      } else {
        // For web, the path is handled by the browser's memory
        path = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordFilePath = path;
        _recordingDuration = 0;
        _slideOffset = 0.0;
        _lockOffset = 0.0;
        _isLocked = false;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDuration++;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка записи: $e')),
      );
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      // ВАЖНО: Сначала останавливаем запись
      final path = await _recorder.stop();
      
      // Обновляем UI сразу после остановки
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isLocked = false;
          _recordingDuration = 0;
          _slideOffset = 0.0;
          _lockOffset = 0.0;
        });
      }

      final sendPath = path ?? _recordFilePath;
      if (sendPath != null && widget.onVoiceRecorded != null) {
        await widget.onVoiceRecorded!(sendPath);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Голосовое сообщение отправлено'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Даже при ошибке останавливаем UI
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isLocked = false;
          _recordingDuration = 0;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e')),
      );
      debugPrint('Error stopping recording: $e');
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      await _recorder.stop();
      setState(() {
        _isRecording = false;
        _isLocked = false;
        _recordingDuration = 0;
      });

      if (_recordFilePath != null && !kIsWeb) {
        final file = File(_recordFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Запись отменена'),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      debugPrint('Error canceling recording: $e');
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _startRecording();
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_isRecording || _isLocked) return;

    setState(() {
      // Горизонтальный свайп для отмены (влево)
      _slideOffset = details.localPosition.dx - details.localOffsetFromOrigin.dx;
      if (_slideOffset < -100) {
        _slideOffset = -100;
      } else if (_slideOffset > 0) {
        _slideOffset = 0;
      }

      // Вертикальный свайп для блокировки (вверх)
      _lockOffset = details.localPosition.dy - details.localOffsetFromOrigin.dy;
      if (_lockOffset < -100) {
        _lockOffset = -100;
      } else if (_lockOffset > 0) {
        _lockOffset = 0;
      }
    });

    // Автоматическая отмена при слайде влево
    if (_slideOffset <= -100) {
      _cancelRecording();
    }

    // Автоматическая блокировка при слайде вверх
    if (_lockOffset <= -100) {
      setState(() {
        _isLocked = true;
        _lockOffset = 0;
        _slideOffset = 0;
      });
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (!_isRecording) return;

    // Если заблокировано - не отправляем автоматически
    if (_isLocked) return;

    // Иначе отправляем
    _stopRecordingAndSend();
  }
  
  void _onLongPressCancel() {
    // Если пользователь прервал long press - отменяем запись
    if (_isRecording && !_isLocked) {
      _cancelRecording();
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isRecording) {
      return _buildRecordingUI();
    }

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      onLongPressCancel: _onLongPressCancel,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.mic,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildRecordingUI() {
    final theme = Theme.of(context);

    return Stack(
      children: [
        // Основной контейнер записи
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.red.withOpacity(0.3), width: 2),
          ),
          child: Row(
            children: [
              // Иконка блокировки (если не заблокировано)
              if (!_isLocked)
                Opacity(
                  opacity: 0.3 + (_lockOffset.abs() / 100) * 0.7,
                  child: const Icon(Icons.lock_open, color: Colors.grey, size: 20),
                ),
              if (_isLocked)
                const Icon(Icons.lock, color: Colors.green, size: 20),
              const SizedBox(width: 8),

              // Анимация записи (пульсирующая точка)
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),

              // Таймер
              Text(
                _formatDuration(_recordingDuration),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 8),

              // Визуализация волны (упрощенная)
              Expanded(
                child: _buildWaveform(),
              ),

              // Кнопки управления (если заблокировано)
              if (_isLocked) ...[
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _cancelRecording,
                  tooltip: 'Удалить',
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.green),
                  onPressed: _stopRecordingAndSend,
                  tooltip: 'Отправить',
                ),
              ],
            ],
          ),
        ),

        // Подсказка "Slide to cancel" (если не заблокировано)
        if (!_isLocked)
          Positioned(
            left: 0,
            right: 0,
            bottom: -30,
            child: Opacity(
              opacity: 0.5 + (_slideOffset.abs() / 100) * 0.5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: 16,
                    color: Colors.red.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Свайп влево для отмены',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.hintColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(
                    Icons.arrow_upward,
                    size: 16,
                    color: Colors.green.withOpacity(0.7),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Свайп вверх для блокировки',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.hintColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWaveform() {
    // Упрощенная визуализация волны (анимированные столбики)
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(20, (index) {
          final animOffset = (_recordingDuration + index) % 3;
          final height = 4.0 + (animOffset * 8.0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 3,
            height: height,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
