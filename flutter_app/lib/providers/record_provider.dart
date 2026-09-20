import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/audio_record_service.dart';

class RecordProvider extends ChangeNotifier {
  final AudioRecordService _recordService;

  bool _isRecording = false;
  bool _isPaused = false;
  int _recordDurationSeconds = 0;
  String? _recordedFilePath;
  final List<double> _amplitudes = [];

  Timer? _timer;
  Timer? _amplitudeTimer;

  RecordProvider(this._recordService);

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  int get recordDurationSeconds => _recordDurationSeconds;
  String? get recordedFilePath => _recordedFilePath;
  List<double> get amplitudes => List.unmodifiable(_amplitudes);

  String get formattedDuration {
    final minutes = (_recordDurationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordDurationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<bool> startRecording() async {
    try {
      final path = await _recordService.startRecording();
      _isRecording = true;
      _isPaused = false;
      _recordedFilePath = path;
      _recordDurationSeconds = 0;
      _amplitudes.clear();

      _startTimers();
      notifyListeners();
      return true;
    } catch (e) {
      _isRecording = false;
      _isPaused = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;
    await _recordService.pauseRecording();
    _isPaused = true;
    _stopTimers();
    notifyListeners();
  }

  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;
    await _recordService.resumeRecording();
    _isPaused = false;
    _startTimers();
    notifyListeners();
  }

  Future<void> cancelRecording() async {
    _stopTimers();
    _isRecording = false;
    _isPaused = false;
    await _recordService.cancelRecording(_recordedFilePath);
    _recordedFilePath = null;
    _amplitudes.clear();
    notifyListeners();
  }

  Future<String?> stopRecording() async {
    _stopTimers();
    _isRecording = false;
    _isPaused = false;

    try {
      final path = await _recordService.stopRecording();
      _recordedFilePath = path;
      _amplitudes.clear();
      notifyListeners();
      return path;
    } catch (e) {
      _amplitudes.clear();
      notifyListeners();
      return null;
    }
  }

  void _startTimers() {
    _stopTimers();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _recordDurationSeconds++;
      notifyListeners();
    });

    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording || _isPaused) return;
      try {
        final amp = await _recordService.getAmplitude();
        // Convert dB (-60 to 0) to normalized 0.0 - 1.0
        double normalized = 0.1;
        if (amp.current > -60) {
          normalized = (amp.current + 60) / 60.0;
        }
        _amplitudes.add(normalized);
        if (_amplitudes.length > 30) {
          _amplitudes.removeAt(0);
        }
        notifyListeners();
      } catch (_) {}
    });
  }

  void _stopTimers() {
    _timer?.cancel();
    _timer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
  }

  @override
  void dispose() {
    _stopTimers();
    _recordService.dispose();
    super.dispose();
  }
}
