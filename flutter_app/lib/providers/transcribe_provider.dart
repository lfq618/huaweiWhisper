import 'dart:async';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/server_stats.dart';
import '../models/transcribe_task.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

class TranscribeProvider extends ChangeNotifier {
  final ApiService _apiService;

  final List<TranscribeTask> _tasks = [];
  bool _isLoading = false;
  bool _isServerHealthy = false;
  String? _errorMessage;

  bool _needPolish = true; // Default to true for DeepSeek AI polish
  String _selectedLang = 'zh';
  String _filterStatus = 'all'; // all, processing, success, failed
  String _searchQuery = '';

  ServerStats? _serverStats;

  final Map<String, Timer> _activePollTimers = {};

  TranscribeProvider(this._apiService, {bool autoFetch = true}) {
    _needPolish = StorageService.instance.needPolish;
    _selectedLang = StorageService.instance.selectedLang;

    if (autoFetch) {
      checkServerHealth();
      loadHistory();
      fetchServerStats();
    }
  }

  List<TranscribeTask> get tasks {
    var list = _tasks;
    if (_filterStatus != 'all') {
      list = list.where((t) {
        if (_filterStatus == 'processing') {
          return t.status == TaskStatus.queued || t.status == TaskStatus.processing;
        }
        return t.status.name == _filterStatus;
      }).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) {
        return (t.fileName ?? '').toLowerCase().contains(q) ||
            t.text.toLowerCase().contains(q) ||
            (t.polishedText ?? '').toLowerCase().contains(q) ||
            t.taskId.toLowerCase().contains(q);
      }).toList();
    }
    return List.unmodifiable(list);
  }

  List<TranscribeTask> get allTasks => List.unmodifiable(_tasks);
  bool get isLoading => _isLoading;
  bool get isServerHealthy => _isServerHealthy;
  String? get errorMessage => _errorMessage;
  bool get needPolish => _needPolish;
  String get selectedLang => _selectedLang;
  String get filterStatus => _filterStatus;
  String get searchQuery => _searchQuery;
  ServerStats? get serverStats => _serverStats;

  void setNeedPolish(bool value) {
    _needPolish = value;
    StorageService.instance.setNeedPolish(value);
    notifyListeners();
  }

  void setSelectedLang(String lang) {
    _selectedLang = lang;
    StorageService.instance.setSelectedLang(lang);
    notifyListeners();
  }


  void setFilterStatus(String status) {
    _filterStatus = status;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> checkServerHealth() async {
    _isServerHealthy = await _apiService.checkHealth();
    notifyListeners();
  }

  Future<void> fetchServerStats() async {
    _serverStats = await _apiService.fetchStats();
    notifyListeners();
  }

  Future<void> loadHistory() async {
    _isLoading = true;
    notifyListeners();

    try {
      final history = await _apiService.listHistoryTasks();
      for (final item in history) {
        final existingIdx = _tasks.indexWhere((t) => t.taskId == item.taskId);
        if (existingIdx == -1) {
          _tasks.add(item);
        } else {
          _tasks[existingIdx] = item;
        }

        // 若存在未完成的任务且未在轮询中，自动恢复轮询
        if (!item.isCompleted && !_activePollTimers.containsKey(item.taskId)) {
          _startPolling(item.taskId);
        }
      }
      // Sort newest first
      _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      // Ignored
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 当应用从后台唤醒回到前台时，主动同步所有进行中任务
  Future<void> onAppResumed() async {
    checkServerHealth();
    fetchServerStats();
    await loadHistory();
  }


  /// 提交音频并启动轮询
  Future<TranscribeTask?> uploadAudioFile(
    String filePath, {
    String? lang,
    bool? needPolish,
    String? clientTraceId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final resp = await _apiService.uploadAndCreateTask(
        filePath: filePath,
        lang: lang ?? _selectedLang,
        needPolish: needPolish ?? _needPolish,
        clientTraceId: clientTraceId,
      );

      if (!resp.isSuccess || resp.data == null) {
        _errorMessage = resp.message;
        _isLoading = false;
        notifyListeners();
        return null;
      }

      final task = resp.data!;
      final existingIdx = _tasks.indexWhere((t) => t.taskId == task.taskId);
      if (existingIdx != -1) {
        _tasks[existingIdx] = task;
      } else {
        _tasks.insert(0, task);
      }

      _isLoading = false;
      notifyListeners();

      // 开始轮询任务状态 (若尚未完成)
      if (!task.isCompleted) {
        _startPolling(task.taskId);
      }

      // 刷新服务端状态
      fetchServerStats();

      return task;
    } catch (e) {
      _errorMessage = '上传失败: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// 手动重试失败任务
  Future<bool> retryTask(String taskId) async {
    final resp = await _apiService.retryTask(taskId);
    if (resp.isSuccess && resp.data != null) {
      final updated = resp.data!;
      _updateTaskWithDTO(taskId, updated);
      _startPolling(taskId);
      fetchServerStats();
      return true;
    }
    return false;
  }

  /// 删除任务
  Future<bool> deleteTask(String taskId) async {
    final success = await _apiService.deleteTask(taskId);
    if (success) {
      _activePollTimers[taskId]?.cancel();
      _activePollTimers.remove(taskId);
      _tasks.removeWhere((t) => t.taskId == taskId);
      notifyListeners();
      fetchServerStats();
      return true;
    }
    return false;
  }

  void _startPolling(String taskId) {
    _activePollTimers[taskId]?.cancel();

    int elapsedSeconds = 0;

    _activePollTimers[taskId] = Timer.periodic(
      Duration(seconds: AppConfig.pollIntervalSeconds),
      (timer) async {
        elapsedSeconds += AppConfig.pollIntervalSeconds;

        if (elapsedSeconds > AppConfig.pollTimeoutSeconds) {
          timer.cancel();
          _activePollTimers.remove(taskId);
          _updateTaskState(taskId, TaskStatus.failed, errorMsg: '任务转写超时');
          return;
        }

        final statusResp = await _apiService.queryTaskStatus(taskId);
        if (statusResp.isSuccess && statusResp.data != null) {
          final updated = statusResp.data!;
          _updateTaskWithDTO(taskId, updated);

          if (updated.isCompleted) {
            timer.cancel();
            _activePollTimers.remove(taskId);
            fetchServerStats();

            // 触发本地系统通知
            final task = _tasks.firstWhere((t) => t.taskId == taskId, orElse: () => updated);
            if (updated.status == TaskStatus.success) {
              NotificationService.instance.showTaskCompletedNotification(task);
            } else if (updated.status == TaskStatus.failed) {
              NotificationService.instance.showTaskFailedNotification(task);
            }
          }
        }
      },
    );
  }

  void _updateTaskWithDTO(String taskId, TranscribeTask dto) {
    final index = _tasks.indexWhere((t) => t.taskId == taskId);
    if (index != -1) {
      _tasks[index].status = dto.status;
      _tasks[index].text = dto.text;
      _tasks[index].polishedText = dto.polishedText;
      _tasks[index].audioDurationSec = dto.audioDurationSec;
      _tasks[index].errorCode = dto.errorCode;
      _tasks[index].errorMsg = dto.errorMsg;
      _tasks[index].durationMs = dto.durationMs;
      _tasks[index].retryCount = dto.retryCount;
      if (dto.finishedAt != null) _tasks[index].finishedAt = dto.finishedAt;
      notifyListeners();
    }
  }

  void _updateTaskState(String taskId, TaskStatus status, {String? errorMsg}) {
    final index = _tasks.indexWhere((t) => t.taskId == taskId);
    if (index != -1) {
      _tasks[index].status = status;
      if (errorMsg != null) _tasks[index].errorMsg = errorMsg;
      notifyListeners();

      if (status == TaskStatus.failed) {
        NotificationService.instance.showTaskFailedNotification(_tasks[index]);
      }
    }
  }

  @override
  void dispose() {
    for (final timer in _activePollTimers.values) {
      timer.cancel();
    }
    _activePollTimers.clear();
    super.dispose();
  }
}
