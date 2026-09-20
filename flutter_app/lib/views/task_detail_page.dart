import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/transcribe_task.dart';
import '../providers/transcribe_provider.dart';
import '../services/api_service.dart';

class TaskDetailPage extends StatefulWidget {
  final TranscribeTask task;

  const TaskDetailPage({super.key, required this.task});

  @override
  State<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<TaskDetailPage>
    with SingleTickerProviderStateMixin {
  late TranscribeTask _currentTask;
  int _selectedTabIndex = 0; // 0: AI 润色稿, 1: 原始转写

  // Audio Playback State via AudioPlayer
  late final AudioPlayer _audioPlayer;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  final List<double> _speedOptions = [1.0, 1.25, 1.5, 2.0];
  int _speedIndex = 0;
  bool _showVisualizer = false;

  bool _isLocalAudioAvailable = false;
  String? _resolvedAudioSource;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;

    // Check if task has AI polished text; default to polished if available
    final hasPolished = _currentTask.polishedText != null &&
        _currentTask.polishedText!.isNotEmpty;
    _selectedTabIndex = hasPolished ? 0 : 1;

    // Initialize total duration
    if (_currentTask.audioDurationSec > 0) {
      _totalDuration = Duration(
        milliseconds: (_currentTask.audioDurationSec * 1000).toInt(),
      );
    } else {
      _totalDuration = const Duration(seconds: 60); // fallback duration
    }

    _checkAudioSource();

    _audioPlayer = AudioPlayer();
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    _posSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) {
        setState(() {
          _currentPosition = p;
        });
      }
    });

    _durSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) {
        setState(() {
          _totalDuration = d;
        });
      }
    });

    _stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// 智能检测音频来源：手机端本地优先，不存在则回退至服务端流式地址
  void _checkAudioSource() {
    if (_currentTask.localFilePath != null &&
        _currentTask.localFilePath!.isNotEmpty) {
      try {
        final localFile = File(_currentTask.localFilePath!);
        if (localFile.existsSync()) {
          _isLocalAudioAvailable = true;
          _resolvedAudioSource = _currentTask.localFilePath;
          return;
        }
      } catch (_) {
        _isLocalAudioAvailable = false;
      }
    }

    // 本地不存在，使用服务端音频流
    _isLocalAudioAvailable = false;
    final apiService = ApiService();
    _resolvedAudioSource = apiService.getAudioUrl(_currentTask.taskId);
  }

  Future<void> _togglePlayPause() async {
    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_audioPlayer.state == PlayerState.paused) {
          await _audioPlayer.resume();
        } else {
          // Play local or server stream
          if (_isLocalAudioAvailable && _currentTask.localFilePath != null) {
            await _audioPlayer.play(DeviceFileSource(_currentTask.localFilePath!));
          } else if (_resolvedAudioSource != null && _resolvedAudioSource!.isNotEmpty) {
            await _audioPlayer.play(UrlSource(_resolvedAudioSource!));
          } else {
            _showToast('未找到可用的音频源');
            return;
          }
          await _audioPlayer.setPlaybackRate(_playbackSpeed);
        }
      }
    } catch (e) {
      _showToast('播放音频失败: $e');
    }
  }

  Future<void> _seekTo(Duration position) async {
    final clamped = position < Duration.zero
        ? Duration.zero
        : (position > _totalDuration ? _totalDuration : position);
    setState(() {
      _currentPosition = clamped;
    });
    try {
      await _audioPlayer.seek(clamped);
    } catch (_) {}
  }

  void _seekRelative(int seconds) {
    final next = _currentPosition + Duration(seconds: seconds);
    _seekTo(next);
  }

  Future<void> _cyclePlaybackSpeed() async {
    setState(() {
      _speedIndex = (_speedIndex + 1) % _speedOptions.length;
      _playbackSpeed = _speedOptions[_speedIndex];
    });
    try {
      await _audioPlayer.setPlaybackRate(_playbackSpeed);
    } catch (_) {}
    _showToast('倍速已切换至 ${_playbackSpeed}x');
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xE61E293B),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  void _copyText(String content, String label) {
    if (content.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: content));
    _showToast('已复制 $label 到剪贴板');
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatElapsed(int ms) {
    if (ms <= 0) return '0.0秒';
    if (ms < 60000) {
      return '${(ms / 1000).toStringAsFixed(1)}秒';
    }
    final mins = (ms / 60000).toStringAsFixed(1);
    return '$mins分';
  }

  /// 将全文根据断句/标点或换行拆分为具有逻辑时间戳的段落
  List<_TranscriptSegment> _buildParagraphSegments(String rawText, Duration totalAudioDuration) {
    if (rawText.trim().isEmpty) return [];

    // Split by newlines or full-stops
    var lines = rawText
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.length <= 1 && rawText.length > 80) {
      // Split into 3-4 segments if single big paragraph
      final sentences = rawText.split(RegExp(r'(?<=[。！？；\n])'));
      final buffer = <String>[];
      var cur = '';
      for (final s in sentences) {
        cur += s;
        if (cur.length >= 60) {
          buffer.add(cur.trim());
          cur = '';
        }
      }
      if (cur.isNotEmpty) buffer.add(cur.trim());
      lines = buffer.where((e) => e.isNotEmpty).toList();
    }

    if (lines.isEmpty) {
      lines = [rawText];
    }

    final totalSec = max(totalAudioDuration.inSeconds, 10);
    final interval = totalSec / max(lines.length, 1);

    final segments = <_TranscriptSegment>[];
    for (int i = 0; i < lines.length; i++) {
      final startSec = (i * interval).toInt();
      final endSec = ((i + 1) * interval).toInt();
      segments.add(_TranscriptSegment(
        startTime: Duration(seconds: startSec),
        endTime: Duration(seconds: endSec),
        text: lines[i],
      ));
    }

    return segments;
  }

  void _showExportSheet(BuildContext context, String textToExport) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');
    final taskDate = dateFormat.format(_currentTask.createdAt);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '分享与导出',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.content_copy_rounded, color: AppTheme.primaryColor, size: 20),
                  ),
                  title: const Text('复制全部文本', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('复制当前标签页的完整转写结果', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyText(textToExport, '转写全文');
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.description_outlined, color: Color(0xFF06B6D4), size: 20),
                  ),
                  title: const Text('导出为 Markdown', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('包含任务元数据、时长与转写内容', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  onTap: () {
                    Navigator.pop(ctx);
                    final md = '# 语音转写记录\n\n'
                        '- **任务 ID**: ${_currentTask.taskId}\n'
                        '- **创建时间**: $taskDate\n'
                        '- **音频时长**: ${_formatDuration(_totalDuration)}\n'
                        '- **耗时**: ${_formatElapsed(_currentTask.durationMs)}\n\n'
                        '## 转写正文\n\n$textToExport\n';
                    Clipboard.setData(ClipboardData(text: md));
                    _showToast('Markdown 文档已复制到剪贴板');
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.audio_file_outlined, color: Color(0xFF10B981), size: 20),
                  ),
                  title: const Text('音频源信息', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(
                    _isLocalAudioAvailable
                        ? '本地源文件: ${_currentTask.localFilePath}'
                        : '云端流地址: $_resolvedAudioSource',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (_resolvedAudioSource != null) {
                      Clipboard.setData(ClipboardData(text: _resolvedAudioSource!));
                      _showToast('音频路径已复制');
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TranscribeProvider>(context);
    final latest = provider.allTasks.firstWhere(
      (t) => t.taskId == _currentTask.taskId,
      orElse: () => _currentTask,
    );
    _currentTask = latest;

    final hasPolished = _currentTask.polishedText != null &&
        _currentTask.polishedText!.trim().isNotEmpty;
    final activeText = (_selectedTabIndex == 0 && hasPolished)
        ? _currentTask.polishedText!
        : _currentTask.text;

    final segments = _buildParagraphSegments(activeText, _totalDuration);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FF), // Design token: surface
      body: SafeArea(
        child: Column(
          children: [
            // 1. 顶部极简导航栏 (Header)
            _buildHeader(context, activeText, provider),

            // 主体滚动内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 2. 紧凑克制元信息条
                    _buildMetadataBar(),
                    const SizedBox(height: 12),

                    // 3. 音频播放控制区极简重构
                    _buildAudioPlayerCard(),
                    const SizedBox(height: 14),

                    // 4. 轻量分段切换与辅助操作
                    _buildSegmentedSwitch(hasPolished, activeText),
                    const SizedBox(height: 12),

                    // 5. 转写段落正文排版 (或失败/加载视图)
                    if (_currentTask.status == TaskStatus.success) ...[
                      _buildTranscriptCard(segments),
                    ] else if (_currentTask.status == TaskStatus.failed) ...[
                      _buildFailedCard(provider),
                    ] else ...[
                      _buildProcessingCard(),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 1. 顶部极简导航栏
  Widget _buildHeader(BuildContext context, String activeText, TranscribeProvider provider) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF8FF).withValues(alpha: 0.95),
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withValues(alpha: 0.04),
            width: 1,
          ),
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(19),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: Color(0xFF131B2E),
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.center,
            child: Text(
              '转写详情',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF131B2E),
                letterSpacing: -0.2,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  color: const Color(0xFF131B2E),
                  tooltip: '分享 / 导出',
                  onPressed: () => _showExportSheet(context, activeText),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20, color: Color(0xFF131B2E)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) async {
                    if (value == 'retry') {
                      final ok = await provider.retryTask(_currentTask.taskId);
                      if (context.mounted && ok) {
                        _showToast('已重新发起转写');
                      }
                    } else if (value == 'delete') {
                      final ok = await provider.deleteTask(_currentTask.taskId);
                      if (context.mounted && ok) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    if (_currentTask.status == TaskStatus.failed)
                      const PopupMenuItem(
                        value: 'retry',
                        child: Row(
                          children: [
                            Icon(Icons.refresh_rounded, size: 18, color: AppTheme.primaryColor),
                            SizedBox(width: 8),
                            Text('重新转写'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('删除记录', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 2. 紧凑克制元信息条
  Widget _buildMetadataBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧元数据流
          Flexible(
            child: Row(
              children: [
                Text(
                  _formatDuration(_totalDuration),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF131B2E),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('·', style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.bold)),
                ),
                Text(
                  '耗时 ${_formatElapsed(_currentTask.durationMs)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('·', style: TextStyle(color: Color(0xFFCBD5E1), fontWeight: FontWeight.bold)),
                ),
                Flexible(
                  child: Text(
                    _isLocalAudioAvailable ? '本地音源' : '云端音频',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _isLocalAudioAvailable ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // 右侧状态指示胶囊
          _buildStatusPill(_currentTask.status),
        ],
      ),
    );
  }

  Widget _buildStatusPill(TaskStatus status) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case TaskStatus.success:
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF047857);
        label = '已完成';
        break;
      case TaskStatus.processing:
        bg = const Color(0xFFF0F9FF);
        fg = const Color(0xFF0284C7);
        label = '转写中';
        break;
      case TaskStatus.queued:
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFB45309);
        label = '排队中';
        break;
      case TaskStatus.failed:
        bg = const Color(0xFFFFF1F2);
        fg = const Color(0xFFBE123C);
        label = '失败';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: fg,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  // 3. 音频播放控制区极简重构
  Widget _buildAudioPlayerCard() {
    final progressRatio = _totalDuration.inMilliseconds > 0
        ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 纤细进度条与时间
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final localX = details.localPosition.dx;
                final width = box.size.width - 64; // accounting for padding
                if (width > 0) {
                  final ratio = (localX / width).clamp(0.0, 1.0);
                  final nextMs = (ratio * _totalDuration.inMilliseconds).toInt();
                  _seekTo(Duration(milliseconds: nextMs));
                }
              }
            },
            onTapDown: (details) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null) {
                final localX = details.localPosition.dx;
                final width = box.size.width - 64;
                if (width > 0) {
                  final ratio = (localX / width).clamp(0.0, 1.0);
                  final nextMs = (ratio * _totalDuration.inMilliseconds).toInt();
                  _seekTo(Duration(milliseconds: nextMs));
                }
              }
            },
            child: Container(
              height: 14,
              alignment: Alignment.center,
              color: Colors.transparent,
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progressRatio,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 进度时间文本
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_currentPosition),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _formatDuration(_totalDuration),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF94A3B8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          // 动态声波可视化（可选展开）
          if (_showVisualizer) ...[
            const SizedBox(height: 10),
            _buildWaveformVisualizer(),
          ],

          const SizedBox(height: 8),

          // 播放器核心操作按钮行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 倍速按钮
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _cyclePlaybackSpeed,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ),
              ),

              // 核心控制区：快退10秒、主播放、快进10秒
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10_rounded, size: 22),
                    color: const Color(0xFF475569),
                    tooltip: '快退 10 秒',
                    onPressed: () => _seekRelative(-10),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _togglePlayPause,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F46E5), Color(0xFF4338CA)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.forward_10_rounded, size: 22),
                    color: const Color(0xFF475569),
                    tooltip: '快进 10 秒',
                    onPressed: () => _seekRelative(10),
                  ),
                ],
              ),

              // 声波可视化切换
              IconButton(
                icon: Icon(
                  Icons.graphic_eq_rounded,
                  size: 20,
                  color: _showVisualizer ? AppTheme.primaryColor : const Color(0xFF94A3B8),
                ),
                tooltip: '声波效果',
                onPressed: () {
                  setState(() {
                    _showVisualizer = !_showVisualizer;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 动态声波可视化组件
  Widget _buildWaveformVisualizer() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(24, (index) {
          final isHighlighted = index < 24 * (_currentPosition.inMilliseconds / max(_totalDuration.inMilliseconds, 1));
          final waveHeight = _isPlaying
              ? 6.0 + (sin((index + _currentPosition.inMilliseconds / 200)) * 10).abs()
              : 8.0 + (index % 4) * 3.0;

          return Container(
            width: 3,
            height: waveHeight.clamp(4.0, 24.0),
            decoration: BoxDecoration(
              color: isHighlighted
                  ? AppTheme.primaryColor
                  : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  // 4. 轻量分段切换与辅助操作
  Widget _buildSegmentedSwitch(bool hasPolished, String activeText) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Segmented Switch
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSegmentTab(
                label: 'AI 润色稿',
                isSelected: _selectedTabIndex == 0,
                onTap: () {
                  setState(() {
                    _selectedTabIndex = 0;
                  });
                },
              ),
              _buildSegmentTab(
                label: '原始转写',
                isSelected: _selectedTabIndex == 1,
                onTap: () {
                  setState(() {
                    _selectedTabIndex = 1;
                  });
                },
              ),
            ],
          ),
        ),

        // 复制全文按钮
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _copyText(activeText, '转写全文'),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.content_copy_rounded, size: 14, color: Color(0xFF64748B)),
                SizedBox(width: 4),
                Text(
                  '复制全文',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // 5. 转写段落正文排版
  Widget _buildTranscriptCard(List<_TranscriptSegment> segments) {
    if (segments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: Text('暂无文本内容', style: TextStyle(color: Color(0xFF94A3B8))),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(segments.length, (index) {
          final seg = segments[index];
          final isCurrent = _currentPosition >= seg.startTime && _currentPosition < seg.endTime;

          return Padding(
            padding: EdgeInsets.only(bottom: index == segments.length - 1 ? 0 : 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 时间戳交互按钮
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    _seekTo(seg.startTime);
                    _showToast('已跳转至 ${_formatDuration(seg.startTime)}');
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      _formatDuration(seg.startTime),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isCurrent ? AppTheme.primaryColor : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // 段落文本内容
                Expanded(
                  child: SelectableText(
                    seg.text,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.65,
                      color: isCurrent ? const Color(0xFF0F172A) : const Color(0xFF334155),
                      fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // 失败状态卡片
  Widget _buildFailedCard(TranscribeProvider provider) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFECDD3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline_rounded, color: Color(0xFFE11D48), size: 20),
              SizedBox(width: 8),
              Text(
                '转写任务未完成',
                style: TextStyle(
                  color: Color(0xFFBE123C),
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currentTask.errorMsg ?? '转写过程发生异常，请检查后端服务是否正常。',
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () async {
              final ok = await provider.retryTask(_currentTask.taskId);
              if (context.mounted && ok) {
                _showToast('已重新发起转写');
              }
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('重试转写'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE11D48),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // 转写处理中卡片
  Widget _buildProcessingCard() {
    return Container(
      padding: const EdgeInsets.all(36),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _currentTask.status == TaskStatus.processing
                ? 'Whisper 正在逐句转写中...'
                : '排队等待处理中...',
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptSegment {
  final Duration startTime;
  final Duration endTime;
  final String text;

  _TranscriptSegment({
    required this.startTime,
    required this.endTime,
    required this.text,
  });
}
