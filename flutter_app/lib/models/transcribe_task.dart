enum TaskStatus {
  queued,
  processing,
  success,
  failed;

  static TaskStatus fromString(String status) {
    switch (status.toLowerCase()) {
      case 'processing':
        return TaskStatus.processing;
      case 'success':
        return TaskStatus.success;
      case 'failed':
        return TaskStatus.failed;
      case 'queued':
      default:
        return TaskStatus.queued;
    }
  }

  String get label {
    switch (this) {
      case TaskStatus.queued:
        return '排队中';
      case TaskStatus.processing:
        return '转写中';
      case TaskStatus.success:
        return '已完成';
      case TaskStatus.failed:
        return '转写失败';
    }
  }
}

class TranscribeTask {
  final String taskId;
  final String? localFilePath;
  final String? fileName;
  TaskStatus status;
  String text;
  String? polishedText;
  double audioDurationSec;
  String? errorCode;
  String? errorMsg;
  int durationMs;
  int retryCount;
  final DateTime createdAt;
  DateTime? finishedAt;

  TranscribeTask({
    required this.taskId,
    this.localFilePath,
    this.fileName,
    this.status = TaskStatus.queued,
    this.text = '',
    this.polishedText,
    this.audioDurationSec = 0,
    this.errorCode,
    this.errorMsg,
    this.durationMs = 0,
    this.retryCount = 0,
    DateTime? createdAt,
    this.finishedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TranscribeTask.fromJson(Map<String, dynamic> json, {String? localFilePath, String? fileName}) {
    return TranscribeTask(
      taskId: json['task_id'] as String? ?? '',
      localFilePath: localFilePath,
      fileName: fileName ?? json['source_file_path']?.toString().split('/').last,
      status: TaskStatus.fromString(json['status'] as String? ?? 'queued'),
      text: json['text'] as String? ?? '',
      polishedText: json['polished_text'] as String?,
      audioDurationSec: (json['audio_duration_sec'] as num?)?.toDouble() ?? 0,
      errorCode: json['error_code']?.toString(),
      errorMsg: json['error_msg'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      finishedAt: json['finished_at'] != null ? DateTime.tryParse(json['finished_at'].toString()) : null,
    );
  }

  bool get isCompleted => status == TaskStatus.success || status == TaskStatus.failed;

  String get effectiveText {
    if (polishedText != null && polishedText!.isNotEmpty) {
      return polishedText!;
    }
    return text;
  }
}
