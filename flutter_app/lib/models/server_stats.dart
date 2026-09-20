class ServerStats {
  final int uptimeSec;
  final int queueLength;
  final int activeWorkers;
  final int totalTasks;
  final int successTasks;
  final int failedTasks;
  final int processingTasks;
  final int queuedTasks;
  final int avgDurationMs;
  final bool whisperHealthy;
  final bool llmHealthy;
  final bool ffmpegAvailable;

  ServerStats({
    this.uptimeSec = 0,
    this.queueLength = 0,
    this.activeWorkers = 0,
    this.totalTasks = 0,
    this.successTasks = 0,
    this.failedTasks = 0,
    this.processingTasks = 0,
    this.queuedTasks = 0,
    this.avgDurationMs = 0,
    this.whisperHealthy = false,
    this.llmHealthy = false,
    this.ffmpegAvailable = false,
  });

  factory ServerStats.fromJson(Map<String, dynamic> json) {
    return ServerStats(
      uptimeSec: (json['uptime_sec'] as num?)?.toInt() ?? 0,
      queueLength: (json['queue_length'] as num?)?.toInt() ?? 0,
      activeWorkers: (json['active_workers'] as num?)?.toInt() ?? 0,
      totalTasks: (json['total_tasks'] as num?)?.toInt() ?? 0,
      successTasks: (json['success_tasks'] as num?)?.toInt() ?? 0,
      failedTasks: (json['failed_tasks'] as num?)?.toInt() ?? 0,
      processingTasks: (json['processing_tasks'] as num?)?.toInt() ?? 0,
      queuedTasks: (json['queued_tasks'] as num?)?.toInt() ?? 0,
      avgDurationMs: (json['avg_duration_ms'] as num?)?.toInt() ?? 0,
      whisperHealthy: json['whisper_healthy'] as bool? ?? false,
      llmHealthy: json['llm_healthy'] as bool? ?? false,
      ffmpegAvailable: json['ffmpeg_available'] as bool? ?? false,
    );
  }

  double get successRate {
    if (totalTasks == 0) return 100.0;
    final finished = successTasks + failedTasks;
    if (finished == 0) return 100.0;
    return (successTasks / finished) * 100.0;
  }

  String get formattedUptime {
    final days = uptimeSec ~/ 86400;
    final hours = (uptimeSec % 86400) ~/ 3600;
    final minutes = (uptimeSec % 3600) ~/ 60;
    if (days > 0) return '$days天 $hours小时 $minutes分';
    if (hours > 0) return '$hours小时 $minutes分';
    return '$minutes分钟';
  }
}
