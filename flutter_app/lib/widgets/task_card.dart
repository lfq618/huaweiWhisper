import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/transcribe_task.dart';
import '../providers/transcribe_provider.dart';
import '../views/task_detail_page.dart';
import 'status_badge.dart';

class TaskCard extends StatelessWidget {
  final TranscribeTask task;

  const TaskCard({super.key, required this.task});

  String _formatDuration(double seconds) {
    if (seconds <= 0) return '';
    final mins = seconds ~/ 60;
    final secs = (seconds % 60).toInt();
    if (mins > 0) {
      return '$mins分$secs秒';
    }
    return '$secs秒';
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MM-dd HH:mm');
    final timeStr = dateFormat.format(task.createdAt);
    final hasPolished = task.polishedText != null && task.polishedText!.isNotEmpty;
    final displayText = task.effectiveText;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskDetailPage(task: task),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Icon + Title + Status + Action Menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 20,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.fileName ?? task.taskId,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                            color: AppTheme.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (task.audioDurationSec > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '音频时长: ${_formatDuration(task.audioDurationSec)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  StatusBadge(status: task.status),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.textMuted),
                    padding: EdgeInsets.zero,
                    onSelected: (value) async {
                      final provider = Provider.of<TranscribeProvider>(context, listen: false);
                      if (value == 'copy') {
                        Clipboard.setData(ClipboardData(text: displayText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('已复制转写文本'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else if (value == 'retry') {
                        final ok = await provider.retryTask(task.taskId);
                        if (context.mounted && ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已重新发起转写任务'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else if (value == 'delete') {
                        final ok = await provider.deleteTask(task.taskId);
                        if (context.mounted && ok) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已删除任务'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      if (displayText.isNotEmpty)
                        const PopupMenuItem(
                          value: 'copy',
                          child: Row(
                            children: [
                              Icon(Icons.copy_rounded, size: 18),
                              SizedBox(width: 8),
                              Text('复制文本'),
                            ],
                          ),
                        ),
                      if (task.status == TaskStatus.failed)
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
                            Text('删除任务', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Content / Status Area
              if (task.status == TaskStatus.success && displayText.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEDF2F7)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasPolished)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.deepseekColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.auto_awesome, size: 12, color: AppTheme.deepseekColor),
                                    SizedBox(width: 4),
                                    Text(
                                      'DeepSeek AI 已润色',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.deepseekColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      Text(
                        displayText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          height: 1.5,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ] else if (task.status == TaskStatus.failed) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.statusFailed.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.statusFailed.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 18, color: AppTheme.statusFailed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          task.errorMsg ?? '转写失败，点击重试',
                          style: const TextStyle(color: AppTheme.statusFailed, fontSize: 12.5),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: task.status == TaskStatus.processing
                              ? AppTheme.statusProcessing
                              : AppTheme.statusQueued,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        task.status == TaskStatus.processing ? '正在使用 Whisper 本地引擎转写中...' : '排队等待消费...',
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Footer Meta Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                  if (task.durationMs > 0)
                    Text(
                      '耗时 ${(task.durationMs / 1000).toStringAsFixed(1)}s',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
