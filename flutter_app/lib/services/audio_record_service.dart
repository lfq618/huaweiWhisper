import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class AudioRecordService {
  final AudioRecorder _audioRecorder = AudioRecorder();

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  Future<bool> isRecording() async {
    return await _audioRecorder.isRecording();
  }

  Future<bool> isPaused() async {
    return await _audioRecorder.isPaused();
  }

  /// 开始录制 16kHz 单声道 WAV (whisper.cpp 原生匹配格式，省去服务端转码耗时)
  Future<String> startRecording() async {
    final permitted = await hasPermission();
    if (!permitted) {
      throw Exception('未获得麦克风录音权限');
    }

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${tempDir.path}${Platform.pathSeparator}rec_$timestamp.wav';

    const config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
      bitRate: 256000,
    );

    await _audioRecorder.start(config, path: filePath);
    return filePath;
  }

  Future<void> pauseRecording() async {
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.pause();
    }
  }

  Future<void> resumeRecording() async {
    if (await _audioRecorder.isPaused()) {
      await _audioRecorder.resume();
    }
  }

  /// 停止录音并返回文件绝对路径
  Future<String?> stopRecording() async {
    final path = await _audioRecorder.stop();
    return path;
  }

  /// 取消并删除本次临时录音
  Future<void> cancelRecording(String? filePath) async {
    try {
      await _audioRecorder.stop();
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
  }

  /// 获取音量振幅 (用于 UI 动画波形)
  Future<Amplitude> getAmplitude() async {
    return await _audioRecorder.getAmplitude();
  }

  Future<void> dispose() async {
    await _audioRecorder.dispose();
  }
}
