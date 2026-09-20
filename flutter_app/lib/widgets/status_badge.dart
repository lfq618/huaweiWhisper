import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/transcribe_task.dart';

class StatusBadge extends StatelessWidget {
  final TaskStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData icon;

    switch (status) {
      case TaskStatus.queued:
        bg = AppTheme.statusQueued.withValues(alpha: 0.12);
        fg = AppTheme.statusQueued;
        icon = Icons.schedule;
        break;
      case TaskStatus.processing:
        bg = AppTheme.statusProcessing.withValues(alpha: 0.12);
        fg = AppTheme.statusProcessing;
        icon = Icons.sync;
        break;
      case TaskStatus.success:
        bg = AppTheme.statusSuccess.withValues(alpha: 0.12);
        fg = AppTheme.statusSuccess;
        icon = Icons.check_circle_rounded;
        break;
      case TaskStatus.failed:
        bg = AppTheme.statusFailed.withValues(alpha: 0.12);
        fg = AppTheme.statusFailed;
        icon = Icons.error_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.25), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            status.label,
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
